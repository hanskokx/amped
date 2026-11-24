/// Picard-style online tag lookup: fingerprint the audio with Chromaprint's
/// algorithm (the pure-Dart `chromaprint_dart` package, on PCM from
/// `pcm_decoder`), find the recording with AcoustID, then fetch its tags from
/// MusicBrainz.
///
/// Nothing here writes to a file. A lookup returns [TagCandidate]s, and the
/// File Info dialog puts the one the user picks into its fields, which are
/// saved only when the user presses OK.
library;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:chromaprint_dart/chromaprint_dart.dart";
import "package:pcm_decoder/pcm_decoder.dart";

import "path_hints.dart";
import "tag_model.dart";

/// Why a lookup failed, for the message the user sees.
enum TagLookupFailure {
  /// No AcoustID API key is set in Preferences.
  missingApiKey,

  /// AcoustID rejected the API key.
  invalidApiKey,

  /// The file couldn't be decoded or fingerprinted.
  fingerprintFailed,

  /// A web service couldn't be reached or answered with an error.
  network,
}

class TagLookupException implements Exception {
  const TagLookupException(this.failure, [this.detail = ""]);

  final TagLookupFailure failure;

  /// The underlying error, for the message (may be empty).
  final String detail;

  @override
  String toString() => "TagLookupException($failure, $detail)";
}

/// A file's Chromaprint fingerprint and length, what AcoustID looks up.
class AudioFingerprint {
  const AudioFingerprint({required this.duration, required this.fingerprint});

  /// In whole seconds, as AcoustID wants it.
  final int duration;

  /// The compressed, base64-encoded Chromaprint fingerprint.
  final String fingerprint;
}

/// One AcoustID result: how well the fingerprint matched, and the
/// MusicBrainz recordings linked to it.
class AcoustIdMatch {
  const AcoustIdMatch({required this.score, required this.recordingIds});

  /// From 0 to 1.
  final double score;
  final List<String> recordingIds;
}

/// A set of tags the lookup proposes: one release a matching recording is
/// on.
class TagCandidate {
  const TagCandidate({
    required this.fields,
    required this.score,
    required this.recordingId,
    required this.releaseId,
    this.releaseStatus,
    this.releaseType,
    this.date,
  });

  /// The proposed values; only fields MusicBrainz has a value for.
  final Map<TagField, String> fields;

  /// The AcoustID match score, from 0 to 1.
  final double score;
  final String recordingId;
  final String? releaseId;

  /// `Official`, `Bootleg`, ... when known.
  final String? releaseStatus;

  /// The release group's type, e.g. `Album`, `Single`, `Album + Live`.
  final String? releaseType;

  /// The release date, `YYYY[-MM[-DD]]`.
  final String? date;

  String operator [](TagField field) => fields[field] ?? "";
}

/// An HTTP response, as plain data so tests can replay recorded ones.
class LookupResponse {
  const LookupResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Fetches [uri]: a GET, or a form POST when [form] is given.
typedef LookupHttp = Future<LookupResponse> Function(
  Uri uri, {
  Map<String, String>? form,
});

/// Fingerprints the audio file at a path. A [cached] fingerprint (from the
/// file's tags) is used instead of computing one.
typedef Fingerprinter = Future<AudioFingerprint> Function(
  String path, {
  String cached,
});

/// What a lookup found: the candidates, best first, and the fingerprint it
/// used, which File Info saves to the file's tags along with the rest.
class TagLookupResult {
  const TagLookupResult(this.candidates, this.fingerprint);

