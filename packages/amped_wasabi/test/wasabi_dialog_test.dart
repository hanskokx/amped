import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  Future<WasabiSkinData> load(WidgetTester tester, String xml) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_dialog");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync(
      '<?xml version="1.0"?><WasabiXML version="1.2">$xml</WasabiXML>',
    );
    return (await tester.runAsync(() => WasabiSkinData.load(dir)))!;
  }

  testWidgets("a dialog without a width opens wide enough to read", (
    tester,
  ) async {
    final skin = await load(tester, """
<container id="manager" default_visible="0">
  <layout id="normal" minimum_w="100" minimum_h="400">
    <Wasabi:StandardFrame:Modal fitparent="1"/>
  </layout>
</container>
<container id="avs" dynamic="1"><layout id="normal" w="1" h="1"/></container>
""");
    final manager = skin.container("manager")!;
    expect(manager.layouts.first.size, const Size(320, 400));
    expect(manager.isPlaceholder, isFalse);
    expect(skin.container("avs")!.isPlaceholder, isTrue);
  });

  testWidgets("fitparent on a use replaces the groupdef's size", (
    tester,
  ) async {
    final skin = await load(tester, """
<groupdef id="area" xuitag="Test:Area" h="100"/>
<container id="main">
  <layout id="normal" w="200" h="40"><Test:Area id="a" fitparent="1"/></layout>
</container>
""");
    final area = skin.container("main")!.layout("normal")!.root.children.single;
    expect(
      wasabiObjectRect(area, const Size(200, 40), skin),
      const Rect.fromLTWH(0, 0, 200, 40),
    );
  });

  testWidgets("a GroupList draws its rows", (tester) async {
    final skin = await load(tester, """
<groupdef id="row" h="10">
  <rect fitparent="1" filled="1" color="255,0,0"/>
</groupdef>
<container id="main">
  <layout id="normal" w="40" h="40">
    <grouplist id="list" x="0" y="0" w="40" h="40"/>
  </layout>
</container>
""");
    final layout = skin.container("main")!.layout("normal")!;
    final row = skin.newGroup("row")!..attributes.addAll({"w": "40"});
    layout.root.children.single.children.add(row);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: FakeHost(),
            container: "main",
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint && "${w.painter?.runtimeType}" == "_RectPainter",
      ),
      findsOneWidget,
    );
  });
}
