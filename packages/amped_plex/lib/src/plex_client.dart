import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_media_source/amped_media_source.dart";

/// The server answered, but with an error (or something that isn't Plex).
class PlexException implements Exception {
  const PlexException(this.message);

  final String message;

  @override
  String toString() => "PlexException: $message";
}

/// A client for a Plex Media Server's music libraries, signed in with an
/// `X-Plex-Token`: https://support.plex.tv/articles/204059436/
class PlexClient {
  PlexClient({
    required String server,
    required String token,
    HttpClient? client,
  }) : server = normalizeServer(server),
       // ignore: prefer_initializing_formals
       _token = token,
       _client = client ?? HttpClient();

  /// [server] without trailing slashes, and with `http://` when it names no
  /// scheme: `http://nas:32400`.
  static String normalizeServer(String server) {
    var text = server.trim();
    while (text.endsWith("/")) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isNotEmpty && !text.contains("://")) text = "http://$text";
    return text;
  }

  /// How many tracks one request asks for.
  static const pageSize = 500;

  /// The type of a track in Plex's `type=` filter.
  static const _trackType = 10;

  final String server;
  final String _token;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String> parameters = const {}]) {
    final base = Uri.parse("$server$path");
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        ...parameters,
        "X-Plex-Token": _token,
      },
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> parameters = const {},
  ]) async {
    try {
      final request = await _client
          .getUrl(_uri(path, parameters))
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set("Accept", "application/json")
        ..set("X-Plex-Client-Identifier", "amped")
        ..set("X-Plex-Product", "Amped");
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        throw const RemoteAuthException("The server refused the token.");
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw PlexException("HTTP ${response.statusCode}");
      }
      final text = await response.transform(utf8.decoder).join();
      final decoded = await decodeJson(text);
      if (decoded is! Map<String, dynamic> ||
          decoded["MediaContainer"] is! Map<String, dynamic>) {
        throw const PlexException("Not a Plex server.");
      }
      return decoded["MediaContainer"] as Map<String, dynamic>;
    } on FormatException {
      throw const PlexException("Not a Plex server.");
    } on SocketException catch (error) {
      throw PlexException(error.message);
    } on TimeoutException {
      throw const PlexException("The server did not answer.");
    } on HandshakeException catch (error) {
      throw PlexException(error.message);
    }
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const [];

  /// Throws when the server can't be reached or the token is refused.
  Future<void> ping() => _get("/library/sections");

  /// The keys of the music libraries (those of type "artist").
  Future<List<String>> musicSections() async {
    final body = await _get("/library/sections");
    return [
      for (final section in _list(body["Directory"]))
        if (section["type"] == "artist") "${section["key"]}",
    ];
  }

  /// Where the file [partKey] (`/library/parts/...`) is streamed from.
  String streamUrl(String partKey) => _uri(partKey).toString();

  /// Every track of every music library, a page at a time: [onPage] gets
  /// each page's tracks as they arrive. Their paths are [pathOf] of the
  /// track's part key. Stops after the page it is on when [isCancelled]
  /// says so.
  Future<void> tracks({
    required void Function(List<TrackTags> page) onPage,
    String Function(String partKey)? pathOf,
    bool Function()? isCancelled,
  }) async {
    for (final section in await musicSections()) {
      for (var offset = 0; ; offset += pageSize) {
        if (isCancelled?.call() ?? false) return;
        final body = await _get("/library/sections/$section/all", {
          "type": "$_trackType",
          "X-Plex-Container-Start": "$offset",
          "X-Plex-Container-Size": "$pageSize",
        });
        final items = _list(body["Metadata"]);
        final page = [
          for (final item in items) ?_track(item, pathOf ?? streamUrl),
        ];
        if (page.isNotEmpty) onPage(page);
        if (items.length < pageSize) break;
      }
    }
  }

  /// The keys of the libraries of the given Plex section [types]
  /// (`movie`, `show`).
  Future<List<({String key, String type})>> videoSections() async {
    final body = await _get("/library/sections");
    return [
      for (final section in _list(body["Directory"]))
        if (section["type"] == "movie" || section["type"] == "show")
          (key: "${section["key"]}", type: "${section["type"]}"),
    ];
  }

  /// Every movie and episode of the video libraries, a page at a time like
  /// [tracks]. Titles are the movie's, or "Show - S01E02 - Episode".
  Future<void> videos({
    required void Function(List<TrackTags> page) onPage,
    String Function(String partKey)? pathOf,
    bool Function()? isCancelled,
  }) async {
    for (final section in await videoSections()) {
      // 1 is a movie, 4 an episode.
      final type = section.type == "movie" ? 1 : 4;
      final summaries = section.type == "show"
          ? await _showSummaries(section.key)
          : const <String, String>{};
      for (var offset = 0; ; offset += pageSize) {
        if (isCancelled?.call() ?? false) return;
        final body = await _get("/library/sections/${section.key}/all", {
          "type": "$type",
          "X-Plex-Container-Start": "$offset",
          "X-Plex-Container-Size": "$pageSize",
        });
        final items = _list(body["Metadata"]);
        final page = [
          for (final item in items)
            ?_video(item, pathOf ?? streamUrl, summaries),
        ];
        if (page.isNotEmpty) onPage(page);
        if (items.length < pageSize) break;
      }
    }
  }

  /// What each show of the library [section] is about, by its key.
  Future<Map<String, String>> _showSummaries(String section) async {
    final summaries = <String, String>{};
    for (var offset = 0; ; offset += pageSize) {
      final body = await _get("/library/sections/$section/all", {
        "type": "2",
        "X-Plex-Container-Start": "$offset",
        "X-Plex-Container-Size": "$pageSize",
      });
      final items = _list(body["Metadata"]);
      for (final item in items) {
        final summary = item["summary"];
        if (summary is String && summary.isNotEmpty) {
          summaries["${item["ratingKey"]}"] = summary;
        }
      }
      if (items.length < pageSize) break;
    }
    return summaries;
  }

  TrackTags? _video(
    Map<String, dynamic> item,
    String Function(String partKey) pathOf,
    Map<String, String> summaries,
  ) {
    final track = _track(item, pathOf);
    if (track == null) return null;
    final show = item["grandparentTitle"] as String?;
    return TrackTags(
      track.path,
      artist: show,
      album: show == null ? null : item["parentTitle"] as String?,
      title: item["title"] as String?,
      trackNumber: track.trackNumber,
      discNumber: track.discNumber,
      year: track.year,
      duration: track.duration,
      bitrate: track.bitrate,
      channels: track.channels,
      genres: track.genres,
      imageUrl: _url(item["thumb"]) ?? track.imageUrl,
      published: _date(item["originallyAvailableAt"]),
      progress: _watched(item, track.duration),
      description: _text(item["summary"]),
      showDescription: summaries["${item["grandparentRatingKey"]}"],
      showImageUrl: show == null ? null : _url(item["grandparentThumb"]),
      seasonImageUrl: show == null ? null : _url(item["parentThumb"]),
      added: _epoch(item["addedAt"]),
      lastWatched: _epoch(item["lastViewedAt"]),
    );
  }

  String? _url(Object? path) =>
      path is String && path.isNotEmpty ? _uri(path).toString() : null;

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// A date written `2023-01-03`.
  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// A moment given in seconds since 1970.
  static DateTime? _epoch(Object? value) => value is num && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true)
      : null;

  /// How much was watched, 0 to 1 (1 when finished); null when not started.
  static double? _watched(Map<String, dynamic> item, Duration? length) {
    final offset = item["viewOffset"];
    if (offset is num &&
        offset > 0 &&
        length != null &&
        length > Duration.zero) {
      return (offset / length.inMilliseconds).clamp(0.0, 1.0).toDouble();
    }
    final count = item["viewCount"];
    return count is num && count > 0 ? 1.0 : null;
  }

  /// The video playlists of the server, each with the paths of its items
  /// ([pathOf] of their part keys), by name.
  Future<Map<String, List<String>>> videoPlaylists({
    String Function(String partKey)? pathOf,
  }) async {
    final lists = <String, List<String>>{};
    final body = await _get("/playlists", {"playlistType": "video"});
    for (final playlist in _list(body["Metadata"])) {
      final key = playlist["ratingKey"];
      final title = playlist["title"];
      if (key == null || title is! String) continue;
      final items = await _get("/playlists/$key/items");
      final paths = <String>[];
      for (final item in _list(items["Metadata"])) {
        final track = _track(item, pathOf ?? streamUrl);
        if (track != null) paths.add(track.path);
      }
      lists[title] = paths;
    }
    return lists;
  }

  /// The track of [item], or null when it has no file.
  TrackTags? _track(
    Map<String, dynamic> item,
    String Function(String partKey) pathOf,
  ) {
    int? number(Object? value) => switch (value) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    final media = _list(item["Media"]);
    final first = media.isEmpty ? null : media.first;
    final parts = first == null
        ? const <Map<String, dynamic>>[]
        : _list(first["Part"]);
    final key = parts.isEmpty ? null : parts.first["key"];
    if (key is! String) return null;
    final milliseconds = number(item["duration"]) ?? number(first?["duration"]);
    return TrackTags(
      pathOf(key),
      artist: (item["originalTitle"] ?? item["grandparentTitle"]) as String?,
      album: item["parentTitle"] as String?,
      title: item["title"] as String?,
      trackNumber: number(item["index"]),
      discNumber: number(item["parentIndex"]),
      year: number(item["parentYear"] ?? item["year"]),
      duration: milliseconds == null
          ? null
          : Duration(milliseconds: milliseconds),
      bitrate: number(first?["bitrate"]),
      channels: number(first?["audioChannels"]),
      genres: [
        for (final genre in _list(item["Genre"]))
          if (genre["tag"] is String) genre["tag"] as String,
      ],
      imageUrl: _thumbUrl(item),
      artistImageUrl: _url(item["grandparentThumb"]),
    );
  }

  /// Where the picture of [item] is: its own, else its album's or show's.
  String? _thumbUrl(Map<String, dynamic> item) {
    for (final key in const ["thumb", "parentThumb", "grandparentThumb"]) {
      final thumb = item[key];
      if (thumb is String && thumb.isNotEmpty) return _uri(thumb).toString();
    }
    return null;
  }

  void close() => _client.close(force: true);
}
