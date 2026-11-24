import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("scripts hear wheel, key, seek, move and layout events", (
    tester,
  ) async {
    final host = FakeHost();
    final dir = Directory.systemTemp.createTempSync("maki_events");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/events.m")
      ..writeAsStringSync(r'''
Global Text log;
Global Layout lay;
Global Slider s;
Global Container cont;
Global PopupMenu pm;
Global PopupMenu sub;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  s = lay.findObject("s");
  cont = getContainer("main");
}
System.onKeyDown(String key) { note("key:" + key); complete; }
System.onAccelerator(String action, String section, String key) { note("acc:" + action + ":" + section + ":" + key); complete; }
System.onSeek(int ms) { note("seek:" + integertostring(ms)); }
System.onShowLayout(Layout l) { note("show"); }
cont.onSwitchToLayout(Layout l) { note("switch"); }
lay.onMove() { note("move"); }
lay.onEndMove() { note("endmove"); }
s.onPostedPosition(int p) { note("posted:" + integertostring(p)); }
s.onMouseWheelUp(int clicked, int lines) { note("wheelup:" + integertostring(lines)); }
s.onLeftButtonDblClk(int x, int y) { note("dbl"); }
s.onRightButtonUp(int x, int y) {
  pm = new PopupMenu;
  sub = new PopupMenu;
  sub.addCommand("Deep", 7, 0, 0);
  pm.addCommand("One", 1, 0, 0);
  pm.addCommand("Two", 2, 1, 0);
  pm.addSeparator();
  pm.addSubMenu(sub, "More");
  int a = pm.popAtMouse();
  note("pick:" + integertostring(a));
}
''');
    File("${dir.path}/events.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<accelerators section="normal"><accelerator bind="Shift+Alt+F" action="MENUHOTKEY_FILE"/></accelerators>
<scripts><script file="events.maki"/></scripts>
<container id="main">
  <layout id="normal" w="40" h="30">
    <text id="log" x="0" y="0" w="40" h="10"/>
    <slider id="s" x="0" y="10" w="40" h="10" low="0" high="100"/>
  </layout>
  <layout id="shade" w="40" h="10"/>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    final container = skin.container("main")!;
    final layout = container.layout("normal")!;
    final log = runtime.find(layout.root, "log")!;
    final slider = runtime.find(layout.root, "s")!;

    expect(runtime.keyEvent("ctrl+a", down: true), isTrue);
    runtime.seeked(1500);
    runtime.layoutMoved(layout, ended: false);
    runtime.layoutMoved(layout, ended: true);
    runtime.sliderPosted(slider, 0.5);
    runtime.mouseWheel(slider, up: true);
    runtime.pointer(slider, "onLeftButtonDblClk", Offset.zero);
    runtime.layoutSwitched("main", layout, container.layout("shade")!);

    final text = log["#text"] ?? "";
    expect(text, contains("key:ctrl+a;"));
    expect(text, contains("seek:1500;"));
    expect(text, contains("move;endmove;"));
    expect(text, contains("posted:50;"));
    expect(text, contains("wheelup:1;"));
    expect(text, contains("dbl;"));
    expect(text, contains("switch;"));
    expect(text, contains("show;"));

    // A key the skin binds is an accelerator: found by its normalized name,
    // and told to the scripts.
    expect(skin.accelerator("normal", "alt+shift+f"), "MENUHOTKEY_FILE");
    expect(skin.accelerator("general", "alt+shift+f"), isNull);
    expect(
      runtime.accelerator("MENUHOTKEY_FILE", "normal", "alt+shift+f"),
      isTrue,
    );
    expect(log["#text"], contains("acc:MENUHOTKEY_FILE:normal:alt+shift+f;"));

    // A popup menu opens when the handler is done (its first answer is -1)
    // and the handler runs again with the pick.
    runtime.pointer(slider, "onRightButtonUp", Offset.zero);
    final popup = host.popup!;
    expect(popup.map((i) => i.label), ["One", "Two", "", "More"]);
    expect(popup[1].checked, isTrue);
    expect(popup[2].separator, isTrue);
    expect(popup[3].children.single.id, 7);
    expect(log["#text"], contains("pick:-1;"));
    host.popupChosen!(7);
    expect(log["#text"], contains("pick:7;"));
  });
}
