import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/library_view.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/library/track_drag_out.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  scanningTests();
  sourceTreeTests();
  final localizations = lookupAppLocalizations(const Locale("en"));
  late ClassicSkinData skin;

  setUpAll(() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List(280 * 186 * 4),
      280,
      186,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    skin = ClassicSkinData(
      name: "test",
      images: {"pledit.bmp": await completer.future},
    );
  });

  Widget host(
    MediaLibrary library, {
    void Function(List<String>)? onPlay,
    void Function(List<String>)? onEnqueue,
    VoidCallback? onAddMedia,
    void Function(List<String>)? onContextMenu,
    double width = 900,
  }) => _overlaid(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 300)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 300,
            child: LibraryView(
              library: library,
              skin: skin,
              colors: skin.pledit,
              localizations: localizations,
              onPlay: onPlay ?? (_) {},
              onEnqueue: onEnqueue ?? (_) {},
              onAddMedia: onAddMedia ?? () {},
              onContextMenu: onContextMenu ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  group("dragging a track out of the library", () {
    late List<List<String>> added;
    SkinWindow? under;
    late TrackDragOut dragOut;

    setUp(() {
      added = [];
      under = SkinWindow.pl;
      dragOut = TrackDragOut(windowAt: () => under, add: added.add);
    });

    /// A library with one track, whose row is dragged to [to] and let go.
    /// Gives the window shown as the target just before.
    Future<SkinWindow?> drag(WidgetTester tester, Offset to) async {
      final dir = Directory.systemTemp.createTempSync("library_view_test");
      addTearDown(() => dir.deleteSync(recursive: true));
      File("${dir.path}/one.mp3").writeAsStringSync("x");
      final library = MediaLibrary(
        readTags: (files) async => [
          for (final f in files) TrackTags(f, title: "Song"),
        ],
      );
      await tester.runAsync(() => library.add([dir.path]));
      await tester.pumpWidget(
        TrackDragOutScope(dragOut: dragOut, child: host(library)),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text("Song")),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      final over = dragOut.over.value;
      await gesture.up();
      // Past the row's wait for a double click.
      await tester.pump(const Duration(seconds: 1));
      return over;
    }

    // Beyond the right edge of the 800 by 600 test window.
    const outside = Offset(1200, 100);

    testWidgets("onto the playlist's window adds it", (tester) async {
      expect(await drag(tester, outside), SkinWindow.pl);

      expect(added.single.single, endsWith("one.mp3"));
      expect(dragOut.over.value, isNull);
    });

    testWidgets("to where no window takes it adds nothing", (tester) async {
      under = null;

      expect(await drag(tester, outside), isNull);

      expect(added, isEmpty);
    });

    testWidgets("and letting go inside the library adds nothing", (
      tester,
    ) async {
      // Though another window lies under that spot, behind the library's.
      expect(await drag(tester, const Offset(500, 500)), isNull);

      expect(added, isEmpty);
    });
  });

  testWidgets("says so when the library is empty", (tester) async {
    await tester.pumpWidget(host(MediaLibrary()));
    expect(find.text(localizations.mlEmpty), findsOneWidget);
  });

  testWidgets("the Add media button asks for folders", (tester) async {
    var added = 0;
    await tester.pumpWidget(host(MediaLibrary(), onAddMedia: () => added++));
    await tester.tap(find.text(localizations.mlAddMediaButton));
    expect(added, 1);
  });

  testWidgets("typing in the search box filters the tracks", (tester) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ["one.mp3", "two.mp3"]) {
      File("${dir.path}/$name").writeAsStringSync("x");
    }
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files) TrackTags(f, title: f.split("/").last),
      ],
    );
    await tester.runAsync(() => library.add([dir.path]));
    await tester.pumpWidget(host(library));
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), "two");
    await tester.pump();
    expect(find.text("one.mp3"), findsNothing);
    expect(find.text("two.mp3"), findsOneWidget);
  });

  testWidgets("renaming the picked artist goes back to all tracks", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/one.mp3").writeAsStringSync("x");
    var artist = "Old Name";
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files) TrackTags(f, title: "Song", artist: artist),
      ],
    );
    await tester.runAsync(() => library.add([dir.path]));
    await tester.pumpWidget(host(library));
    // (The artist is in the list of artists, first, and in the tracks' column.)
    await tester.tap(find.text("Old Name").first);
    await tester.pump();
    expect(find.textContaining("Song"), findsOneWidget);

    // The tags are edited (a MusicBrainz lookup, say): the artist is renamed.
    artist = "New Name";
    await tester.runAsync(() => library.refresh(["${dir.path}/one.mp3"]));
    await tester.pump();
    expect(find.text("New Name"), findsWidgets);
    expect(find.textContaining("Song"), findsOneWidget);
  });

  testWidgets("the wheel scrolls the list one row at a time", (tester) async {
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files) TrackTags(f, title: f.split("/").last),
      ],
    );
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    for (var i = 0; i < 60; i++) {
      File("${dir.path}/t${i.toString().padLeft(2, "0")}.mp3")
          .writeAsStringSync("x");
    }
    await tester.runAsync(() => library.add([dir.path]));
    await tester.pumpWidget(host(library));
    expect(find.text("t00.mp3"), findsOneWidget);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text("t01.mp3"))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
    await tester.pump();
    expect(find.text("t00.mp3"), findsNothing);
    expect(find.text("t01.mp3"), findsOneWidget);
  });

  testWidgets("right-clicking a track asks for its context menu", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/one.mp3").writeAsStringSync("x");
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files) TrackTags(f, title: "One"),
      ],
    );
    await tester.runAsync(() => library.add([dir.path]));
    final asked = <List<String>>[];
    await tester.pumpWidget(host(library, onContextMenu: asked.add));
    await tester.tap(find.text("One"), buttons: kSecondaryButton);
    await tester.pump();
    expect(asked.single.single, endsWith("one.mp3"));
  });

  testWidgets("Escape twice, within three seconds, cancels a scan", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    for (var i = 0; i < 40; i++) {
      File("${dir.path}/$i.mp3").writeAsStringSync("x");
    }
    final gate = Completer<void>();
    final library = MediaLibrary(
      readTags: (files) async {
        await gate.future;
        return [for (final f in files) TrackTags(f, title: f.split("/").last)];
      },
    );
    await tester.pumpWidget(host(library));
    // Nothing is being added: Escape does nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text(localizations.mlCancelPrompt), findsNothing);

    final scan = tester.runAsync(() => library.add([dir.path]));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ScanningText), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text(localizations.mlCancelPrompt), findsWidgets);
    expect(find.byType(ScanningText), findsNothing);

    // Too late for a second press: back to the scanning text.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(localizations.mlCancelPrompt), findsNothing);
    expect(find.byType(ScanningText), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    gate.complete();
    await scan;
    await tester.pump();
    expect(library.scanning, isFalse);
    expect(library.tracks.length, lessThan(40));
  });

  testWidgets("pressing the scrollbar never drags the window", (tester) async {
    final claimed = <int>[];
    SkinPointerClaim.claim = (event) => claimed.add(event.pointer);
    addTearDown(() => SkinPointerClaim.claim = null);
    await tester.pumpWidget(host(MediaLibrary()));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SkinScrollbar).first),
    );
    await gesture.up();
    expect(claimed, hasLength(1));
  });

  testWidgets("content of an embedded window claims presses by default", (
    tester,
  ) async {
    final claimed = <int>[];
    SkinPointerClaim.claim = (event) => claimed.add(event.pointer);
    addTearDown(() => SkinPointerClaim.claim = null);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SkinNoWindowDrag(child: SizedBox(width: 50, height: 50)),
      ),
    );
    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.up();
    expect(claimed, hasLength(1));
  });

  testWidgets("dragging the divider resizes the panes within their limits", (
    tester,
  ) async {
    await tester.pumpWidget(host(MediaLibrary(), width: 400));
    final divider = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
    );
    // The source tree has a divider of its own, to the left of this one.
    double x() => tester.getCenter(divider.last).dx;
    final start = x();

    // The artists pane starts at its least width.
    await tester.dragFrom(Offset(start, 150), const Offset(-60, 0));
    await tester.pump();
    expect(x(), start);

    await tester.dragFrom(Offset(start, 150), const Offset(60, 0));
    await tester.pump();
    expect(x(), start + 60);

    // Far to the right: the tracks keep that width too (the view is 400
    // wide, and the bar is 5).
    await tester.dragFrom(Offset(x(), 150), const Offset(900, 0));
    await tester.pump();
    expect(400 - (x() + 2.5), 120);
  });

  testWidgets("a title too long for its row is cut with an ellipsis", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/long.mp3").writeAsStringSync("x");
    final title = "An extraordinarily long title " * 6;
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files) TrackTags(f, title: title),
      ],
    );
    await tester.runAsync(() => library.add([dir.path]));
    await tester.pumpWidget(host(library));
    final text = tester.widget<Text>(find.text(title));
    // Not wrapped at a word, with the rest dropped.
    expect(text.softWrap, isFalse);
    expect(text.overflow, TextOverflow.ellipsis);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isTrue);
  });

  testWidgets("a right-click in the content leaves the main menu out", (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SkinNoWindowDrag(child: SizedBox(width: 50, height: 50)),
      ),
    );
    final pointer = TestPointer(
      7,
      PointerDeviceKind.mouse,
      null,
      kSecondaryButton,
    );
    await tester.sendEventToBinding(pointer.down(const Offset(10, 10)));
    // The window takes the press to open its main menu unless it was claimed.
    expect(SkinSecondaryClaim.take(7), isTrue);
    await tester.sendEventToBinding(pointer.up());
  });

  testWidgets("a track with no title shows its file name without extension", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/01. Hand on Your Heart.mp3").writeAsStringSync("x");
    final library = MediaLibrary(
      readTags: (files) async => [for (final f in files) TrackTags(f)],
    );
    await tester.runAsync(() => library.add([dir.path]));
    await tester.pumpWidget(host(library));
    expect(find.text("01. Hand on Your Heart"), findsOneWidget);
    expect(find.textContaining(".mp3"), findsNothing);
  });

  testWidgets("lists tracks and plays one on double tap", (tester) async {
    final dir = Directory.systemTemp.createTempSync("library_view_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ["one.mp3", "two.mp3"]) {
      File("${dir.path}/$name").writeAsStringSync("x");
    }
    final library = MediaLibrary(
      readTags: (files) async => [
        for (final f in files)
          TrackTags(
            f,
            artist: f.endsWith("one.mp3") ? "Alpha" : "Beta",
            title: f.endsWith("one.mp3") ? "Sunrise" : "Moonset",
          ),
      ],
    );
    await tester.runAsync(() => library.add([dir.path]));
    final played = <List<String>>[];
    final enqueued = <List<String>>[];
    await tester.pumpWidget(
      host(library, onPlay: played.add, onEnqueue: enqueued.add),
    );
    expect(find.text("Sunrise"), findsOneWidget);
    expect(find.text("Moonset"), findsOneWidget);

    await tester.tap(find.text("Sunrise"));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(localizations.mlEnqueue));
    expect(enqueued.single.single, endsWith("one.mp3"));

    await tester.tap(find.text("Moonset"));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text("Moonset"));
    await tester.pump();
    expect(played.single.single, endsWith("two.mp3"));
    await tester.pump(const Duration(seconds: 1));
  });

  group("compact", () {
    Future<MediaLibrary> filled(WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync("library_view_test");
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final name in ["one.mp3", "two.mp3"]) {
        File("${dir.path}/$name").writeAsStringSync("x");
      }
      final library = MediaLibrary(
        readTags: (files) async => [
          for (final f in files)
            TrackTags(
              f,
              artist: f.endsWith("one.mp3") ? "Alpha" : "Beta",
              title: f.endsWith("one.mp3") ? "Sunrise" : "Moonset",
            ),
        ],
      );
      await tester.runAsync(() => library.add([dir.path]));
      return library;
    }

    testWidgets("a narrow pane shows a track list, a search and a menu", (
      tester,
    ) async {
      final library = await filled(tester);
      await tester.pumpWidget(host(library, width: 140));
      expect(tester.takeException(), isNull);
      expect(find.textContaining("Sunrise"), findsOneWidget);
      expect(find.textContaining("Moonset"), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.text("☰"), findsOneWidget);
      // No label, headings, buttons or status row.
      expect(find.text("${localizations.mlSearch}:"), findsNothing);
      expect(find.text(localizations.mlColumnTitle), findsNothing);
      expect(find.text(localizations.mlEnqueue), findsNothing);
    });

    testWidgets("a wide pane shows the full view", (tester) async {
      final library = await filled(tester);
      await tester.pumpWidget(host(library));
      expect(find.text("${localizations.mlSearch}:"), findsOneWidget);
      expect(find.text(localizations.mlEnqueue), findsOneWidget);
      expect(find.text("☰"), findsNothing);
    });

    testWidgets("selects, plays and opens the menu of a track", (
      tester,
    ) async {
      final library = await filled(tester);
      final played = <List<String>>[];
      final menus = <List<String>>[];
      await tester.pumpWidget(
        host(library, width: 200, onPlay: played.add, onContextMenu: menus.add),
      );
      await tester.tap(find.textContaining("Moonset"));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining("Moonset"));
      await tester.pump();
      expect(played.single.single, endsWith("two.mp3"));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(
        find.textContaining("Sunrise"),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      expect(menus.single.single, endsWith("one.mp3"));
    });

    testWidgets("the menu sorts, and the list keeps its state on widening", (
      tester,
    ) async {
      final library = await filled(tester);
      Future<void> size(double width) async {
        await tester.pumpWidget(host(library, width: width));
        await tester.pump();
      }

      await size(140);
      await tester.tap(find.text("☰"));
      await tester.pump();
      await tester.tap(find.text(localizations.mlColumnTitle));
      await tester.pump();
      // Moonset before Sunrise, ascending.
      expect(
        tester.getTopLeft(find.textContaining("Moonset")).dy,
        lessThan(tester.getTopLeft(find.textContaining("Sunrise")).dy),
      );
      // Again: descending.
      await tester.tap(find.text("☰"));
      await tester.pump();
      await tester.tap(find.textContaining(localizations.mlColumnTitle));
      await tester.pump();
      expect(
        tester.getTopLeft(find.textContaining("Sunrise")).dy,
        lessThan(tester.getTopLeft(find.textContaining("Moonset")).dy),
      );

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), "sun");
      await tester.pump();
      expect(find.textContaining("Moonset"), findsNothing);

      await size(900);
      expect(tester.takeException(), isNull);
      expect(find.text("${localizations.mlSearch}:"), findsOneWidget);
      expect(find.text("sun"), findsOneWidget);
      expect(find.text("Moonset"), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group("multi-select", () {
    Future<MediaLibrary> filled(WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync("library_view_test");
      addTearDown(() => dir.deleteSync(recursive: true));
      const names = {
        "a1": ("Alpha", "First"),
        "a2": ("Alpha", "First"),
        "a3": ("Alpha", "Second"),
        "b1": ("Beta", "Third"),
        "c1": ("Gamma", "Fourth"),
      };
      for (final name in names.keys) {
        File("${dir.path}/$name.mp3").writeAsStringSync("x");
      }
      final library = MediaLibrary(
        readTags: (files) async => [
          for (final f in files)
            TrackTags(
              f,
              artist: names[f.split("/").last.split(".").first]!.$1,
              album: names[f.split("/").last.split(".").first]!.$2,
              title: f.split("/").last.split(".").first,
            ),
        ],
      );
      await tester.runAsync(() => library.add([dir.path]));
      return library;
    }

    Future<void> click(
      WidgetTester tester,
      String text, {
      List<LogicalKeyboardKey> keys = const [],
      int buttons = kPrimaryButton,
    }) async {
      for (final key in keys) {
        await tester.sendKeyDownEvent(key);
      }
      // (A selected track is named again in the details under the list.)
      await tester.tap(find.text(text).first, buttons: buttons);
      await tester.pump(const Duration(milliseconds: 500));
      for (final key in keys.reversed) {
        await tester.sendKeyUpEvent(key);
      }
    }

    testWidgets("ctrl and shift select tracks and the status counts them", (
      tester,
    ) async {
      final library = await filled(tester);
      final enqueued = <List<String>>[];
      await tester.pumpWidget(host(library, onEnqueue: enqueued.add));
      expect(find.text("5 items"), findsOneWidget);

      await click(tester, "a1");
      await click(
        tester,
        "b1",
        keys: [LogicalKeyboardKey.controlLeft],
      );
      expect(find.text("2 tracks"), findsOneWidget);
      await tester.tap(find.text(localizations.mlEnqueue));
      expect(enqueued.last.map((p) => p.split("/").last), [
        "a1.mp3",
        "b1.mp3",
      ]);

      // ctrl again takes one out.
      await click(
        tester,
        "b1",
        keys: [LogicalKeyboardKey.metaLeft],
      );
      expect(find.text("1 track"), findsOneWidget);

      await click(tester, "a1");
      await click(
        tester,
        "b1",
        keys: [LogicalKeyboardKey.shiftLeft],
      );
      expect(find.text("4 tracks"), findsOneWidget);
    });

    testWidgets("artists and albums can be picked several at a time", (
      tester,
    ) async {
      final library = await filled(tester);
      await tester.pumpWidget(host(library));
      await click(tester, "Alpha");
      expect(find.text("1 artist, 3 tracks"), findsOneWidget);
      await click(tester, "Beta", keys: [LogicalKeyboardKey.controlLeft]);
      expect(find.text("2 artists, 4 tracks"), findsOneWidget);
      await click(tester, "Gamma", keys: [LogicalKeyboardKey.shiftLeft]);
      expect(find.text("2 artists, 2 tracks"), findsOneWidget);
      await click(tester, "Alpha");
      await click(tester, "Gamma", keys: [LogicalKeyboardKey.shiftLeft]);
      expect(find.text("3 artists, 5 tracks"), findsOneWidget);

      await click(tester, "Alpha");
      await click(tester, "First");
      await click(
        tester,
        "Second",
        keys: [LogicalKeyboardKey.controlLeft],
      );
      expect(find.text("1 artist, 2 albums, 3 tracks"), findsOneWidget);
    });

    testWidgets("right-clicking inside a selection keeps it", (tester) async {
      final library = await filled(tester);
      final asked = <List<String>>[];
      await tester.pumpWidget(host(library, onContextMenu: asked.add));
      await click(tester, "a1");
      await click(
        tester,
        "a2",
        keys: [LogicalKeyboardKey.shiftLeft],
      );
      await click(tester, "a2", buttons: kSecondaryButton);
      expect(asked.last, hasLength(2));
      await click(tester, "b1", buttons: kSecondaryButton);
      expect(asked.last, hasLength(1));
    });
  });
}

void scanningTests() {
  final localizations = lookupAppLocalizations(const Locale("en"));

  testWidgets("the scanning dots animate without changing the width", (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScanningText(localizations: localizations, count: 5),
      ),
    );
    final widths = <double>[];
    final texts = <String>[];
    for (var i = 0; i < 3; i++) {
      widths.add(tester.getSize(find.byType(ScanningText)).width);
      final rich = tester.widget<RichText>(find.byType(RichText));
      // The visible dots are the second span; the rest is invisible padding.
      final spans = ((rich.text as TextSpan).children!.single as TextSpan)
          .children!
          .cast<TextSpan>();
      texts.add(spans[0].text! + spans[1].text!);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(widths.toSet().length, 1);
    expect(texts.toSet().length, 3);
    expect(texts.first, startsWith("Scanning."));
  });
}

