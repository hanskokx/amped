import "package:amped/src/dialogs/remote_login_page.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  Future<void> show(
    WidgetTester tester,
    RemoteLoginRequest request,
    void Function(RemoteLogin?) onAnswer,
  ) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RemoteLoginPage(request: request, onAnswer: onAnswer),
      ),
    ),
  );

  testWidgets("shows the saved login and why it failed", (tester) async {
    await show(
      tester,
      const RemoteLoginRequest(
        "smb://nas",
        login: RemoteLogin("ann", "old"),
        error: "logon failure",
      ),
      (_) {},
    );
    expect(find.text("ann"), findsOneWidget);
    expect(find.textContaining("logon failure"), findsOneWidget);
    expect(find.textContaining("smb://nas"), findsOneWidget);
  });

  testWidgets("answers with what was entered, or null on cancel", (
    tester,
  ) async {
    final answers = <RemoteLogin?>[];
    await show(
      tester,
      const RemoteLoginRequest("smb://nas", login: RemoteLogin("ann", "old")),
      answers.add,
    );
    await tester.enterText(find.byType(TextField).last, "new");
    await tester.tap(find.text("Sign in"));
    await tester.tap(find.text("Cancel"));
    expect(answers, [const RemoteLogin("ann", "new"), null]);
  });
}
