import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped_bamp_skin/amped_bamp_skin.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

const _w = 275;
const _h = 348;

BampLayer _layer(
  void Function(Uint8List rgba, void Function(int x, int y, List<int> c) set)
  paint,
) {
  final rgba = Uint8List(_w * _h * 4);
  void set(int x, int y, List<int> c) {
    final i = (y * _w + x) * 4;
    rgba.setRange(i, i + 4, c);
  }

  paint(rgba, set);
  return BampLayer(width: _w, height: _h, rgba: rgba);
}

BampLayer _solid(List<int> color) => _layer((rgba, set) {
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      set(x, y, color);
    }
  }
});

BampLayer _empty() => BampLayer(
  width: _w,
  height: _h,
  rgba: Uint8List(_w * _h * 4),
);

List<int> _pixel(List<int> bmp, int x, int y) {
  final image = decodeBmp(Uint8List.fromList(bmp));
  final i = (y * image.width + x) * 4;
  return image.rgba.sublist(i, i + 3);
}

Uint8List _png(BampLayer layer) {
  final raw = BytesBuilder();
  for (var y = 0; y < layer.height; y++) {
    raw.addByte(0);
    raw.add(layer.rgba.sublist(y * layer.width * 4, (y + 1) * layer.width * 4));
  }
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final length = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)..setUint32(0, getCrc32(body));
    out
      ..add(length.buffer.asUint8List())
      ..add(body)
      ..add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, layer.width)
    ..setUint32(4, layer.height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk("IHDR", header.buffer.asUint8List());
  chunk("IDAT", zlib.encode(raw.toBytes()));
  chunk("IEND", const []);
  return out.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BampSpec spec;
  const formats = SkinFormats(converters: {BampSkinFormat()});

  setUpAll(() async {
    spec = await BampSpec.load();
  });

  test("the spec lists the layers bottom first, palette last", () {
    expect(spec.layerNames.first, "00.png");
    expect(spec.layerNames.last, "font_and_palette.png");
    expect(spec.layerNames, contains("37.png"));
  });

  test("a skin with a base layer and a palette layer is a Bamp skin", () {
    expect(isBampSkin({"00.png": [], "font_and_palette.png": []}), isTrue);
    expect(isBampSkin({"00.png": []}), isFalse);
    expect(isBampSkin({"main.bmp": []}), isFalse);
  });

  test("layers are spliced into the classic bitmaps", () {
    final files = composeBamp({
      "00.png": _solid([10, 20, 30, 255]),
    }, spec);

    expect(decodeBmp(Uint8List.fromList(files["main.bmp"]!)).width, 275);
    expect(decodeBmp(Uint8List.fromList(files["main.bmp"]!)).height, 116);
    expect(_pixel(files["main.bmp"]!, 100, 50), [10, 20, 30]);
    // The posbar background comes from the same layer.
    expect(_pixel(files["posbar.bmp"]!, 5, 5), [10, 20, 30]);
  });

  test("transparent pixels of the base layer become magenta", () {
    final files = composeBamp({"00.png": _empty()}, spec);
    expect(_pixel(files["main.bmp"]!, 100, 50), [255, 0, 255]);
  });

  test("an upper layer lies over the one beneath, alpha included", () {
    // Layer 01 draws the first volume background at [107, 57, 175, 70].
    final files = composeBamp({
      "00.png": _solid([0, 0, 200, 255]),
      "01.png": _layer((_, set) {
        set(107, 57, [255, 0, 0, 255]);
        set(108, 57, [255, 255, 255, 128]);
      }),
    }, spec);

    final volume = files["volume.bmp"]!;
    expect(_pixel(volume, 0, 0), [255, 0, 0]);
    final blended = _pixel(volume, 1, 0);
    expect(blended[0], inInclusiveRange(126, 130));
    expect(blended[2], inInclusiveRange(226, 229));
    // Elsewhere the lower layer shows through.
    expect(_pixel(volume, 2, 0), [0, 0, 200]);
  });

  test("a slider handle left transparent is cropped from the bitmap", () {
    final without = composeBamp({
      "00.png": _solid([0, 0, 0, 255]),
    }, spec);
    expect(decodeBmp(Uint8List.fromList(without["volume.bmp"]!)).height, 422);
    expect(decodeBmp(Uint8List.fromList(without["balance.bmp"]!)).height, 422);

    final handle = [for (final m in _handleRegions(spec)) m];
    BampLayer handles() => _layer((_, set) {
      for (final r in handle) {
        set(r[0], r[1], [255, 255, 255, 255]);
      }
    });
    // Both the handle and its pressed look are drawn, on layers 29 and 30.
    final withHandle = composeBamp({
      "00.png": _solid([0, 0, 0, 255]),
      "29.png": handles(),
      "30.png": handles(),
    }, spec);
    expect(
      decodeBmp(Uint8List.fromList(withHandle["volume.bmp"]!)).height,
      433,
    );
  });

  test("viscolor.txt and pledit.txt come from the palette swatches", () {
    final files = composeBamp({
      "00.png": _empty(),
      "font_and_palette.png": _layer((_, set) {
        // viscolor swatch 3 (12px tall, from x 0, y 35), centre pixel.
        set(6, 35 + 6 + 12 * 3, [1, 2, 3, 255]);
        // pledit swatch 1 ("Current"), from x 125, y 80.
        set(131, 80 + 6 + 12, [0xAB, 0xCD, 0xEF, 255]);
      }),
    }, spec);

    final viscolor = utf8.decode(files["viscolor.txt"]!).trim().split("\n");
    expect(viscolor, hasLength(24));
    expect(viscolor[3], "1, 2, 3");
    expect(parseVisColors(utf8.decode(files["viscolor.txt"]!)), hasLength(24));

    final pledit = parsePlEditConfig(utf8.decode(files["pledit.txt"]!));
    expect(pledit.current.toARGB32(), 0xFFABCDEF);
    expect(pledit.fontName, "Arial");
  });

  test("PNG layers load as a skin from an archive", () async {
    final archive = Archive();
    void add(String name, BampLayer layer) {
      final bytes = _png(layer);
      archive.addFile(ArchiveFile("MySkin/$name", bytes.length, bytes));
    }

    add("00.png", _solid([40, 50, 60, 255]));
    add("font_and_palette.png", _empty());
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    final base = await loadBaseSkin();
    final skin = await loadSkinFromArchive(
      base,
      zip,
      name: "Bamp Test",
      formats: formats,
    );

    expect(skin.name, "Bamp Test");
    final main = skin.image("main.bmp")!;
    expect((main.width, main.height), (275, 116));
    expect(identical(main, base.image("main.bmp")), isFalse);
    // A Bamp skin has no gen.bmp layer: its frame is derived from its
    // playlist editor rather than being the base skin's.
    expect(skin.hasOwnGen, isFalse);
    expect(identical(skin.image("gen.bmp"), base.image("gen.bmp")), isFalse);
  });

  test("a Bamp archive imports into the registry and loads", () async {
    final dir = await Directory.systemTemp.createTemp("bamp_registry_test");
    addTearDown(() => dir.delete(recursive: true));

    final archive = Archive();
    for (final name in ["00.png", "font_and_palette.png"]) {
      final bytes = _png(_solid([1, 2, 3, 255]));
      archive.addFile(ArchiveFile("bamp/$name", bytes.length, bytes));
    }
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));

    final registry = await SkinRegistry.load(dir);
    final info = await registry.importArchive(
      zip,
      fileName: "cool.zip",
      formats: formats,
    );
    expect(info.name, "cool");
    expect(info.format, SkinFormat.bamp);

    final skin = await registry.loadSkin(info, formats: formats);
    expect(skin.image("main.bmp")!.height, 116);
  });
}

/// A pixel in each optional slider-handle region of the spec's layers.
Iterable<List<int>> _handleRegions(BampSpec spec) => spec.handleRegions;
