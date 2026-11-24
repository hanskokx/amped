import "package:amped/src/main_window/presets_window.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";
import "package:shared_preferences/shared_preferences.dart";

Widget localizedApp(Widget child) => MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: child),
);

void main() {
  late ClassicSkinData skin;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester, PresetsMode mode) async {
    skin = (await tester.runAsync(loadBaseSkin))!;
    await tester.pumpWidget(
      localizedApp(PresetsWindow(mode: mode, skin: skin)),
    );
    await tester.pump();
  }

  /// The Load action button.
  SkinTextButton action(WidgetTester tester) => tester.widget<SkinTextButton>(
    find.byWidgetPredicate(
      (w) => w is SkinTextButton && w.label == "Load",
    ),
  );

  testWidgets("shows the preset list in load mode with no name field", (
    tester,
  ) async {
    await pump(tester, PresetsMode.load);

    expect(find.text("Classical"), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets("delete mode has a Delete action and no name field", (
    tester,
  ) async {
    await pump(tester, PresetsMode.delete);

    expect(
      find.byWidgetPredicate((w) => w is SkinTextButton && w.label == "Delete"),
      findsOneWidget,
    );
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets("save mode adds the name field", (tester) async {
    await pump(tester, PresetsMode.save);

    expect(find.text("Preset name"), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets("selecting a preset enables the Load action", (tester) async {
    await pump(tester, PresetsMode.load);

    expect(action(tester).onPressed, isNull);

    await tester.tap(find.text("Classical"));
    // The list rows have an onDoubleTap in load mode, so the single-tap
    // callback only fires after the double-tap timeout elapses.
    await tester.pump(const Duration(milliseconds: 350));
    expect(action(tester).onPressed, isNotNull);
  });

  testWidgets("the wheel scrolls the list one line at a time", (tester) async {
    skin = (await tester.runAsync(loadBaseSkin))!;
    await tester.pumpWidget(
      localizedApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 256,
            height: 100,
            child: PresetsWindow(mode: PresetsMode.load, skin: skin),
          ),
        ),
      ),
    );
    await tester.pump();

    final list = find.byType(ListView);
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;

    expect(offset(), 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 50),
      ),
    );
    await tester.pump();
    expect(offset(), 13);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -50),
      ),
    );
    await tester.pump();
    expect(offset(), 0);
  });

  testWidgets("Escape closes the window, in every mode", (tester) async {
    skin = (await tester.runAsync(loadBaseSkin))!;
    for (final mode in PresetsMode.values) {
      var closed = 0;
      await tester.pumpWidget(
        localizedApp(
          PresetsWindow(mode: mode, skin: skin, onClose: () => closed++),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1, reason: "$mode");
    }
  });
}
