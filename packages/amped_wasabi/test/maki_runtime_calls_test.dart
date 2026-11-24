import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets(
    "getExtension, removePath and getScale",
    (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync("maki_calls");
      addTearDown(() => dir.deleteSync(recursive: true));
      // Names its results on the objects it finds.
      final source = File("${dir.path}/calls.m")
        ..writeAsStringSync(r'''
System.onScriptLoaded() {
  Layout layout = getContainer("main").getLayout("normal");
  GuiObject mark = layout.findObject("mark");
  if (mark != NULL) {
    mark.setXmlParam("default", getExtension(removePath("C:\\music\\a.b\\Song.MP3")) + "|" + removePath("/x/y.flac") + "|" + getExtension("noext") + "|" + floatToString(layout.getScale(), 1));
  }
}
''');
      File("${dir.path}/calls.maki").writeAsBytesSync(compileMaki(source.path));
      File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="calls.maki"/></scripts>
<container id="main">
  <layout id="normal" w="40" h="30"><text id="mark" x="0" y="0" w="40" h="10"/></layout>
</container>
</WasabiXML>''');
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(Directory(dir.path)),
      ))!;
      final runtime = WasabiScriptRuntime(
        skin: skin,
        host: FakeHost(),
        log: (_) {},
      )..start();
      addTearDown(runtime.dispose);
      final layout = skin.container("main")!.layout("normal")!;
      expect(runtime.find(layout.root, "mark")!["default"], "MP3|y.flac||1.0");
    },
  );
}
