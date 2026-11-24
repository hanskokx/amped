import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A 40 x 20 PNG, opaque on its left half.
Future<List<int>> _leftHalf() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 20, 20),
    ui.Paint()..color = const ui.Color(0xFF808080),
  );
  final image = await recorder.endRecording().toImage(40, 20);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets("a group whose background is only its shape clips to it", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_group_shape");
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(
      () async => File("${dir.path}/shape.png").writeAsBytesSync(
        await _leftHalf(),
      ),
    );
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<bitmap id="shape" file="shape.png"/>
<groupdef id="shaped" background="shape" drawbackground="0" w="40" h="20"/>
<groupdef id="plain" background="shape" w="40" h="20"/>
<container id="a"><layout id="normal" w="40" h="20">
  <group id="shaped" x="0" y="0"/>
</layout></container>
<container id="b"><layout id="normal" w="40" h="20">
  <group id="plain" x="0" y="0"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    Future<int> clips(String container) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: skin.container(container)!.layout("normal")!,
              host: FakeHost(),
              container: container,
            ),
          ),
        ),
      );
      return tester.widgetList(find.byType(ClipPath)).length;
    }

    final shaped = await clips("a");
    final plain = await clips("b");
    expect(shaped, plain + 1);
  });
}
