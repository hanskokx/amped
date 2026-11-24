import "dart:io";
import "dart:ui" as ui;

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("Map.loadMap of the playing file's path has its cover's size", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_map_cover");
    addTearDown(() => dir.deleteSync(recursive: true));
    // SC-Cover sizes its pictures by loading the file the item plays.
    final source = File("${dir.path}/m.m")
      ..writeAsStringSync(r"""
#include <lib/std.mi>
System.onScriptLoaded() {
  Map cover = new Map;
  cover.loadMap(getPlayItemString());
  Map other = new Map;
  other.loadMap("/music/other.mp3");
  Text log = getContainer("main").getLayout("normal").findObject("log");
  log.setText(integerToString(cover.getWidth()) + "x" + integerToString(cover.getHeight()) + "," + integerToString(other.getWidth()));
}
""");
    File("${dir.path}/m.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="m.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="20"><text id="log" x="0" y="0" w="80" h="10"/></layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final image = await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint(),
      );
      return recorder.endRecording().toImage(6, 4);
    });
    final host = FakeHost()..albumArt = image;
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    expect(runtime.find(root, "log")!["#text"], "6x4,0");
  });
}
