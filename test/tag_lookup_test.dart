import "dart:io";
import "dart:math" as math;
import "dart:typed_data";

import "package:amped/src/tags/tag_lookup.dart";
import "package:amped/src/tags/tag_model.dart";
import "package:chromaprint_dart/chromaprint_dart.dart";
import "package:flutter_test/flutter_test.dart";

/// Recorded responses: the MusicBrainz ones are real lookups, the AcoustID
/// error is a real reply to a bad key, and the AcoustID match follows the
/// documented `/v2/lookup` format (a real one needs a real key).
String fixture(String name) =>
    File("test/fixtures/tag_lookup/$name").readAsStringSync();

const nevermind = "a10a1bb0-c828-495b-9436-5010d5e4a14b";
const abbeyRoad = "73361485-b84f-459f-9549-b1ba20bc50d2";

Matcher failsWith(TagLookupFailure failure) => throwsA(
  isA<TagLookupException>().having((e) => e.failure, "failure", failure),
);

void main() {
  group("fingerprinting", () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync("tag_lookup"));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Five seconds of a stereo chord at 44.1 kHz, as a WAV file.
    (String, Int16List) writeWav() {
      const rate = 44100;
      final samples = Int16List(rate * 5 * 2);
      for (var f = 0; f < rate * 5; f++) {
        final t = f / rate;
        final step = (t * 2).floor();
        samples[f * 2] = (8000 * math.sin(2 * math.pi * (220 + 55 * step) * t))
            .round();
        samples[f * 2 + 1] = (8000 * math.sin(2 * math.pi * 330 * t)).round();
      }
      final data = samples.buffer.asUint8List();
      final header = ByteData(44)
        ..setUint32(0, 0x52494646)
        ..setUint32(4, 36 + data.length, Endian.little)
        ..setUint32(8, 0x57415645)
        ..setUint32(12, 0x666d7420)
        ..setUint32(16, 16, Endian.little)
        ..setUint16(20, 1, Endian.little)
        ..setUint16(22, 2, Endian.little)
        ..setUint32(24, rate, Endian.little)
        ..setUint32(28, rate * 4, Endian.little)
        ..setUint16(32, 4, Endian.little)
        ..setUint16(34, 16, Endian.little)
        ..setUint32(36, 0x64617461)
        ..setUint32(40, data.length, Endian.little);
      final path = "${dir.path}/chord.wav";
      File(path).writeAsBytesSync([...header.buffer.asUint8List(), ...data]);
      return (path, samples);
    }

    test("decodes every channel and fingerprints in the background", () async {
      final (path, samples) = writeWav();
      final fp = await chromaprintFingerprint(path);
      expect(fp.duration, 5);
      expect(
        fp.fingerprint,
        Chromaprint()
            .fingerprint(
              samples,
              sampleRate: 44100,
              channels: 2,
            )
            .toString(),
      );
      expect(fp.fingerprint, startsWith("AQAA"));
    });

    test(
      "a cached fingerprint is used as is; only the length is read",
      () async {
        final (path, _) = writeWav();
        final fp = await chromaprintFingerprint(path, cached: "AQADcached");
        expect(fp.fingerprint, "AQADcached");
        expect(fp.duration, 5);
      },
    );

    test("a file that can't be decoded is reported as such", () async {
      final path = "${dir.path}/notes.txt";
      File(path).writeAsStringSync("not audio");
      await expectLater(
        chromaprintFingerprint(path),
        failsWith(TagLookupFailure.fingerprintFailed),
      );
    });
  });

  group("AcoustID", () {
    test("lists matches best first, without duplicates or empty ones", () {
      final matches = parseAcoustIdResponse(fixture("acoustid_lookup.json"));
      expect(matches, hasLength(2));
      expect(matches[0].score, closeTo(0.972, 0.001));
      expect(matches[0].recordingIds, [nevermind]);
      expect(matches[1].recordingIds, [abbeyRoad]);
    });

    test("no results is an empty list", () {
      expect(parseAcoustIdResponse(fixture("acoustid_no_results.json")), []);
    });

    test("a rejected key is told apart from other errors", () {
      expect(
        () => parseAcoustIdResponse(fixture("acoustid_invalid_key.json")),
        failsWith(TagLookupFailure.invalidApiKey),
      );
      expect(
        () => parseAcoustIdResponse(
          '{"status": "error", "error": {"code": 3, "message": "bad fp"}}',
        ),
        failsWith(TagLookupFailure.network),
      );
    });

    test("the form carries the key, duration and fingerprint", () {
      final form = acoustIdForm(
        "KEY",
        const AudioFingerprint(duration: 290, fingerprint: "AQAD"),
      );
      expect(form, containsPair("client", "KEY"));
      expect(form, containsPair("duration", "290"));
      expect(form, containsPair("fingerprint", "AQAD"));
      expect(form, containsPair("meta", "recordingids"));
    });
  });

  group("MusicBrainz", () {
    test("a release's tags: track and disc, album artist, year", () {
      final candidates = parseMusicBrainzRecording(
        fixture("musicbrainz_recording_abbey_road.json"),
        score: 0.5,
      );
      expect(candidates, hasLength(1));
      final candidate = candidates.single;
      expect(candidate.fields, {
        TagField.title: "Here Comes The Sun",
        TagField.artist: "The Beatles",
        TagField.album: "Abbey Road",
        TagField.albumArtist: "The Beatles",
        TagField.year: "1969",
        TagField.track: "5/12",
        TagField.disc: "1",
      });
      expect(candidate.score, 0.5);
      expect(candidate.recordingId, abbeyRoad);
      expect(candidate.releaseType, "Album");
    });

    test("releases are ordered and identical tags shown once", () {
      final candidates = parseMusicBrainzRecording(
        fixture("musicbrainz_recording_nevermind.json"),
      );
      // Seven releases, but several editions tag the same way.
      expect(candidates.length, lessThan(7));
      final first = candidates.first;
      expect(first.date, "1991-09-24");
      expect(
        first[TagField.album],
        "Nevermind (30th Anniversary Super Deluxe)",
      );
      // The position on the medium, as Picard writes it, not the printed
      // number ("5").
      expect(first[TagField.track], "18/75");
      expect(
        first[TagField.title],
        "Smells Like Teen Spirit (Live In Amsterdam)",
      );
      // The genre with the most votes, title-cased.
      expect(first[TagField.genre], "Grunge");
      expect(first.releaseStatus, "Official");
      final dates = [for (final c in candidates) c.date ?? ""];
      expect(dates, orderedEquals([...dates]..sort()));
      final keys = {for (final c in candidates) c.fields.toString()};
      expect(keys, hasLength(candidates.length));
    });

    test("a recording on no release still gives its title and artist", () {
      final candidates = parseMusicBrainzRecording(
        '{"id": "x", "title": "Demo", "artist-credit": [ '
        '{"name": "A", "joinphrase": " feat. "}, {"name": "B"}], '
        '"releases": []}',
      );
      expect(candidates.single.fields, {
        TagField.title: "Demo",
        TagField.artist: "A feat. B",
      });
    });
  });

  group("the lookup", () {
    late List<(Uri, Map<String, String>?)> requests;
    late List<Duration> waits;
    late int fingerprinted;
    late List<String> cachedSeen;

    TagLookup lookup(
      String apiKey,
      Map<String, List<LookupResponse>> responses,
    ) {
      requests = [];
      waits = [];
      fingerprinted = 0;
      cachedSeen = [];
      return TagLookup(
        apiKey: apiKey,
        fingerprint: (path, {cached = ""}) async {
          fingerprinted++;
          cachedSeen.add(cached);
          return AudioFingerprint(
            duration: 290,
            fingerprint: cached.isEmpty ? "AQAD" : cached,
          );
        },
        http: (uri, {form}) async {
          requests.add((uri, form));
          final queue = responses[uri.path]!;
          return queue.length > 1 ? queue.removeAt(0) : queue.single;
        },
        wait: (duration) async => waits.add(duration),
      );
    }

    test("without a key it explains, before fingerprinting", () async {
      final run = lookup("  ", {});
      await expectLater(
        run("/a.mp3"),
        failsWith(TagLookupFailure.missingApiKey),
      );
      expect(fingerprinted, 0);
      expect(requests, isEmpty);
    });

    test("fingerprint, AcoustID, then MusicBrainz per recording", () async {
      final run = lookup("KEY", {
        "/v2/lookup": [LookupResponse(200, fixture("acoustid_lookup.json"))],
        "/ws/2/recording/$nevermind": [
          LookupResponse(200, fixture("musicbrainz_recording_nevermind.json")),
        ],
        "/ws/2/recording/$abbeyRoad": [
          LookupResponse(200, fixture("musicbrainz_recording_abbey_road.json")),
        ],
      });
      final result = await run("/a.mp3");
      final candidates = result.candidates;
      expect(result.fingerprint.fingerprint, "AQAD");

      expect(requests[0].$1, acoustIdLookupUri);
      expect(requests[0].$2, containsPair("client", "KEY"));
      expect(requests[1].$1.host, "musicbrainz.org");
      expect(requests[1].$1.queryParameters["inc"], contains("releases"));
      expect(requests.map((r) => r.$1.path), [
        "/v2/lookup",
        "/ws/2/recording/$nevermind",
        "/ws/2/recording/$abbeyRoad",
      ]);
      // MusicBrainz is asked at most once a second.
      expect(waits, [TagLookup.musicBrainzInterval]);
      expect(candidates.first.recordingId, nevermind);
      expect(candidates.last[TagField.album], "Abbey Road");
      expect(candidates.last.score, closeTo(0.512, 0.001));
    });

    test("AcoustID's 400 for a bad key reads as a bad key", () async {
      final run = lookup("WRONG", {
        "/v2/lookup": [
          LookupResponse(400, fixture("acoustid_invalid_key.json")),
        ],
      });
      await expectLater(
        run("/a.mp3"),
        failsWith(TagLookupFailure.invalidApiKey),
      );
    });

    test("no AcoustID match means no candidates and no MusicBrainz", () async {
      final run = lookup("KEY", {
        "/v2/lookup": [
          LookupResponse(200, fixture("acoustid_no_results.json")),
        ],
      });
      expect((await run("/a.mp3")).candidates, isEmpty);
      expect(requests, hasLength(1));
    });

    test("a fingerprint cached in the tags is passed on and sent", () async {
      final run = lookup("KEY", {
        "/v2/lookup": [
          LookupResponse(200, fixture("acoustid_no_results.json")),
        ],
      });
      final result = await run("/a.mp3", cachedFingerprint: " AQADcached ");
      expect(cachedSeen, ["AQADcached"]);
      expect(requests.single.$2, containsPair("fingerprint", "AQADcached"));
      expect(result.fingerprint.fingerprint, "AQADcached");
    });

    test("MusicBrainz's 503 is retried once", () async {
      final run = lookup("KEY", {
        "/v2/lookup": [
          const LookupResponse(
            200,
            '{"status": "ok", "results": [{"score": 1, '
            '"recordings": [{"id": "$abbeyRoad"}]}]}',
          ),
        ],
        "/ws/2/recording/$abbeyRoad": [
          const LookupResponse(503, "slow down"),
          LookupResponse(200, fixture("musicbrainz_recording_abbey_road.json")),
        ],
      });
      final candidates = (await run("/a.mp3")).candidates;
      expect(candidates.single[TagField.album], "Abbey Road");
      expect(waits, [const Duration(seconds: 2)]);
    });

    test("an unreachable service is a network failure", () async {
      final run = TagLookup(
        apiKey: "KEY",
        fingerprint: (_, {cached = ""}) async =>
            const AudioFingerprint(duration: 1, fingerprint: "AQAD"),
        http: (uri, {form}) async =>
            throw const SocketException("Failed host lookup"),
      );
      await expectLater(run("/a.mp3"), failsWith(TagLookupFailure.network));
    });
  });
}
