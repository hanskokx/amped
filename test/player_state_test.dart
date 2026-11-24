import "dart:io";
import "dart:math";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/eq_presets.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/playlist.dart";
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Records what would be played; every track "fails" to open so no ticker
/// or audio device is started.
class _FakeEngine extends AudioEngine {
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

/// "Plays" every track with a fixed length and never reports its end, like
/// a SoLoud MP3 stream whose voice outlives the audio; the position is set
/// by the test.
class _OverrunEngine extends AudioEngine {
  final List<String> played = [];
  final List<VoidCallback> finishCallbacks = [];

  /// The crossfade length each track in [played] was started with.
  final List<Duration?> crossfades = [];
  Duration fakePosition = Duration.zero;

  static const Duration length = Duration(seconds: 219);

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async {
    played.add(location);
    crossfades.add(crossfade);
    finishCallbacks.add(onFinished);
    fakePosition = Duration.zero;
    return length;
  }

  @override
  Future<void> stop() async {}

  /// Where the player seeked to.
  final List<Duration> seeks = [];

  @override
  void seek(Duration position) => seeks.add(position);

  @override
  Duration get position => fakePosition;
}

/// "Plays" every location as a live station that announces its bitrate
/// and sample rate; the test sends its song titles.
class _StationEngine extends AudioEngine {
  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async {
    streamInfo.value = StreamInfo(location, bitrate: 320, sampleRate: 44100);
    return Duration.zero;
  }

  @override
  Future<void> stop() async => streamInfo.value = null;

  @override
  Duration get position => Duration.zero;

