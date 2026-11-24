import "dart:async";
import "dart:io";
import "dart:ui" as ui;
import "dart:ui" show Size;

import "package:amped/src/player/album_art.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";

/// Plays nothing, so no audio device is opened.
class _FakeEngine extends AudioEngine {
  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async => null;

  @override
  Future<void> stop() async {}
}

Future<ui.Image> _image(int size) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  return recorder.endRecording().toImage(size, size);
}

void main() {
  group("fitWindowToArt", () {
    // The classic frame: 19 wider and 34 taller than the picture.
    const frame = Size(19, 34);
    const min = Size(275, 116);

    Size fit(Size dragged, Size art) =>
        fitWindowToArt(dragged: dragged, frame: frame, art: art, min: min);

    test("gives the picture area the cover's shape", () {
      // A square cover in a window dragged wider than tall.
      expect(
        fit(const Size(519, 434), const Size(600, 600)),
        const Size(469, 484),
      );
      // A wide one: twice as wide as tall inside the frame.
      final wide = fit(const Size(819, 434), const Size(1000, 500));
      expect(wide.width - frame.width, (wide.height - frame.height) * 2);
    });

    test("follows the pointer along the cover's diagonal", () {
      final small = fit(const Size(319, 334), const Size(1, 1));
      final large = fit(const Size(619, 634), const Size(1, 1));
      expect(small, const Size(319, 334));
      expect(large, const Size(619, 634));
      // Dragged only one way, it still grows.
      expect(
        fit(const Size(619, 334), const Size(1, 1)).width,
        greaterThan(319),
      );
    });

    test("keeps to the minimum and maximum size", () {
      // A tall cover at the minimum width is taller than the minimum.
      expect(fit(const Size(100, 100), const Size(1, 2)), const Size(275, 546));
      final capped = fitWindowToArt(
        dragged: const Size(9000, 9000),
        frame: frame,
        art: const Size(1, 1),
        min: min,
        max: const Size(1000, 1000),
      );
      expect(capped, const Size(985, 1000));
    });
  });

  late Directory dir;
  late PlayerState player;
  late List<String> files;

  /// The files art was read for, and the reads still waiting.
  late List<String> reads;
  late Map<String, Completer<Uint8List?>> pending;

  /// The image each file's bytes decode to: its first byte's size.
  late Map<int, ui.Image> images;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync("album_art_test");
    files = [
      for (final name in ["a", "b", "c"])
        (File("${dir.path}/$name.mp3")..createSync()).path,
    ];
    player = PlayerState(engine: _FakeEngine());
    await player.playlist.add([...files, "http://example.com/stream"]);
    reads = [];
    pending = {};
    images = {
      for (final size in [4, 8]) size: await _image(size),
    };
  });

  tearDown(() => dir.deleteSync(recursive: true));

  NowPlayingArt art() => NowPlayingArt(
    player,
    read: (location) {
      reads.add(location);
      return (pending[location] = Completer()).future;
    },
    decode: (bytes) async => images[bytes.first],
  );

  test("reads the cover only once something shows it", () async {
    final loader = art();
    addTearDown(loader.dispose);
    player.playlist.setCurrent(1);
    player.playlist.setCurrent(0);
    await pumpEventQueue();
    expect(reads, isEmpty);

    loader.addListener(() {});
    await pumpEventQueue();
    expect(reads, [files[0]]);
    expect(loader.loading, isTrue);
    pending[files[0]]!.complete(Uint8List.fromList([4]));
    await pumpEventQueue();
    expect(loader.loading, isFalse);
    expect(loader.image, same(images[4]));
  });

  test("follows the playing item, ignoring a slow earlier read", () async {
    final loader = art();
    addTearDown(loader.dispose);
    loader.addListener(() {});
    await pumpEventQueue();
    player.playlist.setCurrent(1);
    await pumpEventQueue();
    expect(reads, [files[0], files[1]]);

    pending[files[1]]!.complete(Uint8List.fromList([8]));
    pending[files[0]]!.complete(Uint8List.fromList([4]));
    await pumpEventQueue();
    expect(loader.image, same(images[8]));

    // A file without art, then a stream (never read), show nothing.
    player.playlist.setCurrent(2);
    pending[files[2]]!.complete(null);
    await pumpEventQueue();
    expect(loader.image, isNull);
    player.playlist.setCurrent(3);
    await pumpEventQueue();
    expect(reads, hasLength(3));
    expect(loader.image, isNull);
    expect(loader.loading, isFalse);
  });

  test("refresh reads the cover again", () async {
    final loader = art();
    addTearDown(loader.dispose);
    loader.addListener(() {});
    await pumpEventQueue();
    pending[files[0]]!.complete(null);
    await pumpEventQueue();
    expect(loader.image, isNull);

    loader.refresh();
    pending[files[0]]!.complete(Uint8List.fromList([4]));
    await pumpEventQueue();
    expect(reads, [files[0], files[0]]);
    expect(loader.image, same(images[4]));
  });

  test("refreshing the same item keeps its cover on show", () async {
    final loader = art();
    addTearDown(loader.dispose);
    var changes = 0;
    loader.addListener(() => changes++);
    await pumpEventQueue();
    pending[files[0]]!.complete(Uint8List.fromList([4]));
    await pumpEventQueue();
    final shown = loader.image;
    expect(shown, same(images[4]));
    changes = 0;

    // A skin asking again every second: the cover stays put while it is
    // read, and the same file is no change.
    loader.refresh();
    expect(loader.image, same(shown));
    expect(loader.loading, isFalse);
    pending[files[0]]!.complete(Uint8List.fromList([4]));
    await pumpEventQueue();
    expect(loader.image, same(shown));
    expect(changes, 0);

    // A new cover in the file replaces it.
    loader.refresh();
    pending[files[0]]!.complete(Uint8List.fromList([8]));
    await pumpEventQueue();
    expect(loader.image, same(images[8]));
  });
}
