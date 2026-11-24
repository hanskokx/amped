import "dart:io";
import "dart:typed_data";

import "package:amped/src/skin/input_idle_tracker.dart";
import "package:amped/src/skin/skin_preview_index.dart";
import "package:amped/src/skin/skin_preview_renderer.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync("preview_index"));
  tearDown(() => temp.deleteSync(recursive: true));

  final modified = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  test("a skin file as it was found is known, a changed one is not", () async {
    final file = File("${temp.path}/previews/index.json");
    final index = SkinPreviewIndex(file)
      ..record("/a.wal", 10, modified, "k", drawn: true);
    await index.save();

    final reloaded = SkinPreviewIndex(file);
    await reloaded.load();
    expect(reloaded.lookup("/a.wal", 10, modified)?.key, "k");
    expect(reloaded.lookup("/a.wal", 10, modified)?.drawn, isTrue);
    expect(reloaded.lookup("/a.wal", 11, modified), isNull, reason: "size");
    expect(
      reloaded.lookup("/a.wal", 10, modified.add(const Duration(seconds: 1))),
      isNull,
      reason: "modification time",
    );
    expect(reloaded.lookup("/b.wal", 10, modified), isNull);
  });

  test("a damaged index is an empty one", () async {
    final file = File("${temp.path}/index.json")
      ..writeAsStringSync("{not json");
    final index = SkinPreviewIndex(file);
    await index.load();
    expect(index.lookup("/a.wal", 1, modified), isNull);
  });

  test("a skin that could not be drawn is tried again after a week", () {
    var now = DateTime(2026, 11, 23);
    final index = SkinPreviewIndex(
      File("${temp.path}/index.json"),
      now: () => now,
    )..record("/a.wal", 10, modified, "k", drawn: false);

    expect(index.lookup("/a.wal", 10, modified), isNotNull);
    now = now.add(const Duration(days: 6));
    expect(index.lookup("/a.wal", 10, modified), isNotNull);
    now = now.add(const Duration(days: 2));
    expect(index.lookup("/a.wal", 10, modified), isNull);
  });

  test("an index nothing was added to writes nothing", () async {
    final file = File("${temp.path}/index.json");
    await SkinPreviewIndex(file).save();
    expect(file.existsSync(), isFalse);
  });

  test("the app is idle once it was left alone for the quiet time", () async {
    var now = DateTime(2026, 11, 23, 10);
    final tracker = InputIdleTracker(
      quiet: const Duration(seconds: 3),
      poll: const Duration(milliseconds: 1),
      now: () => now,
    );
    expect(tracker.isIdle, isTrue, reason: "nothing has happened yet");
    tracker.touch();
    expect(tracker.isIdle, isFalse);
    now = now.add(const Duration(seconds: 2));
    expect(tracker.isIdle, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(tracker.isIdle, isTrue);

    tracker.touch();
    var waited = false;
    final wait = tracker.whenIdle().then((_) => waited = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(waited, isFalse);
    now = now.add(const Duration(seconds: 4));
    await wait;
    expect(waited, isTrue);
  });

  test("the picture's visible bounds are found", () {
    // 4x3, one pixel at (2, 1) with alpha, one at (0, 0) too faint.
    final rgba = Uint8List(4 * 3 * 4);
    rgba[3] = 8;
    rgba[(1 * 4 + 2) * 4 + 3] = 255;
    expect(SkinPreviewRenderer.bounds(rgba, 4, 3), [2, 1, 2, 1]);
    expect(SkinPreviewRenderer.bounds(Uint8List(4 * 3 * 4), 4, 3), isNull);
  });
}
