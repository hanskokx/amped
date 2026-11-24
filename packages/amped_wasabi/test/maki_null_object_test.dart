import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets(
    "a missing object is reported once, and setXmlParam id renames nothing",
    (tester) async {
      final dir = Directory.systemTemp.createTempSync("maki_null_object");
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File("${dir.path}/e.m")
        ..writeAsStringSync(r"""
#include <lib/std.mi>
Global Text log;
System.onScriptLoaded() {
  Layout lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  GuiObject missing = lay.findObject("nothing");
  missing.setXmlParam("x", "1");
  missing.setXmlParam("x", "2");
  missing.setXmlParam("x", "3");
  log.setXmlParam("id", "other");
}
""");
      File("${dir.path}/e.maki").writeAsBytesSync(compileMaki(source.path));
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="e.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="30">
  <text id="log" x="0" y="0" w="80" h="10"/>
</layout></container>
</WasabiXML>""");
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(Directory(dir.path)),
      ))!;
      final logged = <String>[];
      final runtime = WasabiScriptRuntime(
        skin: skin,
        host: FakeHost(),
        log: logged.add,
      )..start();
      addTearDown(runtime.dispose);
      expect(
        logged.where((l) => l.contains("null object called")),
        hasLength(1),
      );
      final root = skin.container("main")!.layout("normal")!.root;
      expect(runtime.find(root, "log"), isNotNull);
      expect(runtime.find(root, "other"), isNull);
    },
  );
}