  final List<TagCandidate> candidates;
  final AudioFingerprint fingerprint;
}

/// Looks up tags for the file at a path (what the File Info dialog calls),
/// with the fingerprint cached in its tags, if any.
typedef TagLookupFn = Future<TagLookupResult> Function(
  String path, {
  String cachedFingerprint,
});

// --- Settings ---------------------------------------------------------------

/// The AcoustID application key, built into the app with
/// `--dart-define=ACOUSTID_API_KEY=...`; empty in a build without one.
const String acoustIdApiKey = String.fromEnvironment("ACOUSTID_API_KEY");

// --- Fingerprinting ------------------------------------------------------------

/// How much of a file is fingerprinted, as `fpcalc` does by default.
const Duration fingerprintLength = Duration(seconds: 120);

/// Fingerprints [path] in a background isolate: decodes up to
/// [fingerprintLength] of it, then runs Chromaprint's algorithm. With a
/// [cached] fingerprint it only reads the file's length.
Future<AudioFingerprint> chromaprintFingerprint(
  String path, {
  String cached = "",
}) async {
  try {
    return await Isolate.run(() {
      if (cached.isNotEmpty) {
        final audio = probeFile(path);
        return AudioFingerprint(
          duration: _seconds(audio.duration),
          fingerprint: cached,
        );
      }
      final audio = decodeFile(path, maxDuration: fingerprintLength);
      final fingerprint = Chromaprint().fingerprint(
        audio.samples,
        sampleRate: audio.sampleRate,
        channels: audio.channels,
        maxDuration: fingerprintLength,
      );
      if (fingerprint.raw.isEmpty) {
        throw const TagLookupException(
          TagLookupFailure.fingerprintFailed,
          "too short",
        );
      }
      return AudioFingerprint(
        duration: _seconds(audio.duration),
        fingerprint: fingerprint.toString(),
      );
    });
  } on TagLookupException {
    rethrow;
  } on Object catch (error) {
    throw TagLookupException(TagLookupFailure.fingerprintFailed, "$error");
  }
}

int _seconds(Duration duration) =>
    (duration.inMicroseconds / Duration.microsecondsPerSecond).round();

// --- AcoustID -----------------------------------------------------------------

final Uri acoustIdLookupUri = Uri.parse("https://api.acoustid.org/v2/lookup");

/// The form for an AcoustID lookup of [fingerprint] (POSTed, since
/// fingerprints are too long for a URL).
Map<String, String> acoustIdForm(String apiKey, AudioFingerprint fingerprint) =>
    {
      "client": apiKey,
      "meta": "recordingids",
      "duration": "${fingerprint.duration}",
      "fingerprint": fingerprint.fingerprint,
      "format": "json",
    };

/// Parses an AcoustID `/v2/lookup` response, best match first. Results
/// with no linked recording are left out.
List<AcoustIdMatch> parseAcoustIdResponse(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException catch (error) {
    throw TagLookupException(TagLookupFailure.network, error.message);
  }
  if (json case {"status": "error", "error": final Map<String, Object?> e}) {
    // Code 4 is "invalid API key".
    throw TagLookupException(
      e["code"] == 4
          ? TagLookupFailure.invalidApiKey
          : TagLookupFailure.network,
      "${e["message"] ?? ""}",
    );
  }
  final results = json is Map<String, Object?> ? json["results"] : null;
  if (results is! List) {
    throw const TagLookupException(TagLookupFailure.network);
  }
  final matches = <AcoustIdMatch>[
    for (final result in results)
      if (result case {
        "score": final num score,
        "recordings": final List<Object?> recordings,
      })
        AcoustIdMatch(
          score: score.toDouble(),
          recordingIds: <String>{
            for (final recording in recordings)
              if (recording case {"id": final String id}) id,
          }.toList(),
        ),
  ]..removeWhere((match) => match.recordingIds.isEmpty);
  return matches..sort((a, b) => b.score.compareTo(a.score));
}

// --- MusicBrainz --------------------------------------------------------------

/// The MusicBrainz lookup of recording [id] with what the tags need.
Uri musicBrainzRecordingUri(String id) => Uri.https(
  "musicbrainz.org",
  "/ws/2/recording/$id",
  {"inc": "artist-credits releases media release-groups genres", "fmt": "json"},
);

/// Parses a MusicBrainz recording lookup into one candidate per release
/// it's on, the likeliest first (official albums, then the earliest),
/// leaving out releases whose tags would be the same as one before.
List<TagCandidate> parseMusicBrainzRecording(String body, {double score = 1}) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException catch (error) {
    throw TagLookupException(TagLookupFailure.network, error.message);
  }
  if (json is! Map<String, Object?>) {
    throw const TagLookupException(TagLookupFailure.network);
  }
  final recordingId = json["id"] as String? ?? "";
  final recordingTitle = json["title"] as String? ?? "";
  final artist = _artistCredit(json["artist-credit"]);
  final genre = _topGenre(json["genres"]);
  final base = <TagField, String>{
    TagField.title: recordingTitle,
    TagField.artist: artist,
    TagField.genre: genre,
  };
  final releases = [
    for (final release in json["releases"] as List? ?? const [])
      if (release is Map<String, Object?>) release,
  ]..sort(_compareReleases);
  final candidates = <TagCandidate>[];
  final seen = <String>{};
  for (final release in releases) {
    final group = release["release-group"];
    final date = release["date"] as String? ?? "";
    final fields = {
      ...base,
      TagField.album: release["title"] as String? ?? "",
      TagField.albumArtist: _artistCredit(release["artist-credit"]),
      if (date.length >= 4) TagField.year: date.substring(0, 4),
    };
    if (_track(release) case (final medium, final track)) {
      fields
        ..[TagField.disc] = medium
        ..[TagField.track] = track.$1
        ..[TagField.title] = track.$2.isEmpty ? recordingTitle : track.$2;
    }
    fields.removeWhere((_, value) => value.isEmpty);
    final key =
        (fields.entries.toList()
              ..sort((a, b) => a.key.index.compareTo(b.key.index)))
            .join("|");
    if (!seen.add(key)) continue;
    candidates.add(
      TagCandidate(
        fields: fields,
        score: score,
        recordingId: recordingId,
        releaseId: release["id"] as String?,
        releaseStatus: release["status"] as String?,
        releaseType: group is Map<String, Object?> ? _groupType(group) : null,
        date: date.isEmpty ? null : date,
      ),
    );
  }
  if (candidates.isEmpty) {
    // A recording on no release (a standalone recording).
    final fields = {...base}..removeWhere((_, value) => value.isEmpty);
    candidates.add(
      TagCandidate(
        fields: fields,
        score: score,
        recordingId: recordingId,
        releaseId: null,
      ),
    );
  }
  return candidates;
}

