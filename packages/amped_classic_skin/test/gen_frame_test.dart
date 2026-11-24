import "dart:async";
import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

Future<ui.Image> _solid(int width, int height, int argb) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = (argb >> 16) & 0xFF;
    bytes[i + 1] = (argb >> 8) & 0xFF;
    bytes[i + 2] = argb & 0xFF;
    bytes[i + 3] = 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
}

void main() {
  testWidgets("the base skin keeps its own gen.bmp", (tester) async {
    final skin = (await tester.runAsync(loadBaseSkin))!;
    expect(skin.hasOwnGen, isTrue);
  });

  testWidgets("a derived frame takes the playlist's colours", (tester) async {
    await tester.runAsync(() async {
      final base = (await loadBaseSkin()).image("gen.bmp")!;
      final pledit = await _solid(280, 186, 0xFF204060);
      final derived = await deriveGenFrame(
        base: base,
        pledit: pledit,
        colors: const PlEditConfig(
          current: Color(0xFFFFFFFF),
          normal: Color(0xFF808080),
        ),
      );
      expect(derived.width, base.width);
      expect(derived.height, base.height);
      // Title bar, side border and bottom edge come from the playlist.
      expect(await _pixel(derived, 5, 5), [0x20, 0x40, 0x60]);
      expect(await _pixel(derived, 130, 50), [0x20, 0x40, 0x60]);
      expect(await _pixel(derived, 60, 48), [0x20, 0x40, 0x60]);
      expect(await _pixel(derived, 130, 76), [0x20, 0x40, 0x60]);
      // Pieces the frame doesn't use are untouched (the digits).
      expect(await _pixel(derived, 2, 20), await _pixel(base, 2, 20));
    });
  });

  testWidgets("a playlist too small to slice leaves the base frame", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final base = (await loadBaseSkin()).image("gen.bmp")!;
      final derived = await deriveGenFrame(
        base: base,
        pledit: await _solid(10, 10, 0xFF000000),
        colors: const PlEditConfig(),
      );
      expect(derived, same(base));
    });
  });

  testWidgets("render Reflex frame", (tester) async {
    const dir = String.fromEnvironment("REFSKIN");
    if (dir.isEmpty) return;
    final key = GlobalKey();
    late ClassicSkinData skin;
    await tester.runAsync(() async {
      final base = await loadBaseSkin();
      skin = await loadSkinFromDirectory(base, Directory(dir));
    });
    expect(skin.hasOwnGen, isFalse);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Row(
            children: [
              for (final s in [(skin.name, 275.0, 120.0)])
                SizedBox(
                  width: s.$2,
                  height: s.$3,
                  child: SkinnedDialogFrame(
                    skin: skin,
                    title: "New Track",
                    size: Size(s.$2, s.$3),
                    child: const SizedBox.expand(),
                  ),
                ),
              const SizedBox(width: 10),
              SizedBox(
                width: 275,
                height: 120,
                child: SkinnedDialogFrame(
                  skin: skin,
                  title: "Library",
                  size: const Size(275, 120),
                  onResizeStart: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File("$dir/../frame.png").writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
