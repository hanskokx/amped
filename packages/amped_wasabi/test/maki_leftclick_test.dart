import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a script's leftClick runs the button's action", (tester) async {
    final dir = Directory.systemTemp.createTempSync("maki_leftclick");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/c.maki").writeAsBytesSync(
      compileMaki(
        (File("${dir.path}/c.m")..writeAsStringSync(r"""
#include <lib/std.mi>
System.onScriptLoaded() {
  Button b = getContainer("main").getLayout("normal").findObject("hidden");
  b.leftClick();
}
"""))
            .path,
      ),
    );
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="c.maki"/></scripts>
<container id="main"><layout id="normal" w="40" h="30">
  <button id="hidden" action="SWITCH" param="CLASSIC" x="0" y="0"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    expect(host.actions.map((a) => "${a.action}:${a.param}:${a.container}"), [
      "SWITCH:CLASSIC:main",
    ]);
  });
}
