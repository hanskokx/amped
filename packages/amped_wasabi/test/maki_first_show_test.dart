import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A player that starts windowshaded.
class _ShadedHost extends FakeHost {
  @override
  String? currentLayout(String id) => "shade";
}

void main() {
  testWidgets("a layout first shown after the start tells its objects they "
      "are visible", (tester) async {
    final dir = Directory.systemTemp.createTempSync("maki_first_show");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/area.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
Global Group area;
System.onScriptLoaded() {
  area = getScriptGroup();
}
area.onSetVisible(boolean on) {
  if (on) area.findObject("ready").show();
}
""");
    File("${dir.path}/area.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="area">
  <layer id="ready" x="0" y="0" w="1" h="1" visible="0"/>
  <script file="area.maki"/>
</groupdef>
<container id="main">
  <layout id="normal" w="80" h="60">
    <group id="area" fitparent="1"/>
  </layout>
  <layout id="shade" w="80" h="10"/>
</container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(skin: skin, host: _ShadedHost())
      ..start();
    addTearDown(runtime.dispose);
    final main = skin.container("main")!;
    final normal = main.layout("normal")!;
    final ready = normal.root.children.single.children.firstWhere(
      (c) => c.id == "ready",
    );
    expect(ready.visible, isFalse);

    runtime.layoutSwitched("main", main.layout("shade")!, normal);

    expect(ready.visible, isTrue);
  });
}
