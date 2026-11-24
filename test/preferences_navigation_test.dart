import "package:amped/src/features/preferences/preferences_navigation.dart";
import "package:amped/src/features/preferences/preferences_page.dart";
import "package:amped/src/features/preferences/screens/preferences_sidebar.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  test("starts on Skins > Installed and remembers visited pages", () {
    final navigation = PreferencesNavigation();

    expect(navigation.page, PreferencesPage.skinsInstalled);
    expect(navigation.hasVisited(PreferencesPage.skinsInstalled), isTrue);
    expect(navigation.hasVisited(PreferencesPage.remoteSources), isFalse);

    navigation.select(PreferencesPage.remoteSources);

    expect(navigation.page, PreferencesPage.remoteSources);
    expect(navigation.hasVisited(PreferencesPage.remoteSources), isTrue);
  });

  testWidgets(
    "the selected Preferences page survives the inspector remount",
    (tester) async {
      final navigation = PreferencesNavigation();
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, _) =>
              Material(child: PreferencesSidebar(navigation: navigation)),
        ),
      );

      await tester.tap(find.text("Remote sources"));
      await tester.pump();
      expect(navigation.page, PreferencesPage.remoteSources);
      expect(_selectedTile(tester, "Remote sources"), isTrue);

      // WidgetsApp wraps its subtree in a WidgetInspector when this flips,
      // remounting everything and throwing away local State.
      WidgetsBinding.instance.debugShowWidgetInspectorOverride = true;
      addTearDown(
        () => WidgetsBinding.instance.debugShowWidgetInspectorOverride = false,
      );
      await tester.pump();

      expect(navigation.page, PreferencesPage.remoteSources);
      expect(_selectedTile(tester, "Remote sources"), isTrue);
    },
  );
}

bool _selectedTile(WidgetTester tester, String label) {
  final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, label));
  return tile.selected;
}
