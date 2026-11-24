// The text painters are private to the view; the tests read what they
// draw through `dynamic`.
// ignore_for_file: avoid_dynamic_calls

import "dart:io";
import "dart:typed_data";

import "package:amped_vis/amped_vis.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

/// A player that can be stopped, with a title too long for the ticker and
/// a visualization the scripts show and hide by its GUID.
class _Host extends FakeHost {
  bool stopped = false;
  bool visShown = false;
  final List<(String, bool)> shown = [];

  /// The level of the sound (1 is full scale), for the meters.
  double level = 0;
  int sampleUsers = 0;

  @override
  bool get visRunning => level > 0;

  @override
  void startVisualization() => sampleUsers++;

  @override
  void stopVisualization() => sampleUsers--;

  @override
  (Float32List, Float32List)? get visSamples => (
    Float32List.fromList([0, -level, level / 2]),
    Float32List.fromList([0, level / 4, 0]),
  );

  @override
  String get songTitle => "DJ Mike Llama - Llama Whippin' Intro";

  @override
  int get lengthMs => 5000;

  @override
  int get positionMs => stopped ? -1 : 3000;

  @override
  int get playbackStatus => stopped ? 0 : 1;

  /// Set to do what the app does with a script's resize: size the layout
  /// and tell the scripts.
  WasabiScriptRuntime? runtime;

  @override
  void resizeLayout(String container, WasabiLayout layout, Size size) {
    super.resizeLayout(container, layout, size);
    final runtime = this.runtime;
    if (runtime == null) return;
    layout.root.attributes
      ..["w"] = "${size.width.round()}"
      ..["h"] = "${size.height.round()}";
    runtime
      ..layoutResized(layout)
      ..changed();
  }

  @override
  bool isContainerVisible(String id) =>
      wasabiComponentOf(id) == "vis" ? visShown : super.isContainerVisible(id);

  @override
  void setContainerVisible(String id, bool visible) {
    shown.add((id, visible));
    if (wasabiComponentOf(id) == "vis") visShown = visible;
  }
}

