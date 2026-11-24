import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("Wasabi's own controls are built when a skin has none", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_controls");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="one" name="First">
  <Wasabi:CheckBox id="a" x="0" y="0" text="Alpha" radioid="r"/>
  <Wasabi:Button id="ok" x="0" y="20" w="48" h="21" text="OK"/>
</groupdef>
<groupdef id="two" name="Second">
  <Wasabi:Text x="0" y="0" text="Hello"/>
</groupdef>
<container id="main">
  <layout id="normal" w="100" h="100">
    <Wasabi:TabSheet x="0" y="0" w="100" h="100" children="one;two"/>
  </layout>
</container>
</WasabiXML>''');
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
    final sheet = root.children.single;
    expect(sheet.tag, "tabsheet");
    expect(sheet.children.map((page) => page["name"]), ["First", "Second"]);
    // Only the first page shows.
    expect(sheet.children.first.visible, isTrue);
    expect(sheet.children.last.visible, isFalse);
    final first = sheet.children.first;
    expect(first.children.map((child) => child.tag), [
      "checkbox",
      "wasabibutton",
    ]);
    expect(first.children.first.intAttr("h"), 14);
    expect(sheet.children.last.children.single.tag, "text");

    // Switching pages.
    runtime.setNodeVisible(sheet.children.first, false);
    runtime.setNodeVisible(sheet.children.last, true);
    expect(sheet.children.first.visible, isFalse);
    expect(sheet.children.last.visible, isTrue);
  });
}
