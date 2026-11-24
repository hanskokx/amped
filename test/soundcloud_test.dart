import "dart:convert";
import "dart:io";

import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_soundcloud/amped_soundcloud.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A SoundCloud that knows one application and one profile.
class _FakeSoundCloud {
  late final HttpServer _http;
  final List<String> requests = [];
  int tokens = 0;
  final List<String> refreshes = [];

  String get address => "http://127.0.0.1:${_http.port}";

  Map<String, dynamic> _track(int i, {String? access}) => {
    "urn": "soundcloud:tracks:$i",
    "title": "Track $i",
    "user": {"username": "Artist"},
    "duration": 180000 + i,
    "genre": "Techno",
    "access": access ?? "playable",
    "streamable": true,
  };

  Future<void> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((request) async {
      requests.add("${request.method} ${request.uri}");
      Object? reply;
      var status = 200;
      final auth = request.headers.value("authorization");
      final path = request.uri.path;
      if (path == "/oauth/token") {
        final form = Uri.splitQueryString(
          await utf8.decoder.bind(request).join(),
        );
        final expected = "Basic ${base64.encode(utf8.encode("id:secret"))}";
        if (form["grant_type"] == "authorization_code") {
          reply = {
            "access_token": "user1",
            "refresh_token": "refresh1",
            "expires_in": form["code"] == "short" ? 1 : 3600,
          };
        } else if (form["grant_type"] == "refresh_token") {
          refreshes.add(form["refresh_token"]!);
          reply = {
            "access_token": "user${refreshes.length + 1}",
            "refresh_token": "refresh${refreshes.length + 1}",
            "expires_in": 3600,
          };
        } else if (auth == expected) {
          tokens++;
          reply = {"access_token": "tok$tokens", "expires_in": 3600};
        } else {
          status = 401;
        }
      } else if (path.startsWith("/me")) {
        if (auth == "OAuth user${refreshes.length + 1}") {
          reply = path == "/me"
              ? {"urn": "soundcloud:users:7"}
              : {
                  "collection": [
                    _track(path.contains("likes") ? 20 : 10),
                  ],
                };
        } else {
          status = 401;
        }
      } else if (auth != "OAuth tok$tokens") {
        status = 401;
      } else if (path == "/resolve") {
        if (request.uri.queryParameters["url"] ==
            "https://soundcloud.com/artist") {
          request.response.statusCode = 302;
          request.response.headers.set(
            "location",
            "$address/users/soundcloud:users:7",
          );
          await request.response.close();
          return;
        }
        status = 404;
      } else if (path == "/users/soundcloud:users:7") {
        reply = {"urn": "soundcloud:users:7", "username": "Artist"};
      } else if (path == "/users/soundcloud:users:7/tracks") {
        reply = {
          "collection": [_track(1), _track(2, access: "blocked")],
          "next_href": "$address/page2",
        };
      } else if (path == "/page2") {
        reply = {
          "collection": [_track(3)],
        };
      } else if (path == "/users/soundcloud:users:7/likes/tracks") {
        reply = {
          "collection": [_track(3), _track(4)],
        };
      } else if (path == "/tracks/soundcloud:tracks:1/streams") {
        reply = {"hls_aac_160_url": "https://cdn.example/1.m3u8"};
      } else {
        status = 404;
      }
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply ?? {}));
      await request.response.close();
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
  late _FakeSoundCloud server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _FakeSoundCloud();
    await server.start();
  });

  tearDown(() => server.stop());

  SoundCloudClient client({String secret = "secret", String id = "id"}) =>
      SoundCloudClient(
        profile: "https://soundcloud.com/artist",
        clientId: id,
        clientSecret: secret,
        apiBase: server.address,
        authBase: server.address,
      );

  test("normalizes profile addresses", () {
    expect(
      SoundCloudClient.normalizeProfile("artist"),
      "https://soundcloud.com/artist",
    );
    expect(
      SoundCloudClient.normalizeProfile("soundcloud.com/artist/tracks"),
      "https://soundcloud.com/artist",
    );
    expect(
      SoundCloudClient.normalizeProfile("https://soundcloud.com/artist/"),
      "https://soundcloud.com/artist",
    );
  });

  test("resolves the profile and lists uploads and likes once each", () async {
    final soundcloud = client();
    final pages = <List<TrackTags>>[];
    await soundcloud.tracks(
      onPage: pages.add,
      pathOf: (urn) => "x://$urn",
    );
    final tracks = pages.expand((page) => page).toList();
    // Track 2 is blocked, and 3 is liked as well as uploaded.
    expect(tracks.map((track) => track.path), [
      "x://soundcloud:tracks:1",
      "x://soundcloud:tracks:3",
      "x://soundcloud:tracks:4",
    ]);
    expect(tracks.first.artist, "Artist");
    expect(tracks.first.title, "Track 1");
    expect(tracks.first.duration, const Duration(milliseconds: 180001));
    soundcloud.close();
  });

  test("a wrong secret is an auth error", () async {
    final soundcloud = client(secret: "nope");
    await expectLater(
      soundcloud.check(),
      throwsA(isA<RemoteAuthException>()),
    );
    soundcloud.close();
  });

  test("an unknown profile is an error", () async {
    final soundcloud = SoundCloudClient(
      profile: "https://soundcloud.com/ghost",
      clientId: "id",
      clientSecret: "secret",
      apiBase: server.address,
      authBase: server.address,
    );
    await expectLater(
      soundcloud.check(),
      throwsA(isA<SoundCloudException>()),
    );
    soundcloud.close();
  });

  test("streamUrl gives the HLS stream, and tokens are reused", () async {
    final soundcloud = client();
    expect(
      await soundcloud.streamUrl("soundcloud:tracks:1"),
      "https://cdn.example/1.m3u8",
    );
    await soundcloud.check();
    expect(server.tokens, 1);
    await expectLater(
      soundcloud.streamUrl("soundcloud:tracks:9"),
      throwsA(isA<SoundCloudException>()),
    );
    soundcloud.close();
  });

  group("browser sign-in", () {
    late _MemoryStore store;
    late LibrarySourceManager manager;
    late int port;

    setUp(() async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = socket.port;
      await socket.close();
      store = _MemoryStore();
      manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: store,
        remoteFactory: (config, password) => SoundCloudRemote(
          config.connection,
          password,
          apiBase: server.address,
          authBase: server.address,
        ),
        pkceFor: (clientId, secret) => SoundCloudClient.pkce(
          clientId,
          secret,
          authBase: server.address,
          port: port,
        ),
        browserOpener: (url) async {
          final redirect = Uri.parse(url.queryParameters["redirect_uri"]!);
          final http = HttpClient();
          final request = await http.getUrl(
            redirect.replace(
              queryParameters: {
                "code": "the-code",
                "state": url.queryParameters["state"]!,
              },
            ),
          );
          await (await request.close()).drain<void>();
          http.close();
        },
      );
    });

    tearDown(() => manager.dispose());

    test("lists the signed-in user's own tracks and likes", () async {
      final config = await manager.addSoundCloud(
        name: "Me",
        profile: "",
        clientId: "id",
        clientSecret: "secret",
        browserSignIn: true,
      );
      final saved = SoundCloudCredentials.parse(
        store.logins.values.single.password,
      );
      expect(saved.secret, "secret");
      expect(saved.tokens?.refreshToken, "refresh1");
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNull);
      final source = manager.sections(localLabel: "Local").last.sources.single;
      expect(source.library!.tracks, hasLength(2));
    });

    test("an expired sign-in is refreshed, and the new tokens saved", () async {
      final config = await manager.addSoundCloud(
        name: "Me",
        profile: "",
        clientId: "id",
        clientSecret: "secret",
        browserSignIn: true,
      );
      final key = store.logins.keys.single;
      // Age the saved access token.
      store.logins[key] = RemoteLogin(
        "id",
        SoundCloudCredentials(
          "secret",
          tokens: OAuthTokens(
            accessToken: "user1",
            refreshToken: "refresh1",
            expires: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ).encode(),
      );
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNull);
      expect(server.refreshes, ["refresh1"]);
      final saved = SoundCloudCredentials.parse(store.logins[key]!.password);
      expect(saved.tokens?.refreshToken, "refresh2");
    });
  });

  group("LibrarySourceManager", () {
    late _MemoryStore store;
    late LibrarySourceManager manager;

    setUp(() {
      store = _MemoryStore();
      manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: store,
        remoteFactory: (config, password) => SoundCloudRemote(
          config.connection,
          password,
          apiBase: server.address,
          authBase: server.address,
        ),
      );
    });

    tearDown(() => manager.dispose());

    test("adding checks the key and keeps the secret in the store", () async {
      await expectLater(
        manager.addSoundCloud(
          name: "",
          profile: "artist",
          clientId: "id",
          clientSecret: "wrong",
        ),
        throwsA(isA<RemoteAuthException>()),
      );
      expect(manager.remotes, isEmpty);

      final config = await manager.addSoundCloud(
        name: "Mine",
        profile: "artist",
        clientId: "id",
        clientSecret: "secret",
      );
      expect(config.type, RemoteSourceType.soundcloud);
      expect(config.server, "https://soundcloud.com/artist");
      expect(store.logins.values.single.password, "secret");
      final saved = (await SharedPreferences.getInstance()).getString(
        "amped.library_sources",
      )!;
      expect(saved, isNot(contains("secret")));
    });

    test("opening loads tracks and resolving signs a stream", () async {
      final config = await manager.addSoundCloud(
        name: "Mine",
        profile: "artist",
        clientId: "id",
        clientSecret: "secret",
      );
      await manager.open(config.id);
      expect(manager.errorOf(config.id), isNull);
      final source = manager.sections(localLabel: "Local").last.sources.single;
      expect(source.library!.tracks, hasLength(3));
      final location = SourceLocation.build(config.id, "soundcloud:tracks:1");
      expect(await manager.resolve(location), "https://cdn.example/1.m3u8");
    });
  });
}
