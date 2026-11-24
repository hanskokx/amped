import "dart:io";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

/// Anexa, from the test skins, when it is around.
/// An opaque PNG of [width] by [height].
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

/// The offsets of the thumbs of [layout]'s sliders from their sliders'
/// tops, in the order the skin lists them.
List<double> _thumbTops(WidgetTester tester) {
  final sliders = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == "_SliderView",
  );
  return [
    for (var i = 0; i < sliders.evaluate().length; i++)
      tester
              .widget<Positioned>(
                find.descendant(
                  of: sliders.at(i),
                  matching: find.byType(Positioned),
                ),
              )
              .top ??
          -1,
  ];
}

/// Where a vertical slider of [travel] pixels puts its thumb for [value].
double _topFor(double value, double travel) =>
    ((1 - value) * travel).truncateToDouble();

Future<void> _pump(
  WidgetTester tester,
  WasabiSkinData skin,
  WasabiLayout layout,
  FakeHost host, {
  WasabiScriptRuntime? scripts,
}) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: WasabiLayoutView(
        skin: skin,
        layout: layout,
        host: host,
        container: "eq",
        scripts: scripts,
      ),
    ),
  ),
);

void main() {
  testWidgets("EQ sliders follow EQ changes made elsewhere", (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp("wasabi_eq"),
    ))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
    final skin = (await tester.runAsync(() async {
      await File("${dir.path}/body.png").writeAsBytes(await _png(60, 80));
      await File("${dir.path}/thumb.png").writeAsBytes(await _png(10, 10));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
<elements>
  <bitmap id="body" file="body.png"/>
  <bitmap id="thumb" file="thumb.png"/>
</elements>
<container id="eq">
  <layout id="main" background="body">
    <slider x="0" y="0" w="10" h="60" orientation="v" thumb="thumb" action="EQ_PREAMP"/>
    <slider x="20" y="0" w="10" h="60" orientation="v" thumb="thumb" action="EQ_BAND" param="1"/>
    <slider x="40" y="0" w="10" h="60" orientation="v" thumb="thumb" action="EQ_BAND" param="10"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
      return WasabiSkinData.load(dir);
    }))!;
    final host = FakeHost();
    await _pump(tester, skin, skin.container("eq")!.layout("main")!, host);
    expect(_thumbTops(tester), [25, 25, 25]);

    // A preset from the menu, auto-load or the classic window changes the
    // player's EQ, which the host reports.
    host.values["EQ_PREAMP"] = 1;
    host.values["EQ_BAND1"] = 0;
    host.values["EQ_BAND10"] = 0.75;
    host.notifyListeners();
    await tester.pump();
    expect(_thumbTops(tester), [0, 50, _topFor(0.75, 50)]);
  });

  testWidgets("an EQ toggle button shows the EQ state when it starts on", (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp("wasabi_eq_toggle"),
    ))!;
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
    final skin = (await tester.runAsync(() async {
      await File("${dir.path}/body.png").writeAsBytes(await _png(60, 40));
      await File("${dir.path}/off.png").writeAsBytes(await _png(20, 20));
      await File("${dir.path}/on.png").writeAsBytes(await _png(20, 20));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
<elements>
  <bitmap id="body" file="body.png"/>
  <bitmap id="off" file="off.png"/>
  <bitmap id="on" file="on.png"/>
</elements>
<container id="eq">
  <layout id="main" background="body">
    <togglebutton x="0" y="0" image="off" activeimage="on" action="EQ_TOGGLE"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
      return WasabiSkinData.load(dir);
    }))!;
    final host = _EqHost()..eq = true;
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);
    await _pump(
      tester,
      skin,
      skin.container("eq")!.layout("main")!,
      host,
      scripts: runtime,
    );

    WasabiBitmap shown() =>
        (tester.widget(
                      find
                          .byWidgetPredicate(
                            (widget) =>
                                widget.runtimeType.toString() == "_BitmapPaint",
                          )
                          .last,
                    )
                    as dynamic)
                .bitmap
            as WasabiBitmap;

    expect(shown(), skin.bitmap("on"));
    // Each click turns the EQ off or on, and the button follows it instead
    // of staying lit from its own flip.
    for (final eq in const [false, true, false]) {
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(host.eq, eq);
      expect(shown(), skin.bitmap(eq ? "on" : "off"), reason: "EQ $eq");
    }
    // Turned on elsewhere (the classic window, a shortcut).
    host
      ..eq = true
      ..notifyListeners();
    await tester.pump();
    expect(shown(), skin.bitmap("on"));
  });
}

/// A host whose EQ_TOGGLE action turns its EQ on and off.
class _EqHost extends FakeHost {
  @override
  void runAction(WasabiAction action) {
    super.runAction(action);
    if (action.action == "EQ_TOGGLE") {
      eq = !eq;
      notifyListeners();
    }
  }
}
