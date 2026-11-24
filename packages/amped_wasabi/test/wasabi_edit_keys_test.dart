import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  test("keys have Windows virtual-key codes", () {
    expect(wasabiVirtualKey(LogicalKeyboardKey.enter), 13);
    expect(wasabiVirtualKey(LogicalKeyboardKey.escape), 27);
    expect(wasabiVirtualKey(LogicalKeyboardKey.arrowDown), 40);
    expect(wasabiVirtualKey(LogicalKeyboardKey.keyA), 65);
    expect(wasabiVirtualKey(LogicalKeyboardKey.digit5), 53);
    expect(wasabiVirtualKey(LogicalKeyboardKey.f1), 112);
    expect(wasabiVirtualKey(LogicalKeyboardKey.f12), 123);
    expect(wasabiVirtualKey(LogicalKeyboardKey.audioVolumeUp), isNull);
  });

  testWidgets("an edit's scripts hear its keys", (tester) async {
    final dir = Directory.systemTemp.createTempSync("edit_keys");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/keys.m")
      ..writeAsStringSync(r'''
Global Text log;
Global Edit ed;
Global Layout lay;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  ed = lay.findObject("ed");
}
ed.onKeyDown(int vk) { note("down:" + integertostring(vk)); }
ed.onKeyUp(int vk) { note("up:" + integertostring(vk)); }
ed.onChar(String c) { note("char:" + c); }
ed.onAbort() { note("abort"); }
''');
    File("${dir.path}/keys.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="keys.maki"/></scripts>
<container id="main">
  <layout id="normal" w="100" h="60">
    <text id="log" x="0" y="0" w="100" h="14"/>
    <edit id="ed" x="0" y="20" w="100" h="14"/>
  </layout>
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
    final edit = runtime.find(layout.root, "ed")!;
    final log = runtime.find(layout.root, "log")!;
    runtime
      ..objectKey(edit, 65, down: true, character: "a")
      ..objectKey(edit, 65, down: false)
      ..objectKey(edit, 13, down: true)
      ..editCancelled(edit);
    final text = log["#text"] ?? "";
    expect(text, contains("down:65;char:a;"));
    expect(text, contains("up:65;"));
    expect(text, contains("down:13;"));
    expect(text, isNot(contains("char:;")));
    expect(text, contains("abort;"));
  });
}
