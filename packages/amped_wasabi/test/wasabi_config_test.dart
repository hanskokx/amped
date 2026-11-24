import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
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

void main() {
  group("cfgattrib", () {
    test("parses an item and an attribute name", () {
      final shuffle = WasabiCfgAttrib.parse(
        "{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d};Shuffle",
      )!;
      expect(shuffle.item, WasabiCfgAttrib.playlistEditor);
      expect(shuffle.name, "Shuffle");
      expect(
        shuffle,
        const WasabiCfgAttrib(WasabiCfgAttrib.playlistEditor, "shuffle"),
      );
      expect(WasabiCfgAttrib.parse(null), isNull);
      expect(WasabiCfgAttrib.parse("Shuffle"), isNull);
      expect(WasabiCfgAttrib.parse("{45F3F7C1};"), isNull);
    });

    test("names the classic player's playback settings", () {
      AmpedSetting? setting(String value) =>
          WasabiCfgAttrib.parse(value)!.setting;
      expect(
        setting("{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"),
        AmpedSetting.shuffle,
      );
      expect(
        setting("{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Repeat"),
        AmpedSetting.repeat,
      );
      expect(setting("Playlist Editor;repeat"), AmpedSetting.repeat);
      expect(
        setting("{FC3EAF78-C66E-4ED2-A0AA-1494DFCC13FF};Enable crossfading"),
        AmpedSetting.crossfade,
      );
      // A skin's own options are none of them.
      expect(
        setting("{F1036C9C-3919-47ac-8494-366778CF10F9};Show Playlist Tab"),
        isNull,
      );
      expect(
        setting("{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Random"),
        isNull,
      );
    });
  });

  test("NStatesButton states map to cfgvals and images", () {
    WasabiObject button(Map<String, String> attributes) =>
        WasabiObject("nstatesbutton", attributes, const []);
    final repeat = WasabiNStates(
      button({"nstates": "3", "cfgvals": "0;1;-1"}),
    );
    expect(repeat.count, 3);
    expect([0, 1, 2].map(repeat.cfgValue), [0, 1, -1]);
    expect(repeat.stateOf(-1), 2);
    expect(repeat.stateOf(2), isNull);
    expect(repeat.next(2), 0);
    expect(repeat.image("player.button.repeat", 2), "player.button.repeat2");
    final plain = WasabiNStates(
      button({"nstates": "2", "autoelements": "0"}),
    );
    expect(plain.cfgValue(1), 1);
    expect(plain.stateOf(1), 1);
    expect(plain.image("button", 1), "button");
  });

  group("skin controls", () {
    late Directory dir;
    late WasabiSkinData skin;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp("wasabi_config");
      await File("${dir.path}/body.png").writeAsBytes(await _png(60, 40));
      // A cover over the left half, see-through on its right half.
      await File("${dir.path}/cover.png").writeAsBytes(
        await _png(30, 40, hole: const ui.Rect.fromLTWH(15, 0, 15, 40)),
      );
      await File("${dir.path}/button.png").writeAsBytes(await _png(10, 10));
      await File("${dir.path}/strip.png").writeAsBytes(await _png(10, 30));
      await File("${dir.path}/skin.xml").writeAsString('''
<?xml version="1.0"?>
<WinampAbstractionLayer version="1.1">
<elements>
  <bitmap id="body" file="body.png"/>
  <bitmap id="cover" file="cover.png"/>
  <bitmap id="button" file="button.png"/>
  <bitmap id="strip" file="strip.png"/>
  <bitmap id="rep0" file="button.png"/>
  <bitmap id="rep1" file="button.png"/>
  <bitmap id="rep2" file="strip.png"/>
</elements>
<groupdef id="ghostly">
  <button id="inghost" image="button" x="0" y="0" action="next"/>
</groupdef>
<container id="main">
  <layout id="normal" background="body">
    <togglebutton id="repeat" image="button" x="2" y="2"
      cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Repeat" cfgval="2"/>
    <togglebutton id="under" image="button" x="17" y="2"
      cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle"/>
    <layer id="cover" image="cover" x="0" y="0" rectrgn="0"/>
    <layer id="block" image="button" x="0" y="25"/>
    <group id="ghostly" x="40" y="2" w="20" h="20" ghost="1"/>
    <NStatesButton id="states" x="20" y="25" nstates="3" image="rep"
      cfgattrib="{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Repeat"
      cfgvals="0;1;-1"/>
    <animatedlayer id="anim" image="strip" x="40" y="25" frameheight="10"/>
  </layout>
</container>
</WinampAbstractionLayer>''');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<FakeHost> pump(WidgetTester tester) async {
      skin = (await tester.runAsync(() => WasabiSkinData.load(dir)))!;
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
      return host;
    }

    testWidgets("a toggle button sets its config attribute to its cfgval", (
      tester,
    ) async {
      final host = await pump(tester);
      const repeat = WasabiCfgAttrib(WasabiCfgAttrib.playlistEditor, "Repeat");
      // Out from under the cover.
      final layout = skin.container("main")!.layout("normal")!;
      layout.root.children[2].attributes["visible"] = "0";
      host.notifyListeners();
      await tester.pump();
      await tester.tapAt(const Offset(7, 7));
      expect(host.configValue(repeat), 2);
      await tester.tapAt(const Offset(7, 7));
      expect(host.configValue(repeat), 0);
    });

    testWidgets("an NStatesButton steps through its states' cfgvals", (
      tester,
    ) async {
      final host = await pump(tester);
      const repeat = WasabiCfgAttrib(WasabiCfgAttrib.playlistEditor, "Repeat");
      final layout = skin.container("main")!.layout("normal")!;
      final button = layout.root.children.firstWhere(
        (child) => child.id == "states",
      );
      // Sized by its first state's image.
      expect(
        wasabiObjectRect(button, layout.size, skin),
        const Rect.fromLTWH(20, 25, 10, 10),
      );
      final values = <int>[];
      for (var i = 0; i < 4; i++) {
        await tester.tapAt(const Offset(25, 30));
        values.add(host.configValue(repeat));
      }
      expect(values, [1, -1, 0, 1]);
      // It shows the state of a value set elsewhere.
      host.setConfigValue(repeat, -1);
      await tester.tapAt(const Offset(25, 30));
      expect(host.configValue(repeat), 0);
    });

    testWidgets("a rectrgn=0 layer lets clicks through its holes", (
      tester,
    ) async {
      final host = await pump(tester);
      const shuffle = WasabiCfgAttrib(
        WasabiCfgAttrib.playlistEditor,
        "Shuffle",
      );
      // The button at x 17 is under the cover's see-through half.
      await tester.tapAt(const Offset(22, 7));
      expect(host.configValue(shuffle), 1);
      // The repeat button is under its opaque half.
      await tester.tapAt(const Offset(7, 7));
      expect(
        host.configValue(
          const WasabiCfgAttrib(WasabiCfgAttrib.playlistEditor, "Repeat"),
        ),
        0,
      );
    });

    testWidgets("a ghost group still passes clicks to its objects", (
      tester,
    ) async {
      final host = await pump(tester);
      await tester.tapAt(const Offset(45, 7));
      expect(host.actions.single.action, "NEXT");
    });

    testWidgets("an animated layer shows one frame of its strip", (
      tester,
    ) async {
      await pump(tester);
      final layout = skin.container("main")!.layout("normal")!;
      final anim = layout.root.children.last;
      final strip = skin.bitmap("strip")!;
      expect(wasabiAnimationFrames(anim, strip)!.count, 3);
      expect(
        wasabiObjectRect(anim, layout.size, skin),
        const Rect.fromLTWH(40, 25, 10, 10),
      );
      anim.attributes["#frame"] = "2";
      expect(
        wasabiFrameBitmap(anim, strip).src,
        const Rect.fromLTWH(0, 20, 10, 10),
      );
      // Past the end it shows the first frame.
      anim.attributes["#frame"] = "3";
      expect(wasabiFrameBitmap(anim, strip).src.top, 0);
    });
  });
}
