import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

Future<List<int>> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Every `<Menu>` under [object], in XML order.
List<WasabiMenu> _menusIn(WasabiObject object) => [
  if (WasabiMenu.of(object) case final menu?) menu,
  for (final child in object.children) ..._menusIn(child),
];

/// A skin with one menu button whose group swaps its layers by look.
Future<WasabiSkinData> _menuSkin(WidgetTester tester) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp("wasabi_menu"),
  ))!;
  addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
  final skin = (await tester.runAsync(() async {
    await File("${dir.path}/bg.png").writeAsBytes(await _png(60, 30));
    await File("${dir.path}/btn.png").writeAsBytes(await _png(20, 16));
    await File("${dir.path}/skin.xml").writeAsString('''
<WinampAbstractionLayer>
<elements>
  <bitmap id="bg" file="bg.png"/>
  <bitmap id="btn" file="btn.png"/>
</elements>
<groupdef id="menugroup.file" w="20" h="16">
  <layer id="up.btn" image="btn"/>
  <layer id="hover.btn" image="btn" visible="0"/>
  <layer id="down.btn" image="btn" visible="0"/>
  <Menu id="File.menu" w="0" h="16" relatw="1" menu="WA5:File"
    normal="up.btn" hover="hover.btn" down="down.btn"/>
</groupdef>
<container id="main" name="Main">
  <layout id="normal" background="bg">
    <group id="menugroup.file" x="10" y="5"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
    return WasabiSkinData.load(dir);
  }))!;
  return skin;
}

void main() {
  group("WasabiMenu", () {
    final object = WasabiObject("menu", {
      "id": "File.menu",
      "menugroup": "main",
      "next": "Play.menu",
      "prev": "Help.menu",
      "menu": "WA5:File",
      "normal": "File.up.btn",
      "hover": "File.hover.btn",
      "down": "File.down.btn",
    }, const []);

    test("reads a <Menu> object", () {
      final menu = WasabiMenu.of(object)!;
      expect(menu.menu, "WA5:File");
      expect(menu.menuGroup, "main");
      expect(menu.next, "Play.menu");
      expect(menu.prev, "Help.menu");
      expect(
        WasabiMenu.of(WasabiObject("layer", {"menu": "x"}, const [])),
        isNull,
      );
      expect(WasabiMenu.of(WasabiObject("menu", const {}, const [])), isNull);
    });

    test("shows the button for its look", () {
      final menu = WasabiMenu.of(object)!;
      Map<String, bool?> shown(WasabiMenuLook look) => {
        for (final id in const [
          "File.up.btn",
          "file.hover.btn",
          "File.down.btn",
          "File.txt",
        ])
          id: menu.showsButton(id, look),
      };
      expect(shown(WasabiMenuLook.normal), {
        "File.up.btn": true,
        "file.hover.btn": false,
        "File.down.btn": false,
        "File.txt": null,
      });
      expect(shown(WasabiMenuLook.hover), {
        "File.up.btn": false,
        "file.hover.btn": true,
        "File.down.btn": false,
        "File.txt": null,
      });
      expect(shown(WasabiMenuLook.down)["File.down.btn"], isTrue);

      // Without a hover button the normal one stays.
      const plain = WasabiMenu(menu: "WA5:Play", normal: "up");
      expect(plain.showsButton("up", WasabiMenuLook.hover), isTrue);
    });
  });

  testWidgets("a <Menu> shows its hover button and opens its menu", (
    tester,
  ) async {
    final skin = await _menuSkin(tester);
    final layout = skin.container("main")!.layout("normal")!;
    final host = FakeHost();
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
          ),
        ),
      ),
    );

    bool layerShown(String id) => find
        .byWidgetPredicate(
          (w) =>
              w is Positioned &&
              w.child.runtimeType.toString() == "_ObjectView" &&
              ((w.child as dynamic).object as WasabiObject).id == id,
        )
        .evaluate()
        .isNotEmpty;

    expect(layerShown("up.btn"), isTrue);
    expect(layerShown("hover.btn"), isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(20, 12));
    await tester.pump();
    expect(layerShown("up.btn"), isFalse);
    expect(layerShown("hover.btn"), isTrue);

    await mouse.down(const Offset(20, 12));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    final request = host.menus.single;
    expect(request.menu, "WA5:File");
    expect(request.container, "main");
    expect(request.anchor, const Rect.fromLTWH(10, 5, 20, 16));
    // Back at rest once the menu has closed.
    expect(layerShown("up.btn"), isTrue);
    expect(layerShown("down.btn"), isFalse);
  });

  testWidgets("a <Menu> removed while hovered resets its look quietly", (
    tester,
  ) async {
    final skin = await _menuSkin(tester);
    final layout = skin.container("main")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: FakeHost(),
            container: "main",
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(const Offset(20, 12));
    await tester.pump();

    // Unmounting used to assert: the look was reset while the tree was locked.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets("Amped Modern's menu bars name the Wasabi 5 menus", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final main = skin.container("main")!.layout("normal")!;
    expect(_menusIn(main.root).map((m) => m.menu), [
      "WA5:File",
      "WA5:Play",
      "WA5:Options",
      "WA5:Windows",
      "WA5:Help",
    ]);
    final pl = skin.container("pledit")!.layout("normal")!;
    expect(_menusIn(pl.root).map((m) => m.menu), [
      "WA5:PE_File",
      "WA5:PE_Playlist",
      "WA5:PE_Sort",
      "WA5:PE_Help",
    ]);
  });
}