void sourceTreeTests() {
  final localizations = lookupAppLocalizations(const Locale("en"));

  Widget host(MediaLibrary library, {List<LibrarySourceSection>? sections}) =>
      _overlaid(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(500, 300)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 500,
                height: 300,
                child: LibraryView(
                  library: library,
                  sections: sections,
                  colors: const PlEditConfig(),
                  localizations: localizations,
                  onPlay: (_) {},
                  onEnqueue: (_) {},
                  onAddMedia: () {},
                  onContextMenu: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets("the tree lists the local source under its section", (
    tester,
  ) async {
    await tester.pumpWidget(host(MediaLibrary()));
    expect(find.textContaining("Library"), findsOneWidget);
    expect(find.text("Local"), findsOneWidget);
  });

  testWidgets("a source without tracks says it can't be browsed yet", (
    tester,
  ) async {
    final local = MediaLibrary();
    await tester.pumpWidget(
      host(
        local,
        sections: [
          ...librarySections(local, localLabel: "Local"),
          const LibrarySourceSection(
            id: "urls",
            kind: LibrarySourceKind.remote,
            sources: [LibrarySource(id: "radio", label: "Radio")],
          ),
          const LibrarySourceSection(
            id: "empty",
            kind: LibrarySourceKind.remote,
            label: "Plex",
            sources: [],
          ),
        ],
      ),
    );
    expect(find.text("All Artists"), findsOneWidget);
    expect(find.text("None added"), findsOneWidget);

    await tester.tap(find.text("Radio"));
    await tester.pump();
    expect(find.text(localizations.mlSourceUnavailable), findsOneWidget);
    expect(find.text("All Artists"), findsNothing);

    await tester.tap(find.text("Local"));
    await tester.pump();
    expect(find.text("All Artists"), findsOneWidget);
  });

  testWidgets("tapping a section's heading folds its sources away", (
    tester,
  ) async {
    await tester.pumpWidget(host(MediaLibrary()));
    await tester.tap(find.textContaining("Library"));
    await tester.pump();
    expect(find.text("Local"), findsNothing);
    await tester.tap(find.textContaining("Library"));
    await tester.pump();
    expect(find.text("Local"), findsOneWidget);
  });
}

/// A host with no [Overlay], as in the app: the view must bring its own.
Widget _overlaid(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);
