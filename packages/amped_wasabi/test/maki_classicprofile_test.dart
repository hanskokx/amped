import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("ClassicProFile: explore, open and find files", (tester) async {
    final dir = Directory.systemTemp.createTempSync("maki_cprofile");
    addTearDown(() => dir.deleteSync(recursive: true));
    final music = Directory("${dir.path}/music")..createSync();
    for (final name in ["b.mp3", "A.mp3", "c.txt", "z.exe"]) {
      File("${music.path}/$name").writeAsStringSync("x");
    }
    final source = File("${dir.path}/c.m")
      ..writeAsStringSync("""
#include <lib/std.mi>
#include <lib/pldir.mi>
#include "../lib/ClassicProFile.mi"
Global Text log;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  log = getContainer("main").getLayout("normal").findObject("log");
  ClassicProFile.exploreFile("${music.path}/b.mp3");
  ClassicProFile.exploreFolder("${music.path}");
  ClassicProFile.openFile("${music.path}/c.txt", "");
  ClassicProFile.openFile("${music.path}/z.exe", "");
  List mp3 = new List;
  note("mp3:" + integerToString(ClassicProFile.findFiles("${music.path}/", "*.mp3", mp3)) + ":" + integerToString(mp3.getNumItems()) + ":" + mp3.enumItem(0) + "," + mp3.enumItem(1));
  List all = new List;
  ClassicProFile.findFiles("${music.path}/", "*.*", all);
  note("all:" + integerToString(all.getNumItems()) + ":" + all.enumItem(0) + all.enumItem(1) + all.enumItem(2));
  List none = new List;
  note("missing:" + integerToString(ClassicProFile.findFiles("${dir.path}/nothing/", "*.*", none)));
  // The way the plugin's scripts build a path: a backslash after the folder.
  String bs = strleft("\\\\ ", 1);
  List viaBackslash = new List;
  note("bs:" + integerToString(ClassicProFile.findFiles("${music.path}/" + bs, "*.mp3", viaBackslash)));
  note("same:" + integerToString("${music.path}/" + bs + "b.mp3" == "${music.path}/b.mp3"));
  note("other:" + integerToString("${music.path}/" + bs + "b.mp3" == "${music.path}/c.txt"));
}
""");
    File("${dir.path}/c.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="c.maki"/></scripts>
<container id="main"><layout id="normal" w="80" h="20"><text id="log" x="0" y="0" w="80" h="10"/></layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final logged = <String>[];
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: logged.add,
    )..start();
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    expect(host.revealed, ["${music.path}/b.mp3"]);
    expect(host.foldersOpened, [music.path]);
    // A document opens; a program does not.
    expect(host.filesOpened, ["${music.path}/c.txt"]);
    expect(
      logged.where((l) => l.contains("will not start z.exe")),
      hasLength(1),
    );
    final text = runtime.find(root, "log")!["#text"];
    // The matches, "." and ".." first when the pattern fits, in name order.
    expect(text, contains("mp3:0:2:A.mp3,b.mp3;"));
    expect(text, contains("all:6:...A.mp3;"));
    expect(text, contains("missing:-1;"));
    // A path built with a backslash reaches the folder, and compares equal
    // to the player's.
    expect(text, contains("bs:0;"));
    expect(text, contains("same:1;"));
    expect(text, contains("other:0;"));
    expect(logged.where((l) => l.contains("not implemented")), isEmpty);
  });
}
