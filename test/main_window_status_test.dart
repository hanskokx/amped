import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

/// Only what the main window reads while building.
class _FakeHost extends ChangeNotifier implements ClassicHost {
  _FakeHost(this.skin, this.player);

  @override
  final ClassicSkinData skin;

  @override
  final PlayerState player;

  @override
  final ValueNotifier<String?> songTitleOverride = ValueNotifier(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHost host;

  setUp(() async {
    final skin = await loadBaseSkin();
    host = _FakeHost(skin, PlayerState(engine: AudioEngine()));
    await host.player.playlist.add([
      "http://one.example/",
      "http://two.example/",
    ]);
  });

  Future<void> pumpMainWindow(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SkinButtonScope(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 275,
            height: 116,
            child: MainWindowView(host: host),
          ),
        ),
      ),
    ),
  );

  /// The top of the drawn text that starts with [start], or null when none.
  double? topOf(WidgetTester tester, String start) {
    final found = find.byWidgetPredicate(
      (w) => w is SkinText && w.text.startsWith(start),
    );
    return found.evaluate().isEmpty ? null : tester.getTopLeft(found).dy;
  }

  const textTop = 27.0; // The song title's row in the main window.
  const status = "SORTING PLAYLIST";

  testWidgets("a status replaces the title; a click swaps them", (
    tester,
  ) async {
    await pumpMainWindow(tester);
    expect(topOf(tester, "1. HTTP://ONE"), textTop);

    host.songTitleOverride.value = "Sorting playlist...";
    await tester.pump();
    expect(topOf(tester, status), textTop);
    expect(
      topOf(tester, "1. HTTP://ONE"),
      textTop + 8,
      reason: "below, hidden",
    );

    await tester.tapAt(const Offset(180, 30));
    await tester.pumpAndSettle();
    expect(topOf(tester, "1. HTTP://ONE"), textTop);
    expect(topOf(tester, status), textTop - 8, reason: "above, hidden");

    await tester.tapAt(const Offset(180, 30));
    await tester.pumpAndSettle();
    expect(topOf(tester, status), textTop);

    host.songTitleOverride.value = null;
    await tester.pump();
    expect(topOf(tester, status), isNull);
    expect(topOf(tester, "1. HTTP://ONE"), textTop);
  });

  testWidgets("a new track shows for a moment, sliding a pixel at a time", (
    tester,
  ) async {
    await pumpMainWindow(tester);
    host.songTitleOverride.value = "Sorting playlist...";
    await tester.pump();

    host.player.playlist.setCurrent(1);
    await pumpMainWindow(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final midway = topOf(tester, "2. HTTP://TWO")!;
    expect(midway, greaterThan(textTop));
    expect(midway, lessThan(textTop + 8));
    expect(midway, midway.roundToDouble(), reason: "whole pixels, like LEDs");

    await tester.pump(const Duration(milliseconds: 400));
    expect(topOf(tester, "2. HTTP://TWO"), textTop);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(topOf(tester, status), textTop);
  });

  testWidgets("a long status scrolls like the title, keeping its place", (
    tester,
  ) async {
    await pumpMainWindow(tester);
    String shown() => tester
        .widgetList<SkinText>(find.byType(SkinText))
        .map((t) => t.text)
        .firstWhere((t) => t.contains("TAGS") || t.startsWith("DING"));
    const long = "SORTING PLAYLIST: READING TAGS 1500/9131";
    const loop = "$long  ***  ";
    host.songTitleOverride.value = long;
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(shown(), (loop + loop).substring(3, 3 + 30));

    const later = "SORTING PLAYLIST: READING TAGS 1750/9131";
    host.songTitleOverride.value = later;
    await tester.pump();
    expect(shown(), "$later  ***  ".substring(3, 3 + 30));
  });
}
