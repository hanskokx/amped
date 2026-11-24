import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("navigateUrl opens web links in the browser, nothing else", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_navigate");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/n.maki").writeAsBytesSync(
      compileMaki(
        (File("${dir.path}/n.m")..writeAsStringSync(r"""
#include <lib/std.mi>
System.onScriptLoaded() {
  navigateUrl("http://www.quad-helix.com/index3.htm");
  navigateUrl("file:///etc/passwd");
  navigateUrl("/Applications/Calculator.app");
  navigateUrl("https://example.com/");
}
"""))
            .path,
      ),
    );
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="n.maki"/></scripts>
<container id="main"><layout id="normal" w="40" h="30"/></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    expect(host.filesOpened, [
      "http://www.quad-helix.com/index3.htm",
      "https://example.com/",
    ]);
  });
}
