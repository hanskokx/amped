import "dart:convert";
import "dart:io";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped/src/remote/remote_file_system.dart";
import "package:amped/src/remote/remote_files.dart";
import "package:amped/src/remote/remote_location.dart";
import "package:amped/src/remote/remote_progress_text.dart";
import "package:amped/src/remote/webdav_file_system.dart";
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A share kept in memory: folders end in a slash.
class _FakeShare implements RemoteFileSystem {
  _FakeShare(this.files);

  final Map<String, String> files;
  bool closed = false;

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final prefix = path.endsWith("/") ? path : "$path/";
    final names = <String, bool>{};
    for (final file in files.keys) {
      if (!file.startsWith(prefix)) continue;
      final rest = file.substring(prefix.length);
      final slash = rest.indexOf("/");
      names[slash < 0 ? rest : rest.substring(0, slash)] = slash >= 0;
    }
    if (names.isEmpty) throw const RemoteFileException("No such folder");
    return [
      for (final entry in names.entries)
        RemoteEntry(entry.key, isDirectory: entry.value),
    ];
  }

  @override
  Future<void> download(
    String path,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final content = files[path];
    if (content == null) throw const RemoteFileException("Not found");
    await destination.writeAsString(content);
    onProgress?.call(content.length, content.length);
  }

  @override
  Future<int> size(String path) async {
    final content = files[path];
    if (content == null) throw const RemoteFileException("Not found");
    return content.length;
  }

  @override
  Stream<List<int>> openRead(String path, int start, [int? end]) async* {
    final content = files[path];
    if (content == null) throw const RemoteFileException("Not found");
    yield utf8.encode(content.substring(start, end));
  }

  @override
  Future<void> close() async => closed = true;
}

