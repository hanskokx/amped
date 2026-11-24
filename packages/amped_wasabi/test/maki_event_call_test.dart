import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a script calling onToggle on a <button> triggers its handlers", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_event_call");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/e.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
Global Togglebutton tog;
Global Text log;
System.onScriptLoaded() {
  Layout lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  tog = lay.findObject("b");
  tog.onToggle(1);
}
tog.onToggle(int on) { log.setText(log.getText() + "toggled:" + integerToString(on) + ";"); }
""");
    File("${dir.path}/e.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="e.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="30">
  <text id="log" x="0" y="0" w="80" h="10"/>
  <button id="b" x="0" y="10" w="20" h="20"/>
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
    final root = skin.container("main")!.layout("normal")!.root;
    expect(runtime.find(root, "log")!["#text"], "toggled:1;");
    expect(logged.where((l) => l.contains("not implemented")), isEmpty);
  });
}