  void sendTitle(String title) =>
      streamInfo.value = streamInfo.value!.withTitle(title);
}

void main() {
  late Directory dir;
  late _FakeEngine engine;
  late PlayerState player;
  late List<String> files;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync("player_state_test");
    files = [
      for (final name in ["a", "b", "c", "d"])
        (File("${dir.path}/$name.mp3")..createSync()).path,
    ];
    engine = _FakeEngine();
    player = PlayerState(engine: engine);
    await player.playlist.add(files);
  });

  // The player is not disposed: the playlist reads tags in the background
  // and notifies when done, after the test ends.
  tearDown(() => dir.deleteSync(recursive: true));

  test("Play starts the first track when shuffle is off", () async {
    player.togglePlay();
    await pumpEventQueue();
    expect(engine.played.first, files.first);
  });

  test("the Video window's always on top is for that window, or off", () {
    SharedPreferences.setMockInitialValues({});
    player.toggleVideoAlwaysOnTop();
    expect((player.alwaysOnTop, player.videoAlwaysOnTop), (false, true));
    player.toggleVideoAlwaysOnTop();
    expect((player.alwaysOnTop, player.videoAlwaysOnTop), (false, false));
    // From every window it turns them all off.
    player.toggleAlwaysOnTop();
    player.toggleVideoAlwaysOnTop();
    expect((player.alwaysOnTop, player.videoAlwaysOnTop), (false, false));
  });

  test(
    "always on top from the main menu turns the Video window's into all",
    () {
      SharedPreferences.setMockInitialValues({});
      player.toggleVideoAlwaysOnTop();
      player.toggleAlwaysOnTop();
      expect((player.alwaysOnTop, player.videoAlwaysOnTop), (true, false));
      player.toggleAlwaysOnTop();
      expect((player.alwaysOnTop, player.videoAlwaysOnTop), (false, false));
    },
  );

  test("mute brings back the volume from before", () {
    SharedPreferences.setMockInitialValues({});
    player.setVolume(120);
    player.toggleMute();
    expect(player.muted, isTrue);
    player.toggleMute();
    expect(player.volume, 120);
  });

  /// A shuffling player whose random picks come from `Random(seed)`.
  Future<PlayerState> seededPlayer(int seed) async {
    final player = PlayerState(
      engine: engine,
      playlist: Playlist(random: Random(seed)),
    )..shuffle = true;
    await player.playlist.add(files);
    return player;
  }

  test(
    "Play in shuffle mode starts a random track when none is picked",
    () async {
      const seed = 42;
      final player = await seededPlayer(seed);
      expect(player.playlist.hasChosenCurrent, isFalse);
      player.togglePlay();
      await pumpEventQueue();
      expect(engine.played.first, files[Random(seed).nextInt(files.length)]);
    },
  );

  test("Play in shuffle mode can start the first track", () async {
    var seed = 0;
    while (Random(seed).nextInt(files.length) != 0) {
      seed++;
    }
    final player = await seededPlayer(seed);
    player.togglePlay();
    await pumpEventQueue();
    expect(engine.played.first, files.first);
  });

  test("Play in shuffle mode keeps a picked or selected track", () async {
    player.shuffle = true;
    player.playlist.setCurrent(2);
    player.togglePlay();
    await pumpEventQueue();
    expect(engine.played.first, files[2]);

    player.playlist.clear();
    await player.playlist.add(files);
    player.playlist.select({1});
    engine.played.clear();
    player.togglePlay();
    await pumpEventQueue();
    expect(engine.played.first, files.first);
  });

  group("EQ AUTO", () {
    const songPreset = [40, 41, 42, 43, 44, 45, 46, 47, 48, 49];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await EqPresets.save(
        const EqPreset(name: "b.mp3", preamp: 20, bands: songPreset),
        autoLoad: true,
      );
    });

    test("loads the per-file preset when its track starts", () async {
      player.setEqAuto(true);
      await player.playIndex(1);
      expect(player.preamp, 20);
      expect(player.eqBands, songPreset);
    });

    test("does nothing while AUTO is off", () async {
      await player.playIndex(1);
      expect(player.eqBands, everyElement(31));
    });

    test("leaves the EQ alone for a track without a preset", () async {
      player.setEqAuto(true);
      await player.playIndex(1);
      // a.mp3 has no per-file preset and no genre tag.
      await player.playIndex(0);
      expect(player.eqBands, songPreset);
    });

    test("switching AUTO on loads the current track's preset", () async {
      player.playlist.setCurrent(1);
      player.setEqAuto(true);
      await pumpEventQueue();
      expect(player.eqBands, songPreset);
    });

    test("a track change while stopped re-evaluates the preset", () async {
      player.setEqAuto(true);
      player.next(); // a.mp3 -> b.mp3, nothing playing
      await pumpEventQueue();
      expect(player.playlist.current, 1);
      expect(player.eqBands, songPreset);
    });
  });

  group("Resuming a source track", () {
    test(
      "seeks to the offered position, and not when none is offered",
      () async {
        final overrun = _OverrunEngine();
        final player = PlayerState(engine: overrun);
        addTearDown(player.stop);
        const location = "amped-source://abs/item%7C1";
        await player.playlist.add([location, files.first]);
        final asked = <String>[];
        player.resumeOffer = (entry) async {
          asked.add(entry.location);
          return entry.location == location
              ? const Duration(seconds: 100)
              : null;
        };
        await player.playIndex(0);
        expect(overrun.seeks, [const Duration(seconds: 100)]);
        expect(player.elapsedSec, 100);
        await player.playIndex(1);
        expect(overrun.seeks, hasLength(1));
        // Only tracks of a remote source are asked about.
        expect(asked, [location]);
      },
    );
  });

  group("Reporting progress", () {
    test("tells where a source track was left, and that it ended", () async {
      final overrun = _OverrunEngine();
      final player = PlayerState(engine: overrun);
      addTearDown(player.stop);
      const location = "amped-source://abs/item%7C1";
      await player.playlist.add([location, files.first]);
      final reports = <(String, Duration, bool)>[];
      player.progressReporter = (
        entry,
        position,
        length, {
        required finished,
      }) => reports.add((entry.location, position, finished));
      await player.playIndex(0);
      overrun.fakePosition = const Duration(seconds: 42);
      player.pause();
      expect(reports, [(location, const Duration(seconds: 42), false)]);
      // Resuming and skipping away reports where it was left again.
      player.pause();
      await player.playIndex(1);
      expect(reports, hasLength(2));
      // A local file is no business of the server's.
      overrun.fakePosition = const Duration(seconds: 7);
      player.stop();
      expect(reports, hasLength(2));
      // Playing it to the end.
      await player.playIndex(0);
      overrun.fakePosition = _OverrunEngine.length + PlayerState.overrunGrace;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(reports.last, (location, _OverrunEngine.length, true));
      // Nothing more is said once it ended.
      final count = reports.length;
      player.stop();
      expect(reports, hasLength(count));
    });
  });

  group("End of track", () {
    late _OverrunEngine overrun;
    late PlayerState player;

    setUp(() async {
      overrun = _OverrunEngine();
      player = PlayerState(engine: overrun);
      await player.playlist.add(files);
      await player.playIndex(0);
    });

    tearDown(() => player.stop());

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test("a track still playing at its length keeps playing", () async {
      overrun.fakePosition = _OverrunEngine.length;
      await tick();
      expect(overrun.played, [files[0]]);
    });

    test("a position past the length moves on to the next track", () async {
      overrun.fakePosition = _OverrunEngine.length + PlayerState.overrunGrace;
      await tick();
      expect(overrun.played, [files[0], files[1]]);
    });

    test("the engine's end report after an overrun is ignored", () async {
      overrun.fakePosition = _OverrunEngine.length + PlayerState.overrunGrace;
      await tick();
      overrun.finishCallbacks.first();
      await pumpEventQueue();
      expect(overrun.played, [files[0], files[1]]);
    });

    test("a repeated end report advances only once", () async {
      overrun.finishCallbacks.first();
      overrun.finishCallbacks.first();
      await pumpEventQueue();
      expect(overrun.played, [files[0], files[1]]);
    });

    test("repeat track plays the finished track again", () async {
      player.repeatValue = -1;
      expect(player.repeat && player.manualAdvance, isTrue);
      overrun.finishCallbacks.last();
      await pumpEventQueue();
      overrun.finishCallbacks.last();
      await pumpEventQueue();
      expect(overrun.played, [files[0], files[0], files[0]]);
    });

    test("manual advance without repeat stops at the track's end", () async {
      player.manualAdvance = true;
      overrun.finishCallbacks.last();
      await pumpEventQueue();
      expect(overrun.played, [files[0]]);
      expect(player.playing, isFalse);
    });

    test("Next still moves on in repeat track", () async {
      player.repeatValue = -1;
      player.next();
      await pumpEventQueue();
      expect(overrun.played, [files[0], files[1]]);
    });
  });

  test("Repeat's config value is off, the playlist or the track", () {
    expect(player.repeatValue, 0);
    player.repeatValue = 1;
    expect((player.repeat, player.manualAdvance), (true, false));
    player.repeatValue = -1;
    expect((player.repeat, player.manualAdvance), (true, true));
    expect(player.repeatValue, -1);
    // R toggles repeat alone, as the classic player's FILE_REPEAT does.
    player.toggleRepeat();
    expect(player.repeatValue, 0);
    player.toggleRepeat();
    expect(player.repeatValue, -1);
    player.repeatValue = 0;
    expect((player.repeat, player.manualAdvance), (false, false));
  });

  test("a station's song titles show while its entry keeps its own", () async {
    const url = "http://45.85.191.114:8012/OldMenRock";
    final station = _StationEngine();
    final player = PlayerState(engine: station);
    addTearDown(player.stop);
    await player.playlist.add([url]);
    final entry = player.playlist.entries.single
      ..title = "(#1 - 51/350) ISKC Old Men's Rock";
    await player.playIndex(0);
    expect(player.bitrate, 320);
    expect(player.mixrate, 44);
    expect(entry.duration, isNull, reason: "a station has no length");
    expect(player.title, "1. (#1 - 51/350) ISKC Old Men's Rock");

    station.sendTitle("Thin Lizzy - The Boys Are Back in Town");
    expect(player.title, "1. Thin Lizzy - The Boys Are Back in Town");
    expect(entry.playingTitle, "Thin Lizzy - The Boys Are Back in Town");
    expect(entry.artist, "Thin Lizzy");
    expect(entry.trackTitle, "The Boys Are Back in Town");
    // The playlist (and the list saved from it) shows the station.
    expect(entry.title, "(#1 - 51/350) ISKC Old Men's Rock");

    station.sendTitle("Station ID");
    expect(player.title, "1. Station ID");
    expect(entry.artist, isNull);

    player.stop();
    await pumpEventQueue();
    expect(player.title, "1. (#1 - 51/350) ISKC Old Men's Rock");
    expect(entry.streamTitle, isNull);
    expect(entry.trackTitle, isNull);
  });

  group("Crossfading", () {
    late _OverrunEngine overrun;
    late PlayerState player;
    const length = _OverrunEngine.length;
    const fade = PlayerState.crossfadeLength;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      overrun = _OverrunEngine();
      player = PlayerState(engine: overrun)..setCrossfade(true);
      await player.playlist.add(files);
      await player.playIndex(0);
    });

    tearDown(() => player.stop());

    Future<void> tick() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    test("is off at first", () {
      expect(PlayerState(engine: overrun).crossfade, isFalse);
    });

    test("starts the next track before the current one ends", () async {
      overrun.fakePosition = length - fade - const Duration(seconds: 1);
      await tick();
      expect(overrun.played, [files[0]]);
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played, [files[0], files[1]]);
      expect(overrun.crossfades, [null, fade]);
      expect(player.playlist.current, 1);
      expect(player.playing, isTrue);
    });

    test("fades over the time the current track has left", () async {
      overrun.fakePosition = length - const Duration(milliseconds: 1500);
      await tick();
      expect(overrun.crossfades.last, const Duration(milliseconds: 1500));
    });

    test("the fading track's end report is ignored", () async {
      overrun.fakePosition = length - fade;
      await tick();
      overrun.finishCallbacks.first();
      await pumpEventQueue();
      expect(overrun.played, [files[0], files[1]]);
    });

    test("fades into the same track in repeat track", () async {
      player.repeatValue = -1;
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played, [files[0], files[0]]);
      expect(overrun.crossfades, [null, fade]);
    });

    test("does not fade with manual advance alone", () async {
      player.manualAdvance = true;
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played, [files[0]]);
    });

    test("does nothing while off", () async {
      player.setCrossfade(false);
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played, [files[0]]);
    });

    test("does not run past the last track without repeat", () async {
      await player.playIndex(files.length - 1);
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played.last, files.last);
      expect(overrun.played, hasLength(2));
      // The track then ends as usual and playback stops.
      overrun.finishCallbacks.last();
      await pumpEventQueue();
      expect(player.playing, isFalse);
    });

    test("wraps to the first track with repeat", () async {
      player.toggleRepeat();
      await player.playIndex(files.length - 1);
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played.last, files.first);
      expect(overrun.crossfades.last, fade);
    });

    test("leaves Stop after current alone", () async {
      player.toggleStopAfterCurrent();
      overrun.fakePosition = length - fade;
      await tick();
      expect(overrun.played, [files[0]]);
      overrun.finishCallbacks.first();
      await pumpEventQueue();
      expect(player.playing, isFalse);
      expect(overrun.played, [files[0]]);
    });

    test("manual track changes cut over without fading", () async {
      player.next();
      await pumpEventQueue();
      expect(overrun.crossfades, [null, null]);
    });

    test("is remembered", () async {
      final restored = PlayerState(engine: overrun);
      await restored.loadCrossfade();
      expect(restored.crossfade, isTrue);
      player.setCrossfade(false);
      await pumpEventQueue();
      await restored.loadCrossfade();
      expect(restored.crossfade, isFalse);
    });
  });
}
