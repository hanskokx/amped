import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

/// A 1×1 or larger PNG of a solid color, made with the engine's encoder.
Future<Uint8List> _png(int width, int height, {bool holes = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  if (holes) {
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()
        ..blendMode = ui.BlendMode.clear
        ..color = const ui.Color(0x00000000),
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  group("parseXmlFragment", () {
    test("reads fragments, sloppy comments and attribute case", () {
      final nodes = parseXmlFragment('''
<!-- a comment --> -->
<elements>
  <bitmap id="A" file="a.png" downImage="x &amp; y"/>
</elements>
<groupdef id="g"><layer id="l" x=3 y="4"/></groupdef>
''');
      expect(nodes.map((n) => n.tag), ["elements", "groupdef"]);
      final bitmap = nodes.first.children.single;
      expect(bitmap["id"], "A");
      expect(bitmap["downimage"], "x & y");
      expect(nodes.last.children.single["x"], "3");
    });

    test("closes unbalanced elements", () {
      final nodes = parseXmlFragment("<a><b></a><c/>");
      expect(nodes.map((n) => n.tag), ["a", "c"]);
      expect(nodes.first.children.single.tag, "b");
    });
  });

  group("WasabiSkinData", () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp("wasabi_test");
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test("loads includes, groups, containers and the alpha region", () async {
      await Directory("${dir.path}/xml").create();
      await Directory("${dir.path}/img").create();
      await File(
        "${dir.path}/img/bg.png",
      ).writeAsBytes(await _png(20, 10, holes: true));
      await File("${dir.path}/img/btn.png").writeAsBytes(await _png(5, 3));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="0.8">
<skininfo><name>Test Skin</name><author>Me</author></skininfo>
<include file="xml/main.xml"/>
</WinampAbstractionLayer>''');
      await File("${dir.path}/xml/main.xml").writeAsString('''
<include file="elements.xml"/>
<groupdef id="buttons"><button id="Play" action="PLAY" x="2" y="3" image="btn"/></groupdef>
<container id="Main" name="Main Window" default_visible="1">
  <layout id="normal" background="bg">
    <group id="buttons" x="1" y="1"/>
  </layout>
</container>''');
      await File("${dir.path}/xml/elements.xml").writeAsString('''
<elements>
<bitmap id="bg" file="img/BG.png"/>
<bitmap id="btn" file="img/missing.png"/>
<bitmap id="btn" file="img/btn.png"/>
<bitmap id="btn" file="img/bg.png"/>
</elements>''');

      final skin = await WasabiSkinData.load(dir);
      expect(skin.name, "Test Skin");
      expect(skin.info["author"], "Me");
      // Case-insensitive file names; the first definition of an id that
      // loads wins.
      expect(skin.bitmap("BG")?.size, const ui.Size(20, 10));
      expect(skin.bitmap("btn")?.size, const ui.Size(5, 3));
      final main = skin.container("main")!;
      final layout = main.layout("normal")!;
      expect(layout.size, const ui.Size(20, 10));
      final group = layout.root.children.single;
      expect(group.tag, "group");
      final button = group.children.single;
      expect(button["action"], "PLAY");
      expect(
        wasabiObjectRect(button, layout.size, skin),
        const ui.Rect.fromLTWH(2, 3, 5, 3),
      );
      // The transparent top-left corner is cut out of the shape.
      final region = layout.region!;
      bool inside(ui.Offset p) => region.any(
        (poly) => ui.Rect.fromPoints(poly[0], poly[2]).contains(p),
      );
      expect(inside(const ui.Offset(1, 1)), isFalse);
      expect(inside(const ui.Offset(10, 5)), isTrue);
      expect(isWasabiSkinDirectory(dir), isTrue);

      // relatx/relatw 1 count from the right edge, 2 is percent.
      final relative = WasabiObject("layer", {
        "x": "-10",
        "relatx": "1",
        "y": "50",
        "relaty": "2",
        "w": "-20",
        "relatw": "1",
        "h": "4",
      }, const []);
      expect(
        wasabiObjectRect(relative, const ui.Size(100, 40), skin),
        const ui.Rect.fromLTWH(90, 20, 80, 4),
      );
    });

    test("an image attribute may name a file instead of a bitmap id", () async {
      await Directory("${dir.path}/img").create();
      await File("${dir.path}/img/bg.png").writeAsBytes(await _png(20, 10));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="20" h="10" background="img/bg.png"/>
</container>
</WasabiXML>''');
      final skin = await WasabiSkinData.load(dir);
      expect(skin.bitmap("img/bg.png")?.size, const ui.Size(20, 10));
    });

    test(
      "the player's windows are found by alias or by component guid",
      () async {
        await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="20" h="10"/></container>
<container id="medlib" name="Media Library"><layout id="normal" w="20" h="10"/></container>
<container id="equalizer"><layout id="normal" w="20" h="10"/></container>
<container id="PL" component="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}">
  <layout id="normal" w="20" h="10"/>
</container>
<container id="whatever" component="guid:{0000000A-000C-0010-FF7B-01014263450C}">
  <layout id="normal" w="20" h="10"/>
</container>
</WasabiXML>''');
        final skin = await WasabiSkinData.load(dir);
        expect(skin.windowContainer("library")?.id, "medlib");
        expect(skin.windowContainer("eq")?.id, "equalizer");
        expect(skin.windowContainer("pl")?.id, "pl");
        // Only the guid says that `whatever` is the visualization window.
        expect(skin.windowContainer("vis")?.id, "whatever");
        expect(skin.windowContainer("video"), isNull);
      },
    );

    test(
      "containers beyond the player's windows are the skin's extras",
      () async {
        await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="20" h="10"/></container>
<container id="eq"><layout id="normal" w="20" h="10"/></container>
<container id="control" default_visible="1">
  <layout id="normal" w="20" h="10"><togglebutton id="glass" tooltip="Glass"
    cfgattrib="{9149C445-3C30-4E04-8433-5A518ED0FDDE};Enable desktop alpha"/>
  <togglebutton id="shuffle" cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"/>
  </layout>
</container>
<container id="cont.frame" dynamic="1"><layout id="normal" w="20" h="10"/></container>
</WasabiXML>''');
        final skin = await WasabiSkinData.load(dir);
        expect(skin.extraContainers.map((c) => c.id), ["control"]);
        expect(skin.extraContainers.single.defaultVisibleExplicit, isTrue);
        // Its own switch is an option; the classic player's Shuffle is not.
        expect(skin.cfgToggles.map((t) => t.label), ["Glass"]);
      },
    );

    test("a bitmap may give only some of x, y, w and h", () async {
      await File("${dir.path}/strip.png").writeAsBytes(await _png(20, 60));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<bitmap id="up" file="strip.png" h="30"/>
<bitmap id="down" file="strip.png" y="30" h="30"/>
<bitmap id="right" file="strip.png" x="5"/>
<bitmap id="all" file="strip.png"/>
<bitmap id="none" file="strip.png" x="0" y="0" w="0" h="0"/>
<container id="main"><layout id="normal" w="20" h="30"/></container>
</WasabiXML>''');
      final skin = await WasabiSkinData.load(dir);
      expect(skin.bitmap("up")!.src, const ui.Rect.fromLTWH(0, 0, 20, 30));
      expect(skin.bitmap("down")!.src, const ui.Rect.fromLTWH(0, 30, 20, 30));
      expect(skin.bitmap("right")!.src, const ui.Rect.fromLTWH(5, 0, 15, 60));
      expect(skin.bitmap("all")!.size, const ui.Size(20, 60));
      // A size of 0 is an empty picture, not the whole image.
      expect(skin.bitmap("none")!.size, ui.Size.zero);
    });

    test(
      "a skin with standard frames but no library window gets a frame for it",
      () async {
        await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="wasabi.standardframe.statusbar"><layer id="x" x="0" y="0"/></groupdef>
<container id="main"><layout id="normal" w="20" h="30"/></container>
<container id="Pledit" component="guid:pl"><layout id="normal" w="20" h="30"/></container>
</WasabiXML>''');
        final skin = await WasabiSkinData.load(dir);
        final library = skin.windowContainer("library")!;
        expect(library.component, "guid:ml");
        expect(library.name, "Media Library");
        expect(library.layouts.single.size, const ui.Size(500, 348));
        expect(skin.windowContainer("pl")?.id, "pledit");
        // Not one of the skin's extras.
        expect(skin.extraContainers, isEmpty);
      },
    );

    test("a layout with no size opens at its minimum", () async {
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="354" minimum_w="309" minimum_h="147"/>
</container>
</WasabiXML>''');
      final skin = await WasabiSkinData.load(dir);
      expect(
        skin.container("main")!.layout("normal")!.size,
        const ui.Size(354, 147),
      );
    });

    test(
      "sysregion -2 layers cut their opaque pixels out of the window",
      () async {
        // Opaque except for the transparent 4×4 top-left corner.
        await File(
          "${dir.path}/mask.png",
        ).writeAsBytes(await _png(6, 6, holes: true));
        await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WasabiXML version="1.35">
<bitmap id="mask" file="mask.png"/>
<bitmap id="tall" file="mask.png" x="0" y="2" w="6" h="6"/>
<groupdef id="drawer">
  <layer id="drawer.region" x="0" y="0" image="tall" sysregion="-1"/>
</groupdef>
<groupdef id="frame">
  <layer id="corner.region" x="10" y="2" image="mask" sysregion="-2"/>
  <layer id="hidden.region" x="0" y="0" image="mask" sysregion="sub" visible="0"/>
  <layer id="corner" x="0" y="20" image="mask" sysregion="1"/>
</groupdef>
<container id="main">
  <layout id="normal" w="40" h="30">
    <group id="frame" x="1" y="1" w="0" h="0" relatw="1" relath="1"/>
  </layout>
</container>
</WasabiXML>''');

        final skin = await WasabiSkinData.load(dir);
        final layout = skin.container("main")!.layout("normal")!;
        final cutouts = wasabiRegionCutouts(skin, layout);
        bool cut(ui.Offset p) => cutouts.any((r) => r.contains(p));
        // The mask's opaque pixels, at the layer's place in the group.
        expect(cut(const ui.Offset(16.5, 4.5)), isTrue);
        expect(cut(const ui.Offset(11.5, 7.5)), isTrue);
        // Its transparent pixels, hidden subtractors and adding layers stay.
        expect(cut(const ui.Offset(12.5, 4.5)), isFalse);
        expect(cut(const ui.Offset(2.5, 6.5)), isFalse);
        expect(cut(const ui.Offset(4.5, 25.5)), isFalse);

        // The cutter does not count as something the window draws.
        final shape = wasabiWindowShape(skin, layout)!;
        expect(shape, hasLength(1));
        expect(ui.Rect.fromPoints(shape.single[0], shape.single[2]).top, 21);

        // Groups only scripts create have their masks read too, cropped to
        // the image when the bitmap reaches past it.
        expect(skin.regionMasks["tall"], isNotNull);
        final drawer = skin.newGroup("drawer")!..parent = layout.root;
        layout.root.children.add(drawer);
        // A `sub` (-1) layer cuts its own group, not the whole window: what
        // else covers those pixels (the main body over a closed drawer)
        // still shows.
        expect(wasabiRegionCutouts(skin, layout), cutouts);
        final more = wasabiGroupCutouts(skin, drawer, const ui.Size(40, 30));
        bool cutNow(ui.Offset p) => more.any((r) => r.contains(p));
        expect(cutNow(const ui.Offset(4.5, 2.5)), isTrue);
        expect(cutNow(const ui.Offset(0.5, 0.5)), isFalse);
        expect(cutNow(const ui.Offset(0.5, 4.5)), isFalse);
      },
    );
  });

  test("WasabiArchive finds skin.xml under a top folder", () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          "Top/skin.xml",
          "<WinampAbstractionLayer><skininfo><name>Zip Skin</name></skininfo></WinampAbstractionLayer>",
        ),
      )
      ..addFile(ArchiveFile.string("Top/xml/a.xml", "<elements/>"));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final wal = WasabiArchive.tryOpen(bytes)!;
    expect(wal.displayName, "Zip Skin");
    final dir = await Directory.systemTemp.createTemp("wasabi_zip");
    addTearDown(() => dir.delete(recursive: true));
    await wal.extractTo(dir);
    expect(File("${dir.path}/skin.xml").existsSync(), isTrue);
    expect(File("${dir.path}/xml/a.xml").existsSync(), isTrue);

    final classic = Archive()..addFile(ArchiveFile.string("main.bmp", "x"));
    expect(
      WasabiArchive.tryOpen(Uint8List.fromList(ZipEncoder().encode(classic))),
      isNull,
    );
  });
}
