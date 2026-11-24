import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Wasabi 5's own modern skin, from the original source tree when it is
/// around.
final Directory _modern = ampedModern;

WasabiObject? _byId(WasabiObject node, String id) {
  if (node.id == id) return node;
  for (final child in node.children) {
    final found = _byId(child, id);
    if (found != null) return found;
  }
  return null;
}

WasabiObject? _byAction(WasabiObject node, String action) {
  if (node["action"]?.toUpperCase() == action) return node;
  for (final child in node.children) {
    final found = _byAction(child, action);
    if (found != null) return found;
  }
  return null;
}

/// Where [object] is drawn on screen.
Rect _rectOf(WidgetTester tester, WasabiObject object) => tester.getRect(
  find.byWidgetPredicate(
    (widget) =>
        widget.runtimeType.toString() == "_ObjectView" &&
        identical((widget as dynamic).object, object),
  ),
);

void main() {
  testWidgets("Amped Modern main window: buttons under scripted groups "
      "click", (tester) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    final layout = skin.container("main")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            container: "main",
            scripts: scripts,
          ),
        ),
      ),
    );

    // The transport buttons sit under `player.bar.rightbottom`, a scripted
    // group spanning the whole player.
    final play = _byAction(layout.root, "PLAY")!;
    await tester.tapAt(_rectOf(tester, play).center);
    expect(host.actions.last.action, "PLAY");

    // The config button opens the drawer under the player (configtabs.m).
    final drawer = _byId(layout.root, "player.normal.drawer")!;
    expect(drawer["y"], "-263");
    final open = _byId(layout.root, "drawer.button.open")!;
    await tester.tapAt(_rectOf(tester, open).center);
    await tester.pump(const Duration(seconds: 2));
    expect(drawer["y"], "-147");
    expect(open.visible, isFalse);

    // Its periodic timers would outlive the test.
    scripts.dispose();
  });
}
