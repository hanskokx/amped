import "dart:convert";
import "dart:io";

import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/video_engine.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_audiobookshelf/amped_audiobookshelf.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _MemoryStore implements RemoteCredentialStore {
  final Map<String, RemoteLogin> logins = {};

  @override
  Future<RemoteLogin?> read(String server) async => logins[server];

  @override
  Future<void> write(String server, RemoteLogin login) async =>
      logins[server] = login;

  @override
  Future<void> delete(String server) async => logins.remove(server);
}

class _FakeAudio extends AudioEngine {
  final List<String> played = [];

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async {
    played.add(location);
    return const Duration(seconds: 10);
  }

  @override
  Future<void> stop() async {}
}

class _FakeVideo extends VideoEngine {
  final List<String> played = [];
  final List<Duration> seeks = [];

  @override
  bool get active => false;

  @override
  Size? get videoSize => null;

  @override
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  @override
  Future<String?> extractAudio(String location) async => null;

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double balance,
    required VoidCallback onFinished,
    String? audioLocation,
  }) async {
    played.add(location);
    return const Duration(minutes: 30);
  }

  @override
  Duration get position => Duration.zero;

  @override
  void setVolume(double volume) {}

  @override
  void setBalance(double balance) {}

  @override
  void setPaused(bool paused) {}

  @override
  void seek(Duration position) => seeks.add(position);

  @override
  Future<void> stop() async {}
}

