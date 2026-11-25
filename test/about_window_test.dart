import "dart:io";

import "package:amped/src/app/amped_dialog.dart";
import "package:amped/src/dialogs/about_window.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../packages/amped_wasabi/test/wasabi_view_test.dart" show FakeHost;

Directory _extractAmpedModern() {
  final directory = Directory.systemTemp.createTempSync("about_window");
  final archive = ZipDecoder().decodeBytes(
    File("assets/skins/Amped-Modern.wal").readAsBytesSync(),
  );
  for (final entry in archive) {
    if (!entry.isFile) continue;
    File("${directory.path}/${entry.name}")
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.content);
  }
  return directory;
}

void main() {
  final localizations = lookupAppLocalizations(const Locale("en"));
  final notes = [
    localizations.aboutReportBugNote,
    localizations.aboutReportBugFailed,
  ];

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: "Amped",
      packageName: "amped",
      version: "0.1.1",
      buildNumber: "1",
      buildSignature: "",
    );
  });

  Future<void> pump(WidgetTester tester, Widget window) async {
    tester.view.physicalSize = AmpedDialog.about.size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: window),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  test("the About window can't be resized", () {
    expect(AmpedDialog.about.resizable, isFalse);
  });

  for (final (index, note) in notes.indexed) {
    // An overflow fails the test by itself.
    testWidgets("it all fits under the tabs, with bug report note $index", (
      tester,
    ) async {
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(_extractAmpedModern()),
      ))!;
      await pump(
        tester,
        AboutWindow(skin: skin, host: FakeHost(), reportNote: note),
      );
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);

      await tester.tap(find.text(localizations.skinMenu));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(
        tester.getSize(find.byType(WasabiAboutPanel)),
        WasabiAboutPanel.size,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("without a modern skin there are no tabs", (tester) async {
    await pump(tester, AboutWindow(skin: null, host: FakeHost()));
    expect(find.byType(TabBar), findsNothing);
  });
}
