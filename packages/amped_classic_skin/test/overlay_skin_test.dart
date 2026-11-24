import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

/// A 24-bit bitmap of [width]×[height] in one color.
Uint8List _bmp(int width, int height, int r, int g, int b) {
  final stride = (width * 3 + 3) & ~3;
  final out = BytesBuilder();
  void le(int value, int bytes) {
    for (var i = 0; i < bytes; i++) {
      out.addByte((value >> (8 * i)) & 0xFF);
    }
  }

  out.add([0x42, 0x4D]);
  le(54 + stride * height, 4);
  le(0, 4);
  le(54, 4);
  le(40, 4);
  le(width, 4);
  le(height, 4);
  le(1, 2);
  le(24, 2);
  le(0, 4);
  le(stride * height, 4);
  le(2835, 4);
  le(2835, 4);
  le(0, 4);
  le(0, 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out.add([b, g, r]);
    }
    out.add(List.filled(stride - width * 3, 0));
  }
  return out.takeBytes();
}

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.bytes(key, value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<int> _alphaAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData();
  return data!.getUint8((y * image.width + x) * 4 + 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("a skin made of the overlay color lets what is behind show", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final base = await loadBaseSkin();
      final skin = await loadSkinFromArchive(
        base,
        _zip({
          "main.bmp": _bmp(275, 116, 0x10, 0x00, 0x10),
          "eqmain.bmp": _bmp(275, 116, 0x10, 0x00, 0x10),
        }),
      );
      expect(skin.overlay, isTrue);
      expect(await _alphaAt(skin.image("main.bmp")!, 5, 5), 0);
      expect(await _alphaAt(skin.image("eqmain.bmp")!, 5, 5), 0);
    });
  });

  testWidgets("a skin that only has some of that color keeps it", (
    tester,
  ) async {
    await tester.runAsync(() async {
      final base = await loadBaseSkin();
      final skin = await loadSkinFromArchive(
        base,
        _zip({"main.bmp": _bmp(275, 116, 0x20, 0x20, 0x20)}),
      );
      expect(skin.overlay, isFalse);
      expect(await _alphaAt(skin.image("main.bmp")!, 5, 5), 255);
    });
  });
}
