import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("compiled Member variables hold values in the runtime", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_member");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/m.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
Class Group Widget;
Member int Widget.count;
Member string Widget.tag;
Global Widget w;
Global Text log;
Member int log.height;
System.onScriptLoaded() {
  Layout lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  w = lay.findObject("box");
  w.count = 5;
  w.count += 2;
  w.count++;
  w.tag = "x" + integerToString(w.count);
  log.height = w.count * 2;
  log.setText(w.tag + ":" + integerToString(log.height));
}
""");
    File("${dir.path}/m.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="m.maki"/></scripts>
<container id="main">
  <layout id="normal" w="80" h="60">
    <text id="log" x="0" y="0" w="80" h="10"/>
    <group id="box" x="0" y="10" w="20" h="20"/>
  </layout>
</container>
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
    // 5, then 7, then 8; the tag is made from it, and the height from twice.
    expect(runtime.find(root, "log")!["#text"], "x8:16");
    expect(logged.where((l) => l.contains("rror")), isEmpty);
  });
}
