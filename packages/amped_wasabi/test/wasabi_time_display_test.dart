import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a script can read a time display and hears it change", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_time");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/t.maki").writeAsBytesSync(
      compileMaki(
        (File("${dir.path}/t.m")..writeAsStringSync(r"""
#include <lib/std.mi>
Global Text source, shown;
System.onScriptLoaded() {
  Layout lay = getContainer("main").getLayout("normal");
  source = lay.findObject("src");
  shown = lay.findObject("shown");
  shown.setText("start:" + source.getText());
}
source.onTextChanged(String t) { shown.setText("now:" + t); }
"""))
            .path,
      ),
    );
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="t.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="30">
  <text id="src" x="0" y="0" w="0" h="0" display="time"/>
  <text id="shown" x="0" y="10" w="80" h="10"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    // The script reads what the display shows (the fake host is at 1:01).
    expect(runtime.find(root, "shown")!["#text"], "start:1:01");
    // The first host update tells it the time, and the display's text did
    // not change after that.
    host.notifyListeners();
    expect(runtime.find(root, "shown")!["#text"], "now:1:01");
  });
}
