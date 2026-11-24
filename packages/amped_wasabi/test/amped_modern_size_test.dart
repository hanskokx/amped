import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart" show Size;
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

void main() {
  /// Loads the skin and runs its scripts with the "Animate Config Drawer"
  /// option set.
  Future<(WasabiScriptRuntime, WasabiLayout)> start({
    required bool animate,
  }) async {
    final skin = await WasabiSkinData.load(_modern);
    final host = FakeHost();
    host.private["${skin.name}/config/Drawers/Animate Config Drawer"] = animate
        ? "1"
        : "0";
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    addTearDown(scripts.dispose);
    return (scripts, skin.container("main")!.layout("normal")!);
  }

  String drawerY(WasabiLayout layout) =>
      _byId(layout.root, "player.normal.drawer")!["y"]!;

  test("Amped Modern's window leaves out its closed config drawer", () async {
    final (scripts, layout) = await start(animate: false);

    // The layout keeps 116 px under the player for the drawer
    // (configtabs.m `snapAdjust(0, 0, 0, 116)`); the window does not.
    expect(layout.size, const Size(354, 280));
    expect(layout.windowSize, const Size(354, 164));

    scripts.buttonClicked(_byId(layout.root, "drawer.button.open")!);
    expect(drawerY(layout), "-147");
    expect(layout.windowSize, const Size(354, 280));

    scripts.buttonClicked(_byId(layout.root, "drawer.button.close")!);
    expect(drawerY(layout), "-263");
    expect(layout.windowSize, const Size(354, 164));
  });

  test(
    "an animated config drawer has the whole layout while it slides",
    () async {
      final (scripts, layout) = await start(animate: true);
      expect(layout.windowSize, const Size(354, 164));

      // Between `beforeRedock` and `redock` the window grows along with the
      // drawer sliding down (windows docked to it follow, not jump)...
      scripts.buttonClicked(_byId(layout.root, "drawer.button.open")!);
      expect(drawerY(layout), "-263");
      expect(layout.windowSize, const Size(354, 164));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(layout.windowSize.height, inExclusiveRange(164, 280));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(drawerY(layout), "-147");
      expect(layout.windowSize, const Size(354, 280));

      // ...and shrinks along with the drawer sliding back up.
      scripts.buttonClicked(_byId(layout.root, "drawer.button.close")!);
      expect(layout.windowSize, const Size(354, 280));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(layout.windowSize.height, inExclusiveRange(164, 280));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drawerY(layout), "-263");
      expect(layout.windowSize, const Size(354, 164));
    },
  );
}
