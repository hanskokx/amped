import "dart:convert";
import "dart:io";

import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_subsonic/amped_subsonic.dart";
import "package:crypto/crypto.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A Navidrome that knows one user and [songCount] songs.
class _FakeServer {
  _FakeServer({this.songCount = 3});

  final int songCount;
  late final HttpServer _http;
  final List<Uri> requests = [];

  String get address => "http://127.0.0.1:${_http.port}";

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) {
      requests.add(request.uri);
      final query = request.uri.queryParameters;
      final expected = md5
          .convert(utf8.encode("secret${query["s"]}"))
          .toString();
      Map<String, dynamic> reply;
      if (query["u"] != "alice" || query["t"] != expected) {
        reply = {
          "status": "failed",
          "error": {"code": 40, "message": "Wrong username or password"},
        };
      } else if (request.uri.path.endsWith("/rest/ping")) {
        reply = {"status": "ok"};
      } else if (request.uri.path.endsWith("/rest/search3")) {
        final offset = int.parse(query["songOffset"]!);
        final size = int.parse(query["songCount"]!);
        reply = {
          "status": "ok",
          "searchResult3": {
            "song": [
              for (var i = offset; i < songCount && i < offset + size; i++)
                {
                  "id": "s$i",
                  "title": "Song $i",
                  "artist": i.isEven ? "Alpha" : "Beta",
                  "album": "Album ${i % 2}",
                  "track": i,
                  "discNumber": 1,
                  "duration": 180 + i,
                  "bitRate": 320,
                  "genre": "Rock",
                },
            ],
          },
        };
      } else {
        reply = {
          "status": "failed",
          "error": {"code": 70, "message": "Not found"},
        };
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({"subsonic-response": reply}))
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
  late _FakeServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _FakeServer();
    await server.start();
  });

  tearDown(() => server.stop());

  SubsonicClient client({String password = "secret"}) => SubsonicClient(
    server: "${server.address}/",
    user: "alice",
    password: password,
    salt: "abc123",
  );

  test("source locations hold no secrets and parse back", () {
    final location = SourceLocation.build("navidrome-1", "id/with space");
    expect(location, startsWith("amped-source://navidrome-1/"));
    final parsed = SourceLocation.parse(location)!;
    expect(parsed.sourceId, "navidrome-1");
    expect(parsed.itemId, "id/with space");
    expect(SourceLocation.parse("http://x/y"), isNull);
    expect(SourceLocation.isSource("smb://nas/x"), isFalse);
  });

  test("signs requests with a token and never sends the password", () async {
    await client().ping();
    final query = server.requests.single.queryParameters;
    expect(query["s"], "abc123");
    expect(query["t"], md5.convert(utf8.encode("secretabc123")).toString());
    expect(query.containsKey("p"), isFalse);
    expect(server.requests.single.toString(), isNot(contains("secret")));
  });

  test("a wrong password is an auth error", () async {
    await expectLater(
      client(password: "nope").ping(),
      throwsA(isA<RemoteAuthException>()),
    );
  });

  test("something that is not a Subsonic server is reported", () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    other.listen(
      (request) => request.response
        ..write("<html>")
        ..close(),
    );
    final bad = SubsonicClient(
      server: "127.0.0.1:${other.port}",
      user: "alice",
      password: "secret",
    );
    await expectLater(bad.ping(), throwsA(isA<SubsonicException>()));
    await other.close(force: true);
  });

  test("lists every song, a page at a time, with its tags", () async {
    await server.stop();
    server = _FakeServer(songCount: SubsonicClient.pageSize + 2);
    await server.start();
    final pages = <List<TrackTags>>[];
    await client().songs(onPage: pages.add);
    expect(pages.map((p) => p.length), [SubsonicClient.pageSize, 2]);
    final first = pages.first.first;
    expect(first.title, "Song 0");
    expect(first.artist, "Alpha");
    expect(first.album, "Album 0");
    expect(first.duration, const Duration(seconds: 180));
    expect(first.bitrate, 320);
    expect(first.genres, ["Rock"]);
    expect(first.path, contains("/rest/stream"));
    expect(first.path, contains("id=s0"));
    final named = <TrackTags>[];
    await client().songs(
      onPage: named.addAll,
      pathOf: (id) => "x://$id",
    );
    expect(named.first.path, "x://s0");
  });

  group("LibrarySourceManager", () {
    late _MemoryStore store;
    late MediaLibrary local;
    late LibrarySourceManager manager;

    setUp(() {
      store = _MemoryStore();
      local = MediaLibrary(readTags: (files) async => const []);
      manager = LibrarySourceManager(local: local, credentials: store);
    });

    tearDown(() => manager.dispose());

    Future<RemoteSourceConfig> add() => manager.addNavidrome(
      name: "Home",
      server: server.address,
      user: "alice",
      password: "secret",
    );

    test(
      "adding checks the server, and a refused sign-in adds nothing",
      () async {
        await expectLater(
          manager.addNavidrome(
            name: "Home",
            server: server.address,
            user: "alice",
            password: "wrong",
          ),
          throwsA(isA<RemoteAuthException>()),
        );
        expect(manager.remotes, isEmpty);
        expect(store.logins, isEmpty);
      },
    );

    test("an added source is in the tree and loads when opened", () async {
      final config = await add();
      expect(store.logins.values.single.password, "secret");
      final sections = manager.sections(localLabel: "Local");
      expect(sections.map((s) => s.id), ["local", "remote"]);
      final source = sections.last.sources.single;
      expect(source.label, "Home");
      expect(source.library!.isEmpty, isTrue);

      await manager.open(config.id);
      expect(source.library!.tracks.length, 3);
      expect(source.library!.artists, ["Alpha", "Beta"]);
      expect(manager.errorOf(config.id), isNull);

      // Loaded once: opening again doesn't ask the server again.
      final before = server.requests.length;
      await manager.open(config.id);
      expect(server.requests.length, before);
    });

    test("the tracks carry a name without credentials, resolved to a signed URL when played", () async {
      final config = await add();
      final heard = <TrackTags>[];
      final withTags = LibrarySourceManager(
        local: local,
        credentials: store,
        onTracks: heard.addAll,
      );
      await withTags.restore(await SharedPreferences.getInstance());
      await withTags.open(config.id);
      expect(heard, hasLength(3));
      final track = withTags
          .sections(localLabel: "Local")
          .last
          .sources
          .single
          .library!
          .tracks
          .first;
      expect(SourceLocation.isSource(track.path), isTrue);
      expect(track.path, isNot(contains("secret")));
      expect(track.path, isNot(contains("t=")));

      final first = Uri.parse(await withTags.resolve(track.path));
      final second = Uri.parse(await withTags.resolve(track.path));
      expect(first.path, endsWith("/rest/stream"));
      expect(first.queryParameters["id"], "s0");
      expect(first.queryParameters["u"], "alice");
      expect(
        first.queryParameters["t"],
        md5
            .convert(utf8.encode("secret${first.queryParameters["s"]}"))
            .toString(),
      );
      // A fresh salt each time.
      expect(second.queryParameters["s"], isNot(first.queryParameters["s"]));

      await withTags.remove(config.id);
      await expectLater(
        withTags.resolve(track.path),
        throwsA(isA<SubsonicException>()),
      );
      withTags.dispose();
    });

    test("a load failure is kept for the pane", () async {
      final config = await add();
      store.logins["source:${config.id}"] = const RemoteLogin("alice", "bad");
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNotNull);
      final source = manager.sections(localLabel: "Local").last.sources.single;
      expect(source.library, isNull);
      expect(source.error, isNotNull);
    });

    test(
      "sources are saved and restored; the password is not in the prefs",
      () async {
        final config = await add();
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString("amped.library_sources"),
          isNot(contains("secret")),
        );

        final again = LibrarySourceManager(local: local, credentials: store);
        await again.restore(prefs);
        expect(again.remotes.single.id, config.id);
        expect(again.remotes.single.server, server.address);
        await again.open(config.id);
        expect(
          again
              .sections(localLabel: "Local")
              .last
              .sources
              .single
              .library!
              .tracks,
          hasLength(3),
        );
        again.dispose();
      },
    );

    test("editing changes the name and keeps the password", () async {
      final config = await add();
      await manager.edit(config.id, name: "Office");
      expect(manager.remotes.single.name, "Office");
      expect(store.logins["source:${config.id}"]!.password, "secret");
      await expectLater(
        manager.edit(config.id, password: "wrong"),
        throwsA(isA<RemoteAuthException>()),
      );
      expect(store.logins["source:${config.id}"]!.password, "secret");
    });

    test("removing forgets the source and its password", () async {
      final config = await add();
      await manager.remove(config.id);
      expect(manager.remotes, isEmpty);
      expect(store.logins, isEmpty);
      expect(manager.sections(localLabel: "Local"), hasLength(1));
    });
  });
}
