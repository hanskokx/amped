import "dart:io";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/video_engine.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// "Plays" every location with a fixed length and never ends it.
class _FakeAudio extends AudioEngine {
  final List<String> played = [];
  bool? paused;
  Duration? sought;

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async {
    played.add(location);
    return const Duration(seconds: 100);
  }

  @override
  Future<void> stop() async {}

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  void seek(Duration position) => sought = position;
}

/// Records what the player asks of the picture.
class _FakeVideo extends VideoEngine {
  final List<String> opened = [];
  bool paused = true;
  Duration? sought;
  double? volume;
  double? balance;
  VoidCallback? finish;
  Duration at = Duration.zero;

  /// Files whose sound cannot be read.
  final Set<String> unreadable = {};

  @override
  bool active = false;

  @override
  Size? get videoSize => active ? const Size(320, 240) : null;

  @override
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  @override
  Future<String?> extractAudio(String location) async =>
      unreadable.contains(location) ? null : "$location.wav";

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double balance,
    required VoidCallback onFinished,
    String? audioLocation,
  }) async {
    if (unreadable.contains(location)) return null;
    opened.add(location);
    this.volume = volume;
    this.balance = balance;
    finish = onFinished;
    paused = false;
    active = true;
    notifyListeners();
    return const Duration(seconds: 100);
  }

  @override
  Duration get position => at;

  @override
  void setVolume(double volume) => this.volume = volume;

  @override
  void setBalance(double balance) => this.balance = balance;

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  void seek(Duration position) => sought = position;

  @override
  Future<void> stop() async {
    if (!active) return;
    active = false;
    notifyListeners();
  }
}

void main() {
  late Directory dir;
  late _FakeAudio audio;
  late _FakeVideo video;
  late PlayerState player;
  late String song;
  late String clip;

  String file(String name) => (File("${dir.path}/$name")..createSync()).path;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync("video_test");
    song = file("song.mp3");
    clip = file("clip.mp4");
    audio = _FakeAudio();
    video = _FakeVideo();
    player = PlayerState(engine: audio, video: video);
    await player.playlist.add([song, clip]);
  });

  // The player is not disposed: the playlist reads tags in the background
  // and notifies when done, after the test ends.
  tearDown(() {
    player.stop();
    dir.deleteSync(recursive: true);
  });

  test("the playlist takes video files, also from folders", () async {
    file("notes.txt");
    final playlist = Playlist();
    await playlist.add([dir.path]);
    expect(playlist.entries.map((e) => e.location), [clip, song]);
    expect(Playlist.isVideo(clip), isTrue);
    expect(Playlist.isVideo(song), isFalse);
    expect(Playlist.isVideo("${dir.path}/MOVIE.MKV"), isTrue);
  });

  test("a video plays, sound and picture, in the video engine", () async {
    await player.playIndex(1);
    expect(audio.played, isEmpty);
    expect(video.opened, [clip]);
    expect(
      player.playlist.currentEntry?.duration,
      const Duration(seconds: 100),
    );
    expect(video.paused, isFalse);
    expect(player.videoPlaying, isTrue);
    expect(player.playing, isTrue);
  });

  test("the Video window opens with a video and closes after it", () async {
    await player.playIndex(1);
    expect(player.videoOpen, isTrue);
    await player.playIndex(0);
    expect(audio.played.last, song);
    expect(player.videoPlaying, isFalse);
    expect(player.videoOpen, isFalse);

    await player.playIndex(1);
    player.stop();
    expect(player.videoOpen, isFalse);
  });

  test("the Video window stays as it is with the options off", () async {
    player
      ..setVideoAutoOpen(false)
      ..setVideoAutoClose(false);
    await player.playIndex(1);
    expect(player.videoOpen, isFalse);
    player.setVideoOpen(true);
    player.stop();
    expect(player.videoOpen, isTrue);
  });

  test("an audio track leaves an open Video window alone", () async {
    player.setVideoOpen(true);
    await player.playIndex(0);
    player.stop();
    expect(player.videoOpen, isTrue);
  });

  test("closing the Video window stops the video, as the original", () async {
    await player.playIndex(1);
    player.closeVideoWindow();
    expect(player.videoOpen, isFalse);
    expect(player.playing, isFalse);
    expect(player.videoPlaying, isFalse);
  });

  test("closing it with Shift, or the option off, plays on", () async {
    await player.playIndex(1);
    player.closeVideoWindow(keepPlaying: true);
    expect(player.videoOpen, isFalse);
    expect(player.playing, isTrue);

    player
      ..setVideoOpen(true)
      ..setVideoStopOnClose(false)
      ..closeVideoWindow();
    expect(player.videoOpen, isFalse);
    expect(player.playing, isTrue);
    expect(player.videoPlaying, isTrue);
  });

  test("closing the Video window does not stop an audio track", () async {
    player.setVideoOpen(true);
    await player.playIndex(0);
    player.closeVideoWindow();
    expect(player.playing, isTrue);
  });

  test("pausing and seeking move the picture with the sound", () async {
    await player.playIndex(1);
    player.pause();
    expect(audio.paused, isTrue);
    expect(video.paused, isTrue);
    player.togglePlay();
    expect(video.paused, isFalse);
    player.setSeek(128);
    expect(video.sought, const Duration(seconds: 50));
  });

  test("volume and balance reach the video, from the start on", () async {
    player
      ..setVolume(51)
      ..setBalance(-127);
    await player.playIndex(1);
    expect(video.volume, closeTo(0.2, 0.001));
    expect(video.balance, -1);
    player.setVolume(255);
    player.setBalance(0);
    expect(video.volume, 1);
    expect(video.balance, 0);
  });

  test("a video that ends moves on to the next track", () async {
    await player.playIndex(1);
    video.finish!();
    await pumpEventQueue();
    // The clip is the last entry: playback stops.
    expect(player.playing, isFalse);
    expect(player.videoPlaying, isFalse);
  });

  test("a video does not crossfade in", () async {
    player.setCrossfade(true);
    await player.playIndex(0);
    expect(audio.played, [song]);
    await player.playIndex(1, crossfade: const Duration(seconds: 5));
    expect(audio.played, [song]);
    expect(video.opened, [clip]);
  });

  test("a video that cannot be read is skipped", () async {
    final second = file("second.mp3");
    await player.playlist.add([second]);
    video.unreadable.add(clip);
    await player.playIndex(1);
    await pumpEventQueue();
    expect(audio.played, [second]);
    expect(video.opened, isEmpty);
  });

  test("without a video engine a video file does not play", () async {
    final plain = PlayerState(engine: audio);
    await plain.playlist.add([clip]);
    await plain.playIndex(0);
    expect(audio.played, isEmpty);
    expect(plain.playing, isFalse);
  });

  test("silence for a video with no sound is a valid WAV", () async {
    final wav = File("${dir.path}/silence.wav");
    await MediaKitVideoEngine.writeSilence(wav, const Duration(seconds: 2));
    final bytes = wav.readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), "RIFF");
    expect(String.fromCharCodes(bytes.sublist(8, 12)), "WAVE");
    // 2 s of 8 kHz mono 16-bit after the 44-byte header.
    expect(bytes.length, 44 + 32000);
  });
}
