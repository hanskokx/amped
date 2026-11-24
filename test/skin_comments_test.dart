import "package:amped/src/features/preferences/screens/pages/skins_pages.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

Widget _app(String? comment) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SkinComments(comment: comment)),
);

void main() {
  testWidgets("shows the comments of a skin", (tester) async {
    await tester.pumpWidget(_app("Made by someone"));
    expect(find.text("Comments"), findsOneWidget);
    expect(find.text("Made by someone"), findsOneWidget);
  });

  testWidgets("folds away and back", (tester) async {
    await tester.pumpWidget(_app("Made by someone"));
    await tester.tap(find.text("Comments"));
    await tester.pump();
    expect(find.text("Made by someone"), findsNothing);
    expect(find.text("Comments"), findsOneWidget);
    await tester.tap(find.text("Comments"));
    await tester.pump();
    expect(find.text("Made by someone"), findsOneWidget);
  });

  testWidgets("hides the panel without comments", (tester) async {
    for (final comment in [null, "", "  \n"]) {
      await tester.pumpWidget(_app(comment));
      expect(find.text("Comments"), findsNothing);
    }
  });
}
