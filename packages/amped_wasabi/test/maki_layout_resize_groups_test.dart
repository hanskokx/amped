import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a script resizing its layout tells the groups in it", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_layout_resize");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/e.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
Global Group holder;
Global Layout lay;
Global Text log;
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  holder = lay.findObject("holder");
  log = lay.findObject("log");
  lay.resize(0, 0, 300, 50);
}
holder.onResize(int x, int y, int w, int h) { log.setText(log.getText() + integerToString(w) + ";"); }
""");
    File("${dir.path}/e.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="h" w="0" relatw="1" h="10"/>
<scripts><script file="e.maki"/></scripts>
<container id="main"><layout id="normal" w="100" h="50">
  <text id="log" x="0" y="20" w="80" h="10"/>
  <group id="holder" x="0" y="0" w="-10" relatw="1" h="10"/>
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
    expect(runtime.find(root, "log")!["#text"], contains("290;"));
  });
}