void main() {
  late HttpServer http;
  late List<Map<String, dynamic>> patches;

  String address() => "http://127.0.0.1:${http.port}";

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    patches = [];
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) {
      final response = request.response;
      final path = request.uri.path;
      void json(Object body) => response
        ..write(jsonEncode(body))
        ..close();
      if (request.headers.value("Authorization") != "Bearer abs-token" &&
          path.startsWith("/api/")) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..close();
      } else if (request.method == "PATCH" &&
          path == "/api/me/progress/book1") {
        utf8.decoder.bind(request).join().then((body) {
          patches.add(jsonDecode(body) as Map<String, dynamic>);
          response.close();
        });
      } else if (path == "/api/libraries") {
        json({
          "libraries": [
            {"id": "b", "mediaType": "book"},
            {"id": "p", "mediaType": "podcast"},
          ],
        });
      } else if (path == "/api/libraries/b/items") {
        json({
          "results": [
            {"id": "book1"},
          ],
        });
      } else if (path == "/api/libraries/p/items") {
        json({"results": <Object>[]});
      } else if (path == "/api/me") {
        json({
          "mediaProgress": [
            // 90 seconds into the book: all of the first file (60 s) and 30
            // of the second.
            {"libraryItemId": "book1", "currentTime": 90, "isFinished": false},
          ],
        });
      } else if (path == "/api/me/progress/book1") {
        json({"currentTime": 90, "isFinished": false});
      } else if (path == "/api/items/book1") {
        json({
          "id": "book1",
          "mediaType": "book",
          "media": {
            "metadata": {
              "title": "The Book",
              "authorName": "An Author",
              "narratorName": "A Narrator",
              "description": "<p>About <b>it</b>.</p>",
              "genres": ["Fantasy"],
              "series": [
                {"name": "The Saga", "sequence": "1"},
              ],
            },
            "chapters": [
              {"start": 0, "end": 30, "title": "Opening"},
              {"start": 30, "end": 70, "title": "Rising"},
              // In the second file, 10 seconds into it.
              {"start": 70, "end": 150, "title": "Middle"},
            ],
            "audioFiles": [
              // Out of order, as a server may list them.
              {
                "index": 2,
                "ino": "f2",
                "duration": 100,
                "metadata": {"ext": ".m4b"},
              },
              {
                "index": 1,
                "ino": "f1",
                "duration": 60,
                "metadata": {"ext": ".m4b"},
                "metaTags": {"tagTitle": "Intro"},
              },
            ],
          },
        });
      } else {
        response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  });

  tearDown(() => http.close(force: true));

  AudiobookshelfClient client() =>
      AudiobookshelfClient(server: address(), token: "abs-token");

  test("the audio files of a book are its tracks, in order", () async {
    final abs = client();
    final pages = <List<TrackTags>>[];
    await abs.books(onPage: pages.add, pathOf: (id) => "loc:$id");
    abs.close();
    final tracks = pages.single;
    expect(tracks.map((t) => t.path), ["loc:book1|f1.m4b", "loc:book1|f2.m4b"]);
    expect(tracks.map((t) => t.title), ["Intro", "Part 2"]);
    expect(tracks.map((t) => t.trackNumber), [1, 2]);
    expect(tracks.every((t) => t.album == "The Book"), isTrue);
    expect(tracks.every((t) => t.artist == "An Author"), isTrue);
    expect(tracks.first.genres, ["Audiobook", "Fantasy"]);
    expect(tracks.first.duration, const Duration(seconds: 60));
    expect(tracks.first.imageUrl, contains("/api/items/book1/cover"));
    expect(
      tracks.first.showDescription,
      "Narrated by A Narrator\n\nAbout it.",
    );
    expect(tracks.every((t) => t.series == "The Saga"), isTrue);
    // The chapters are listed with the part they start in, timed from its
    // start.
    expect(tracks.first.description, "Chapters\n0:00  Opening\n0:30  Rising");
    expect(tracks.last.description, "Chapters\n0:10  Middle");
    // 90 seconds into the book: the first file is all heard, 30 of the
    // second's 100 seconds.
    expect(tracks.first.progress, 1);
    expect(tracks.last.progress, closeTo(0.3, 0.001));
  });

  test("the series is read from its name when that is all the server says", () {
    final abs = client();
    final tracks = abs.bookTracks({
      "id": "x",
      "media": {
        "metadata": {"title": "Two", "seriesName": "Big Saga #2"},
        "audioFiles": [
          {"ino": "a", "duration": 10},
        ],
      },
    }, (id) => id);
    abs.close();
    expect(tracks.single.series, "Big Saga");
    expect(tracks.single.description, isNull);
  });

  test("a book with one file is named by the book", () {
    final abs = client();
    final tracks = abs.bookTracks({
      "id": "x",
      "media": {
        "metadata": {"title": "Short"},
        "audioFiles": [
          {
            "ino": "only",
            "duration": 10,
            "metadata": {"ext": ".mp3"},
          },
        ],
      },
    }, (id) => id);
    abs.close();
    expect(tracks.single.title, "Short");
    // MP3 is played as it is: no extension marks it.
    expect(tracks.single.path, "x|only");
  });

  test(
    "where the user stopped is the book's position within the file",
    () async {
      final abs = client();
      // 90 s into the book: past the first file, 30 s into the second.
      expect(
        await abs.resumePosition("book1|f2.m4b"),
        const Duration(seconds: 30),
      );
      expect(await abs.resumePosition("book1|f1.m4b"), isNull);
      expect(
        abs.streamUrl("book1|f2.m4b"),
        contains("/api/items/book1/file/f2?"),
      );
      abs.close();
    },
  );

  test(
    "progress is told to the server as the position in the whole book",
    () async {
      final abs = client();
      await abs.reportProgress(
        "book1|f2.m4b",
        const Duration(seconds: 50),
        const Duration(seconds: 100),
        finished: false,
      );
      await abs.reportProgress(
        "book1|f1.m4b",
        const Duration(seconds: 60),
        const Duration(seconds: 60),
        finished: true,
      );
      await abs.reportProgress(
        "book1|f2.m4b",
        const Duration(seconds: 100),
        const Duration(seconds: 100),
        finished: true,
      );
      abs.close();
      expect(patches[0]["currentTime"], 110);
      expect(patches[0]["duration"], 160);
      expect(patches[0]["isFinished"], isFalse);
      // The end of the first of two files is not the end of the book.
      expect(patches[1]["currentTime"], 60);
      expect(patches[1]["isFinished"], isFalse);
      expect(patches[2]["currentTime"], 160);
      expect(patches[2]["isFinished"], isTrue);
      expect(patches[2]["progress"], 1);
    },
  );

  test("a server's books are a source of their own in the tree", () async {
    final manager = LibrarySourceManager(
      local: MediaLibrary(readTags: (files) async => const []),
      credentials: _MemoryStore(),
    );
    addTearDown(manager.dispose);
    final config = await manager.addAudiobookshelf(
      name: "Shelf",
      server: address(),
      token: "abs-token",
    );
    final section = manager.sections(localLabel: "L").last;
    expect(section.kind, LibrarySourceKind.audiobooks);
    final source = section.sources.single;
    expect(source.id, "$bookSourcePrefix${config.id}");
    expect(source.audiobooks, isTrue);
    expect(source.podcast, isTrue);
    expect(source.library!.tracks, isEmpty);
    // Opening it loads the books.
    await manager.openBooks(config.id);
    final books = manager
        .sections(localLabel: "L")
        .last
        .sources
        .single
        .library!;
    expect(books.tracks, hasLength(2));
    expect(manager.isPodcast(books.tracks.first.path), isTrue);
    // And finishing a part is kept and shown.
    final first = books.tracks.firstWhere((t) => t.trackNumber == 2).path;
    await manager.saveProgress(
      first,
      const Duration(seconds: 50),
      const Duration(seconds: 100),
    );
    expect(books.tagsOf(first)!.progress, 0.5);
    expect(patches.single["currentTime"], 110);
  });

  test("AAC in a source is told by the extension its id ends with", () {
    expect(
      SourceLocation.playsInVideoEngine(SourceLocation.build("s", "b|1.m4b")),
      isTrue,
    );
    expect(
      SourceLocation.playsInVideoEngine(SourceLocation.build("s", "b|1.M4A")),
      isTrue,
    );
    expect(
      SourceLocation.playsInVideoEngine(SourceLocation.build("s", "b|1.mp3")),
      isFalse,
    );
    expect(
      SourceLocation.playsInVideoEngine(SourceLocation.build("s", "b|1")),
      isFalse,
    );
    expect(SourceLocation.playsInVideoEngine("/music/a.m4a"), isFalse);
  });

  group("playing", () {
    late _FakeAudio audio;
    late _FakeVideo video;

    setUp(() {
      audio = _FakeAudio();
      video = _FakeVideo();
      SourceLocation.resolver = (location) async => "https://srv/signed";
      addTearDown(() => SourceLocation.resolver = null);
    });

    test("an m4b of a source plays in the video engine from its address, "
        "resuming where it was left", () async {
      final player = PlayerState(engine: audio, video: video);
      addTearDown(player.stop);
      await player.playlist.add([SourceLocation.build("abs", "book1|f2.m4b")]);
      player.resumeOffer = (entry) async => const Duration(minutes: 12);
      await player.playIndex(0);
      expect(video.played, ["https://srv/signed"]);
      expect(audio.played, isEmpty);
      expect(video.seeks, [const Duration(minutes: 12)]);
      expect(player.elapsedSec, 720);
    });

    test("an mp3 of a source stays with the audio engine", () async {
      final player = PlayerState(engine: audio, video: video);
      addTearDown(player.stop);
      await player.playlist.add([SourceLocation.build("abs", "book1|f2.mp3")]);
      await player.playIndex(0);
      expect(video.played, isEmpty);
      expect(audio.played, hasLength(1));
    });
  });
}
