import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

/// A player that changes track, with what the notifier reads about it.
class _Host extends FakeHost {
  String title = "Song A";
  final List<(String, bool)> shown = [];
  final List<String> layouts = [];

  /// A status (such as "Sorting playlist...") shown in place of the title.
  String? titleStatus;

  @override
  String get songTitle => titleStatus ?? title;

  @override
  String get trackTitle => title;

  int playback = 1;

  @override
  int get playbackStatus => playback;

  @override
  int get playlistCurrent => 1;

  @override
  int get playlistLength => 5;

  @override
  String playItemMetadata(String name) => switch (name) {
    "title" => "My Title",
    "artist" => "My Artist",
    "album" => "My Album",
    "track" => "4",
    "length" => "185000",
    _ => "",
  };

  @override
  void setContainerVisible(String id, bool visible) => shown.add((id, visible));

  @override
  bool isContainerVisible(String id) {
    for (final entry in shown.reversed) {
      if (entry.$1 == id) return entry.$2;
    }
    return id != "notifier";
  }

  @override
  void runAction(WasabiAction action) {
    if (action.container == "notifier") layouts.add(action.param ?? "");
    super.runAction(action);
  }

  void changeTrack(String next) {
    title = next;
    notifyListeners();
  }
}

void main() {
  group("Amped Modern's notifier", () {
    late WasabiSkinData skin;
    late _Host host;
    late WasabiScriptRuntime runtime;
    late WasabiLayout layout;

    Future<void> start(
      WidgetTester tester, {
      String show = "Show always",
    }) async {
      skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
      host = _Host();
      runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
        ..start();
      // The skin starts with "Never show"; the user picks one.
      for (final option in const [
        "Show always",
        "Show with windowshade and when minimized",
        "Show only when minimized",
        "Never show",
      ]) {
        runtime.setConfigAttribute(option, option == show ? "1" : "0");
      }
      layout = skin.container("notifier")!.layout("desktopalpha")!;
      await tester.pump(const Duration(milliseconds: 100));
    }

    WasabiObject object(String id) => runtime.find(layout.root, id)!;

    bool shownNow() => host.shown.isNotEmpty && host.shown.last.$2;

    testWidgets("pops up in the corner of the screen on a track change", (
      tester,
    ) async {
      await start(tester);
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);
      host.changeTrack("Song B");
      await tester.pump(const Duration(milliseconds: 100));

      // Shown, as the `desktopalpha` layout.
      expect(host.shown.where((s) => s.$1 == "notifier").last, (
        "notifier",
        true,
      ));
      expect(host.layouts, contains("desktopalpha"));

      // What it says about the track, as the classic player's notifier does.
      expect(object("title")["#text"], "My Title (3:05)");
      expect(object("artist")["#text"], "My Artist");
      expect(object("album")["#text"], "My Album (Track 4)");
      expect(object("plentry")["#text"], "2 of 5");
      expect(object("nexttrack")["#text"], "New track");

      // At the bottom right of the screen's usable area, 2 px in: 128 px
      // for the text and 32 for the frame, and 80 tall.
      final root = layout.root;
      final w = root.intAttr("w");
      expect(w, greaterThanOrEqualTo(160));
      expect(root.intAttr("x") + w, 1920 - 2);
      expect(root.intAttr("y"), 1080 - 80 - 2);
      expect(root.intAttr("h"), 80);
      runtime.dispose();
    });

    testWidgets("it wears the colour theme", (tester) async {
      await start(tester);
      // The Default theme darkens the text, so white becomes navy, and
      // lightens its shadow.
      final dark = skin.color("notifier.dark")!;
      final bright = skin.color("notifier.bright")!;
      expect(dark.computeLuminance(), lessThan(0.15));
      expect(bright.computeLuminance(), greaterThan(0.9));
      final frame = skin.bitmap("notifier.bg.center.da")!.image;

      // Another theme changes the text and the frame.
      await tester.runAsync(
        () => wasabiSelectColorTheme(skin, host, "Good Ol' Amped"),
      );
      await tester.pump();
      expect(skin.color("notifier.dark"), isNot(dark));
      expect(
        identical(skin.bitmap("notifier.bg.center.da")!.image, frame),
        isFalse,
      );
      runtime.dispose();
    });

    testWidgets("its lines are as tall as their fonts", (tester) async {
      await start(tester);
      // `title` and `plentry` have no height: their font size, 17 and 12.
      expect(runtime.rectOf(object("title")).height, 17);
      expect(runtime.rectOf(object("plentry")).height, 12);
      // The artist and album have theirs.
      expect(runtime.rectOf(object("artist")).height, 18);
      expect(runtime.rectOf(object("album")).height, 14);
      runtime.dispose();
    });

    testWidgets("fades in, stays and fades out, then goes", (tester) async {
      await start(tester);
      host.changeTrack("Song B");
      await tester.pump(const Duration(milliseconds: 100));
      final root = layout.root;
      // Starts invisible and takes a second (`Notifications fade in time`).
      expect(root.alpha, lessThan(60));
      await tester.pump(const Duration(milliseconds: 500));
      expect(root.alpha, inExclusiveRange(60, 255));
      await tester.pump(const Duration(milliseconds: 700));
      expect(root.alpha, 255);
      expect(shownNow(), isTrue);

      // Two seconds on show, then five of fading.
      await tester.pump(const Duration(milliseconds: 1800));
      expect(root.alpha, 255);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(root.alpha, inExclusiveRange(0, 255));
      expect(shownNow(), isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(root.alpha, 0);
      expect(host.shown.last, ("notifier", false));
      runtime.dispose();
    });

    testWidgets("hovering holds it at full opacity until the pointer leaves", (
      tester,
    ) async {
      await start(tester);
      host.changeTrack("Song B");
      await tester.pump(const Duration(milliseconds: 1500));
      // Into the fade out.
      await tester.pump(const Duration(milliseconds: 3500));
      final root = layout.root;
      expect(root.alpha, inExclusiveRange(0, 255));

      runtime.pointer(root, "onEnterArea");
      expect(root.alpha, 255);
      await tester.pump(const Duration(seconds: 20));
      expect(root.alpha, 255);
      expect(shownNow(), isTrue);

      // A new track updates it, and it stays.
      host.changeTrack("Song C");
      await tester.pump(const Duration(seconds: 20));
      expect(root.alpha, 255);
      expect(shownNow(), isTrue);

      // Leaving lets it go.
      runtime.pointer(root, "onLeaveArea");
      await tester.pump(const Duration(seconds: 12));
      expect(root.alpha, 0);
      expect(host.shown.last, ("notifier", false));
      runtime.dispose();
    });

    testWidgets("a title change while stopped is no news", (tester) async {
      await start(tester);
      host.playback = 0;
      host.notifyListeners();
      await tester.pump(const Duration(seconds: 8));
      host.shown.clear();
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);
      runtime.dispose();
    });

    testWidgets("a click brings the player back and dismisses it", (
      tester,
    ) async {
      await start(tester);
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      expect(shownNow(), isTrue);
      runtime.pointer(layout.root, "onLeftButtonDown", const Offset(10, 10));
      await tester.pump();
      // It restores and activates the player (both ask the host).
      expect((host as dynamic).activations, isPositive);
      expect(host.shown.last, ("notifier", false));
      runtime.dispose();
    });

    testWidgets("a right click only dismisses it", (tester) async {
      await start(tester);
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      runtime.pointer(layout.root, "onRightButtonUp", const Offset(10, 10));
      await tester.pump();
      expect((host as dynamic).activations, 0);
      expect(host.shown.last, ("notifier", false));
      runtime.dispose();
    });

    testWidgets("a status in place of the song title is not a track change", (
      tester,
    ) async {
      await start(tester);
      host.titleStatus = "Sorting playlist...";
      host.notifyListeners();
      await tester.pump(const Duration(seconds: 2));
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);

      // The next track still pops up.
      host.changeTrack("Song B");
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.shown.where((s) => s.$1 == "notifier"), isNotEmpty);
      runtime.dispose();
    });

    testWidgets("Never show keeps it away", (tester) async {
      await start(tester, show: "Never show");
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);
      runtime.dispose();
    });

    testWidgets("Show only when minimized waits for the player to be "
        "minimized", (tester) async {
      await start(tester, show: "Show only when minimized");
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);

      host.appMinimized = true;
      host.changeTrack("Song C");
      await tester.pump(const Duration(milliseconds: 200));
      expect(shownNow(), isTrue);
      runtime.dispose();
    });

    testWidgets("it stays away while the video fills the screen", (
      tester,
    ) async {
      await start(tester);
      host.videoFullscreen = true;
      host.changeTrack("Song B");
      await tester.pump(const Duration(seconds: 2));
      expect(host.shown.where((s) => s.$1 == "notifier"), isEmpty);

      // Unless it is turned off ("Disable in fullscreen").
      runtime.setConfigAttribute("Disable in fullscreen", "0");
      host.changeTrack("Song C");
      await tester.pump(const Duration(milliseconds: 200));
      expect(shownNow(), isTrue);
      runtime.dispose();
    });

    testWidgets("it is drawn at its alpha", (tester) async {
      await start(tester);
      host.changeTrack("Song B");
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: layout,
              host: host,
              container: "notifier",
              scripts: runtime,
            ),
          ),
        ),
      );
      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, closeTo(layout.root.alpha / 255, 0.001));
      expect(opacity.opacity, inExclusiveRange(0, 1));
      runtime.dispose();
    });

    testWidgets("the fade sliders show and write the skin's options", (
      tester,
    ) async {
      await start(tester);
      // The drawer's page of fade times, as the drawer makes it.
      final page = skin.newGroup("optionsgroup.notifications.2")!;
      final slider = runtime.find(page, "snotifier_holdtime")!;

      // The slider shows the option: 2 s of a 10 s range.
      expect(runtime.sliderValueOf(slider), closeTo(0.2, 0.001));

      // Dragging it writes the option.
      runtime.sliderMoved(slider, 0.5, done: true);
      expect(runtime.configAttribute("Notifications display time"), "5000");

      // Setting the option elsewhere (Preferences) moves the slider.
      runtime.setConfigAttribute("Notifications display time", "8000");
      expect(runtime.sliderValueOf(slider), closeTo(0.8, 0.001));
      runtime.dispose();
    });
  });
}
