import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("System, Layout, WindowHolder, CfgGroup and PlEdit calls", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_batch3");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/b3.m")
      ..writeAsStringSync(r'''
Global Text log;
Global Layout lay;
Global WindowHolder holder;
Global CfgGroup cfg;
Global PlEdit pl;
Global Int changed;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  holder = lay.findObject("holder");
  cfg = lay.findObject("cfg");

  switchSkin("Other Skin");
  note("appw:" + integertostring(getCurAppWidth()) + "," + integertostring(getCurAppLeft()));
  note("wac:" + integertostring(getWac("{00000000-0000-0000-0000-000000000000}") == null));
  note("art:" + integertostring(getAlbumArt("nothing.mp3")));
  lay.center();
  lay.setFocus();

  note("comp:" + holder.getComponentName());
  note("guid:" + holder.getGuid());

  cfg.cfgSetInt(7);
  note("cfg:" + integertostring(cfg.cfgGetInt()) + "," + cfg.cfgGetString() + "," + cfg.cfgGetName());

  pl = new PlEdit;
  note("n:" + integertostring(pl.getNumTracks()));
  note("t1:" + pl.getTitle(1) + "," + pl.getFileName(1));
  pl.moveTo(0, 2);
  note("first:" + pl.getTitle(0));
  pl.swapTracks(0, 2);
  note("swap:" + pl.getTitle(0) + pl.getTitle(2));
  pl.removeTrack(1);
  note("left:" + integertostring(pl.getNumTracks()));
  pl.clear();
  note("clear:" + integertostring(pl.getNumTracks()));
}
cfg.onCfgChanged() { note("cc"); }
''');
    File("${dir.path}/b3.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="b3.maki"/></scripts>
<container id="main">
  <layout id="normal" w="80" h="60">
    <text id="log" x="0" y="0" w="80" h="10"/>
    <windowholder id="holder" x="0" y="10" w="40" h="40" hold="guid:pl"/>
    <group id="cfg" x="0" y="50" w="10" h="10"
      cfgattrib="{9149C445-3C30-4E04-8433-5A518ED0FDDE};Link layouts scale"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost()..playlist = [("A", 1000), ("B", 2000), ("C", 3000)];
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    final layout = skin.container("main")!.layout("normal")!;
    final text = runtime.find(layout.root, "log")!["#text"] ?? "";
    expect(host.skinSwitches, ["Other Skin"]);
    expect(host.centered, ["main"]);
    expect(host.focused, ["main"]);
    // Once as the group starts, and once for the value the script set.
    expect("cc;".allMatches(text).length, 2);
    expect(text, contains("appw:300,10;"));
    expect(text, contains("wac:1;"));
    expect(text, contains("art:0;"));
    expect(text, contains("comp:Playlist Editor;"));
    expect(text, contains("guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};"));
    expect(text, contains("cfg:7,7,Link layouts scale;"));
    expect(text, contains("n:3;"));
    expect(text, contains("t1:B,song1.mp3;"));
    expect(text, contains("first:B;"));
    // [B, C, A] swapped at 0 and 2 is [A, C, B].
    expect(text, contains("swap:AB;"));
    expect(text, contains("left:2;"));
    expect(text, contains("clear:0;"));
    expect(host.playlist, isEmpty);
  });
}
