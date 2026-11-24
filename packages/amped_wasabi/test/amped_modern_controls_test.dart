import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

void main() {
  group("Amped Modern main window", () {
    late WasabiSkinData skin;
    late FakeHost host;
    late WasabiScriptRuntime runtime;
    late WasabiLayout main;

    Future<void> pump(WidgetTester tester) async {
      skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
      host = FakeHost();
      runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
        ..start();
      main = skin.container("main")!.layout("normal")!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: main,
              host: host,
              container: "main",
              scripts: runtime,
            ),
          ),
        ),
      );
    }

    /// The center of object [id] in layout pixels.
    Offset centerOf(String id) {
      final object = runtime.find(main.root, id)!;
      var rect = runtime.rectOf(object);
      for (var parent = object.parent; parent != null; parent = parent.parent) {
        rect = rect.shift(runtime.rectOf(parent).topLeft);
      }
      return rect.center;
    }

    testWidgets("the transport buttons click through the volume group", (
      tester,
    ) async {
      await pump(tester);
      // player.bar.rightbottom fills the player and has a script; its empty
      // parts must not take the clicks meant for the buttons under it.
      for (final (id, action) in const [
        ("Previous", "PREV"),
        ("Play", "PLAY"),
        ("Pause", "PAUSE"),
        ("Stop", "STOP"),
        ("Next", "NEXT"),
        ("Eject", "EJECT"),
      ]) {
        await tester.tapAt(centerOf(id));
        expect(host.actions.last.action, action, reason: id);
      }
      runtime.dispose();
    });

    testWidgets("the shuffle buttons set the playlist's Shuffle", (
      tester,
    ) async {
      await pump(tester);
      const shuffle = WasabiCfgAttrib(
        WasabiCfgAttrib.playlistEditor,
        "Shuffle",
      );
      expect(shuffle.setting, AmpedSetting.shuffle);
      // The button beside the display, its LED and the display's own
      // indicator all toggle the player's shuffle, not just the display's
      // "Playlist Shuffling: ON" text.
      for (final id in const ["Shuffle", "ShuffleLED", "ShuffleDisplay"]) {
        await tester.tapAt(centerOf(id));
        await tester.pump();
        expect(host.config[shuffle], 1, reason: "$id turns it on");
        await tester.tapAt(centerOf(id));
        await tester.pump();
        expect(host.config[shuffle], 0, reason: "$id turns it off");
      }
      runtime.dispose();
    });

    testWidgets("Repeat steps through off, all and track", (tester) async {
      await pump(tester);
      const repeat = WasabiCfgAttrib(WasabiCfgAttrib.playlistEditor, "Repeat");
      for (var state = 0; state < 3; state++) {
        expect(skin.bitmap("player.button.repeat$state"), isNotNull);
      }
      final infoTicker = runtime.find(main.root, "infoticker")!;
      final values = <int>[];
      final texts = <String?>[];
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(centerOf("Repeat"));
        await tester.pump();
        values.add(host.configValue(repeat));
        texts.add(infoTicker["#text"]);
      }
      // player-normal-group.xml's cfgvals, which display.m reads back.
      expect(values, [1, -1, 0]);
      expect(texts, ["Repeat: ALL", "Repeat: TRACK", "Repeat: OFF"]);
      // The LED beside the button lights for both kinds of repeat.
      final led = runtime.find(main.root, "RepeatLED")!;
      WasabiBitmap? ledShown() {
        final view = find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == "_ObjectView" &&
              identical((widget as dynamic).object, led),
        );
        final paint = find.descendant(
          of: view,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == "_BitmapPaint",
          ),
        );
        return (tester.widget(paint) as dynamic).bitmap as WasabiBitmap?;
      }

      final leds = <WasabiBitmap?>[];
      for (final value in const [1, -1, 0]) {
        host.setConfigValue(repeat, value);
        await tester.pump();
        leds.add(ledShown());
      }
      expect(leds, [
        skin.bitmap("player.led.on"),
        skin.bitmap("player.led.on"),
        skin.bitmap("player.led.off"),
      ]);
      // The display's repeat icon is bound to the same attribute.
      await tester.tapAt(centerOf("RepeatDisplay"));
      expect(host.configValue(repeat), 1);
      runtime.dispose();
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
