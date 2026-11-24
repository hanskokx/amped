import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// A PNG of [width] by [height], opaque except for [hole] (if any).
Future<Uint8List> _png(int width, int height, {ui.Rect? hole}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  if (hole != null) {
    canvas.drawRect(
      hole,
      ui.Paint()
        ..blendMode = ui.BlendMode.clear
        ..color = const ui.Color(0x00000000),
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Anexa, from the test skins, when it is around.
bool _inside(List<List<ui.Offset>>? region, ui.Offset point) =>
    region == null ||
    region.any((p) => ui.Rect.fromPoints(p[0], p[2]).contains(point));

void main() {
  group("composed window region", () {
    late Directory dir;
    late WasabiSkinData skin;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp("wasabi_region");
      // A 40x20 body whose right half is see-through, and a drawer that
      // slides out of a mask covering that half (Anexa's setup drawer).
      await File("${dir.path}/body.png").writeAsBytes(
        await _png(40, 20, hole: const ui.Rect.fromLTWH(20, 0, 20, 20)),
      );
      await File("${dir.path}/mask.png").writeAsBytes(await _png(20, 20));
      await File("${dir.path}/drawer.png").writeAsBytes(await _png(10, 10));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
<elements>
  <bitmap id="body" file="body.png"/>
  <bitmap id="mask" file="mask.png"/>
  <bitmap id="drawer" file="drawer.png"/>
</elements>
<groupdef id="drawer" background="drawer"/>
<groupdef id="drawer.mask" background="mask">
  <group id="drawer" sysregion="AND" x="-10"/>
</groupdef>
<groupdef id="cut"><layer image="drawer" sysregion="-2"/></groupdef>
<groupdef id="stretch"><layer image="drawer" sysregion="-2" w="20" h="10"/></groupdef>
<container id="main">
  <layout id="normal" background="body">
    <group id="drawer.mask" x="20" y="0"/>
  </layout>
  <layout id="cut" background="body">
    <group id="cut" x="0" y="0"/>
  </layout>
  <layout id="stretched" w="40" h="20">
    <group id="stretch" x="0" y="0"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
      skin = await WasabiSkinData.load(dir);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test("follows a drawer sliding out of an AND mask", () {
      final layout = skin.container("main")!.layout("normal")!;
      final drawer = layout.root.children.single.children.single;
      const out = ui.Offset(25, 5);

      // Tucked away left of its mask, the drawer adds nothing.
      var region = wasabiLayoutRegion(skin, layout);
      expect(_inside(region, const ui.Offset(5, 5)), isTrue);
      expect(_inside(region, out), isFalse);
      expect(identical(wasabiLayoutRegion(skin, layout), region), isTrue);

      // Slid into the mask, it is part of the window, clipped to the mask.
      drawer.attributes["x"] = "0";
      region = wasabiLayoutRegion(skin, layout);
      expect(_inside(region, out), isTrue);
      expect(_inside(region, const ui.Offset(25, 15)), isFalse);
      expect(wasabiWindowShape(skin, layout), region);

      // Hidden with its mask, it leaves the window again.
      layout.root.children.single.attributes["visible"] = "0";
      expect(_inside(wasabiLayoutRegion(skin, layout), out), isFalse);
    });

    test("cuts sub2 regions out of the window", () {
      final layout = skin.container("main")!.layout("cut")!;
      final region = wasabiLayoutRegion(skin, layout);
      expect(_inside(region, const ui.Offset(5, 5)), isFalse);
      expect(_inside(region, const ui.Offset(15, 5)), isTrue);
    });

    test("a cutting layer given a size cuts as much as it is stretched", () {
      final layout = skin.container("main")!.layout("stretched")!;
      final cutouts = wasabiRegionCutouts(skin, layout);
      bool cut(ui.Offset p) => cutouts.any((r) => r.contains(p));
      // The 10 pixel mask, stretched to the 20 pixels of the layer.
      expect(cut(const ui.Offset(5, 5)), isTrue);
      expect(cut(const ui.Offset(15, 5)), isTrue);
      expect(cut(const ui.Offset(25, 5)), isFalse);
      expect(cut(const ui.Offset(15, 15)), isFalse);
    });

    test("reverseTarget grows an object up and to the left", () async {
      final runtime = WasabiScriptRuntime(
        skin: skin,
        host: FakeHost(),
        log: (_) {},
      )..start();
      addTearDown(runtime.dispose);
      final layout = skin.container("main")!.layout("normal")!;
      final drawer = runtime.wrap(layout.root.children.single.children.single);
      void call(String member, [List<Object?> args = const []]) =>
          drawer.invoke(runtime.vm, member, args);

      call("reversetarget", [1]);
      call("settargetw", [16]);
      call("settargeth", [14]);
      call("settargetx", [99]);
      call("settargetspeed", [0.05]);
      call("gototarget");
      expect(drawer.invoke(runtime.vm, "isgoingtotarget", const []), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(drawer.invoke(runtime.vm, "isgoingtotarget", const []), isFalse);
      // 6 wider and 4 taller, with the bottom right corner kept.
      expect(
        runtime.rectOf(drawer.node),
        const ui.Rect.fromLTWH(-16, -4, 16, 14),
      );

      // Not reversed, it moves to its target x again.
      call("reversetarget", [0]);
      call("settargetx", [3]);
      call("settargetspeed", [0.05]);
      call("gototarget");
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(runtime.rectOf(drawer.node).left, 3);
    });
  });
}
