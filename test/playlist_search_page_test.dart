import "dart:io";

import "package:amped/src/dialogs/playlist_search_page.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  late Playlist playlist;
  late ClassicSkinData skin;
  late List<int> played;
  late int closed;

  setUp(() {
    played = [];
    closed = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync("playlist_search_page");
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [
      for (final name in ["Alpha.mp3", "Love Song.mp3", "Beta.mp3", "Love.mp3"])
        (File("${dir.path}/$name")..createSync()).path,
    ];
    playlist = Playlist();
    await tester.runAsync(() => playlist.add(paths));
    skin = (await tester.runAsync(loadBaseSkin))!;
    tester.view.physicalSize = const Size(275, 190);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlaylistSearchPage(
            playlist: playlist,
            skin: skin,
            onPlay: played.add,
            onClose: () => closed++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets("lists only the matches, best first", (tester) async {
    await pump(tester);
    expect(find.text("Search the playlist"), findsOneWidget);

    await tester.enterText(find.byType(EditableText), "love");
    await tester.pump();

    expect(find.text("2. Love Song"), findsOneWidget);
    expect(find.text("4. Love"), findsOneWidget);
    expect(find.text("1. Alpha"), findsNothing);

    await tester.enterText(find.byType(EditableText), "zzz");
    await tester.pump();
    expect(find.text("No matches"), findsOneWidget);
  });

  testWidgets("Enter plays the highlighted match and closes", (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText), "love");
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // "Love Song" (entry 1) and "Love" (entry 3) tie, so the playlist's
    // order decides: Down moves to the second.
    expect(played, [3]);
    expect(playlist.selected, {3});
    expect(closed, 1);
  });

  testWidgets("a double-click plays that match; Escape closes", (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText), "love");
    await tester.pump();

    final row = find.text("2. Love Song");
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pump();
    expect(played, [1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 2);
    await tester.pump(const Duration(seconds: 1));
  });
}
