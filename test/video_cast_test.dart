import "dart:io";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/video_cast.dart";
import "package:amped/src/player/video_engine.dart";
import "package:dart_cast/dart_cast.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _Audio extends AudioEngine {
  @override
  Future<void> stop() async {}
}

class _Video extends VideoEngine {
  bool paused = false;
  Duration? sought;
  double? volume;

  @override
  bool active = true;

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
    this.volume = volume;
    return const Duration(seconds: 100);
  }

  @override
  Duration get position => const Duration(seconds: 3);

  @override
  void setVolume(double volume) => this.volume = volume;

  @override
  void setBalance(double balance) {}

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  void seek(Duration position) => sought = position;

  @override
  Future<void> stop() async => active = false;
}

class _Device extends VideoCast {
  _Device();

  bool running = true;
  bool? pausedTo;
  Duration? sought;
  double? volume;
  bool? stoppedSilently;

  @override
  bool get active => running;

  @override
  Duration get position => const Duration(seconds: 40);

  @override
  bool get paused => pausedTo ?? false;

  @override
  void setPaused(bool paused) => pausedTo = paused;

  bool held = false;

  @override
  void hold() => held = true;

  @override
  void seek(Duration position) => sought = position;

  @override
  void setVolume(double volume) => this.volume = volume;

  @override
  Future<void> stop({bool silent = false}) async {
    running = false;
    stoppedSilently = silent;
  }
}

void main() {
  group("which videos a Chromecast plays", () {
    test("MP4, M4V, MOV and WebM files", () {
      for (final name in ["/a/b.mp4", "C:\\v\\b.M4V", "/x.mov", "/x.webm"]) {
        expect(VideoCastController.mediaType(name), CastMediaType.mp4);
      }
    });

    test("music files a Chromecast plays", () {
      for (final name in ["/m/a.mp3", "/m/a.M4A", "/m/a.flac", "/m/a.opus"]) {
        expect(VideoCastController.mediaType(name), CastMediaType.mp4);
      }
      expect(VideoCastController.mediaType("/m/a.wma"), isNull);
    });

    test("music is told to a device as audio", () async {
      expect(await VideoCastController.audioType("/m/a.mp3"), "audio/mpeg");
      expect(await VideoCastController.audioType("/m/a.FLAC"), "audio/flac");
      expect(await VideoCastController.audioType("/m/a.mp4"), isNull);
      expect(await VideoCastController.audioType("/m/a.m4v"), isNull);
    });

    test("addresses with no extension, like stations, are tried", () {
      expect(
        VideoCastController.mediaType("http://radio.example/stream"),
        CastMediaType.mp4,
      );
      expect(VideoCastController.mediaType("http://r.example/a.pls"), isNull);
      expect(VideoCastController.mediaType("http://r.example/a.mkv"), isNull);
      expect(VideoCastController.canCast("jellyfin://server/item"), isFalse);
    });

    test("MP4 and HLS addresses", () {
      expect(
        VideoCastController.mediaType("https://h/v.mp4?token=1"),
        CastMediaType.mp4,
      );
      expect(
        VideoCastController.mediaType("http://h/v.m3u8"),
        CastMediaType.hls,
      );
    });

    test("not Matroska, other formats, or a local playlist", () {
      expect(VideoCastController.mediaType("/a/b.mkv"), isNull);
      expect(VideoCastController.mediaType("/a/b.avi"), isNull);
      expect(VideoCastController.mediaType("/a/b.m3u8"), isNull);
      expect(VideoCastController.mediaType("/a/noextension"), isNull);
    });
  });

  group("the player while a video plays on a device", () {
    late Directory dir;
    late _Video video;
    late _Device device;
    late PlayerState player;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync("video_cast_test");
      final clip = (File("${dir.path}/clip.mp4")..createSync()).path;
      video = _Video();
      device = _Device();
      player = PlayerState(engine: _Audio(), video: video)..cast = device;
      await player.playlist.add([clip]);
      await player.playIndex(0);
      device.running = true;
    });

    tearDown(() {
      player.stop();
      dir.deleteSync(recursive: true);
    });

    test("pause, seek and volume go to the device", () {
      player.castStarted();
      expect(video.paused, isTrue);
      player.pause();
      expect(device.pausedTo, isTrue);
      player.pause();
      expect(device.pausedTo, isFalse);
      expect(video.paused, isTrue);
      player.setSeek(128);
      expect(device.sought, const Duration(seconds: 50));
      player.setVolume(255);
      expect(device.volume, 1);
    });

    test("ending the cast resumes here where the device was", () {
      player.castStarted();
      player.castEnded(const Duration(seconds: 40), false);
      expect(video.sought, const Duration(seconds: 40));
      expect(video.paused, isFalse);
      expect(player.elapsedSec, 40);
    });

    test("moving on to the next track sends it to the device", () async {
      var followed = 0;
      player.castFollow = () => followed++;
      await player.playIndex(0);
      expect(device.held, isTrue);
      expect(device.stoppedSilently, isNull);
      expect(video.paused, isTrue);
      expect(video.volume, 0);
      expect(followed, 1);
    });

    test("stopping ends the cast without resuming", () {
      player.stop();
      expect(device.stoppedSilently, isTrue);
    });
  });
}
