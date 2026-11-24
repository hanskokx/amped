import "dart:convert";
import "dart:io";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/video_engine.dart";
import "package:amped/src/remote/remote_file_system.dart";
import "package:amped/src/remote/remote_files.dart";
import "package:amped/src/remote/remote_location.dart";
import "package:amped/src/remote/remote_stream_server.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _Share implements RemoteFileSystem {
  _Share(this.content);

  final String content;
  int closed = 0;

  @override
  Future<List<RemoteEntry>> list(String path) async => const [];

  @override
  Future<void> download(
    String path,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async => throw StateError("a stream is not a download");

  @override
  Future<int> size(String path) async {
    if (path != "/s/movie.mp4") throw const RemoteFileException("Not found");
    return content.length;
  }

  @override
  Stream<List<int>> openRead(String path, int start, [int? end]) async* {
    yield utf8.encode(content.substring(start, end));
  }

  @override
  Future<void> close() async => closed++;
}

class _Video extends VideoEngine {
  final List<String> played = [];

  @override
  bool active = false;

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
    active = true;
    return const Duration(seconds: 10);
  }

  @override
  Duration get position => Duration.zero;

  @override
  void setPaused(bool paused) {}

  @override
  void seek(Duration position) {}

  @override
  void setVolume(double volume) {}

  @override
  void setBalance(double balance) {}

  @override
  Future<void> stop() async => active = false;
}

class _Audio extends AudioEngine {
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

void main() {
  test("reads Range headers", () {
    const size = 100;
    expect(RemoteStreamServer.parseRange(null, size), isNull);
    expect(RemoteStreamServer.parseRange("bytes=0-9", size), (0, 10));
    expect(RemoteStreamServer.parseRange("bytes=90-", size), (90, 100));
    expect(RemoteStreamServer.parseRange("bytes=-10", size), (90, 100));
    expect(RemoteStreamServer.parseRange("bytes=95-500", size), (95, 100));
    expect(RemoteStreamServer.parseRange("bytes=100-", size), isNull);
    expect(RemoteStreamServer.parseRange("bytes=5-2", size), isNull);
    expect(RemoteStreamServer.parseRange("bytes=0-1,5-6", size), isNull);
  });

  group("on a share", () {
    late _Share share;
    late RemoteFiles remote;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      share = _Share("0123456789");
      remote = RemoteFiles(
        factories: {
          for (final scheme in RemoteScheme.values)
            scheme: (location) async => share,
        },
      );
    });

    tearDown(() => remote.dispose());

    Future<(int, Map<String, String>, String)> get(
      String url, {
      String? range,
      String method = "GET",
    }) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, Uri.parse(url));
        if (range != null) request.headers.set("Range", range);
        final response = await request.close();
        final body = await utf8.decodeStream(response);
        final headers = <String, String>{};
        response.headers.forEach(
          (name, values) => headers[name] = values.first,
        );
        return (response.statusCode, headers, body);
      } finally {
        client.close(force: true);
      }
    }

    test("serves a file whole, and in ranges", () async {
      final url = await remote.stream("smb://nas/s/movie.mp4");
      expect(url, startsWith("http://127.0.0.1:"));
      expect(url, endsWith("/movie.mp4"));

      final whole = await get(url);
      expect(whole.$1, 200);
      expect(whole.$2["accept-ranges"], "bytes");
      expect(whole.$3, "0123456789");

      final part = await get(url, range: "bytes=2-5");
      expect(part.$1, 206);
      expect(part.$2["content-range"], "bytes 2-5/10");
      expect(part.$3, "2345");

      final tail = await get(url, range: "bytes=-3");
      expect(tail.$3, "789");

      final head = await get(url, method: "HEAD");
      expect(head.$1, 200);
      expect(head.$2["content-length"], "10");
      expect(head.$3, isEmpty);
    });

    test("turns down a range past the end and unknown files", () async {
      final url = await remote.stream("smb://nas/s/movie.mp4");
      final past = await get(url, range: "bytes=10-");
      expect(past.$1, 416);
      expect(past.$2["content-range"], "bytes */10");
      final other = await get(
        url.replaceFirst(RegExp(r"/\d+/"), "/999/"),
      );
      expect(other.$1, 404);
    });

    test("a file that is not there can't be streamed", () async {
      await expectLater(
        remote.stream("smb://nas/s/missing.mp4"),
        throwsA(isA<RemoteFileException>()),
      );
    });

    test("the player streams a video from a share, with no copy", () async {
      final video = _Video();
      final audio = _Audio();
      final player = PlayerState(
        engine: audio,
        video: video,
        remoteFiles: remote,
      );
      addTearDown(player.stop);
      await player.playlist.add(["smb://nas/s/movie.mp4"]);
      await player.playIndex(0);
      expect(video.played, hasLength(1));
      expect(video.played.single, startsWith("http://127.0.0.1:"));
      expect(player.buffering.value, isNull);
      expect(player.playing, isTrue);
    });
  });
}
