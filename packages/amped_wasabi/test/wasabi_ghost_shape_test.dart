import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test(
    "a window drawn with ghost layers takes the mouse where they paint",
    () async {
      final dir = await Directory.systemTemp.createTemp("wasabi_ghost");
      addTearDown(() => dir.delete(recursive: true));
      // A 40x10 picture, see-through right of 30, and a 10x10 button picture.
      Future<void> picture(String name, int width, double painted) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          ui.Rect.fromLTWH(0, 0, painted, 10),
          ui.Paint()..color = const ui.Color(0xFF3366CC),
        );
        final image = await recorder.endRecording().toImage(width, 10);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File("${dir.path}/$name.png").writeAsBytes(
          data!.buffer.asUint8List(),
        );
      }

      await picture("body", 40, 30);
      await picture("knob", 10, 10);
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<elements>
  <bitmap id="body" file="body.png"/>
  <bitmap id="knob" file="knob.png"/>
</elements>
<groupdef id="art">
  <layer x="0" y="0" image="body"/>
</groupdef>
<container id="main">
  <layout id="normal" w="60" h="10">
    <group id="art" x="0" y="0" w="40" h="10" ghost="1"/>
    <layer x="40" y="0" image="body" ghost="1" alpha="0"/>
    <button x="50" y="0" image="knob"/>
  </layout>
</container>
</WasabiXML>''');

      final skin = await WasabiSkinData.load(dir);
      final shape = wasabiWindowShape(
        skin,
        skin.container("main")!.layout("normal")!,
      )!;
      bool takes(double x) => shape.any(
        (p) => ui.Rect.fromPoints(p[0], p[2]).contains(ui.Offset(x, 5)),
      );
      expect(takes(5), isTrue, reason: "the ghost artwork");
      expect(takes(35), isFalse, reason: "its see-through pixels");
      expect(takes(45), isFalse, reason: "a layer faded out");
      expect(takes(55), isTrue, reason: "the button");
    },
  );
}
