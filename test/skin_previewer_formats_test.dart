import "dart:io";
import "dart:ui" as ui;

import "package:amped/src/skin/skin_previewer.dart";
import "package:flutter_test/flutter_test.dart";

Future<List<int>> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 2),
    ui.Paint()..color = const ui.Color(0xFF102030),
  );
  final image = await recorder.endRecording().toImage(4, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  test("bitmaps that are not BMP are converted for the renderer", () async {
    final dir = Directory.systemTemp.createTempSync("previewer_formats");
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = await _png();
    File("${dir.path}/MAIN.png").writeAsBytesSync(png);
    File("${dir.path}/cbuttons.png").writeAsBytesSync(png);
    File("${dir.path}/cbuttons.bmp").writeAsBytesSync([0]);
    File("${dir.path}/readme.png").writeAsBytesSync(png);

    final files = await SkinPreviewer.bitmapsAsBmp(dir);

    expect(files.keys, ["/main.bmp"]);
    final bmp = files.values.single;
    expect(bmp.sublist(0, 2), [0x42, 0x4D]);
    expect(bmp.sublist(54, 57), [0x30, 0x20, 0x10]);
  });
}
