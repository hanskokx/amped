import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("bringToFront and friends reorder a layout's objects", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_zorder");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/z.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
#include <lib/pldir.mi>
Global Layout lay;
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  Layer a = lay.findObject("a");
  Layer b = lay.findObject("b");
  Layer c = lay.findObject("c");
  a.bringToFront();
  c.bringToBack();
  b.bringBelow(c);
  PlDir.showCurrentlyPlayingEntry();
}
""");
    File("${dir.path}/z.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="z.maki"/></scripts>
<container id="main">
  <layout id="normal" w="80" h="60">
    <layer id="a" x="0" y="0" w="10" h="10"/>
    <layer id="b" x="0" y="0" w="10" h="10"/>
    <layer id="c" x="0" y="0" w="10" h="10"/>
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
    // a to the front: b c a. c to the back: c b a. b below c: b c a.
    expect(root.children.map((c) => c.id), ["b", "c", "a"]);
    expect(logged.where((l) => l.contains("not implemented")), isEmpty);
  });

  test("the members makic warns about match what the runtime names", () {
    // Regenerate with `dart run tool/gen_runtime_members.dart
    // ../amped_wasabi/lib/src` in packages/amped_maki after implementing or
    // removing a member.
    expect(
      runtimeNames(Directory("lib/src")),
      makiRuntimeNames.toList()..sort(),
    );
  });
}
