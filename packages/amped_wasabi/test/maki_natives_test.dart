import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A host whose container visibility the test sets.
class _Host extends FakeHost {
  final Set<String> shown = {};

  @override
  bool isContainerVisible(String id) => shown.contains(id);
}

void main() {
  testWidgets(
    "notification, quit, right click, shutdown and component natives",
    (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync("maki_natives");
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File("${dir.path}/n.m")
        ..writeAsStringSync(r"""
#include <lib/std.mi>
#include <lib/application.mi>
Global Text log;
Global Layout lay;
Global Layer pad;
Global Button btn;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  pad = lay.findObject("pad");
  btn = lay.findObject("btn");
  note("lang:" + getLanguageId());
}
System.onShowNotification() { note("shown"); complete; return 1; }
System.onQuit() { note("quit"); }
System.onLookForComponent(String guid) { note("look:" + guid); }
btn.onRightClick() { note("rc"); }
pad.onLeftButtonDown(int x, int y) { btn.rightClick(); Application.shutdown(); }
""");
      File("${dir.path}/n.maki").writeAsBytesSync(compileMaki(source.path));
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<scripts><script file="n.maki"/></scripts>
<container id="main">
  <layout id="normal" w="80" h="60">
    <text id="log" x="0" y="0" w="80" h="10"/>
    <layer id="pad" x="0" y="10" w="20" h="20"/>
    <button id="btn" x="30" y="10" w="20" h="20"/>
  </layout>
</container>
<container id="PL" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
  <layout id="normal" w="20" h="30"/>
</container>
</WasabiXML>""");
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(Directory(dir.path)),
      ))!;
      final host = _Host();
      final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
        ..start();
      addTearDown(runtime.dispose);
      final root = skin.container("main")!.layout("normal")!.root;
      final log = runtime.find(root, "log")!;
      final pad = runtime.find(root, "pad")!;

      expect(log["#text"], contains("lang:"));
      expect(log["#text"], isNot(contains("lang:;")));

      expect(runtime.showNotification(), isTrue);
      runtime.pointer(pad, "onLeftButtonDown", const Offset(1, 1));
      runtime.quitting();

      expect(
        log["#text"],
        allOf(
          contains("shown;"),
          contains("rc;"),
          contains("quit;"),
        ),
      );
      expect(host.actions.map((a) => a.action), contains("EXIT"));

      // A component's window being shown asks the scripts for it.
      expect(log["#text"], isNot(contains("look:")));
      host.shown.add(skin.container("PL")!.id);
      host.notifyListeners();
      expect(
        log["#text"],
        contains("look:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};"),
      );
    },
  );

  testWidgets("a skin whose scripts do not handle onShowNotification", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("maki_natives2");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="10" h="10"/></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    expect(runtime.showNotification(), isFalse);
  });
}
