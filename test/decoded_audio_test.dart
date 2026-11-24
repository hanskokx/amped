import "dart:io";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/video_engine.dart";
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

/// Decodes to "<location>.wav" and never shows a picture.
class _FakeDecoder extends VideoEngine {
  final List<String> extracted = [];
  final List<String> opened = [];

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
    opened.add(location);
    return null;
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

/// A first Ogg page whose packet starts with [packet].
List<int> _ogg(List<int> packet) => [
  ..."OggS".codeUnits,
  ...List.filled(22, 0),
  1, // One segment,
  packet.length,
  ...packet,
];

void main() {
  late Directory dir;
  late _FakeAudio audio;
  late _FakeDecoder decoder;
  late PlayerState player;

  String file(String name, [List<int> bytes = const []]) =>
      (File("${dir.path}/$name")..writeAsBytesSync(bytes)).path;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync("decoded_audio_test");
    audio = _FakeAudio();
    decoder = _FakeDecoder();
    player = PlayerState(engine: audio, video: decoder);
  });

  tearDown(() {
    player.stop();
    dir.deleteSync(recursive: true);
  });

  test("formats SoLoud cannot decode are told by extension", () {
    for (final name in [
      "a.ape",
      "a.MPC",
      "a.wv",
      "a.tta",
      "a.tak",
      "a.ofr",
      "a.spx",
    ]) {
      expect(Playlist.isAudio(name), isTrue, reason: name);
      expect(Playlist.needsDecoder(name), isTrue, reason: name);
    }
    for (final name in ["a.mp3", "a.wav", "a.flac", "a.opus", "a.txt"]) {
      expect(Playlist.needsDecoder(name), isFalse, reason: name);
    }
  });

  test("Ogg Speex and Ogg FLAC are told from Vorbis by content", () {
    final speex = file("s.ogg", _ogg("Speex   ".codeUnits));
    final flac = file("f.oga", _ogg([0x7f, ..."FLAC".codeUnits]));
    final vorbis = file("v.ogg", _ogg([1, ..."vorbis".codeUnits]));
    final opus = file("o.oga", _ogg("OpusHead".codeUnits));
    expect(Playlist.needsDecoder(speex), isTrue);
    expect(Playlist.needsDecoder(flac), isTrue);
    expect(Playlist.needsDecoder(vorbis), isFalse);
    expect(Playlist.needsDecoder(opus), isFalse);
    expect(Playlist.needsDecoder("${dir.path}/missing.ogg"), isFalse);
  });

  test("the playlist takes them, also from folders", () async {
    final ape = file("a.ape");
    final mp3 = file("b.mp3");
    final playlist = Playlist();
    await playlist.add([dir.path]);
    expect(playlist.entries.map((e) => e.location), [ape, mp3]);
  });

  test("they play decoded, with no picture", () async {
    final ape = file("a.ape");
    final mp3 = file("b.mp3");
    await player.playlist.add([ape, mp3]);
    await player.playIndex(0);
    expect(decoder.extracted, [ape]);
    expect(audio.played, ["$ape.wav"]);
    expect(decoder.opened, isEmpty);
    expect(player.videoPlaying, isFalse);
    expect(player.playing, isTrue);
    await player.playIndex(1);
    expect(decoder.extracted, [ape]);
    expect(audio.played.last, mp3);
  });

  test("Ogg FLAC plays decoded; Vorbis stays with SoLoud", () async {
    final flac = file("f.oga", _ogg([0x7f, ..."FLAC".codeUnits]));
    final vorbis = file("v.ogg", _ogg([1, ..."vorbis".codeUnits]));
    await player.playlist.add([flac, vorbis]);
    await player.playIndex(0);
    expect(audio.played, ["$flac.wav"]);
    await player.playIndex(1);
    expect(audio.played.last, vorbis);
  });

  test("without a decoder they are skipped", () async {
    final ape = file("a.ape");
    final mp3 = file("b.mp3");
    final bare = PlayerState(engine: audio);
    await bare.playlist.add([ape, mp3]);
    await bare.playIndex(0);
    expect(audio.played, [mp3]);
    bare.stop();
  });
}