void main() {
  group("Amped Modern main window", () {
    late WasabiSkinData skin;
    late _Host host;
    late WasabiScriptRuntime runtime;
    late WasabiLayout main;

    Future<void> pump(WidgetTester tester, {bool stopped = false}) async {
      skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
      host = _Host()..stopped = stopped;
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

    WasabiObject object(String id) => runtime.find(main.root, id)!;

    /// The view of [node].
    Finder viewOf(WasabiObject node) => find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == "_ObjectView" &&
          identical((widget as dynamic).object, node),
    );

    /// What [node], a text, draws: its painter.
    dynamic painterOf(WidgetTester tester, WasabiObject node) => tester
        .widget<CustomPaint>(
          find.descendant(
            of: viewOf(node),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;

    testWidgets("its displays are in the skin's bitmap fonts", (tester) async {
      await pump(tester);
      final font = skin.bitmapFont("player.songticker.font")!;
      expect(font.charWidth, 10);
      expect(font.charHeight, 22);
      expect(font.advance, 9);
      expect(font.textWidth("LLAMA"), 45);
      // Letters on the first row, digits and punctuation on the second,
      // `?` and `*` on the third.
      expect(font.glyph("a".codeUnitAt(0)), Offset.zero);
      expect(font.glyph("C".codeUnitAt(0)), const Offset(20, 0));
      expect(font.glyph("7".codeUnitAt(0)), const Offset(70, 22));
      expect(font.glyph(":".codeUnitAt(0)), const Offset(120, 22));
      expect(font.glyph("*".codeUnitAt(0)), const Offset(40, 44));
      for (final id in ["timer", "Bitrate", "Frequency", "Songticker"]) {
        expect(skin.bitmapFont(object(id)["font"]), isNotNull, reason: id);
      }
      runtime.dispose();
    });

    testWidgets("the timer puts a narrow colon between minutes and seconds", (
      tester,
    ) async {
      await pump(tester);
      final timer = object("timer");
      final runs = painterOf(tester, timer).runs as List;
      expect(runs.join(), "0:03");
      // 12 px a digit, a 5 px colon (`timecolonwidth`), centred in 78 px.
      expect([for (final run in runs) (run as dynamic).x], [18.0, 30.0, 35.0]);
      runtime.dispose();
    });

    testWidgets("the timer shows 00:00 when stopped", (tester) async {
      await pump(tester, stopped: true);
      final runs = painterOf(tester, object("timer")).runs as List;
      expect(runs.join(), "00:00");
      runtime.dispose();
    });

    testWidgets("the song ticker bounces a title that does not fit", (
      tester,
    ) async {
      await pump(tester);
      final ticker = object("Songticker");
      // display.maki picks the skin's "Modern Songticker scrolling".
      expect(ticker["ticker"], "bounce");
      dynamic painter() => painterOf(tester, ticker);
      // The title with its length, upper-cased by the font, from the left
      // padding on.
      expect(
        painter().runs.join(),
        "DJ Mike Llama - Llama Whippin' Intro (0:05)",
      );
      expect((painter().runs as List).single.x, 5.0);
      expect(painter().origin.dx, 0.0);

      // A pixel every 26 ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 520));
      expect(painter().origin.dx, -20.0);

      // 43 characters of 9 px in a ticker 16 px narrower than the display:
      // it stops a pixel short of the end, waits two seconds and comes
      // back.
      final width = tester.getSize(viewOf(ticker)).width;
      final overflow = 43 * 9 + 10 - width;
      expect(overflow, greaterThan(0));
      for (var i = 0; i < 100; i++) {
        final at = painter().origin.dx as double;
        if (at <= -(overflow - 1)) break;
        await tester.pump(const Duration(milliseconds: 26));
      }
      expect(painter().origin.dx, -(overflow - 1));
      // The step past the end turns it around.
      await tester.pump(const Duration(milliseconds: 26));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(painter().origin.dx, -(overflow - 1));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 260));
      expect(painter().origin.dx, greaterThan(-(overflow - 1)));

      // Classic scrolling goes round, the title after itself.
      runtime.setConfigAttribute("Classic Songticker scrolling", "1");
      runtime.setConfigAttribute("Modern Songticker scrolling", "0");
      await tester.pump();
      expect(ticker["ticker"], "scroll");
      expect(
        painter().runs.join(),
        "DJ Mike Llama - Llama Whippin' Intro (0:05) *** "
        "DJ Mike Llama - Llama Whippin' Intro (0:05)",
      );
      runtime.dispose();
    });

    testWidgets("the drawer's tabs are as wide as their labels", (
      tester,
    ) async {
      await pump(tester);
      // 6 px a character, the text's 4 px, and the 24 px the label leaves
      // around itself.
      expect(runtime.rectOf(object("config.tab.eq.on")).width, 82);
      expect(runtime.rectOf(object("config.tab.options.on")).width, 70);
      expect(runtime.rectOf(object("config.tab.colorthemes.on")).width, 100);
      // configtabs.maki puts each tab after the one before, 3 px over it.
      expect(object("config.tab.options.off")["x"], "79");
      expect(object("config.tab.colorthemes.off")["x"], "146");
      runtime.dispose();
    });

    testWidgets("the options tab lists its pages and shows the chosen one", (
      tester,
    ) async {
      await pump(tester);
      final bucket = object("my.bucket");
      expect(bucket.children, hasLength(7));
      expect(bucket.children[1]["y"], "14");
      final target = object("skin.config.target");

      WasabiObject? shown() {
        final visible = target.children.where((child) => child.visible);
        return visible.length == 1 ? visible.single : null;
      }

      bool lit(int index) =>
          runtime.isActivated(runtime.find(bucket.children[index], "btn")!);

      // configtarget.maki opens the first page at startup.
      expect(shown()?.id, "optionsgroup.drawers");
      expect(lit(0), isTrue);

      // The drawer and its Options tab, then the list's second entry.
      await tester.tapAt(
        tester.getRect(viewOf(object("drawer.button.open"))).center,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(
        tester.getRect(viewOf(object("mousetrapTabOPTIONS"))).center,
      );
      await tester.pump();
      final menus = runtime.find(bucket.children[1], "btn")!;
      await tester.tapAt(tester.getRect(viewOf(menus)).center);
      await tester.pump();
      expect(shown()?.id, "optionsgroup.menus");
      // The pages cross-fade for half a second.
      await tester.pump(const Duration(milliseconds: 250));
      final fades = tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: viewOf(target),
              matching: find.byType(FadeTransition),
            ),
          )
          .toList();
      expect(fades, hasLength(2));
      expect(fades[0].opacity.value, closeTo(0.5, 0.01));
      expect(fades[1].opacity.value, closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        find.descendant(
          of: viewOf(target),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      expect(lit(0), isFalse);
      expect(lit(1), isTrue);

      // The arrows turn the list's pages: 7 entries of 14 px in 55 px.
      final down = runtime
          .find(main.root, "player.normal.drawer.options")!
          .children
          .firstWhere((child) => child["action"] == "cb_nextpage");
      await tester.tapAt(tester.getRect(viewOf(down)).center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bucket["#scroll"], "43");
      await tester.pump(const Duration(milliseconds: 300));

      // The entries the list scrolled to can be chosen too.
      final misc = runtime.find(bucket.children[6], "btn")!;
      await tester.tapAt(tester.getRect(viewOf(misc)).center);
      await tester.pump();
      expect(shown()?.id, "optionsgroup.misc");
      expect(lit(6), isTrue);
      runtime.dispose();
    });

    testWidgets("it keeps its own Close button", (tester) async {
      await pump(tester);
      // `<hideobject target="close">` hides the frame's, which comes
      // first; the player's own two (focused and not) stay.
      final all = <WasabiObject>[];
      void visit(WasabiObject node) {
        if (node.id.toLowerCase() == "close") all.add(node);
        node.children.forEach(visit);
      }

      visit(main.root);
      expect(all, hasLength(3));
      expect([for (final close in all) close.visible], [false, true, true]);
      runtime.dispose();
    });

    testWidgets("the transport's status light is as big as its bitmap", (
      tester,
    ) async {
      await pump(tester);
      // The one without a size, over the Play, Pause and Stop buttons.
      final light = main.root.children.isEmpty
          ? null
          : runtime.find(
              runtime.find(main.root, "player.normal.playbuttons")!,
              "status",
            );
      expect(tester.getSize(viewOf(light!)), const Size(90, 29));
      runtime.dispose();
    });

    testWidgets("the mini visualization keeps its clicks and takes the "
        "script's mode", (tester) async {
      await pump(tester);
      final vis = object("visual");
      // visualizer.maki starts with thick bands.
      expect(vis["#mode"], "1");
      expect(vis["bandwidth"], "wide");
      await tester.tapAt(tester.getRect(viewOf(vis)).center);
      await tester.pump();
      // Its mouse trap moved on to thin bands, and the vis still got the
      // click (two of them open the visualization).
      expect(vis["bandwidth"], "thin");
      expect(host.visClicks, 1);
      final options = wasabiVisOptions(vis, const ClassicVisOptions());
      expect(options.mode, ClassicVisMode.spectrum);
      expect(options.thinBands, isTrue);
      await tester.tapAt(tester.getRect(viewOf(vis)).center);
      await tester.pump();
      expect(
        wasabiVisOptions(vis, const ClassicVisOptions()).mode,
        ClassicVisMode.oscilloscope,
      );
      runtime.dispose();
    });

    testWidgets("windows without a title of their own take their name", (
      tester,
    ) async {
      await pump(tester);
      final playlist = skin.container("pledit")!.layout("normal")!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: playlist,
              host: host,
              container: "pledit",
              scripts: runtime,
            ),
          ),
        ),
      );
      final title = runtime.find(playlist.root, "window.titlebar.title")!;
      expect(title["default"], ":componentname");
      expect(painterOf(tester, title).runs.join(), "PLAYLIST EDITOR");
      // titlebar.maki made room for all of it, in the middle.
      final rect = tester.getRect(viewOf(title));
      expect(
        rect.width,
        wasabiTextAutoWidth(title, skin, componentName: "Playlist Editor"),
      );
      expect(
        (rect.center.dx - playlist.size.width / 2).abs(),
        lessThanOrEqualTo(1),
      );
      runtime.dispose();
    });

    testWidgets("title bar streaks keep clear of the system menu button", (
      tester,
    ) async {
      await pump(tester);
      final playlist = skin.container("pledit")!.layout("normal")!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: playlist,
              host: host,
              container: "pledit",
              scripts: runtime,
            ),
          ),
        ),
      );
      // The frame asks the title bar to pad 10 pixels on the left.
      final streak = runtime.find(
        playlist.root,
        "wasabi.titlebar.streak.left",
      )!;
      expect(streak["x"], "10");
      runtime.dispose();
    });

    testWidgets("its buttons still work with the video/vis drawer open", (
      tester,
    ) async {
      await pump(tester);
      host.runtime = runtime;
      await tester.tapAt(
        tester.getRect(viewOf(object("videoavs.open"))).center,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(object("AVSGroup").visible, isTrue);
      final play = runtime
          .find(main.root, "player.normal.playbuttons")!
          .children
          .firstWhere((child) => child["action"] == "PLAY");
      await tester.tapAt(tester.getRect(viewOf(play)).center);
      expect(host.actions.map((a) => a.action), contains("PLAY"));
      runtime.dispose();
    });

    testWidgets("the beat display follows the level of the sound", (
      tester,
    ) async {
      await pump(tester);
      final viewers = host.sampleUsers;
      // The display only shows in a player wider than 480 pixels.
      main.root.attributes["w"] = "600";
      runtime
        ..changed()
        ..layoutResized(main);
      await tester.pump(const Duration(milliseconds: 50));
      // Reading the meters asks the host for samples, once.
      expect(host.sampleUsers, viewers + 1);
      final left = object("beatleft");
      final right = object("beatright");

      // The level is the RMS of the window, a full-scale sine being 255: a
      // constant half scale on the left reads higher than a quarter on the
      // right.
      host.level = 1;
      await tester.pump(const Duration(milliseconds: 100));
      expect(wasabiAnimationFrame(left), greaterThan(0));
      expect(wasabiAnimationFrame(right), greaterThan(0));
      expect(
        wasabiAnimationFrame(left),
        greaterThan(wasabiAnimationFrame(right)),
      );

      // The bars fall one frame at a time once the sound stops.
      host.level = 0;
      await tester.pump(const Duration(milliseconds: 30));
      expect(wasabiAnimationFrame(left), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(wasabiAnimationFrame(left), 0);

      runtime.dispose();
      expect(host.sampleUsers, viewers);
    });

    testWidgets("Detach Visualizer gives the visualization its window", (
      tester,
    ) async {
      await pump(tester);
      // A request to show the visualization opens the drawer for it
      // instead.
      expect(
        runtime.cancelsComponent(wasabiVisGuid, goingVisible: true),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      final holder = object("AVSGroup");
      expect(holder.visible, isTrue);
      host.visShown = true;

      runtime.buttonClicked(object("button.vis.detach"));
      await tester.pump(const Duration(seconds: 1));
      expect(runtime.configAttribute("Detach Vis Window"), "1");
      expect(holder.visible, isFalse);
      expect(host.shown.last, (wasabiVisGuid, true));
      // Detached, its window opens as any other.
      host.visShown = false;
      expect(
        runtime.cancelsComponent(wasabiVisGuid, goingVisible: true),
        isFalse,
      );
      host.visShown = true;

      // Reattach Visualizer, in that window, closes it and opens the
      // drawer again.
      final window = skin.container("avs")!.layout("normal")!;
      runtime.buttonClicked(runtime.find(window.root, "button.vis.reattach")!);
      await tester.pump(const Duration(seconds: 1));
      expect(runtime.configAttribute("Detach Vis Window"), "0");
      expect(host.shown.last, (wasabiVisGuid, false));
      expect(holder.visible, isTrue);
      runtime.dispose();
    });
  });
}
