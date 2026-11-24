import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/video_engine.dart";
import "package:amped_youtube/amped_youtube.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

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
  final List<(String, String?)> played = [];
  final List<String> extracted = [];

  @override
  bool get active => false;

  @override
  Size? get videoSize => null;

  @override
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  @override
  Future<String?> extractAudio(String location) async {
    extracted.add(location);
    return "$location.wav";
  }

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double balance,
    required VoidCallback onFinished,
    String? audioLocation,
  }) async {
    played.add((location, audioLocation));
    return const Duration(seconds: 30);
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
  void seek(Duration position) {}

  @override
  Future<void> stop() async {}
}

class _FakeYouTube implements YouTubeResolver {
  _FakeYouTube(this.result);

  final YouTubeStreams? result;

  @override
  Future<List<YouTubeVideo>> playlist(String url) async => const [];

  @override
  Future<String?> streamUrl(String url) async => result?.audio;

  @override
  Future<YouTubeStreams?> streams(String url) async => result;
}

const _video = "https://www.youtube.com/watch?v=ksS4pLsru60";

void main() {
  late _FakeAudio audio;
  late _FakeVideo video;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    audio = _FakeAudio();
    video = _FakeVideo();
  });

  Future<PlayerState> play(
    YouTubeStreams? streams, {
    bool withVideo = true,
  }) async {
    final player = PlayerState(
      engine: audio,
      video: withVideo ? video : null,
      youtube: _FakeYouTube(streams),
    );
    await player.playlist.add([_video]);
    await player.playIndex(0);
    return player;
  }

  test(
    "a video plays picture and sound together in the video engine",
    () async {
      final player = await play(
        const YouTubeStreams(audio: "https://a/audio", video: "https://a/pic"),
      );
      expect(video.played, [("https://a/pic", "https://a/audio")]);
      expect(audio.played, isEmpty);
      player.stop();
    },
  );

  test("without a picture stream the sound is decoded and played", () async {
    final player = await play(const YouTubeStreams(audio: "https://a/audio"));
    expect(video.played, isEmpty);
    expect(video.extracted, ["https://a/audio"]);
    expect(audio.played, ["https://a/audio.wav"]);
    player.stop();
  });

  test("a link with no streams is skipped", () async {
    final player = await play(null);
    expect(video.played, isEmpty);
    expect(audio.played, isEmpty);
    player.stop();
  });
}
