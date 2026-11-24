import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

void main() {
  testWidgets("runs Amped Modern's scripts against its layouts", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final logs = <String>[];
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: logs.add)
      ..start();

    // XUI frames and groups made with newGroup bring their scripts along.
    expect(runtime.vm.scripts.length, greaterThanOrEqualTo(40));
    expect(logs.where((l) => l.contains("MAKI error")), isEmpty);

    final main = skin.container("main")!.layout("normal")!;
    // <sendparams> named the title.
    expect(
      runtime.find(main.root, "window.titlebar.title")?["default"],
      "AMPED",
    );
    // menualign.maki laid the menus out one after another by their width.
    final file = runtime.find(main.root, "menugroup.file")!;
    final play = runtime.find(main.root, "menugroup.play")!;
    expect(runtime.rectOf(file).left, 0);
    expect(runtime.rectOf(play).left, runtime.rectOf(file).width);

    // Every layout got onResize at start: configtabs.m centered the config
    // drawer's content (w/2 - 163), and does again when the app resizes.
    final content = runtime.find(main.root, "player.normal.drawer.content")!;
    expect(content["x"], "${main.size.width ~/ 2 - 163}");
    main.root.attributes["w"] = "400";
    runtime.layoutResized(main);
    expect(content["x"], "37");

    // Script settings go through the host, per skin.
    final muteButton = runtime.find(main.root, "mute")!;
    runtime.buttonClicked(muteButton);
    expect(host.values["VOLUME"], 0);
    runtime.dispose();
  });

  testWidgets("exposes Amped Modern's equalizer option", (tester) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    const option = "Equalizer\tAlt+G";

    // attribs.m made it; the equalizer drawer starts closed.
    expect(runtime.hasConfigAttribute(option), isTrue);
    expect(runtime.hasConfigAttribute("No such option"), isFalse);
    expect(runtime.configAttribute(option), "0");

    var changes = 0;
    runtime
      ..addListener(() => changes++)
      ..setConfigAttribute(option, "1");
    expect(runtime.configAttribute(option), "1");
    expect(changes, greaterThan(0));
    // Stored with the skin's settings, so it survives a restart.
    expect(
      host.private.entries.where(
        (e) => e.key.endsWith(option) && e.value == "1",
      ),
      isNotEmpty,
    );
    runtime.dispose();
  });
}
