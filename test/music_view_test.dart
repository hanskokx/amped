import "dart:ui" as ui;

import "package:amped/src/app/amped_dialog.dart";
import "package:amped/src/library/cover_grid.dart";
import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/library_view.dart";
import "package:amped/src/library/library_view_settings.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  final l = lookupAppLocalizations(const Locale("en"));

  const tracks = [
    TrackTags(
      "/m/1.mp3",
      artist: "Beta",
      album: "Second",
      title: "Moonset",
      trackNumber: 2,
      duration: Duration(minutes: 3, seconds: 5),
      genres: ["Rock"],
      bitrate: 320,
      sampleRate: 44100,
    ),
    TrackTags(
      "/m/2.mp3",
      artist: "Alpha",
      album: "First",
      title: "Sunrise",
      trackNumber: 1,
      duration: Duration(hours: 1, minutes: 2, seconds: 3),
      genres: ["Folk", "Rock"],
    ),
  ];

  Future<MediaLibrary> filled() async {
    final library = MediaLibrary();
    await library.fill((add, _) async => add(tracks));
    return library;
  }

  Future<void> show(
    WidgetTester tester,
    MediaLibrary library, {
    LibraryViewSettings settings = const LibraryViewSettings(),
    ValueChanged<LibraryViewSettings>? onChanged,
    Future<Uint8List?> Function(String path)? covers,
    void Function(List<String>)? onPlay,
    void Function(List<String>)? onEnqueue,
    void Function(String title, ImageProvider image)? onArtwork,
    void Function(List<String>)? onMenu,
    KeyEventResult Function(FocusNode, KeyEvent)? parentKeys,
  }) async {
    Widget wrap(Widget child) => parentKeys == null
        ? child
        : Focus(canRequestFocus: false, onKeyEvent: parentKeys, child: child);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: wrap(
          MediaQuery(
            data: const MediaQueryData(size: Size(1000, 400)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1000,
                height: 400,
                child: LibraryView(
                  library: library,
                  settings: settings,
                  onSettingsChanged: onChanged,
                  coverLoader: covers,
                  onOpenArtwork: onArtwork,
                  colors: const PlEditConfig(),
                  localizations: l,
                  onPlay: onPlay ?? (_) {},
                  onEnqueue: onEnqueue ?? (_) {},
                  onAddMedia: () {},
                  onContextMenu: onMenu ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Uint8List> png(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawRect(const ui.Rect.fromLTWH(0, 0, 40, 20), ui.Paint());
        final image = await recorder.endRecording().toImage(40, 20);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }))!;

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text).first).dy;

  testWidgets("music is listed in columns under their headings", (
    tester,
  ) async {
    await show(tester, await filled());
    for (final heading in [
      l.mlColumnArtist,
      l.mlColumnAlbum,
      l.mlColumnNumber,
      l.mlColumnTitle,
      l.mlColumnLength,
      l.mlColumnGenre,
    ]) {
      expect(find.textContaining(heading), findsWidgets, reason: heading);
    }
    // One row, one cell per column; lengths and the genres as text.
    expect(find.text("Moonset"), findsOneWidget);
    expect(find.text("3:05"), findsOneWidget);
    expect(find.text("1:02:03"), findsOneWidget);
    expect(find.text("Folk, Rock"), findsOneWidget);
    // The headings are in the usual order, and the columns of podcasts are
    // not among them.
    double x(String text) => tester.getTopLeft(find.text(text).first).dx;
    expect(x(l.mlColumnArtist), lessThan(x(l.mlColumnAlbum)));
    expect(x(l.mlColumnAlbum), lessThan(x(l.mlColumnNumber)));
    expect(x(l.mlColumnNumber), lessThan(x(l.mlColumnTitle)));
    expect(find.textContaining(l.mlColumnPublished), findsNothing);
    expect(find.textContaining(l.mlColumnProgress), findsNothing);
  });

  testWidgets("the widths of the tree and the artists list are remembered", (
    tester,
  ) async {
    final saved = <LibraryViewSettings>[];
    await show(tester, await filled(), onChanged: saved.add);
    final dividers = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == "_PaneDivider",
    );
    await tester.drag(dividers.first, const Offset(40, 0));
    await tester.pump();
    final tree = saved.last.treeWidth;
    expect(tree, greaterThan(80));
    await tester.drag(dividers.last, const Offset(30, 0));
    await tester.pump();
    expect(saved.last.browserWidth, greaterThan(0));
    expect(saved.last.treeWidth, tree);
    // And they come back.
    await show(tester, await filled(), settings: saved.last);
    expect(tester.getRect(dividers.first).left, tree);
  });

  testWidgets("a heading sorts the music, and that is remembered", (
    tester,
  ) async {
    final saved = <LibraryViewSettings>[];
    await show(tester, await filled(), onChanged: saved.add);
    // As the library has them (by artist, album...): Alpha before Beta.
    final before = y(tester, "Sunrise") < y(tester, "Moonset");
    await tester.tap(find.text(l.mlColumnTitle));
    await tester.pump(const Duration(milliseconds: 400));
    // By title ascending: Moonset, Sunrise.
    expect(y(tester, "Moonset"), lessThan(y(tester, "Sunrise")));
    expect(saved.last.musicSortColumn, LibraryColumn.title);
    expect(saved.last.musicSortAscending, isTrue);
    await tester.tap(find.text("${l.mlColumnTitle} ▲"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(y(tester, "Sunrise"), lessThan(y(tester, "Moonset")));
    expect(saved.last.musicSortAscending, isFalse);
    expect(before, isTrue);
  });

  testWidgets("columns are dragged into another order", (tester) async {
    final saved = <LibraryViewSettings>[];
    await show(tester, await filled(), onChanged: saved.add);
    double x(String text) => tester.getTopLeft(find.text(text).first).dx;
    final genre = find.text(l.mlColumnGenre);
    await tester.drag(
      genre,
      Offset(x(l.mlColumnArtist) - x(l.mlColumnGenre), 0),
    );
    await tester.pump();
    expect(x(l.mlColumnGenre), lessThan(x(l.mlColumnArtist)));
    expect(saved.last.musicColumns.first, LibraryColumn.genre);
    // The podcast columns are another list, unchanged.
    expect(saved.last.columns, LibraryColumn.podcast);
  });

  testWidgets("a selected track shows its picture and details", (
    tester,
  ) async {
    final bytes = await png(tester);
    final asked = <String>[];
    await show(
      tester,
      await filled(),
      covers: (path) async {
        asked.add(path);
        return bytes;
      },
    );
    // Nothing selected, nothing picked: nothing to say.
    expect(find.textContaining(l.mlDetails), findsNothing);
    await tester.tap(find.text("Moonset"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(asked, ["/m/1.mp3"]);
    expect(find.textContaining(l.mlDetails), findsOneWidget);
    expect(find.text("Beta  ·  Second  ·  3:05"), findsOneWidget);
    expect(find.text("Rock  ·  320 kbps  ·  44.1 kHz"), findsOneWidget);
    // The picture at the panel's width in its own shape (2:1).
    expect(tester.getSize(find.byType(Image)).width, 160);
  });

  testWidgets("the details panel is dragged taller, never shorter than it "
      "usually is, with the picture kept at the top left", (tester) async {
    final bytes = await png(tester);
    final saved = <LibraryViewSettings>[];
    await show(
      tester,
      await filled(),
      onChanged: saved.add,
      covers: (path) async => bytes,
    );
    await tester.tap(find.text("Moonset"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final panel = find.byType(AnimatedAlign);
    final bar = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
    );
    Offset pictureInPanel() =>
        tester.getTopLeft(find.byType(Image)) - tester.getTopLeft(panel);
    expect(tester.getSize(panel).height, 96);
    expect(pictureInPanel(), Offset.zero);

    // Up: taller, and the picture stays where it is in the panel.
    await tester.dragFrom(tester.getCenter(bar), const Offset(0, -60));
    await tester.pump();
    expect(tester.getSize(panel).height, 156);
    expect(pictureInPanel(), Offset.zero);
    expect(tester.getSize(find.byType(Image)), const Size(160, 96));
    expect(saved.last.detailsExtra, 60);

    // Back down: shorter again, but never under what it usually is.
    await tester.dragFrom(tester.getCenter(bar), const Offset(0, 40));
    await tester.pump();
    expect(tester.getSize(panel).height, 116);
    await tester.dragFrom(tester.getCenter(bar), const Offset(0, 300));
    await tester.pump();
    expect(tester.getSize(panel).height, 96);
    expect(saved.last.detailsExtra, 0);
    expect(pictureInPanel(), Offset.zero);
  });

  test("how much taller the details were dragged is saved", () async {
    final prefs = await _empty();
    await const LibraryViewSettings(detailsExtra: 42.5).save(prefs);
    expect(LibraryViewSettings.load(prefs).detailsExtra, 42.5);
    await prefs.setString("amped.library_view", '{"detailsExtra":-3}');
    expect(LibraryViewSettings.load(prefs).detailsExtra, 0);
  });

  testWidgets("clicking the picture opens it in a window of its own", (
    tester,
  ) async {
    final bytes = await png(tester);
    final opened = <(String, ImageProvider)>[];
    await show(
      tester,
      await filled(),
      covers: (path) async => bytes,
      onArtwork: (title, image) => opened.add((title, image)),
    );
    await tester.tap(find.text("Moonset"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(opened, isEmpty);
    await tester.tap(find.byType(Image));
    await tester.pump();
    expect(opened, hasLength(1));
    // Titled for what it is the picture of; a picture of its own to show.
    expect(opened.single.$1, "Moonset");
    expect(opened.single.$2, isA<MemoryImage>());
  });

  test("the artwork window is drawn in the skin", () {
    expect(AmpedDialog.artwork.skinned, isTrue);
    // And it is not the Album Art window, nor one of the other dialogs.
    expect(
      AmpedDialog.values.where((d) => d.skinned),
      contains(AmpedDialog.artwork),
    );
  });

  testWidgets("without a way to read pictures the details are only text", (
    tester,
  ) async {
    await show(tester, await filled());
    await tester.tap(find.text("Sunrise"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Image), findsNothing);
    expect(find.text("Alpha  ·  First  ·  1:02:03"), findsOneWidget);
  });

  testWidgets("picking an album says what it is", (tester) async {
    await show(tester, await filled());
    await tester.tap(find.text("Second").first);
    await tester.pump();
    expect(find.text("Beta  ·  1 items"), findsOneWidget);
  });

  group("layout", () {
    const more = [
      ...tracks,
      TrackTags(
        "/m/3.mp3",
        artist: "Alpha",
        album: "First",
        title: "Dawn",
        trackNumber: 2,
      ),
    ];

    Future<MediaLibrary> three() async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(more));
      return library;
    }

    Future<void> tap(WidgetTester tester, String text) async {
      await tester.tap(find.text(text).first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets("starts with the list of artists and albums beside the "
        "tracks", (tester) async {
      await show(tester, await three());
      expect(find.text(l.mlAllArtists), findsOneWidget);
      expect(find.text(l.mlColumnAlbums), findsNothing);
    });

    testWidgets("the split layout has an artist and an album panel above the "
        "tracks, with counts", (tester) async {
      final saved = <LibraryViewSettings>[];
      await show(tester, await three(), onChanged: saved.add);
      await tap(tester, "▤");
      expect(saved.last.musicLayout, MusicLayout.split);
      // Artists: Albums and Tracks counts; albums: Tracks.
      expect(find.text(l.mlColumnAlbums), findsOneWidget);
      expect(find.text(l.mlColumnTracks), findsNWidgets(2));
      expect(find.text("All (2 artists)"), findsOneWidget);
      expect(find.text("All (2 albums)"), findsOneWidget);
      // The panels are above the tracks, the artists left of the albums.
      expect(find.text(l.mlAllArtists), findsNothing);
      final alpha = tester.getTopLeft(find.text("Alpha").first);
      final first = tester.getTopLeft(find.text("First").first);
      expect(alpha.dx, lessThan(first.dx));
      expect(alpha.dy, lessThan(tester.getTopLeft(find.text("Dawn")).dy));
      // Alpha: one album, two tracks. Beta: one album, one track.
      Finder row(String name, List<String> counts) => find.byWidgetPredicate(
        (w) =>
            w is Row &&
            w.children.length == 1 + counts.length &&
            w.children.first is Expanded &&
            ((w.children.first as Expanded).child is Text) &&
            (((w.children.first as Expanded).child as Text).data == name) &&
            [
                  for (final c in w.children.skip(1))
                    (((c as SizedBox).child) as Text).data,
                ].join(",") ==
                counts.join(","),
      );
      expect(row("Alpha", ["1", "2"]), findsOneWidget);
      expect(row("Beta", ["1", "1"]), findsOneWidget);
      expect(row("First", ["", "2"]), findsOneWidget);
    });

    testWidgets("the cover layout has the artists, their albums and a "
        "simple track list side by side", (tester) async {
      final saved = <LibraryViewSettings>[];
      final asked = <String>[];
      await show(
        tester,
        await three(),
        onChanged: saved.add,
        covers: (path) async {
          asked.add(path);
          return null;
        },
      );
      await tap(tester, "▦");
      expect(saved.last.musicLayout, MusicLayout.covers);
      expect(find.byType(CoverGrid), findsNWidgets(2));
      Finder inGrid(int i, String text) => find.descendant(
        of: find.byType(CoverGrid).at(i),
        matching: find.text(text),
      );
      // A tile per artist, then one per album.
      expect(inGrid(0, "Alpha"), findsOneWidget);
      expect(inGrid(0, "Beta"), findsOneWidget);
      expect(inGrid(1, "First"), findsOneWidget);
      expect(inGrid(1, "Second"), findsOneWidget);
      expect(asked, isNotEmpty);
      // An artist narrows the albums and the tracks.
      await tester.tap(inGrid(0, "Beta"));
      await tester.pump(const Duration(milliseconds: 400));
      expect(inGrid(1, "First"), findsNothing);
      expect(find.text("Dawn"), findsNothing);
      expect(find.text("Moonset"), findsOneWidget);
    });

    testWidgets("changing the layout keeps the one track selected picked in "
        "the panels", (tester) async {
      await show(tester, await three());
      await tap(tester, "Dawn");
      await tap(tester, "▤");
      // The artist and the album of the track are picked: only theirs are
      // listed.
      expect(find.text("Dawn"), findsWidgets);
      expect(find.text("Moonset"), findsNothing);
    });

    testWidgets("picking an artist narrows the albums and the tracks", (
      tester,
    ) async {
      await show(tester, await three());
      await tap(tester, "▤");
      await tap(tester, "Beta");
      // Only Beta's album is listed, and only its track.
      expect(find.text("All (1 album)"), findsOneWidget);
      expect(find.text("First"), findsNothing);
      expect(find.text("Moonset"), findsOneWidget);
      expect(find.text("Sunrise"), findsNothing);
      // Back to everything.
      await tap(tester, "All (2 artists)");
      expect(find.text("Sunrise"), findsOneWidget);
    });

    testWidgets("picking an album leaves the artists as they are", (
      tester,
    ) async {
      await show(tester, await three());
      await tap(tester, "▤");
      await tap(tester, "Alpha");
      await tap(tester, "First");
      expect(find.text("Moonset"), findsNothing);
      expect(find.text("Dawn"), findsOneWidget);
      // The album's own row (All) puts the albums back.
      await tap(tester, "All (1 album)");
      expect(find.text("Sunrise"), findsOneWidget);
    });

    testWidgets("the bar between the panels and the tracks is dragged, and "
        "that is remembered", (tester) async {
      final saved = <LibraryViewSettings>[];
      await show(tester, await three(), onChanged: saved.add);
      await tap(tester, "▤");
      final bar = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
      );
      final before = tester.getCenter(bar).dy;
      await tester.dragFrom(tester.getCenter(bar), const Offset(0, 60));
      await tester.pump();
      expect(tester.getCenter(bar).dy, closeTo(before + 60, 1));
      expect(saved.last.splitFraction, greaterThan(0.4));
    });

    group("the panels", () {
      const years = [
        TrackTags(
          "/y/1.mp3",
          artist: "Alpha",
          album: "First",
          title: "One",
          year: 2016,
        ),
        TrackTags(
          "/y/2.mp3",
          artist: "Alpha",
          album: "First",
          title: "Two",
          year: 2018,
        ),
        TrackTags(
          "/y/3.mp3",
          artist: "Alpha",
          album: "Second",
          title: "Three",
          year: 2020,
        ),
        TrackTags("/y/4.mp3", artist: "Beta", album: "Third", title: "Four"),
      ];

      Future<MediaLibrary> dated() async {
        final library = MediaLibrary();
        await library.fill((add, _) async => add(years));
        return library;
      }

      double y(WidgetTester tester, String text) =>
          tester.getTopLeft(find.text(text).first).dy;

      testWidgets("the albums have a year, the earliest of its tracks", (
        tester,
      ) async {
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        expect(find.text(l.mlColumnYear), findsOneWidget);
        expect(find.text("2016"), findsOneWidget);
        expect(find.text("2020"), findsOneWidget);
        // The 2018 track is the same album's later one.
        expect(find.text("2018"), findsNothing);
      });

      testWidgets("a heading sorts its panel, again reverses it, and that "
          "is remembered", (tester) async {
        final saved = <LibraryViewSettings>[];
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
          onChanged: saved.add,
        );
        // By name to begin with.
        expect(y(tester, "First"), lessThan(y(tester, "Second")));
        expect(y(tester, "Second"), lessThan(y(tester, "Third")));
        // Year: the newest first, and the one without a year last whichever
        // way.
        await tap(tester, l.mlColumnYear);
        expect(y(tester, "Second"), lessThan(y(tester, "First")));
        expect(y(tester, "First"), lessThan(y(tester, "Third")));
        expect(find.text("${l.mlColumnYear} ▼"), findsOneWidget);
        expect(saved.last.panelSorts["albums"], (1, false));
        await tap(tester, "${l.mlColumnYear} ▼");
        expect(y(tester, "First"), lessThan(y(tester, "Second")));
        expect(y(tester, "Second"), lessThan(y(tester, "Third")));
        // The artists by track count.
        await tap(tester, l.mlColumnAlbums);
        expect(saved.last.panelSorts["artists"], (1, false));
        expect(y(tester, "Alpha"), lessThan(y(tester, "Beta")));
        await tap(tester, "${l.mlColumnAlbums} ▼");
        expect(y(tester, "Beta"), lessThan(y(tester, "Alpha")));
        // Back to the names.
        await tap(tester, l.mlColumnArtist);
        expect(saved.last.panelSorts["artists"], (0, true));
        expect(y(tester, "Alpha"), lessThan(y(tester, "Beta")));
        await tap(tester, "${l.mlColumnArtist} ▲");
        expect(saved.last.panelSorts["artists"], (0, false));
        expect(y(tester, "Beta"), lessThan(y(tester, "Alpha")));
      });

      testWidgets("a click on a sorted panel picks what is listed in that "
          "order", (tester) async {
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        await tap(tester, l.mlColumnYear);
        // Second, First, Third. Shift-clicking Second then Third picks all 3.
        await tap(tester, "Second");
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.text("Third").first);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text("One"), findsOneWidget);
        expect(find.text("Four"), findsOneWidget);
      });

      Finder gripsBetweenPanels() => find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );

      /// The bar between the artists and the albums: the second of the tall
      /// ones, the first being the source tree's.
      Offset panelBar(WidgetTester tester) {
        final tall = [
          for (final e in gripsBetweenPanels().evaluate())
            if (tester.getSize(find.byWidget(e.widget)).height > 30)
              tester.getCenter(find.byWidget(e.widget)),
        ]..sort((a, b) => a.dx.compareTo(b.dx));
        return tall.length > 1 ? tall[1] : tall.first;
      }

      testWidgets("the bar between two panels is dragged, and neither keeps "
          "less than its least width", (tester) async {
        final saved = <LibraryViewSettings>[];
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
          onChanged: saved.add,
        );
        final before = panelBar(tester);
        await tester.dragFrom(before, const Offset(40, 0));
        await tester.pump();
        expect(panelBar(tester).dx, closeTo(before.dx + 40, 1));
        expect(saved.last.splitShares["music"], isNotNull);
        expect(saved.last.splitShares["music"]!.first, greaterThan(0.5));
        // All the way to the right: the albums keep what their counts need.
        await tester.dragFrom(panelBar(tester), const Offset(3000, 0));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final right = tester.getTopRight(find.text(l.mlColumnTracks).last).dx;
        expect(right - panelBar(tester).dx, greaterThanOrEqualTo(90));
        // (Year and Tracks, and a little of the names.)
        // And all the way to the left: the artists keep theirs.
        await tester.dragFrom(panelBar(tester), const Offset(-3000, 0));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final left = tester.getTopLeft(
          find.textContaining(l.mlColumnArtist).first,
        );
        expect(panelBar(tester).dx - left.dx, greaterThanOrEqualTo(90));
      });

      testWidgets("the bar under the panels never takes the room the "
          "tracks need, nor all of the panels'", (tester) async {
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        final bar = find.byWidgetPredicate(
          (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
        );
        // Down: the tracks keep their headings and rows.
        await tester.dragFrom(tester.getCenter(bar), const Offset(0, 2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(l.mlColumnTitle), findsOneWidget);
        expect(find.text("One"), findsOneWidget);
        // Up: the panels keep their headings.
        await tester.dragFrom(tester.getCenter(bar), const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining(l.mlColumnArtist), findsWidgets);
      });

      testWidgets("a window too short for both still lays out", (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 150);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await show(
          tester,
          await dated(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets("the layout buttons say what they do when the pointer rests "
        "on them", (tester) async {
      await show(tester, await three());
      expect(find.text(l.mlLayoutSplit), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text("▤")));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(l.mlLayoutSplit), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l.mlLayoutSplit), findsOneWidget);
      await mouse.moveTo(const Offset(500, 300));
      await tester.pump();
      expect(find.text(l.mlLayoutSplit), findsNothing);
    });

    testWidgets("right-clicking an artist or an album opens the menu for "
        "all of its tracks", (tester) async {
      final menus = <List<String>>[];
      await show(
        tester,
        await three(),
        settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        onMenu: menus.add,
      );
      Future<void> rightClick(String text) async {
        await tester.tap(find.text(text).first, buttons: kSecondaryButton);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await rightClick("Alpha");
      expect(menus.last, unorderedEquals(["/m/2.mp3", "/m/3.mp3"]));
      // Picked too: Beta's track is not listed.
      expect(find.text("Moonset"), findsNothing);
      await rightClick("First");
      expect(menus.last, unorderedEquals(["/m/2.mp3", "/m/3.mp3"]));
      await rightClick("All (2 artists)");
      expect(menus.last, hasLength(3));
      await rightClick("Beta");
      expect(menus.last, ["/m/1.mp3"]);
    });

    testWidgets("right-clicking in the list of artists and albums too", (
      tester,
    ) async {
      final menus = <List<String>>[];
      await show(tester, await three(), onMenu: menus.add);
      await tester.tap(find.text("Beta").first, buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(menus.last, ["/m/1.mp3"]);
      // Beta is picked and its album is listed under it.
      await tester.tap(find.text("Second").first, buttons: kSecondaryButton);
      await tester.pump(const Duration(milliseconds: 400));
      expect(menus.last, ["/m/1.mp3"]);
    });

    group("the keyboard moves between the panels", () {
      Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump(const Duration(milliseconds: 100));
      }

      testWidgets("Left and Right change the panel and Up and Down move in "
          "it", (tester) async {
        await show(
          tester,
          await filled(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        // Albums are First, Second under "All": Left goes to them.
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.text("Sunrise"), findsOneWidget);
        expect(find.text("Moonset"), findsNothing);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.text("Moonset"), findsOneWidget);
        expect(find.text("Sunrise"), findsNothing);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(find.text("Sunrise"), findsOneWidget);
        expect(find.text("Moonset"), findsOneWidget);
        // The artists, on the left of the albums.
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.text("Moonset"), findsOneWidget);
        expect(find.text("Sunrise"), findsNothing);
        // At the left end nothing happens, and Right goes back.
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.arrowRight);
        // On the tracks again: Down selects the first one.
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.textContaining(l.mlDetails), findsOneWidget);
      });

      testWidgets("the panel that has the focus is outlined, and a press "
          "gives it the focus", (tester) async {
        await show(
          tester,
          await filled(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
        );
        bool outlined(String text) {
          final box = find
              .ancestor(
                of: find.text(text).first,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is DecoratedBox &&
                      w.position == DecorationPosition.foreground,
                ),
              )
              .first;
          final border =
              (tester.widget<DecoratedBox>(box).decoration as BoxDecoration)
                      .border
                  as Border?;
          if (border == null) return false;
          // The highlight color, and at least two pixels of it.
          expect(border.top.color, const PlEditConfig().selectedBg);
          expect(border.top.width, greaterThanOrEqualTo(2));
          return true;
        }

        // The tracks to begin with.
        expect(outlined("Moonset"), isTrue);
        expect(outlined("Alpha"), isFalse);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(outlined("Moonset"), isFalse);
        expect(outlined("First"), isTrue);
        // Pressing the artists gives them the focus.
        await tester.tap(find.text("Alpha").first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(outlined("Alpha"), isTrue);
        expect(outlined("First"), isFalse);
      });

      testWidgets("Enter on a panel plays all the tracks it has listed", (
        tester,
      ) async {
        final played = <List<String>>[];
        await show(
          tester,
          await filled(),
          settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
          onPlay: played.add,
        );
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.enter);
        expect(played.single, ["/m/2.mp3"]);
      });
    });

    testWidgets("the panels have clear dividers, sideways and between them "
        "and the tracks", (tester) async {
      await show(
        tester,
        await three(),
        settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
      );
      int lines({bool vertical = true}) => find
          .byWidgetPredicate(
            (w) =>
                w is SizedBox &&
                (vertical ? w.width == 2 : w.height == 2) &&
                w.child is ColoredBox,
          )
          .evaluate()
          .length;
      // The source tree's, and the one between the artists and the albums.
      expect(lines(), greaterThanOrEqualTo(2));
      // Between the panels and the tracks.
      expect(lines(vertical: false), greaterThanOrEqualTo(1));
    });

    testWidgets("tracks only has no panels at all", (tester) async {
      await show(tester, await three());
      await tap(tester, "≡");
      expect(find.text(l.mlAllArtists), findsNothing);
      expect(find.textContaining("All ("), findsNothing);
      expect(find.text("Moonset"), findsOneWidget);
      // And back.
      await tap(tester, "◧");
      expect(find.text(l.mlAllArtists), findsOneWidget);
    });

    testWidgets("is as it was left", (tester) async {
      await show(
        tester,
        await three(),
        settings: const LibraryViewSettings(musicLayout: MusicLayout.split),
      );
      expect(find.text("All (2 artists)"), findsOneWidget);
    });
  });

  group("the keyboard", () {
    // Alpha's Sunrise is listed before Beta's Moonset.
    const sunrise = "Alpha  ·  First  ·  1:02:03";
    const moonset = "Beta  ·  Second  ·  3:05";

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    testWidgets("the arrow keys move through the tracks", (tester) async {
      await show(tester, await filled());
      expect(find.text(sunrise), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text(sunrise), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text(moonset), findsOneWidget);
      // At the end it stays there.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text(moonset), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(find.text(sunrise), findsOneWidget);
      await press(tester, LogicalKeyboardKey.end);
      expect(find.text(moonset), findsOneWidget);
      await press(tester, LogicalKeyboardKey.home);
      expect(find.text(sunrise), findsOneWidget);
    });

    testWidgets("shift extends the selection", (tester) async {
      await show(tester, await filled());
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(find.text(l.mlSelectedTrackCount(2)), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(find.text(l.mlSelectedTrackCount(1)), findsOneWidget);
    });

    testWidgets("Enter plays the selection and Shift+Enter enqueues it", (
      tester,
    ) async {
      final played = <List<String>>[];
      final enqueued = <List<String>>[];
      await show(
        tester,
        await filled(),
        onPlay: played.add,
        onEnqueue: enqueued.add,
      );
      await press(tester, LogicalKeyboardKey.enter);
      expect(played, isEmpty);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      expect(played.single, ["/m/2.mp3"]);
      await press(tester, LogicalKeyboardKey.enter, shift: true);
      expect(enqueued.single, ["/m/2.mp3"]);
    });

    testWidgets("none of them reach the playback shortcuts around the "
        "library", (tester) async {
      final seen = <LogicalKeyboardKey>[];
      await show(
        tester,
        await filled(),
        parentKeys: (node, event) {
          if (event is KeyDownEvent) seen.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
      );
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await press(tester, key);
      }
      expect(seen, isEmpty);
      // Keys it does not use still go on.
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(seen, [LogicalKeyboardKey.keyJ]);
    });

    testWidgets("in the search field the keys are the field's own", (
      tester,
    ) async {
      final seen = <LogicalKeyboardKey>[];
      await show(
        tester,
        await filled(),
        parentKeys: (node, event) {
          if (event is KeyDownEvent) seen.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
      );
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      // Not a track move: nothing was selected.
      expect(find.textContaining(l.mlDetails), findsNothing);
    });
  });

  group("audiobooks", () {
    const parts = [
      TrackTags(
        "b/1",
        artist: "Ann",
        album: "Saga One",
        title: "Part 1",
        series: "The Saga",
        genres: ["Audiobook"],
      ),
      TrackTags(
        "b/2",
        artist: "Ann",
        album: "Saga One",
        title: "Part 2",
        series: "The Saga",
        genres: ["Audiobook"],
      ),
      TrackTags(
        "b/3",
        artist: "Ann",
        album: "Saga Two",
        title: "Only part",
        series: "The Saga",
        genres: ["Audiobook"],
      ),
      TrackTags(
        "b/4",
        artist: "Bob",
        album: "Alone",
        title: "Single",
        genres: ["Audiobook"],
      ),
    ];

    Future<void> showBooks(
      WidgetTester tester, {
      LibraryViewSettings settings = const LibraryViewSettings(),
      void Function(List<String>)? onMenu,
    }) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(parts));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(1000, 400)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1000,
                height: 400,
                child: LibraryView(
                  library: MediaLibrary(),
                  settings: settings.copyWith(sourceId: "books"),
                  sections: [
                    LibrarySourceSection(
                      id: audiobooksSectionId,
                      kind: LibrarySourceKind.audiobooks,
                      sources: [
                        LibrarySource(
                          id: "books",
                          label: "Shelf",
                          library: library,
                          podcast: true,
                          audiobooks: true,
                        ),
                      ],
                    ),
                  ],
                  colors: const PlEditConfig(),
                  localizations: l,
                  onPlay: (_) {},
                  onEnqueue: (_) {},
                  onAddMedia: () {},
                  onContextMenu: onMenu ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> tap(WidgetTester tester, String text) async {
      await tester.tap(find.text(text).first);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets("are split into authors, series and books above the parts", (
      tester,
    ) async {
      await showBooks(tester);
      // (Each panel is sorted by its names to begin with, as the arrow says.)
      expect(find.text("${l.mlColumnAuthor} ▲"), findsOneWidget);
      expect(find.text("${l.mlColumnSeries} ▲"), findsOneWidget);
      expect(find.textContaining(l.mlColumnBook), findsWidgets);
      expect(find.text("All (2 authors)"), findsOneWidget);
      expect(find.text("All (1 series)"), findsOneWidget);
      expect(find.text("All (3 books)"), findsOneWidget);
      // Left to right, and above the parts.
      double x(String t) => tester.getTopLeft(find.textContaining(t).first).dx;
      expect(x(l.mlColumnAuthor), lessThan(x(l.mlColumnSeries)));
      expect(x(l.mlColumnSeries), lessThan(x("Saga One")));
      expect(
        tester.getTopLeft(find.text("Ann").first).dy,
        lessThan(tester.getTopLeft(find.text("Part 1")).dy),
      );
      expect(find.text("Single"), findsOneWidget);
    });

    testWidgets("an author narrows the series, the books and the parts", (
      tester,
    ) async {
      await showBooks(tester);
      await tap(tester, "Bob");
      // Bob has no series and one book.
      expect(find.text("All (0 series)"), findsOneWidget);
      expect(find.text("All (1 book)"), findsOneWidget);
      expect(find.text("Part 1"), findsNothing);
      expect(find.text("Single"), findsOneWidget);
      await tap(tester, "All (2 authors)");
      expect(find.text("Part 1"), findsOneWidget);
    });

    testWidgets("a series narrows the books, and a book the parts", (
      tester,
    ) async {
      await showBooks(tester);
      await tap(tester, "The Saga");
      expect(find.text("All (2 books)"), findsOneWidget);
      expect(find.text("Single"), findsNothing);
      await tap(tester, "Saga Two");
      expect(find.text("Only part"), findsOneWidget);
      expect(find.text("Part 1"), findsNothing);
      // The series' own row puts the books back.
      await tap(tester, "All (1 series)");
      expect(find.text("Single"), findsOneWidget);
    });

    testWidgets("have a button for the list of books beside the parts, "
        "and another for the panels", (tester) async {
      await showBooks(tester);
      expect(find.text("≡"), findsNothing);
      await tap(tester, "◧");
      expect(find.text(l.mlAllAudiobooks), findsOneWidget);
      expect(find.textContaining(l.mlColumnAuthor), findsNothing);
      await tap(tester, "▤");
      expect(find.textContaining(l.mlColumnAuthor), findsOneWidget);
    });

    testWidgets("with several books the Book column comes first and the "
        "parts are grouped by book", (tester) async {
      final saved = <LibraryViewSettings>[];
      await showBooks(tester);
      double x(String t) => tester.getTopLeft(find.text(t).first).dx;
      // The Book heading (sorted, as the arrow says) before the others.
      expect(find.text("${l.mlColumnBook} ▲"), findsWidgets);
      final book = find.text("${l.mlColumnBook} ▲").last;
      expect(
        tester.getTopLeft(book).dx,
        lessThan(tester.getTopLeft(find.text(l.mlColumnNumber)).dx),
      );
      expect(
        tester.getTopLeft(find.text(l.mlColumnNumber)).dx,
        lessThan(x(l.mlColumnTitle)),
      );
      // Grouped: Alone, then Saga One's parts together, then Saga Two.
      double y(String t) => tester.getTopLeft(find.text(t).first).dy;
      expect(y("Single"), lessThan(y("Part 1")));
      expect(y("Part 1"), lessThan(y("Part 2")));
      expect(y("Part 2"), lessThan(y("Only part")));
      // Another heading takes over, and is remembered.
      await tester.tap(find.text(l.mlColumnTitle));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("${l.mlColumnBook} ▲"), findsNWidgets(1));
      expect(saved, isEmpty);
    });

    testWidgets("one book has no Book column", (tester) async {
      await showBooks(tester);
      await tap(tester, "Saga One");
      // The table has no Book column now (the books panel still says Book,
      // and its first row "All (3 books)" and the details of the book).
      expect(find.text("${l.mlColumnBook} ▲"), findsOneWidget);
    });

    testWidgets("right-clicking an author, a series or a book opens the "
        "menu for all of its parts", (tester) async {
      final menus = <List<String>>[];
      await showBooks(tester, onMenu: menus.add);
      Future<void> rightClick(String text) async {
        await tester.tap(find.text(text).first, buttons: kSecondaryButton);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await rightClick("Saga One");
      expect(menus.last, unorderedEquals(["b/1", "b/2"]));
      // It picked the book too: only its parts are listed.
      expect(find.text("Only part"), findsNothing);
      await rightClick("All (3 books)");
      expect(menus.last, hasLength(4));
      await rightClick("Ann");
      expect(menus.last, unorderedEquals(["b/1", "b/2", "b/3"]));
      await rightClick("The Saga");
      expect(menus.last, unorderedEquals(["b/1", "b/2", "b/3"]));
      await rightClick("Bob");
      expect(menus.last, ["b/4"]);
    });

    testWidgets("start in the layout they were left in", (tester) async {
      await showBooks(
        tester,
        settings: const LibraryViewSettings(bookLayout: MusicLayout.browser),
      );
      expect(find.text(l.mlAllAudiobooks), findsOneWidget);
    });
  });

  test(
    "audiobooks are split unless that was changed, and it is saved",
    () async {
      final prefs = await _empty();
      expect(LibraryViewSettings.load(prefs).bookLayout, MusicLayout.split);
      await const LibraryViewSettings(bookLayout: MusicLayout.browser)
          .save(prefs);
      expect(LibraryViewSettings.load(prefs).bookLayout, MusicLayout.browser);
    },
  );

  test("the order, sort and widths of music are saved", () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await const LibraryViewSettings(
      musicColumns: [LibraryColumn.genre, LibraryColumn.title],
      musicSortColumn: LibraryColumn.artist,
      musicSortAscending: false,
    ).save(prefs);
    final loaded = LibraryViewSettings.load(prefs);
    expect(loaded.musicSortColumn, LibraryColumn.artist);
    expect(loaded.musicSortAscending, isFalse);
    expect(loaded.musicColumns.take(2), [
      LibraryColumn.genre,
      LibraryColumn.title,
    ]);
    // The rest of the columns of music follow, and none of podcasts'.
    expect(loaded.musicColumns.toSet(), LibraryColumn.music.toSet());
    expect(LibraryViewSettings.load(await _empty()).musicSortColumn, isNull);
    expect(
      LibraryViewSettings.load(await _empty()).musicLayout,
      MusicLayout.browser,
    );
    await const LibraryViewSettings(
      musicLayout: MusicLayout.split,
      splitFraction: 0.6,
    ).save(prefs);
    expect(LibraryViewSettings.load(prefs).musicLayout, MusicLayout.split);
    expect(LibraryViewSettings.load(prefs).splitFraction, 0.6);
    // How the panels are sorted and how wide they are.
    await const LibraryViewSettings(
      panelSorts: {"albums": (1, false), "authors": (0, true)},
      splitShares: {
        "music": [0.3, 0.7],
      },
    ).save(prefs);
    final panels = LibraryViewSettings.load(prefs);
    expect(panels.panelSorts, {"albums": (1, false), "authors": (0, true)});
    expect(panels.splitShares["music"], [0.3, 0.7]);
    await prefs.setString(
      "amped.library_view",
      '{"panelSorts":{"a":[9,true],"b":"no"},"splitShares":{"c":[1,-2]}}',
    );
    expect(LibraryViewSettings.load(prefs).panelSorts, isEmpty);
    expect(LibraryViewSettings.load(prefs).splitShares, isEmpty);
    // A fraction by hand that would hide a panel is not taken.
    await prefs.setString(
      "amped.library_view",
      '{"musicLayout":"split","splitFraction":3}',
    );
    expect(LibraryViewSettings.load(prefs).splitFraction, 0.4);
  });
}

Future<SharedPreferences> _empty() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
