import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A PNG of [width] x [height], opaque in its top-left 4 x 4 corner only.
Future<List<int>> _corner(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFF808080),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets("a shaped button with a tooltip leaves the buttons under it "
      "their clicks", (tester) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_shaped_tooltip");
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(() async {
      File("${dir.path}/big.png").writeAsBytesSync(await _corner(40, 20));
      File("${dir.path}/dot.png").writeAsBytesSync(await _corner(8, 8));
    });
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<bitmap id="big" file="big.png"/>
<bitmap id="dot" file="dot.png"/>
<container id="main"><layout id="normal" w="40" h="20">
  <button id="under" action="EJECT" x="30" y="5" image="dot" rectrgn="1"/>
  <button id="handle" action="STOP" x="0" y="0" image="big" tooltip="Handle"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final layout = skin.container("main")!.layouts.single;
    tester.view
      ..physicalSize = const Size(40, 20)
      ..devicePixelRatio = 1;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            container: "main",
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(33, 8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.actions.map((a) => a.action), ["EJECT"]);
    host.actions.clear();
    // Its own pixels still work.
    await tester.tapAt(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.actions.map((a) => a.action), ["STOP"]);
  });
}
