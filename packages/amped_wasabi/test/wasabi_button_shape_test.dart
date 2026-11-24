import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A 40 x 20 PNG, opaque on the [left] or the right half.
Future<List<int>> _half({required bool left}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    left
        ? const ui.Rect.fromLTWH(0, 0, 20, 20)
        : const ui.Rect.fromLTWH(20, 0, 20, 20),
    ui.Paint()..color = const ui.Color(0xFF808080),
  );
  final image = await recorder.endRecording().toImage(40, 20);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets(
    "buttons take the mouse over their pixels, rectrgn=1 over their box",
    (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync("wasabi_button_shape");
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.runAsync(() async {
        File("${dir.path}/left.png").writeAsBytesSync(await _half(left: true));
        File(
          "${dir.path}/right.png",
        ).writeAsBytesSync(await _half(left: false));
      });
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<bitmap id="left" file="left.png"/>
<bitmap id="right" file="right.png"/>
<container id="main"><layout id="normal" w="40" h="60">
  <button id="a" action="PREV" x="0" y="0" image="left"/>
  <button id="b" action="NEXT" x="0" y="0" image="right"/>
  <button id="c" action="PLAY" x="0" y="30" image="left" rectrgn="1"/>
</layout></container>
</WasabiXML>""");
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(Directory(dir.path)),
      ))!;
      final host = FakeHost();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: skin.container("main")!.layout("normal")!,
              host: host,
              container: "main",
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(WasabiLayoutView));
      Future<List<String>> tap(Offset at) async {
        host.actions.clear();
        await tester.tapAt(origin + at);
        return [for (final action in host.actions) action.action];
      }

      // Over its own pixels each; the transparent half lets the click through.
      expect(await tap(const Offset(5, 10)), ["PREV"]);
      expect(await tap(const Offset(35, 10)), ["NEXT"]);
      // A rectrgn="1" button takes its whole box, transparent part included.
      expect(await tap(const Offset(35, 40)), ["PLAY"]);
    },
  );
}