/// An artist credit as one name, e.g. `Artist A feat. Artist B`.
String _artistCredit(Object? credit) => [
  if (credit is List)
    for (final part in credit)
      if (part case {"name": final String name})
        "$name${part["joinphrase"] ?? ""}",
].join().trim();

/// The genre most voted for, in title case (`grunge` → `Grunge`).
String _topGenre(Object? genres) {
  if (genres is! List) return "";
  String best = "";
  num bestCount = 0;
  for (final genre in genres) {
    if (genre case {"name": final String name, "count": final num count}
        when count > bestCount) {
      best = name;
      bestCount = count;
    }
  }
  return best
      .split(" ")
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(" ");
}

/// The disc number and the track's number and title on [release], from the
/// one medium a recording lookup lists the track on.
(String, (String, String))? _track(Map<String, Object?> release) {
  for (final medium in release["media"] as List? ?? const []) {
    if (medium is! Map<String, Object?>) continue;
    final tracks = medium["tracks"];
    if (tracks is! List || tracks.isEmpty) continue;
    final track = tracks.first;
    if (track is! Map<String, Object?>) continue;
    final position = track["position"];
    final number = position is num
        ? "${position.toInt()}"
        : track["number"] as String? ?? "";
    final count = medium["track-count"];
    final disc = medium["position"];
    return (
      disc is num ? "${disc.toInt()}" : "",
      (
        number.isEmpty || count is! num ? number : "$number/${count.toInt()}",
        track["title"] as String? ?? "",
      ),
    );
  }
  return null;
}

String? _groupType(Map<String, Object?> group) {
  final primary = group["primary-type"] as String?;
  final secondary = [
    for (final type in group["secondary-types"] as List? ?? const [])
      if (type is String) type,
  ];
  if (primary == null) return secondary.isEmpty ? null : secondary.join(" + ");
  return [primary, ...secondary].join(" + ");
}

