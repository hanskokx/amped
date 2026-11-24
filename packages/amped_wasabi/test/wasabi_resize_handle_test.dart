import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a small grip keeps to its direction, a long strip takes the "
      "corner at its end too", (tester) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_resize");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="100" h="100">
    <layer id="grip" x="80" y="80" w="12" h="12" resize="right"/>
    <layer id="strip" x="96" y="0" w="4" h="100" resize="right"/>
  </layout>
</container>
</WasabiXML>''');
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

    // A press on the grip's lower half widens the window and nothing else.
    var gesture = await tester.startGesture(const Offset(86, 90));
    await gesture.moveBy(const Offset(10, 10));
    await gesture.up();
    expect(host.resizes, isNotEmpty);
    expect(host.resizes.every((size) => size.height == 100), isTrue);
    expect(host.resizes.last.width, greaterThan(100));

    // The long strip also resizes both ways from its bottom end.
    host.resizes.clear();
    gesture = await tester.startGesture(const Offset(98, 95));
    await gesture.moveBy(const Offset(10, 10));
    await gesture.up();
    expect(host.resizes.last.height, greaterThan(100));
  });
}