class _RecordingEngine extends AudioEngine {
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
    return null;
  }

  @override
  Future<void> stop() async {}
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
  late Directory cache;
  late _FakeShare share;
  late List<RemoteLocation> connections;
  late RemoteFiles remote;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cache = Directory.systemTemp.createTempSync("amped_remote_test");
    share = _FakeShare({
      "/Music Videos/b.mp4": "b",
      "/Music Videos/a.mp3": "a",
      "/Music Videos/notes.txt": "x",
      "/Music Videos/Live/c.flac": "c",
      "/Music Videos/set.m3u":
          "#EXTM3U\n#EXTINF:12,Opening\na.mp3\nLive\\c.flac\n"
          "/Elsewhere/d.ogg\nhttp://station.example/live\n",
    });
    connections = [];
    remote = RemoteFiles(
      cacheDirectory: cache,
      factories: {
        for (final scheme in RemoteScheme.values)
          scheme: (location) async {
            connections.add(location);
            return share;
          },
      },
    );
  });

  tearDown(() => cache.deleteSync(recursive: true));

  group("RemoteLocation", () {
    test("takes a Samba URL apart", () {
      final location = RemoteLocation.tryParse(
        "smb://nas.home.hadak.org/Music%20Videos/",
      )!;
      expect(location.scheme, RemoteScheme.smb);
      expect(location.host, "nas.home.hadak.org");
      expect(location.path, "/Music Videos");
      expect(location.looksLikeFolder, isTrue);
      expect(location.user, isNull);
    });

    test("reads the name, password and domain", () {
      final location = RemoteLocation.tryParse(
        "smb://WORK;ann:p%40ss@nas/share/a.mp3",
      )!;
      expect(location.domain, "WORK");
      expect(location.userName, "ann");
      expect(location.password, "p@ss");
      expect(location.display, isNot(contains("p%40ss")));
    });

    test("knows the other share types, and not web streams", () {
      expect(RemoteLocation.isRemote("ftp://h/a"), isFalse);
      expect(
        RemoteLocation.tryParse("webdav://h/a")?.scheme,
        RemoteScheme.webdav,
      );
      expect(RemoteLocation.tryParse("davs://h/a")?.secure, isTrue);
      expect(RemoteLocation.isRemote("http://station/stream"), isFalse);
      expect(RemoteLocation.isRemote("/home/me/a.mp3"), isFalse);
    });

    test("builds the URL of a name inside a folder", () {
      final folder = RemoteLocation.tryParse("smb://nas/Music Videos/")!;
      expect(folder.child("a b.mp3"), "smb://nas/Music%20Videos/a%20b.mp3");
    });
  });

  group("RemoteFiles", () {
    test("lists the playable files below a folder in name order", () async {
      final files = await remote.listFiles(
        "smb://nas/Music%20Videos/",
        Playlist.isPlayable,
      );
      expect(files, [
        "smb://nas/Music%20Videos/a.mp3",
        "smb://nas/Music%20Videos/b.mp4",
        "smb://nas/Music%20Videos/Live/c.flac",
      ]);
      expect(share.closed, isTrue);
    });

    test("reports a server that can't be reached", () async {
      final broken = RemoteFiles(
        cacheDirectory: cache,
        factories: {
          RemoteScheme.smb: (_) async => throw const SocketException("down"),
        },
      );
      expect(
        () => broken.listFiles("smb://nas/x/", Playlist.isPlayable),
        throwsA(isA<RemoteFileException>()),
      );
    });

    test("fetches a file once and keeps the newest few", () async {
      final path = await remote.fetch("smb://nas/Music%20Videos/a.mp3");
      expect(File(path).readAsStringSync(), "a");
      expect(path, endsWith("a.mp3"));
      expect(await remote.fetch("smb://nas/Music%20Videos/a.mp3"), path);
      expect(connections, hasLength(1));
      expect(File("$path.part").existsSync(), isFalse);

      final small = RemoteFiles(
        cacheDirectory: cache,
        keptFiles: 1,
        factories: {RemoteScheme.smb: (_) async => share},
      );
      final other = await small.fetch("smb://nas/Music%20Videos/b.mp4");
      expect(File(other).existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
    });

    test("leaves nothing behind when a download fails", () async {
      await expectLater(
        remote.fetch("smb://nas/Music%20Videos/missing.mp3"),
        throwsA(isA<RemoteFileException>()),
      );
      expect(cache.listSync(), isEmpty);
    });
  });

  group("sign-in", () {
    late _MemoryStore store;
    late List<RemoteLoginRequest> asked;
    late List<String?> triedUsers;

    /// A server that only lets "ann" with "secret" in.
    RemoteFiles server(RemoteLogin? Function(RemoteLoginRequest) answer) {
      store = _MemoryStore();
      asked = [];
      triedUsers = [];
      return RemoteFiles(
        cacheDirectory: cache,
        store: store,
        prompt: (request) async {
          asked.add(request);
          return answer(request);
        },
        factories: {
          RemoteScheme.smb: (location) async {
            triedUsers.add(location.user);
            if (location.user == "ann" && location.password == "secret") {
              return share;
            }
            throw const RemoteAuthException("logon failure");
          },
        },
      );
    }

    test("asks when the server turns a guest away, then saves", () async {
      final files = server((_) => const RemoteLogin("ann", "secret"));
      final found = await files.listFiles(
        "smb://nas/Music%20Videos/",
        Playlist.isPlayable,
      );
      expect(found, hasLength(3));
      expect(found.first, isNot(contains("secret")));
      expect(triedUsers, [null, "ann"]);
      expect(asked.single.server, "smb://nas");
      expect(asked.single.login, isNull);
      expect(asked.single.error, isNull);
      expect(store.logins["smb://nas"], const RemoteLogin("ann", "secret"));
    });

    test("uses the saved login without asking", () async {
      final files = server((_) => null);
      store.logins["smb://nas"] = const RemoteLogin("ann", "secret");
      await files.listFiles("smb://nas/Music%20Videos/", Playlist.isPlayable);
      expect(asked, isEmpty);
      expect(triedUsers, ["ann"]);
    });

    test("asks again, filled in, when the saved login stops working", () async {
      final files = server((_) => const RemoteLogin("ann", "secret"));
      store.logins["smb://nas"] = const RemoteLogin("ann", "old");
      await files.fetch("smb://nas/Music%20Videos/a.mp3");
      expect(asked.single.login, const RemoteLogin("ann", "old"));
      expect(asked.single.error, "logon failure");
      expect(store.logins["smb://nas"], const RemoteLogin("ann", "secret"));
    });

    test("keeps asking after a wrong password, and stops on cancel", () async {
      var answers = 0;
      final files = server(
        (_) => ++answers < 3 ? const RemoteLogin("ann", "nope") : null,
      );
      await expectLater(
        files.listFiles("smb://nas/Music%20Videos/", Playlist.isPlayable),
        throwsA(isA<RemoteFileException>()),
      );
      expect(asked, hasLength(3));
      expect(asked.last.login, const RemoteLogin("ann", "nope"));
      expect(store.logins, isEmpty);
    });

    test("does not ask when the URL carries the login", () async {
      final files = server((_) => null);
      await files.listFiles(
        "smb://ann:secret@nas/Music%20Videos/",
        Playlist.isPlayable,
      );
      expect(asked, isEmpty);
    });
  });

  group("progress", () {
    test("tells speed, time left and percent", () {
      const progress = RemoteProgress(
        1024 * 1024,
        4 * 1024 * 1024,
        Duration(seconds: 2),
      );
      expect(progress.percent, 25);
      expect(progress.speedText, "512 KB");
      expect(progress.elapsedText, "0:02");
      expect(progress.remainingText, "0:06");
      expect(
        const RemoteProgress(10, null, Duration(seconds: 1)).percent,
        null,
      );
      expect(formatDuration(const Duration(seconds: 3729)), "1:02:09");
      expect(formatBytes(3.1 * 1024 * 1024), "3.1 MB");
    });

    test("fetch reports it, starting at nothing", () async {
      final seen = <RemoteProgress>[];
      await remote.fetch(
        "smb://nas/Music%20Videos/a.mp3",
        onProgress: seen.add,
      );
      expect(seen.first.received, 0);
      expect(seen.last.received, 1);
      expect(seen.last.total, 1);
      seen.clear();
      await remote.fetch(
        "smb://nas/Music%20Videos/a.mp3",
        onProgress: seen.add,
      );
      expect(seen, isEmpty); // Fetched before.
    });

    test("the player shows buffering while it fetches", () async {
      final engine = _RecordingEngine();
      final player = PlayerState(engine: engine, remoteFiles: remote);
      final shown = <RemoteProgress?>[];
      player.buffering.addListener(() => shown.add(player.buffering.value));
      await player.playlist.add(["smb://nas/Music%20Videos/a.mp3"]);
      await player.playIndex(0);
      expect(shown.first, isNotNull);
      expect(shown.last, isNull);
      expect(player.buffering.value, isNull);
    });
  });

  group("Playlist", () {
    test("copies a playlist on a share, then expands it there", () async {
      final playlist = Playlist(remoteFiles: remote);
      await playlist.add(["smb://nas/Music%20Videos/set.m3u"]);
      expect(playlist.entries.map((e) => e.location), [
        "smb://nas/Music%20Videos/a.mp3",
        "smb://nas/Music%20Videos/Live/c.flac",
        "smb://nas/Elsewhere/d.ogg",
        "http://station.example/live",
      ]);
      expect(playlist.entries.first.title, "Opening");
    });

    test("adds the files of a share's folder", () async {
      final playlist = Playlist(remoteFiles: remote);
      await playlist.add(["smb://nas/Music%20Videos/"]);
      expect(playlist.entries.map((e) => e.title), ["a", "b", "c"]);
      expect(
        playlist.entries.first.location,
        "smb://nas/Music%20Videos/a.mp3",
      );
    });

    test("adds a file on a share as one entry, without connecting", () async {
      final playlist = Playlist(remoteFiles: remote);
      await playlist.add(["webdav://host/pub/song.ogg"]);
      expect(playlist.length, 1);
      expect(connections, isEmpty);
    });

    test("adds nothing for a share that can't be read", () async {
      final playlist = Playlist(
        remoteFiles: RemoteFiles(
          cacheDirectory: cache,
          factories: {
            RemoteScheme.smb: (_) async => throw const SocketException("down"),
          },
        ),
      );
      expect(await playlist.add(["smb://nas/Music/"]), -1);
    });
  });

  test("the player plays a copy of a track on a share", () async {
    final engine = _RecordingEngine();
    final player = PlayerState(engine: engine, remoteFiles: remote);
    await player.playlist.add(["smb://nas/Music%20Videos/a.mp3"]);
    await player.playIndex(0);
    expect(engine.played, hasLength(1));
    expect(File(engine.played.single).readAsStringSync(), "a");
  });

  group("WebDAV", () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = "webdav://127.0.0.1:${server.port}";
      server.listen((request) async {
        final response = request.response;
        if (request.headers.value("authorization") !=
            "Basic ${base64.encode(utf8.encode("ann:secret"))}") {
          response.statusCode = HttpStatus.unauthorized;
        } else if (request.method == "PROPFIND") {
          response
            ..statusCode = 207
            ..write(
              '<?xml version="1.0"?> '
              '<D:multistatus xmlns:D="DAV:"> '
              "<D:response><D:href>/dav/Music%20Videos/</D:href>"
              "<D:propstat><D:prop><D:resourcetype><D:collection/>"
              "</D:resourcetype></D:prop></D:propstat></D:response>"
              "<D:response><D:href>/dav/Music%20Videos/a%20b.mp3</D:href>"
              "<D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat>"
              "</D:response>"
              "<D:response><D:href>/dav/Music%20Videos/Live/</D:href>"
              "<D:propstat><D:prop><D:resourcetype><D:collection/>"
              "</D:resourcetype></D:prop></D:propstat></D:response>"
              "</D:multistatus>",
            );
        } else if (request.uri.path == "/dav/Music%20Videos/a%20b.mp3") {
          // Range is ignored, as some servers do.
          if (request.method == "HEAD") {
            response.contentLength = 4;
          } else {
            response.write("song");
          }
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test("lists a folder with PROPFIND and downloads with GET", () async {
      final location = RemoteLocation.tryParse(
        "$base/dav/Music%20Videos/".replaceFirst("//", "//ann:secret@"),
      )!;
      final system = WebDavFileSystem(location);
      final entries = await system.list(location.path);
      expect(
        {for (final e in entries) e.name: e.isDirectory},
        {"a b.mp3": false, "Live": true},
      );
      final file = File("${cache.path}/a.mp3");
      await system.download("/dav/Music Videos/a b.mp3", file);
      expect(file.readAsStringSync(), "song");
      await system.close();
    });

    test("reads a range, also from a server that ignores Range", () async {
      final location = RemoteLocation.tryParse(
        "$base/dav/Music%20Videos/".replaceFirst("//", "//ann:secret@"),
      )!;
      final system = WebDavFileSystem(location);
      const path = "/dav/Music Videos/a b.mp3";
      expect(await system.size(path), 4);
      final bytes = [
        for (final chunk in await system.openRead(path, 1, 3).toList())
          ...chunk,
      ];
      expect(utf8.decode(bytes), "on");
      await system.close();
    });

    test("refuses a wrong login", () async {
      final location = RemoteLocation.tryParse("$base/dav/Music%20Videos/")!;
      final system = WebDavFileSystem(location);
      await expectLater(
        system.list(location.path),
        throwsA(isA<RemoteAuthException>()),
      );
      await system.close();
    });
  });
}
