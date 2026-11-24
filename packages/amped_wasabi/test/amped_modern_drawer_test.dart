import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/rendering.dart";
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

void main() {
  testWidgets("Amped Modern's video/vis drawer holds the app's vis", (
    tester,
  ) async {
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
            components: const {"vis": Text("vis plug-in")},
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    expect(find.text("vis plug-in"), findsNothing);

    // The top-right arrow (videoavs.m) grows the layout and, while playing,
    // shows the `guid:avs` windowholder in it.
    scripts.buttonClicked(_byId(layout.root, "videoavs.open")!);
    await settle();
    expect(layout.size.height, 510);
    expect(find.text("vis plug-in"), findsOneWidget);

    scripts.buttonClicked(_byId(layout.root, "videoavs.close")!);
    await settle();
    expect(layout.size.height, 280);
    expect(find.text("vis plug-in"), findsNothing);

    // Its periodic timers would outlive the test.
    scripts.dispose();
  });

  testWidgets("Amped Modern's config drawer slides once its skin option is "
      "on", (tester) async {
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
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final drawer = _byId(layout.root, "player.normal.drawer")!;
    int drawerY() => drawer.intAttr("y", 0);

    // attribs.m puts it in the Options menu, off as in the classic player:
    // Amped Modern > Drawers > Animate Config Drawer.
    WasabiSkinOption option(List<WasabiSkinOption> options, String label) =>
        options.firstWhere((o) => o.label == label);
    List<WasabiSkinOption> drawers() => option(
      option(scripts.skinOptions, "Amped Modern").children!,
      "Drawers",
    ).children!;
    final animate = option(drawers(), "Animate Config Drawer");
    expect(animate.checkable, isTrue);
    expect(animate.checked, isFalse);
    expect(drawers().where((o) => o.separator), hasLength(1));

    // Off, configtabs.m opens the drawer at once.
    expect(drawerY(), -263);
    scripts.buttonClicked(_byId(layout.root, "drawer.button.open")!);
    await tester.pump();
    expect(drawerY(), -147);
    scripts.buttonClicked(_byId(layout.root, "drawer.button.close")!);
    await tester.pump();
    expect(drawerY(), -263);

    // On, it slides there over a second (setTargetSpeed(1)).
    scripts.toggleSkinOption(animate);
    expect(option(drawers(), "Animate Config Drawer").checked, isTrue);
    scripts.buttonClicked(_byId(layout.root, "drawer.button.open")!);
    await tester.pump(const Duration(milliseconds: 500));
    expect(drawerY(), inExclusiveRange(-263, -147));
    await settle();
    expect(drawerY(), -147);

    // The skin's own check box in the drawer's Options tab is the same
    // option (cfgattrib="{C338B30F-...};Animate Config Drawer").
    const cfgAttrib = WasabiCfgAttrib(
      "{C338B30F-2A04-4B10-871F-4E9D52D62806}",
      "Animate Config Drawer",
    );
    expect(scripts.cfgAttribValue(cfgAttrib), 1);
    expect(scripts.setCfgAttribValue(cfgAttrib, 0), isTrue);
    expect(option(drawers(), "Animate Config Drawer").checked, isFalse);
    expect(
      scripts.cfgAttribValue(
        const WasabiCfgAttrib(
          "{C338B30F-2A04-4B10-871F-4E9D52D62806}",
          "No such option",
        ),
      ),
      isNull,
    );

    scripts.dispose();
  });

  testWidgets("the window follows the config drawer instead of jumping", (
    tester,
  ) async {
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
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    List<WasabiSkinOption> drawers() => scripts.skinOptions
        .firstWhere((o) => o.label == "Amped Modern")
        .children!
        .firstWhere((o) => o.label == "Drawers")
        .children!;
    scripts.toggleSkinOption(
      drawers().firstWhere((o) => o.label == "Animate Config Drawer"),
    );
    final closed = layout.windowSize.height;

    scripts.buttonClicked(_byId(layout.root, "drawer.button.open")!);
    await tester.pump(const Duration(milliseconds: 500));
    expect(layout.windowSize.height, inExclusiveRange(closed, closed + 116));
    await settle();
    final open = layout.windowSize.height;
    expect(open, closed + 116);

    // The window shrinks while the drawer slides in, not after it.
    scripts.buttonClicked(_byId(layout.root, "drawer.button.close")!);
    await tester.pump(const Duration(milliseconds: 500));
    expect(layout.windowSize.height, inExclusiveRange(closed, open));
    await settle();
    expect(layout.windowSize.height, closed);

    scripts.dispose();
  });

  testWidgets("the opening video/vis drawer keeps to its own group", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    final layout = skin.container("main")!.layout("normal")!;
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: WasabiLayoutView(
              skin: skin,
              layout: layout,
              host: host,
              container: "main",
              scripts: scripts,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final avs = _byId(layout.root, "AVSGroup")!;

    // The rows above the video/vis frame: the title and menu bars.
    Future<List<int>> top() async {
      var rows = 0.0;
      for (var n = avs; n.parent != null; n = n.parent!) {
        rows += scripts.rectOf(n).top;
      }
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData();
        return data!.buffer
            .asUint8List(0, rows.round() * image.width * 4)
            .toList();
      }))!;
    }

    final closed = await top();
    expect(closed, isNotEmpty);

    // Animated, the frame is a few pixels tall early on. Its bottom edge
    // (relaty="1" y="-26") then sits above its top, and Wasabi clips it
    // to the group.
    scripts.setConfigAttribute(
      "Animate Video/Vis Drawer (disabled if opacity < 100%)",
      "1",
    );
    scripts.buttonClicked(_byId(layout.root, "videoavs.open")!);
    await tester.pump(const Duration(milliseconds: 140));
    final height = scripts.rectOf(avs).height;
    expect(height, inExclusiveRange(0, 26));
    expect(avs.visible, isTrue);
    expect(await top(), closed);

    scripts.dispose();
  });
}
