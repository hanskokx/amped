import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a <CustomObject> shows the group a script names in groupid", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_customobject");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/e.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
System.onScriptLoaded() {
  GuiObject holder = getContainer("main").getLayout("normal").findObject("holder");
  holder.setXmlParam("groupid", "widget.a");
  holder.setXmlParam("groupid", "widget.b");
}
""");
    File("${dir.path}/e.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="widget.a"><text id="a.text" x="0" y="0" w="10" h="10"/></groupdef>
<groupdef id="widget.b"><text id="b.text" x="0" y="0" w="10" h="10"/></groupdef>
<scripts><script file="e.maki"/></scripts>
<container id="main"><layout id="normal" w="100" h="50">
  <CustomObject id="holder" fitparent="1"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    final holder = runtime.find(root, "holder")!;
    expect(holder.children.map((c) => c.id), ["widget.a", "widget.b"]);
    expect(holder.children.first.visible, isFalse);
    expect(holder.children.last.visible, isTrue);
  });
}
