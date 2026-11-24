import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Wasabi 5's own modern skin, from the original source tree when it is
/// around.
final Directory _modern = ampedModern;

Future<ui.Image> _image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFCC6633),
  );
  return recorder.endRecording().toImage(width, height);
}

Future<Uint8List> _png(int width, int height) async {
  final image = await _image(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  group("wasabiAlbumArtRect", () {
    const box = Size(100, 50);

    test("fits the picture and centers it", () {
      expect(
        wasabiAlbumArtRect(const Size(200, 200), box),
        const Rect.fromLTWH(25, 0, 50, 50),
      );
      expect(
        wasabiAlbumArtRect(const Size(400, 100), box),
        const Rect.fromLTWH(0, 12, 100, 25),
      );
    });

    test("aligns and stretches as the skin says", () {
      expect(
        wasabiAlbumArtRect(const Size(10, 10), box, align: -1),
        const Rect.fromLTWH(0, 0, 50, 50),
      );
      expect(
        wasabiAlbumArtRect(const Size(10, 10), box, align: 1),
        const Rect.fromLTWH(50, 0, 50, 50),
      );
      expect(
        wasabiAlbumArtRect(const Size(40, 10), box, valign: 1),
        const Rect.fromLTWH(0, 25, 100, 25),
      );
      expect(
        wasabiAlbumArtRect(const Size(10, 10), box, stretched: true),
        Offset.zero & box,
      );
    });
  });

  group("<AlbumArt>", () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp("wasabi_album_art");
      await File("${dir.path}/nf.png").writeAsBytes(await _png(10, 10));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
<elements>
  <bitmap id="nf" file="nf.png"/>
</elements>
<container id="main">
  <layout id="normal" w="60" h="40">
    <AlbumArt id="art" x="10" y="10" w="40" h="20" notfoundImage="nf"
      valign="top"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    testWidgets("draws the cover, or the not-found image without one", (
      tester,
    ) async {
      final skin = (await tester.runAsync(() => WasabiSkinData.load(dir)))!;
      final host = FakeHost();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: skin.container("main")!.layout("normal")!,
              host: host,
              container: "main",
            ),
          ),
        ),
      );
      final art = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == "_AlbumArtPainter",
      );
      expect(art, findsOneWidget);
      // The square not-found image, centered across.
      expect(
        art,
        paints..drawImageRect(
          source: const Rect.fromLTWH(0, 0, 10, 10),
          destination: const Rect.fromLTWH(10, 0, 20, 20),
        ),
      );

      host.albumArt = (await tester.runAsync(() => _image(80, 20)))!;
      host.notifyListeners();
      await tester.pump();
      // A wide cover, kept to its shape at the top (valign="top").
      expect(
        art,
        paints..drawImageRect(
          source: const Rect.fromLTWH(0, 0, 80, 20),
          destination: const Rect.fromLTWH(0, 0, 40, 10),
        ),
      );
    });
  });

  testWidgets("a right-click opens the album art menu, a double-click the "
      "folder", (tester) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: skin.container("amped.albumart")!.layout("normal")!,
            host: host,
            scripts: scripts,
            container: "amped.albumart",
          ),
        ),
      ),
    );
    final art = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == "_AlbumArtMouse",
    );
    final center = tester.getCenter(art);
    final right = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    expect(host.albumArtPresses, 1);
    expect(host.albumArtMenus, 0);
    await right.up();
    expect(host.albumArtMenus, 1);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    expect(host.albumArtFolders, 1);
    scripts.dispose();
  });

  testWidgets("Amped Modern's album art window shows the cover", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    final layout = skin.container("amped.albumart")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            scripts: scripts,
            container: "amped.albumart",
          ),
        ),
      ),
    );
    host.albumArt = (await tester.runAsync(() => _image(300, 300)))!;
    host.notifyListeners();
    await tester.pump();
    final art = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == "_AlbumArtPainter",
    );
    expect(art, findsOneWidget);
    expect(
      art,
      paints..drawImageRect(source: const Rect.fromLTWH(0, 0, 300, 300)),
    );
    expect(tester.takeException(), isNull);
    scripts.dispose();
  });

  testWidgets("Amped Modern's album art window has a plate for no cover", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    final layout = skin.container("amped.albumart")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            scripts: scripts,
            container: "amped.albumart",
          ),
        ),
      ),
    );
    await tester.pump();
    // The skin has no picture for a missing cover (the classic player supplies its
    // own), so amped draws a plate with a note.
    expect(skin.bitmap("winamp.cover.notfound"), isNull);
    final plate = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == "_NoCoverPainter",
    );
    expect(plate, findsOneWidget);
    expect(plate, paints..rrect());
    // The note is drawn solid into one translucent layer: shapes that were
    // translucent themselves would add up where the stem meets the head and
    // the flag.
    var layers = 0;
    var solid = true;
    expect(
      plate,
      paints..everything((method, arguments) {
        if (method == #saveLayer) layers++;
        if (method == #drawLine && (arguments[2] as Paint).color.a != 1) {
          solid = false;
        }
        return true;
      }),
    );
    expect(layers, 1);
    expect(solid, isTrue);
    // A cover takes its place.
    host.albumArt = (await tester.runAsync(() => _image(300, 300)))!;
    host.notifyListeners();
    await tester.pump();
    expect(plate, findsNothing);
    scripts.dispose();
  });

  testWidgets("the note on the plate is centred on it", (tester) async {
    tester.view.physicalSize = const Size(260, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = FakeHost();
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: host,
      log: (_) {},
    )..start();
    final layout = skin.container("amped.albumart")!.layout("normal")!;
    layout.root.attributes
      ..["w"] = "230"
      ..["h"] = "230";
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
              scripts: scripts,
              container: "amped.albumart",
            ),
          ),
        ),
      ),
    );
    scripts.layoutResized(layout);
    await tester.pump();

    // The plate is a square, 90% of the object's short side, centred in it.
    final art = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == "_NoCoverPainter",
      ),
    );
    const scale = 4;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: scale.toDouble());
      return (image, (await image.toByteData())!);
    }))!;
    final (image, data) = bytes;
    double luma(int x, int y) {
      final i = (y * image.width + x) * 4;
      return 0.3 * data.getUint8(i) +
          0.59 * data.getUint8(i + 1) +
          0.11 * data.getUint8(i + 2);
    }

    // The note is what differs from the plate beside it in its row (the
    // plate's gradient only runs down).
    final side = 0.9 * art.shortestSide;
    final left = ((art.center.dx - side * 0.42) * scale).round();
    final right = ((art.center.dx + side * 0.42) * scale).round();
    final top = ((art.center.dy - side * 0.42) * scale).round();
    final bottom = ((art.center.dy + side * 0.42) * scale).round();
    var minX = right, maxX = left, minY = bottom, maxY = top;
    for (var y = top; y <= bottom; y++) {
      final base = luma(left, y);
      for (var x = left; x <= right; x++) {
        if ((luma(x, y) - base).abs() > 12) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    expect(maxX, greaterThan(minX), reason: "the note is drawn");
    final centre = Offset((minX + maxX) / 2 / scale, (minY + maxY) / 2 / scale);
    expect((centre.dx - art.center.dx).abs(), lessThan(0.75));
    expect((centre.dy - art.center.dy).abs(), lessThan(0.75));
    scripts.dispose();
  });

  testWidgets("wasabiAlbumArtArea finds the cover inside the frame", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final layout = skin.container("amped.albumart")!.layout("normal")!;
    // The frame's script puts the content group in place.
    expect(wasabiAlbumArtArea(skin, layout), isNull);
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    expect(
      wasabiAlbumArtArea(skin, layout),
      const Rect.fromLTWH(6, 23, 152, 131),
    );
    scripts.dispose();
  });
}
