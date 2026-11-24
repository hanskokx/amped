import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

WasabiObject? _byId(WasabiObject node, String id) {
  for (final child in node.children) {
    if (child.id.toLowerCase() == id.toLowerCase()) return child;
    final found = _byId(child, id);
    if (found != null) return found;
  }
  return null;
}

void main() {
  group("gamma groups", () {
    test("gray 1 takes the brightest channel, then scales", () {
      const group = WasabiGammaGroup(id: "g", gray: 1);
      final pixels = Uint8List.fromList([10, 200, 30, 255]);
      group.filterPixels(pixels);
      // 200 * 65535 >> 16: the bitmap filter loses one level at 0.
      expect(pixels, [199, 199, 199, 255]);
      expect(
        group.filterColor(const ui.Color.fromARGB(255, 10, 200, 30)),
        const ui.Color.fromARGB(255, 200, 200, 200),
      );
    });

    test("gray 2 averages and boost halves and adds half of white", () {
      const average = WasabiGammaGroup(id: "g", gray: 2);
      expect(
        average.filterColor(const ui.Color.fromARGB(255, 30, 60, 90)),
        const ui.Color.fromARGB(255, 60, 60, 60),
      );
      const boost = WasabiGammaGroup(id: "g", boost: true);
      expect(
        boost.filterColor(const ui.Color.fromARGB(255, 0, 100, 255)),
        const ui.Color.fromARGB(255, 128, 178, 255),
      );
    });

    test("a channel's value scales it from -4096 (none) to 4096 (double)", () {
      const group = WasabiGammaGroup(id: "g", red: -4096, blue: 4095);
      final color = group.filterColor(
        const ui.Color.fromARGB(255, 100, 100, 100),
      );
      expect(color.r * 255, closeTo(0, 1));
      expect(color.g * 255, closeTo(100, 1));
      expect(color.b * 255, closeTo(200, 1));
    });

    test("a set adds its General group to the others", () {
      final set = WasabiGammaSet("t")
        ..add(const WasabiGammaGroup(id: "General", red: 100, gray: 1))
        ..add(
          const WasabiGammaGroup(id: "Text", red: 50, green: 7, boost: true),
        );
      final text = set.resolve("text");
      expect((text.red, text.green, text.gray, text.boost), (150, 7, 1, true));
      final other = set.resolve("Nothing");
      expect(
        (other.red, other.green, other.gray, other.boost),
        (100, 0, 1, false),
      );
    });
  });

  group("Amped Modern's color themes", () {
    test("are read from color-presets.xml with their groups", () async {
      final skin = await WasabiSkinData.load(_modern);
      final themes = skin.colorThemes;
      expect(themes.sets, hasLength(45));
      expect(themes.sets.first.name, "Default");
      expect(themes.current!.name, "Default");
      final good = themes.named("good ol' amped")!;
      final backgrounds = good.resolve("Backgrounds");
      expect(
        (
          backgrounds.red,
          backgrounds.green,
          backgrounds.blue,
          backgrounds.gray,
        ),
        (-2848, -2848, -2368, 2),
      );
      expect(good.resolve("Text").boost, isTrue);
      // The list is sorted, ignoring case.
      expect(
        themes.names.first.toLowerCase().compareTo(
          themes.names[1].toLowerCase(),
        ),
        lessThan(0),
      );
      expect(themes.advance(1), isNot("Default"));
    });

    test("include the built-in Kabukichō theme", () async {
      final skin = await WasabiSkinData.load(_modern);
      final themes = skin.colorThemes;
      expect(themes.names, contains("Kabukichō"));
      final kabukicho = themes.named("kabukichō")!;
      expect(kabukicho.resolve("ButtonsHover").green, greaterThan(-1000));
      expect(kabukicho.resolve("Backgrounds").gray, 1);
      expect(themes.sets.first.name, "Default");
    });

    test("bitmaps and colors keep their gamma group", () async {
      final skin = await WasabiSkinData.load(_modern);
      expect(
        skin.bitmaps.values.where((b) => b.gammaGroup != null),
        isNotEmpty,
      );
      expect(skin.colorGroups["wasabi.list.background"], "ListBackground");
    });

    testWidgets("the Color Themes tab lists, switches and remembers", (
      tester,
    ) async {
      final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
      final host = FakeHost();
      final scripts = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
        ..start();
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
      final list = _byId(layout.root, "colorthemes")!;
      expect(wasabiIsColorThemesList(list), isTrue);

      // The buttons' actions reach the list. They run in real time: the
      // bitmaps are filtered and decoded off the test's fake clock.
      Future<void> press(String action) async {
        await tester.runAsync(() async {
          scripts.buttonAction(
            WasabiObject("button", {
              "action": action,
              "action_target": "colorthemes",
            }, const [])..parent = list.parent,
          );
          await skin.colorThemes.settled;
        });
        await tester.pump();
      }

      final names = skin.colorThemes.names;
      await press("colorthemes_next");
      expect(
        skin.colorThemes.current!.name,
        names[(names.indexOf("Default") + 1) % names.length],
      );
      expect(
        host.readPrivate("Color Themes", skin.name),
        skin.colorThemes.current!.name,
      );
      await press("colorthemes_previous");
      expect(skin.colorThemes.current!.name, "Default");

      // Selecting a row and pressing Switch turns that theme on.
      list.attributes["#selected"] = "Good Ol' Amped";
      await press("colorthemes_switch");
      expect(skin.colorThemes.applied!.name, "Good Ol' Amped");
      expect(wasabiSavedColorTheme(host, skin.name), "Good Ol' Amped");

      // A skin loaded again starts in the saved theme.
      final again = (await tester.runAsync(
        () => WasabiSkinData.load(
          _modern,
          colorTheme: wasabiSavedColorTheme(host, skin.name),
        ),
      ))!;
      expect(again.colorThemes.applied!.name, "Good Ol' Amped");

      scripts.dispose();
    });
  });
}