/// Official before other statuses, albums before other types, releases
/// without secondary types (compilations, live, ...) first, then the
/// earliest date (undated last).
int _compareReleases(Map<String, Object?> a, Map<String, Object?> b) {
  int rank(Map<String, Object?> release) {
    final group = release["release-group"];
    final primary = group is Map ? group["primary-type"] : null;
    final secondary = group is Map ? group["secondary-types"] : null;
    return (release["status"] == "Official" ? 0 : 4) +
        (primary == "Album" ? 0 : 2) +
        (secondary is List && secondary.isNotEmpty ? 1 : 0);
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;
  final dateA = a["date"] as String? ?? "";
  final dateB = b["date"] as String? ?? "";
  if (dateA.isEmpty != dateB.isEmpty) return dateA.isEmpty ? 1 : -1;
  return dateA.compareTo(dateB);
}

// --- The lookup -------------------------------------------------------------

/// Fingerprints, matches and fetches tags, in that order.
class TagLookup {
  TagLookup({
    required this.apiKey,
    required this.fingerprint,
    required this.http,
    this.maxRecordings = 3,
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  /// The AcoustID API key (empty when the user hasn't entered one).
  final String apiKey;
  final Fingerprinter fingerprint;
  final LookupHttp http;

  /// How many matched recordings to fetch from MusicBrainz.
  final int maxRecordings;
  final Future<void> Function(Duration) _wait;

  /// MusicBrainz allows one request a second.
  static const Duration musicBrainzInterval = Duration(milliseconds: 1100);

  /// The candidates for the file at [path], best first; none when AcoustID
  /// doesn't know the recording. A [cachedFingerprint] saves computing one.
  Future<TagLookupResult> call(
    String path, {
    String cachedFingerprint = "",
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const TagLookupException(TagLookupFailure.missingApiKey);
    }
    final audio = await fingerprint(path, cached: cachedFingerprint.trim());
    final response = await _fetch(
      acoustIdLookupUri,
      form: acoustIdForm(apiKey.trim(), audio),
      // AcoustID answers a bad key with a 400 and an error body.
      errorBody: true,
    );
    final matches = parseAcoustIdResponse(response.body);
    final scores = <String, double>{};
    for (final match in matches) {
      for (final id in match.recordingIds) {
        scores.putIfAbsent(id, () => match.score);
      }
    }
    final candidates = <TagCandidate>[];
    for (final (index, id) in scores.keys.take(maxRecordings).indexed) {
      if (index > 0) await _wait(musicBrainzInterval);
      final recording = await _fetch(musicBrainzRecordingUri(id));
      candidates.addAll(
        parseMusicBrainzRecording(recording.body, score: scores[id]!),
      );
    }
    return TagLookupResult(rankByPath(candidates, path), audio);
  }

  Future<LookupResponse> _fetch(
    Uri uri, {
    Map<String, String>? form,
    bool errorBody = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final LookupResponse response;
      try {
        response = await http(uri, form: form);
      } on TagLookupException {
        rethrow;
      } on Object catch (error) {
        throw TagLookupException(TagLookupFailure.network, "$error");
      }
      // 503 is MusicBrainz's "slow down"; try once more.
      if (response.statusCode == 503 && attempt == 0) {
        await _wait(const Duration(seconds: 2));
        continue;
      }
      if (response.statusCode == 200 ||
          (errorBody && response.body.trimLeft().startsWith("{"))) {
        return response;
      }
      throw TagLookupException(
        TagLookupFailure.network,
        "${uri.host}: HTTP ${response.statusCode}",
      );
    }
  }
}

/// The User-Agent sent to AcoustID and MusicBrainz: the app, nothing about
/// the user.
const String lookupUserAgent = "amped/0.1.0";

/// [LookupHttp] over `dart:io`.
Future<LookupResponse> ioLookupHttp(
  Uri uri, {
  Map<String, String>? form,
}) async {
  final client = HttpClient()
    ..userAgent = lookupUserAgent
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = form == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, "application/json");
    if (form != null) {
      request.headers.contentType = ContentType(
        "application",
        "x-www-form-urlencoded",
        charset: "utf-8",
      );
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 30));
    return LookupResponse(response.statusCode, body);
  } finally {
    client.close();
  }
}

/// The lookup as the app runs it: the built-in key, over the network.
Future<TagLookupResult> lookUpTags(
  String path, {
  String cachedFingerprint = "",
}) async => TagLookup(
  apiKey: acoustIdApiKey,
  fingerprint: chromaprintFingerprint,
  http: ioLookupHttp,
).call(path, cachedFingerprint: cachedFingerprint);
