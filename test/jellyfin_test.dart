import "dart:convert";
import "dart:io";

import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_jellyfin/amped_jellyfin.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A Jellyfin server with [songCount] tracks, one movie and one user.
class _FakeJellyfin {
  _FakeJellyfin();

  final int songCount = 3;
  late final HttpServer _http;
  final List<Uri> requests = [];

  String get address => "http://127.0.0.1:${_http.port}";

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      requests.add(request.uri);
      Future<void> reply(Object body, [int status = HttpStatus.ok]) async {
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
        await request.response.close();
      }

      if (request.uri.path == "/Users/AuthenticateByName") {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        if (body["Username"] != "hans" || body["Pw"] != "secret") {
          return reply({}, HttpStatus.unauthorized);
        }
        return reply({
          "AccessToken": "tok3n",
          "User": {"Id": "u1"},
        });
      }
      if (!(request.headers.value("Authorization") ?? "").contains(
        'Token="tok3n"',
      )) {
        return reply({}, HttpStatus.unauthorized);
      }
      final query = request.uri.queryParameters;
      if (request.uri.path == "/Users/u1/Items") {
        final types = query["IncludeItemTypes"];
        final start = int.parse(query["StartIndex"]!);
        final limit = int.parse(query["Limit"]!);
        if (types == "Audio") {
          return reply({
            "Items": [
              for (var i = start; i < songCount && i < start + limit; i++)
                {
                  "Id": "song$i",
                  "Name": "Song $i",
                  "AlbumArtist": i.isEven ? "Alpha" : "Beta",
                  "Album": "Album ${i % 2}",
                  "IndexNumber": i,
                  "ParentIndexNumber": 1,
                  "RunTimeTicks": (180 + i) * 10000000,
                  "Genres": ["Rock"],
                  "AlbumId": "album${i % 2}",
                  "AlbumPrimaryImageTag": "t",
                  "MediaSources": [
                    {
                      "Path": "/music/$i.${i == 2 ? "m4a" : "flac"}",
                      "Bitrate": 320000,
                      "MediaStreams": [
                        {"Type": "Audio", "Channels": 2},
                      ],
                    },
                  ],
                },
            ],
          });
        }
        if (types == "Movie,Episode") {
          return reply({
            "Items": [
              {
                "Id": "movie1",
                "Name": "A Movie",
                "RunTimeTicks": 6000 * 10000000,
                "Overview": "About things.",
                "UserData": {"PlaybackPositionTicks": 3000 * 10000000},
                "MediaSources": [
                  {"Path": "/movies/a.mkv"},
                ],
              },
            ],
          });
        }
        return reply({"Items": []});
      }
      await reply({}, HttpStatus.notFound);
    });
  }

  Future<void> close() => _http.close(force: true);
}

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

void main() {
  late _FakeJellyfin server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _FakeJellyfin();
    await server.start();
  });

  tearDown(() => server.close());

  test("the server address is tidied", () {
    expect(JellyfinClient.normalizeServer(" nas:8096/ "), "http://nas:8096");
  });

  test("a wrong password is refused", () async {
    final client = JellyfinClient(
      server: server.address,
      user: "hans",
      password: "nope",
    );
    await expectLater(client.ping(), throwsA(isA<RemoteAuthException>()));
    client.close();
  });

  test("tracks and videos are read", () async {
    final client = JellyfinClient(
      server: server.address,
      user: "hans",
      password: "secret",
    );
    final tracks = <TrackTags>[];
    await client.tracks(onPage: tracks.addAll);
    expect(tracks.length, 3);
    final first = tracks.first;
    expect(first.path, "song0.flac");
    expect(first.title, "Song 0");
    expect(first.artist, "Alpha");
    expect(first.album, "Album 0");
    expect(first.duration, const Duration(seconds: 180));
    expect(first.bitrate, 320);
    expect(first.channels, 2);
    expect(first.genres, ["Rock"]);
    expect(first.imageUrl, contains("/Items/album0/Images/Primary"));
    expect(tracks.last.path, "song2.m4a");

    final videos = <TrackTags>[];
    await client.videos(onPage: videos.addAll);
    expect(videos.single.title, "A Movie");
    expect(videos.single.path, "movie1.mkv");
    expect(videos.single.progress, 0.5);
    expect(videos.single.description, "About things.");

    expect(
      Uri.parse(await client.streamUrl("song0.flac")).queryParameters,
      {"api_key": "tok3n"},
    );
    client.close();
  });

  group("LibrarySourceManager", () {
    late _MemoryStore store;
    late LibrarySourceManager manager;

    setUp(() {
      store = _MemoryStore();
      manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: store,
      );
    });

    tearDown(() => manager.dispose());

    Future<RemoteSourceConfig> add() => manager.addJellyfin(
      name: "Jelly",
      server: server.address,
      user: "hans",
      password: "secret",
    );

    test("a refused password adds nothing", () async {
      await expectLater(
        manager.addJellyfin(
          name: "Jelly",
          server: server.address,
          user: "hans",
          password: "bad",
        ),
        throwsA(isA<RemoteAuthException>()),
      );
      expect(manager.remotes, isEmpty);
      expect(store.logins, isEmpty);
    });

    test("an added server loads when opened and plays signed", () async {
      final config = await add();
      expect(config.type, RemoteSourceType.jellyfin);
      final source = manager.sections(localLabel: "Local").last.sources.single;
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNull);
      expect(source.library!.tracks.length, 3);
      expect(source.library!.artists, ["Alpha", "Beta"]);

      final track = source.library!.tracks.first;
      expect(SourceLocation.isSource(track.path), isTrue);
      expect(track.path, isNot(contains("tok3n")));
      final url = Uri.parse(await manager.resolve(track.path));
      expect(url.path, "/Items/song0/Download");
      expect(url.queryParameters["api_key"], "tok3n");

      await manager.remove(config.id);
      expect(store.logins, isEmpty);
    });

    test("sources survive a restart", () async {
      await add();
      final again = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: store,
      );
      await again.restore(await SharedPreferences.getInstance());
      expect(again.remotes.single.type, RemoteSourceType.jellyfin);
      again.dispose();
    });
  });
}
