import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a Wasabi:TitleBar has a mousetrap for scripts to find", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_titlebar_trap");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="80" h="30">
  <Wasabi:TitleBar id="wasabi.titlebar" x="0" y="0" w="80" h="11"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    );
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    final bar = runtime.find(root, "wasabi.titlebar")!;
    expect(runtime.find(bar, "mousetrap"), isNotNull);
    expect(bar.children.where((c) => c.id == "mousetrap"), hasLength(1));
  });
}
