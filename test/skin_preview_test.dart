// The native skin preview (native/skin_preview, used by the Quick Look,
// Windows shell and freedesktop thumbnailers), built with the system C
// compiler and run through its command-line thumbnailer.

import "dart:convert";
import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter_test/flutter_test.dart";

/// A PNG of [width]×[height] in [color], with the rectangle [clear] (if
/// any) transparent, made with the engine's encoder.
Future<Uint8List> _png(
  int width,
  int height,
  ui.Color color, {
  ui.Rect? clear,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = color,
    );
  if (clear != null) {
    canvas.drawRect(clear, ui.Paint()..blendMode = ui.BlendMode.clear);
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// An interlaced (Adam7) 8-bit RGBA PNG of [width]×[height] whose pixel at
/// (x, y) is `(x * 40, y * 40, 0, 255)`.
Uint8List _interlacedPng(int width, int height) {
  const passes = [
    [0, 0, 8, 8],
    [4, 0, 8, 8],
    [0, 4, 4, 8],
    [2, 0, 4, 4],
    [0, 2, 2, 4],
    [1, 0, 2, 2],
    [0, 1, 1, 2],
  ];
  final raw = <int>[];
  for (final [x0, y0, dx, dy] in passes) {
    for (var y = y0; y < height; y += dy) {
      if (x0 >= width) break;
      raw.add(0);
      for (var x = x0; x < width; x += dx) {
        raw.addAll([x * 40, y * 40, 0, 255]);
      }
    }
  }
  final data = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> body) {
    final length = ByteData(4)..setUint32(0, body.length);
    data
      ..add(length.buffer.asUint8List())
      ..add(type.codeUnits)
      ..add(body)
      // The checksum is not read.
      ..add([0, 0, 0, 0]);
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(12, 1);
  chunk("IHDR", header.buffer.asUint8List());
  chunk("IDAT", ZLibCodec().encode(raw));
  chunk("IEND", const []);
  return data.toBytes();
}

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

int _lastIndexOf(Uint8List bytes, List<int> pattern) {
  for (var i = bytes.length - pattern.length; i >= 0; i--) {
    var match = true;
    for (var j = 0; j < pattern.length && match; j++) {
      match = bytes[i + j] == pattern[j];
    }
    if (match) return i;
  }
  return -1;
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// A zip archive of [files], stored without compression.
Uint8List _zip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void le(BytesBuilder b, int value, int bytes) {
    for (var i = 0; i < bytes; i++) {
      b.addByte((value >> (8 * i)) & 0xFF);
    }
  }

  for (final MapEntry(key: name, value: data) in files.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(name);
    final crc = _crc32(data);
    le(out, 0x04034b50, 4);
    le(out, 20, 2); // Version needed.
    le(out, 0, 2); // Flags.
    le(out, 0, 2); // Stored.
    le(out, 0, 4); // Time and date.
    le(out, crc, 4);
    le(out, data.length, 4);
    le(out, data.length, 4);
    le(out, nameBytes.length, 2);
    le(out, 0, 2);
    out
      ..add(nameBytes)
      ..add(data);
    le(central, 0x02014b50, 4);
    le(central, 20, 2); // Version made by.
    le(central, 20, 2);
    le(central, 0, 2);
    le(central, 0, 2);
    le(central, 0, 4);
    le(central, crc, 4);
    le(central, data.length, 4);
    le(central, data.length, 4);
    le(central, nameBytes.length, 2);
    le(central, 0, 2); // Extra.
    le(central, 0, 2); // Comment.
    le(central, 0, 2); // Disk.
    le(central, 0, 2); // Internal attributes.
    le(central, 0, 4); // External attributes.
    le(central, offset, 4);
    central.add(nameBytes);
  }
  final centralOffset = out.length;
  final centralBytes = central.takeBytes();
  out.add(centralBytes);
  le(out, 0x06054b50, 4);
  le(out, 0, 4); // Disks.
  le(out, files.length, 2);
  le(out, files.length, 2);
  le(out, centralBytes.length, 4);
  le(out, centralOffset, 4);
  le(out, 0, 2);
  return out.takeBytes();
}

/// A 600×100 solid red JPEG.
const _jpeg =
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUG"
    "BgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYH"
    "CgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAAR"
    "CABkAlgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAA"
    "AgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK"
    "FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG"
    "h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl"
    "5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA"
    "AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYk"
    "NOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE"
    "hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk"
    "5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD4vooor+Uz/fwKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKA"
    "CiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoo"
    "ooAKKKKACiiigAooooAKKKKAP//Z";

/// A 600×100 solid red GIF.
const _gif =
    "R0lGODdhWAJkAIEAAP8AAAAAAAAAAAAAACwAAAAAWAJkAEAI/wABCBxIsKDBgwgTKlzIsKHD"
    "hxAjSpxIsaLFixgzatzIsaPHjyBDihxJsqTJkyhTqlzJsqXLlzBjypxJs6bNmzhz6tzJs6fP"
    "n0CDCh1KtKjRo0iTKl3KtKnTp1CjSp1KtarVq1izat3KtavXr2DDih1LtqzZs2jTql3Ltq3b"
    "t3Djyp1Lt67du3jz6t3Lt6/fv4ADCx5MuLDhw4gTK17MuLHjx5AjS55MubLly5gza97MubPn"
    "z6BDix5NurTp06hTq17NurXr17Bjy55Nu7bt27hz697Nu7fv38CDCx9OvLjx48iTK1/OvLnz"
    "59CjS59Ovbr169iza9/Ovbv37+DDi5QfT768+fPo06tfz769+/fw48ufT7++/fv48+vfz7+/"
    "//8ABijggAQWaOCBCCao4IIMNujggxBGKOGEFFZo4YUYZqjhhhx26OGHIIYo4ogklmjiiSim"
    "qOKKLLbo4oswxijjjDTWaOONOOao44489ujjj0AGKeSQRBZp5JFIJqnkkkw26eSTUEYp5ZRU"
    "VmnllVhmuWNAADs=";

void main() {
  late Directory temp;
  late String thumbnailer;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp("skin_preview_test");
    thumbnailer = "${temp.path}/thumbnailer";
    final build = await Process.run("cc", [
      "-O1",
      "-o",
      thumbnailer,
      "native/skin_preview/skin_preview.c",
      "native/skin_preview/skin_thumbnailer.c",
    ]);
    expect(build.exitCode, 0, reason: "${build.stdout}${build.stderr}");
  });

  tearDownAll(() => temp.delete(recursive: true));

  /// The preview of [skin] at its own size, as straight RGBA rows.
  Future<(int, int, Uint8List)> preview(Uint8List skin, int longest) async {
    final input = File("${temp.path}/skin.wal")..writeAsBytesSync(skin);
    final output = "${temp.path}/preview.png";
    final run = await Process.run(thumbnailer, [
      "-s",
      "$longest",
      input.path,
      output,
    ]);
    expect(run.exitCode, 0, reason: "${run.stdout}${run.stderr}");
    final codec = await ui.instantiateImageCodec(
      File(output).readAsBytesSync(),
    );
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return (image.width, image.height, data!.buffer.asUint8List());
  }

  test(
    "a .wal's interlaced images are drawn, and a group at alpha 0 is not",
    () async {
      const red = ui.Color(0xFFFF0000);
      const green = ui.Color(0xFF00FF00);
      final skin = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <elements>
    <bitmap id="bg" file="bg.png"/>
    <bitmap id="grid" file="grid.png"/>
    <bitmap id="green" file="green.png"/>
  </elements>
  <groupdef id="hidden">
    <layer image="green" x="0" y="0"/>
  </groupdef>
  <container id="main">
    <layout id="normal" background="bg">
      <layer image="grid" x="1" y="1"/>
      <group id="hidden" x="0" y="7" alpha="0"/>
    </layout>
  </container>
</WinampAbstractionLayer>
"""),
        "Skin/bg.png": await _png(8, 8, red),
        "Skin/grid.png": _interlacedPng(5, 5),
        "Skin/green.png": await _png(1, 1, green),
      });

      final (width, height, rgba) = await preview(skin, 8);
      expect((width, height), (8, 8));
      List<int> pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return rgba.sublist(i, i + 4);
      }

      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          expect(
            pixel(1 + x, 1 + y),
            [x * 40, y * 40, 0, 255],
            reason: "the interlaced image's pixel ($x, $y)",
          );
        }
      }
      expect(pixel(0, 7), [255, 0, 0, 255], reason: "alpha=0 hides a group");
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test(
    "what a mask group holds is cut to the group's own rectangle",
    () async {
      const red = ui.Color(0xFFFF0000);
      const green = ui.Color(0xFF00FF00);
      final skin = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <elements>
    <bitmap id="bg" file="bg.png"/>
    <bitmap id="mask" file="mask.png"/>
    <bitmap id="green" file="green.png"/>
  </elements>
  <groupdef id="drawer" background="mask" drawbackground="0">
    <group id="panel" x="-4" sysregion="AND"/>
  </groupdef>
  <groupdef id="panel">
    <layer image="green" x="0" y="0"/>
    <layer image="green" x="5" y="0"/>
  </groupdef>
  <container id="main">
    <layout id="normal" background="bg">
      <group id="drawer" x="4" y="0"/>
    </layout>
  </container>
</WinampAbstractionLayer>
"""),
        "Skin/bg.png": await _png(12, 2, red),
        "Skin/mask.png": await _png(6, 2, red),
        "Skin/green.png": await _png(1, 1, green),
      });

      final (width, height, rgba) = await preview(skin, 12);
      List<int> pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return rgba.sublist(i, i + 4);
      }

      // The drawer is at x 4..10; its panel starts at x 0, outside it.
      expect(pixel(0, 0), [255, 0, 0, 255], reason: "outside the mask");
      expect(pixel(5, 0), [0, 255, 0, 255], reason: "inside the mask");
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test("a .wal without a screenshot shows its main layout's objects", () async {
    const red = ui.Color(0xFFFF0000);
    const blue = ui.Color(0xFF0000FF);
    const green = ui.Color(0xFF00FF00);
    final skin = _zip({
      "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <elements>
    <bitmap id="bg" file="bg.png"/>
    <bitmap id="Blue" file="blue.png"/>
    <bitmap id="green" file="sheet.png" x="1" y="0" w="1" h="1"/>
  </elements>
  <include file="xml/groups.xml"/>
  <container id="main">
    <layout id="normal" background="bg">
      <layer image="blue" x="1" y="1"/>
      <!-- <layer image="green" x="0" y="0"/> -->
      <layer image="green" x="0" y="3" visible="0"/>
      <layer image="green" x="2" y="3" alpha="0"/>
      <group id="g" x="3" y="2"/>
      <button image="green" x="-2" relatx="1"/>
      <layer image="green" x="7" y="1"/>
    </layout>
  </container>
</WinampAbstractionLayer>
"""),
      "Skin/xml/groups.xml": utf8.encode("""
<groupdef id="g">
  <layer image="green" x="1"/>
</groupdef>
"""),
      // The window's shape leaves out the right column, which is trimmed.
      "Skin/bg.png": await _png(
        8,
        4,
        red,
        clear: const ui.Rect.fromLTWH(7, 0, 1, 4),
      ),
      "Skin/blue.png": await _png(2, 2, blue),
      "Skin/sheet.png": await _png(
        2,
        1,
        green,
        clear: const ui.Rect.fromLTWH(0, 0, 1, 1),
      ),
    });

    final (width, height, rgba) = await preview(skin, 7);
    expect(
      (width, height),
      (7, 4),
      reason: "the transparent column is trimmed",
    );
    int pixel(int x, int y) {
      final i = (y * width + x) * 4;
      return rgba[i] << 24 | rgba[i + 1] << 16 | rgba[i + 2] << 8 | rgba[i + 3];
    }

    const r = 0xFF0000FF, b = 0x0000FFFF, g = 0x00FF00FF;
    expect(pixel(0, 0), r);
    expect(pixel(1, 1), b);
    expect(pixel(2, 2), b);
    expect(pixel(0, 3), r, reason: "visible=0 is not drawn");
    expect(pixel(2, 3), r, reason: "alpha=0 is not drawn");
    expect(pixel(4, 2), g, reason: "the group's layer, inside the group");
    expect(pixel(6, 0), g, reason: "relatx=1 places from the right edge");
  }, skip: Platform.isWindows ? "needs a C compiler named cc" : false);

  test(
    "a .wal's frames, content and other windows are drawn at full size",
    () async {
      const red = ui.Color(0xFFFF0000);
      const blue = ui.Color(0xFF0000FF);
      const green = ui.Color(0xFF00FF00);
      final skin = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <skininfo><screenshot>shot.png</screenshot></skininfo>
  <elements>
    <bitmap id="top" file="red.png"/>
    <bitmap id="blue" file="blue.png"/>
    <bitmap id="green" file="green.png"/>
  </elements>
  <!-- A frame with a menu bar, and the group it hosts. -->
  <groupdef id="frame" xuitag="My:Frame">
    <layer image="top" x="0" y="0" w="0" relatw="1"/>
    <group id="wasabi.menubar" x="0" y="4"/>
    <script file="frame.maki" param="0,4,0,0"/>
  </groupdef>
  <groupdef id="wasabi.menubar" h="2"><layer image="green" x="0" y="0"/></groupdef>
  <groupdef id="content"><layer image="blue" x="1" y="1"/></groupdef>
  <container id="main">
    <layout id="normal" w="40" h="20">
      <My:Frame x="0" y="0" w="0" relatw="1" h="0" relath="1" content="content"/>
    </layout>
  </container>
  <container id="eq">
    <layout id="normal" background="green"/>
  </container>
</WinampAbstractionLayer>
"""),
        // A thumbnail of the main window, much smaller than its layout.
        "Skin/shot.png": await _png(4, 2, red),
        "Skin/red.png": await _png(40, 4, red),
        "Skin/blue.png": await _png(2, 2, blue),
        "Skin/green.png": await _png(40, 6, green),
      });

      final (width, height, rgba) = await preview(skin, 40);
      // The layout, not the thumbnail, is drawn: the main window (trimmed to
      // the 10 rows with something on them) with the equalizer (40x6) drawn
      // from row 4.
      expect((width, height), (40, 10));
      int pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return rgba[i] << 24 |
            rgba[i + 1] << 16 |
            rgba[i + 2] << 8 |
            rgba[i + 3];
      }

      expect(pixel(0, 0), 0xFF0000FF, reason: "the frame's own layer");
      // The content sits at the frame's padding (4), where its menu bar is
      // too: a skin's content leaves room for the bar itself.
      expect(pixel(1, 5), 0x0000FFFF);
      expect(pixel(0, 9), 0x00FF00FF, reason: "the equalizer is drawn too");
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test(
    "a classic skin made of the overlay color is transparent",
    () async {
      final skin = _zip({"main.bmp": _bmp(275, 116, 0x10, 0x00, 0x10)});
      final (width, _, rgba) = await preview(skin, 348);
      int alpha(int x, int y) => rgba[(y * width + x) * 4 + 3];
      // Where nothing is drawn over the window, what is behind it shows.
      expect(alpha(270, 100), 0);
      // The skin's other windows are not overlay colored.
      expect(alpha(100, 200), 255);
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test(
    "a group's background is not drawn when drawbackground is 0",
    () async {
      const red = ui.Color(0xFFFF0000);
      const blue = ui.Color(0xFF0000FF);
      final skin = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <skininfo><screenshot>shot.png</screenshot></skininfo>
  <elements>
    <bitmap id="bg" file="red.png"/>
    <bitmap id="mask" file="blue.png"/>
  </elements>
  <!-- A mask: its shape clips the group, it is not a picture. -->
  <groupdef id="masked" background="mask" drawbackground="0"/>
  <groupdef id="shown" background="mask"/>
  <container id="main">
    <layout id="normal" background="bg">
      <group id="masked" x="0" y="0"/>
      <group id="shown" x="0" y="4"/>
    </layout>
  </container>
</WinampAbstractionLayer>
"""),
        "Skin/shot.png": await _png(4, 2, red),
        "Skin/red.png": await _png(6, 8, red),
        "Skin/blue.png": await _png(3, 3, blue),
      });

      final (width, _, rgba) = await preview(skin, 8);
      int pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return rgba[i] << 24 |
            rgba[i + 1] << 16 |
            rgba[i + 2] << 8 |
            rgba[i + 3];
      }

      expect(pixel(1, 1), 0xFF0000FF, reason: "the mask is not drawn");
      expect(pixel(1, 5), 0x0000FFFF, reason: "a background is");
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test(
    "a .wal cut short, with its zip directory partly gone, is still read",
    () async {
      const red = ui.Color(0xFFFF0000);
      final whole = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <elements><bitmap id="bg" file="red.png"/></elements>
  <include file="xml/main.xml"/>
</WinampAbstractionLayer>
"""),
        "Skin/xml/main.xml": utf8.encode("""
<container id="main"><layout id="normal" background="bg"/></container>
"""),
        "Skin/red.png": await _png(6, 4, red),
      });
      // The directory starts after the last file; cut off its last record
      // and the end that says where it is.
      final directory = _lastIndexOf(whole, [0x50, 0x4B, 0x01, 0x02]);
      final cut = Uint8List.sublistView(whole, 0, whole.length - 30);
      expect(directory, lessThan(cut.length));

      final (width, height, rgba) = await preview(cut, 6);
      expect((width, height), (6, 4));
      expect(rgba[0], 0xFF);
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test(
    "a bitmap past its file is clipped, an inactive-only layer is left out, the "
    "snap adjustment is not part of the window and the playlist has tracks",
    () async {
      const red = ui.Color(0xFFFF0000);
      const blue = ui.Color(0xFF0000FF);
      final skin = _zip({
        "Skin/skin.xml": utf8.encode("""
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
  <elements>
    <!-- Two rows past the 8 of its file. -->
    <bitmap id="tall" file="red.png" x="0" y="2" w="10" h="10"/>
    <bitmap id="blue" file="blue.png"/>
    <color id="wasabi.list.background" value="10,20,30"/>
  </elements>
  <container id="main">
    <layout id="normal" w="40" h="30" snapadjustbottom="10">
      <layer image="tall" x="0" y="0"/>
      <group id="playlistpro" x="0" y="8" w="40" h="14"/>
      <layer image="blue" x="20" y="0" w="4" h="4" activealpha="0"/>
      <layer image="blue" x="30" y="14" w="4" h="4"/>
    </layout>
  </container>
</WinampAbstractionLayer>
"""),
        "Skin/shot.png": await _png(4, 2, red),
        "Skin/red.png": await _png(10, 8, red),
        "Skin/blue.png": await _png(2, 2, blue),
      });

      final (width, height, rgba) = await preview(skin, 40);
      // The 30 rows of the layout less the 10 of the room kept for a drawer
      // (and the list reaches row 22, which is cut at 20).
      expect((width, height), (40, 20));
      int pixel(int x, int y) {
        final i = (y * width + x) * 4;
        return rgba[i] << 24 |
            rgba[i + 1] << 16 |
            rgba[i + 2] << 8 |
            rgba[i + 3];
      }

      expect(pixel(0, 5), 0xFF0000FF, reason: "the clipped bitmap is drawn");
      expect(pixel(0, 6) & 0xFF, 0, reason: "and no taller than its file");
      expect(pixel(21, 1) & 0xFF, 0, reason: "activealpha 0 is not drawn");
      expect(pixel(31, 15), 0x0000FFFF, reason: "a layer over the list");
      // The list is in the skin's color, with sample tracks in lighter pixels.
      expect(pixel(39, 19), 0x0A141EFF, reason: "the list background");
      var lighter = 0;
      for (var x = 0; x < 30; x++) {
        for (var y = 8; y < 20; y++) {
          if ((rgba[(y * width + x) * 4] & 0xFF) > 100) lighter++;
        }
      }
      expect(lighter, greaterThan(10), reason: "tracks are written in it");
    },
    skip: Platform.isWindows ? "needs a C compiler named cc" : false,
  );

  test("a Bamp skin in a zip is drawn as a classic skin", () async {
    const color = ui.Color(0xFF28323C);
    final skin = _zip({
      "MyBamp/00.png": await _png(275, 348, color),
      "MyBamp/font_and_palette.png": await _png(
        275,
        348,
        const ui.Color(0x00000000),
      ),
      "MyBamp/extra/readme.txt": utf8.encode("hello"),
    });

    final (width, height, rgba) = await preview(skin, 348);
    expect((width, height), (275, 348));
    int channel(int x, int y, int c) => rgba[(y * width + x) * 4 + c];
    // The main window's and the equalizer's backgrounds come from layer 00.
    for (final y in [110, 116 + 100]) {
      expect(
        [channel(5, y, 0), channel(5, y, 1), channel(5, y, 2)],
        [0x28, 0x32, 0x3C],
        reason: "row $y",
      );
    }
  }, skip: Platform.isWindows ? "needs a C compiler named cc" : false);

  test("a zip that holds no skin gets no preview", () async {
    final input = File("${temp.path}/other.zip")
      ..writeAsBytesSync(_zip({"notes.txt": utf8.encode("not a skin")}));
    final run = await Process.run(thumbnailer, [
      "-s",
      "64",
      input.path,
      "${temp.path}/other.png",
    ]);
    expect(run.exitCode, isNot(0));
  }, skip: Platform.isWindows ? "needs a C compiler named cc" : false);

  test(
    "a classic skin with a main window size hint is drawn at that size",
    () async {
      // A 24-bit BMP of the given size in one colour.
      Uint8List bmp(int width, int height, List<int> bgr) {
        final stride = (width * 3 + 3) & ~3;
        final out = Uint8List(54 + stride * height);
        final data = ByteData.sublistView(out)
          ..setUint8(0, 0x42)
          ..setUint8(1, 0x4D)
          ..setUint32(2, out.length, Endian.little)
          ..setUint32(10, 54, Endian.little)
          ..setUint32(14, 40, Endian.little)
          ..setInt32(18, width, Endian.little)
          ..setInt32(22, height, Endian.little)
          ..setUint16(26, 1, Endian.little)
          ..setUint16(28, 24, Endian.little);
        assert(data.lengthInBytes == out.length);
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            out.setRange(
              54 + y * stride + x * 3,
              54 + y * stride + x * 3 + 3,
              bgr,
            );
          }
        }
        return out;
      }

      final skin = _zip({
        "Skin/Main.bmp": bmp(600, 100, [0, 0, 255]),
        "Skin/skin.hints": utf8.encode(
          "[skin]\r\nmainwinWidth=600 //x\r\nMainwinHeight=100\r\n",
        ),
      });
      final (width, height, rgba) = await preview(skin, 600);
      // The main window is 600 wide and 100 high, the equalizer and playlist
      // (275 wide) below it.
      expect(width, 600);
      expect(height, 100 + 116 + 116);
      // The window's red (BGR 0,0,255) is its main.bmp, not the base skin's.
      expect(rgba.sublist(0, 4), [255, 0, 0, 255]);
      final far = (50 * width + 590) * 4;
      expect(rgba.sublist(far, far + 4), [255, 0, 0, 255]);
    },
  );

  test("a classic skin's PNG bitmaps stand in for its missing BMPs", () async {
    const red = ui.Color(0xFFFF0000);
    final skin = _zip({
      "Skin/MAIN.png": await _png(600, 100, red),
      "Skin/skin.hints": utf8.encode(
        "[skin]\nmainwinWidth=600\nmainwinHeight=100\n",
      ),
    });
    final (width, _, rgba) = await preview(skin, 600);
    // The main window is the skin's red PNG, not the base skin's.
    final far = (50 * width + 590) * 4;
    expect(rgba.sublist(far, far + 4), [255, 0, 0, 255]);
  });

  for (final (name, extension, data) in [
    ("JPEG", "jpg", _jpeg),
    ("GIF", "gif", _gif),
  ]) {
    test(
      "a classic skin's $name bitmap stands in for its missing BMP",
      () async {
        final skin = _zip({
          "Skin/MAIN.$extension": base64Decode(data),
          "Skin/skin.hints": utf8.encode(
            "[skin]\nmainwinWidth=600\nmainwinHeight=100\n",
          ),
        });
        final (width, _, rgba) = await preview(skin, 600);
        final far = (50 * width + 590) * 4;
        expect(rgba[far], greaterThan(240));
        expect(rgba[far + 1], lessThan(15));
        expect(rgba[far + 2], lessThan(15));
      },
    );
  }

  test("a PNG wins over a JPEG of the same bitmap", () async {
    const blue = ui.Color(0xFF0000FF);
    final skin = _zip({
      "Skin/main.png": await _png(600, 100, blue),
      "Skin/main.jpg": base64Decode(_jpeg),
      "Skin/skin.hints": utf8.encode(
        "[skin]\nmainwinWidth=600\nmainwinHeight=100\n",
      ),
    });
    final (width, _, rgba) = await preview(skin, 600);
    final far = (50 * width + 590) * 4;
    expect(rgba.sublist(far, far + 3), [0, 0, 255], reason: "the PNG is next");
  });
}
