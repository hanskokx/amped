import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("fitparent fills the parent, and a group's alpha fades its "
      "children", (tester) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_fit");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="texts"><text id="t" x="10" y="0" w="-20" relatw="1" default="Hi"/></groupdef>
<container id="main">
  <layout id="normal" w="200" h="50">
    <group id="g" fitparent="1" x="0" y="0" alpha="100"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    final layout = skin.container("main")!.layout("normal")!;
    final group = layout.root.children.single;
    expect(runtime.rectOf(group), const Rect.fromLTWH(0, 0, 200, 50));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WasabiLayoutView(
          skin: skin,
          layout: layout,
          host: host,
          container: "main",
          scripts: runtime,
        ),
      ),
    );
    final opacity = tester.widgetList<Opacity>(find.byType(Opacity));
    expect(opacity.map((o) => o.opacity), contains(closeTo(100 / 255, 0.001)));
  });
}
