import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets(
    "a parameter a script sets on a group reaches the group's script",
    (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync("maki_xui_param");
      addTearDown(() => dir.deleteSync(recursive: true));
      File("${dir.path}/item.maki").writeAsBytesSync(
        compileMaki(
          (File("${dir.path}/item.m")..writeAsStringSync(r"""
#include <lib/std.mi>
Global Text name;
System.onScriptLoaded() { name = getScriptGroup().getObject("name"); }
System.onSetXuiParam(String param, String value) {
  if (strlower(param) == "widgetname") { name.setText(value); }
}
"""))
              .path,
        ),
      );
      File("${dir.path}/main.maki").writeAsBytesSync(
        compileMaki(
          (File("${dir.path}/main.m")..writeAsStringSync(r"""
#include <lib/std.mi>
System.onScriptLoaded() {
  Group item = getContainer("main").getLayout("normal").findObject("listitem");
  item.setXmlParam("widgetname", getToken("Now Playing;icon", ";", 0));
}
"""))
              .path,
        ),
      );
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="listitem" h="20">
  <text id="name" x="0" y="0" w="80" h="10" text=""/>
  <script file="item.maki"/>
</groupdef>
<scripts><script file="main.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="30">
  <group id="listitem" x="0" y="0"/>
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
      expect(runtime.find(root, "name")!["#text"], "Now Playing");
    },
  );
}
