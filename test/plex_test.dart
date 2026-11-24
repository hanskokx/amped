import "dart:convert";
import "dart:io";

import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_plex/amped_plex.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A Plex server with a music library of [songCount] tracks, a movie library,
/// and one valid token.
class _FakePlex {
  _FakePlex({this.songCount = 3});

  final int songCount;
  late final HttpServer _http;
  final List<Uri> requests = [];

  String get address => "http://127.0.0.1:${_http.port}";

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) {
      requests.add(request.uri);
      final query = request.uri.queryParameters;
      if (query["X-Plex-Token"] != "tok3n") {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..close();
        return;
      }
      Map<String, dynamic> container;
      if (request.uri.path == "/library/sections") {
        container = {
          "Directory": [
            {"key": "1", "type": "movie", "title": "Movies"},
            {"key": "2", "type": "artist", "title": "Music"},
          ],
        };
      } else if (request.uri.path == "/library/sections/2/all") {
        final offset = int.parse(query["X-Plex-Container-Start"]!);
        final size = int.parse(query["X-Plex-Container-Size"]!);
        container = {
          "Metadata": [
            for (var i = offset; i < songCount && i < offset + size; i++)
              {
                "ratingKey": "$i",
                "title": "Song $i",
                "grandparentTitle": i.isEven ? "Alpha" : "Beta",
                "parentTitle": "Album ${i % 2}",
                "index": i,
                "parentIndex": 1,
                "duration": 180000 + i * 1000,
                "Genre": [
                  {"tag": "Rock"},
                ],
                "Media": [
                  {
                    "bitrate": 320,
                    "audioChannels": 2,
                    "Part": [
                      {"key": "/library/parts/$i/1/file.mp3"},
                    ],
                  },
                ],
              },
          ],
        };
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"MediaContainer": container}))
        ..close();
    });
  }

  Future<void> stop() => _http.close(force: true);
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
  late _FakePlex server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _FakePlex();
    await server.start();
  });

  tearDown(() => server.stop());

  PlexClient client({String token = "tok3n"}) =>
      PlexClient(server: "${server.address}/", token: token);

  test("a wrong token is an auth error", () async {
    await expectLater(
      client(token: "nope").ping(),
      throwsA(isA<RemoteAuthException>()),
    );
  });

  test("something that is not a Plex server is reported", () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    other.listen(
      (request) => request.response
        ..write("<html>")
        ..close(),
    );
    final bad = PlexClient(server: "127.0.0.1:${other.port}", token: "x");
    await expectLater(bad.ping(), throwsA(isA<PlexException>()));
    await other.close(force: true);
  });

  test("lists the tracks of the music libraries only, with tags", () async {
    await server.stop();
    server = _FakePlex(songCount: PlexClient.pageSize + 2);
    await server.start();
    final pages = <List<TrackTags>>[];
    await client().tracks(onPage: pages.add);
    expect(pages.map((p) => p.length), [PlexClient.pageSize, 2]);
    expect(
      server.requests.where((r) => r.path.startsWith("/library/sections/1")),
      isEmpty,
    );
    final first = pages.first.first;
    expect(first.title, "Song 0");
    expect(first.artist, "Alpha");
    expect(first.album, "Album 0");
    expect(first.trackNumber, 0);
    expect(first.duration, const Duration(seconds: 180));
    expect(first.bitrate, 320);
    expect(first.channels, 2);
    expect(first.genres, ["Rock"]);
    expect(first.path, contains("/library/parts/0/1/file.mp3"));
  });

  test("signs in through a PIN approved on the website", () async {
    var polls = 0;
    final plexTv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plexTv.listen((request) {
      Object body;
      if (request.method == "POST" && request.uri.path == "/api/v2/pins") {
        body = {"id": 7, "code": "ABCD"};
      } else if (request.uri.path == "/api/v2/pins/7") {
        body = {"authToken": ++polls < 3 ? null : "tok3n"};
      } else if (request.uri.path == "/api/v2/resources") {
        expect(request.headers.value("X-Plex-Token"), "tok3n");
        body = [
          {
            "provides": "server",
            "owned": false,
            "connections": [
              {"uri": "https://shared.example", "relay": false},
            ],
          },
          {
            "provides": "server",
            "owned": true,
            "connections": [
              {"uri": "https://relay.example", "relay": true},
              {"uri": "http://192.168.1.2:32400", "relay": false},
            ],
          },
          {"provides": "player", "connections": []},
        ];
      } else {
        body = {};
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    final signIn = PlexSignIn(
      api: "http://127.0.0.1:${plexTv.port}",
      web: "https://app.plex.tv",
      clientId: "amped-test",
    );
    Uri? opened;
    final token = await signIn.signIn(
      (url) async => opened = url,
      interval: const Duration(milliseconds: 5),
    );
    expect(opened!.host, "app.plex.tv");
    expect(opened!.fragment, contains("code=ABCD"));
    expect(opened!.fragment, contains("clientID=amped-test"));
    expect(token, "tok3n");
    expect(polls, 3);
    expect(await signIn.servers("tok3n"), [
      "http://192.168.1.2:32400",
      "https://shared.example",
    ]);
    signIn.close();
    await plexTv.close(force: true);
  });

  test("lists the Plex Home users and switches to one with its PIN", () async {
    final plexTv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plexTv.listen((request) {
      Object body = {};
      var status = 200;
      if (request.uri.path == "/api/v2/home/users") {
        body = {
          "users": [
            {"uuid": "u1", "title": "Dad", "protected": false},
            {"uuid": "u2", "title": "Kid", "protected": true},
          ],
        };
      } else if (request.method == "POST" &&
          request.uri.path == "/api/v2/home/users/u2/switch") {
        if (request.uri.queryParameters["pin"] == "1234") {
          body = {"authToken": "kid-token"};
        } else {
          status = 403;
        }
      }
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
    final signIn = PlexSignIn(api: "http://127.0.0.1:${plexTv.port}");
    final users = await signIn.homeUsers("tok3n");
    expect(users.map((user) => user.name), ["Dad", "Kid"]);
    expect(users.map((user) => user.protected), [false, true]);
    expect(
      await signIn.switchUser("tok3n", users[1], pin: "1234"),
      "kid-token",
    );
    await expectLater(
      signIn.switchUser("tok3n", users[1], pin: "0000"),
      throwsA(isA<PlexException>()),
    );
    signIn.close();
    await plexTv.close(force: true);
  });

  test("giving up waiting for the approval throws", () async {
    final plexTv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plexTv.listen(
      (request) => request.response
        ..write(jsonEncode({"id": 1, "code": "X", "authToken": null}))
        ..close(),
    );
    final signIn = PlexSignIn(api: "http://127.0.0.1:${plexTv.port}");
    await expectLater(
      signIn.signIn(
        (url) async {},
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<BrowserSignInException>()),
    );
    signIn.close();
    await plexTv.close(force: true);
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

    Future<RemoteSourceConfig> add() =>
        manager.addPlex(name: "Plex", server: server.address, token: "tok3n");

    test("a refused token adds nothing", () async {
      await expectLater(
        manager.addPlex(name: "Plex", server: server.address, token: "bad"),
        throwsA(isA<RemoteAuthException>()),
      );
      expect(manager.remotes, isEmpty);
      expect(store.logins, isEmpty);
    });

    test("an added server loads when opened and plays signed", () async {
      final config = await add();
      expect(config.type, RemoteSourceType.plex);
      final source = manager.sections(localLabel: "Local").last.sources.single;
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNull);
      expect(source.library!.tracks.length, 3);
      expect(source.library!.artists, ["Alpha", "Beta"]);

      final track = source.library!.tracks.first;
      expect(SourceLocation.isSource(track.path), isTrue);
      expect(track.path, isNot(contains("tok3n")));
      final url = Uri.parse(await manager.resolve(track.path));
      expect(url.path, "/library/parts/0/1/file.mp3");
      expect(url.queryParameters["X-Plex-Token"], "tok3n");

      await manager.remove(config.id);
      expect(store.logins, isEmpty);
    });

    test("editing with a new token reconnects", () async {
      final config = await add();
      await expectLater(
        manager.edit(config.id, password: "bad"),
        throwsA(isA<RemoteAuthException>()),
      );
      await manager.edit(config.id, name: "Den", password: "tok3n");
      expect(manager.remotes.single.name, "Den");
    });

    test("sources survive a restart", () async {
      await add();
      final again = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: store,
      );
      await again.restore(await SharedPreferences.getInstance());
      expect(again.remotes.single.type, RemoteSourceType.plex);
      again.dispose();
    });
  });
}
