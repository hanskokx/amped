import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/library_view.dart";
import "package:amped/src/library/library_view_settings.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/library/source_settings.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";

import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  final l = lookupAppLocalizations(const Locale("en"));

  final tracks = [
    TrackTags(
      "a",
      album: "Show",
      title: "Bravo",
      trackNumber: 1,
      duration: const Duration(hours: 1, minutes: 2, seconds: 3),
      published: DateTime.utc(2023, 1, 1),
      progress: 1,
    ),
    TrackTags(
      "b",
      album: "Show",
      title: "Alpha",
      trackNumber: 2,
      duration: const Duration(minutes: 10),
      published: DateTime.utc(2023, 3, 1),
      progress: 0.4,
    ),
    TrackTags(
      "c",
      album: "Show",
      title: "Charlie",
      trackNumber: 3,
      duration: const Duration(minutes: 20),
      published: DateTime.utc(2023, 2, 1),
    ),
  ];

  test("episodes sort by each column, missing values last", () {
    List<String> order(LibraryColumn column, bool ascending) => [
      for (final t in LibraryColumn.sorted(tracks, column, ascending)) t.path,
    ];
    expect(order(LibraryColumn.published, false), ["b", "c", "a"]);
    expect(order(LibraryColumn.published, true), ["a", "c", "b"]);
    expect(order(LibraryColumn.title, true), ["b", "a", "c"]);
    expect(order(LibraryColumn.length, false), ["a", "c", "b"]);
    expect(order(LibraryColumn.number, true), ["a", "b", "c"]);
    expect(order(LibraryColumn.progress, false), ["a", "b", "c"]);
    final withMissing = [...tracks, const TrackTags("d", title: "Delta")];
    for (final ascending in [true, false]) {
      expect(
        LibraryColumn.sorted(
          withMissing,
          LibraryColumn.published,
          ascending,
        ).last.path,
        "d",
      );
    }
  });

  testWidgets("a podcast source lists episodes under sortable headings", (
    tester,
  ) async {
    final library = MediaLibrary();
    await library.fill((add, _) async => add(tracks));
    await tester.pumpWidget(
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
                library: MediaLibrary(),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Show",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.tap(find.text("Show"));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.mlAllArtists), findsNothing);

    List<String> shown() {
      final names = ["Alpha", "Bravo", "Charlie"];
      final found = [
        for (final n in names) (n, tester.getTopLeft(find.text(n)).dy),
      ]..sort((x, y) => x.$2.compareTo(y.$2));
      return [for (final f in found) f.$1];
    }

    // Newest first to begin with.
    expect(shown(), ["Alpha", "Charlie", "Bravo"]);
    expect(find.text("2023-03-01"), findsOneWidget);
    // Lengths are m:ss, or h:mm:ss from an hour on.
    expect(find.text("1:02:03"), findsOneWidget);
    expect(find.text("10:00"), findsOneWidget);
    expect(find.text("20:00"), findsOneWidget);
    // Right aligned: the texts end where their column does.
    expect(
      tester.getTopRight(find.text("10:00")).dx,
      tester.getTopRight(find.text("1:02:03")).dx,
    );
    await tester.tap(find.textContaining(l.mlColumnPublished));
    await tester.pump();
    expect(shown(), ["Bravo", "Charlie", "Alpha"]);
    await tester.tap(find.textContaining(l.mlColumnEpisode));
    await tester.pump();
    expect(shown(), ["Alpha", "Bravo", "Charlie"]);
    await tester.tap(find.textContaining(l.mlColumnLength));
    await tester.pump();
    expect(shown(), ["Alpha", "Charlie", "Bravo"]);
    expect(find.text("40%"), findsOneWidget);
    expect(find.text("100%"), findsOneWidget);
    await tester.tap(find.textContaining(l.mlColumnProgress));
    await tester.pump();
    expect(shown(), ["Bravo", "Alpha", "Charlie"]);
  });

  testWidgets("hide listened to leaves out the finished episodes", (
    tester,
  ) async {
    final library = MediaLibrary();
    await library.fill((add, _) async => add(tracks));
    await tester.pumpWidget(
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
                library: MediaLibrary(),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Show",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.tap(find.text("Show"));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Bravo"), findsOneWidget);
    await tester.tap(find.text(l.mlHideListened));
    await tester.pump(const Duration(milliseconds: 400));
    // Bravo was heard to the end; the others were not.
    expect(find.text("Bravo"), findsNothing);
    expect(find.text("Alpha"), findsOneWidget);
    await tester.tap(find.text(l.mlHideListened));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Bravo"), findsOneWidget);
  });

  testWidgets("episodes of several podcasts get a sortable podcast column", (
    tester,
  ) async {
    final library = MediaLibrary();
    await library.fill(
      (add, _) async => add([
        ...tracks,
        TrackTags(
          "z",
          album: "Other",
          title: "Zulu",
          published: DateTime.utc(2023, 4, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 300)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 300,
              child: LibraryView(
                library: MediaLibrary(),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Server",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.tap(find.text("Server"));
    await tester.pump(const Duration(seconds: 1));
    // All podcasts: the column is there.
    expect(find.text(l.mlColumnPodcast), findsOneWidget);
    expect(find.text("Other"), findsNWidgets(2)); // in the list and a row
    await tester.tap(find.text(l.mlColumnPodcast));
    await tester.pump();
    expect(find.text("${l.mlColumnPodcast} ▲"), findsOneWidget);
    // One podcast picked: its name is no news.
    await tester.tap(find.text("Other").first);
    await tester.pump();
    expect(find.text(l.mlColumnPodcast), findsNothing);
  });

  testWidgets("a window too narrow for the columns scrolls sideways", (
    tester,
  ) async {
    final library = MediaLibrary();
    await library.fill((add, _) async => add(tracks));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(360, 300)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              height: 300,
              child: LibraryView(
                library: MediaLibrary(),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Show",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.tap(find.text("Show"));
    await tester.pump(const Duration(seconds: 1));
    // Laid out without overflowing, with the last column out of view.
    expect(tester.takeException(), isNull);
    final heading = find.textContaining(l.mlColumnProgress);
    expect(tester.getTopLeft(heading).dx, greaterThan(360));
    // A trackpad or sideways wheel scrolls it (drags on the rows move tracks,
    // on the headings columns).
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(250, 100)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(300, 0)));
    await tester.pump();
    expect(tester.getTopLeft(heading).dx, lessThan(360));
    // The vertical scrollbar stays at the edge of the view meanwhile, and the
    // sideways one is there under the columns.
    Finder bar(Axis axis) => find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == "_ThemedScrollbar" &&
          (w as dynamic).axis == axis,
    );
    // (The rightmost of them is the episodes'.)
    expect(
      tester.getRect(bar(Axis.vertical).last).right,
      lessThanOrEqualTo(360),
    );
    expect(tester.getRect(bar(Axis.vertical).last).left, greaterThan(340));
    expect(bar(Axis.horizontal), findsOneWidget);
    expect(tester.getRect(bar(Axis.horizontal)).left, lessThan(360));
  });

  group("remembered settings", () {
    Future<void> show(
      WidgetTester tester,
      MediaLibrary library, {
      LibraryViewSettings settings = const LibraryViewSettings(),
      ValueChanged<LibraryViewSettings>? onChanged,
      ImageProvider Function(String url)? cover,
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 300)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 800,
                height: 300,
                child: LibraryView(
                  library: MediaLibrary(),
                  settings: settings,
                  onSettingsChanged: onChanged,
                  coverProvider: cover ?? (url) => MemoryImage(Uint8List(0)),
                  sections: [
                    LibrarySourceSection(
                      id: "podcasts",
                      kind: LibrarySourceKind.podcasts,
                      sources: [
                        LibrarySource(
                          id: "p",
                          label: "Server",
                          library: library,
                          podcast: true,
                        ),
                      ],
                    ),
                  ],
                  colors: const PlEditConfig(),
                  localizations: l,
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
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets("dragging a heading onto another moves the column", (
      tester,
    ) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      final saved = <LibraryViewSettings>[];
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(sourceId: "p"),
        onChanged: saved.add,
      );
      double x(String text) => tester.getTopLeft(find.textContaining(text)).dx;
      expect(x(l.mlColumnPublished), lessThan(x(l.mlColumnLength)));
      await tester.drag(
        find.textContaining(l.mlColumnLength),
        Offset(x(l.mlColumnPublished) - x(l.mlColumnLength) - 5, 0),
      );
      await tester.pump();
      expect(x(l.mlColumnLength), lessThan(x(l.mlColumnPublished)));
      // The rows follow the headings.
      expect(
        tester.getTopLeft(find.text("10:00")).dx,
        lessThan(tester.getTopLeft(find.text("2023-03-01")).dx),
      );
      final order = saved.last.columns;
      expect(
        order.indexOf(LibraryColumn.length),
        lessThan(order.indexOf(LibraryColumn.published)),
      );
      // Clicking the heading still sorts, and that is remembered too.
      await tester.tap(find.textContaining(l.mlColumnLength));
      await tester.pump();
      expect(saved.last.sortColumn, LibraryColumn.length);
    });

    group("cover", () {
      Future<Uint8List> png(WidgetTester tester) async =>
          (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            ui.Canvas(recorder).drawRect(
              const ui.Rect.fromLTWH(0, 0, 40, 20),
              ui.Paint(),
            );
            final image = await recorder.endRecording().toImage(40, 20);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            return data!.buffer.asUint8List();
          }))!;

      Future<void> settle(WidgetTester tester) async {
        // A single tap on a row waits out the double-tap window.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      final covered = [
        const TrackTags(
          "a",
          album: "Show",
          title: "Alpha",
          imageUrl: "http://i/a",
        ),
        const TrackTags("z", album: "Other", title: "Zulu"),
      ];

      testWidgets("shows at the column's width in the picture's shape, and "
          "folds away", (tester) async {
        final bytes = await png(tester);
        final library = MediaLibrary();
        await library.fill((add, _) async => add(covered));
        final saved = <LibraryViewSettings>[];
        await show(
          tester,
          library,
          settings: const LibraryViewSettings(sourceId: "p"),
          onChanged: saved.add,
          cover: (url) => MemoryImage(bytes),
        );
        // Nothing picked or selected: no picture.
        expect(find.byType(Image), findsNothing);
        expect(find.textContaining(l.mlDetails), findsNothing);
        // An episode with a picture.
        await tester.tap(find.text("Alpha"));
        await tester.pump();
        await settle(tester);
        expect(find.textContaining(l.mlDetails), findsOneWidget);
        expect(tester.getSize(find.byType(Image)), const Size(160, 96));
        // Another episode has none, and its podcast is not picked: hidden.
        await tester.tap(find.text("Zulu"));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Image), findsNothing);
        // Picking the podcast shows its picture.
        await tester.tap(find.widgetWithText(GestureDetector, "Show").first);
        await tester.pump();
        await settle(tester);
        expect(find.byType(Image), findsOneWidget);
        // The heading folds it, sliding down out of view, and that is
        // remembered.
        double shown() => tester.getSize(find.byType(AnimatedAlign)).height;
        expect(shown(), 96);
        await tester.tap(find.textContaining(l.mlDetails));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(shown(), allOf(greaterThan(0), lessThan(96)));
        await tester.pump(const Duration(milliseconds: 300));
        expect(shown(), 0);
        expect(saved.last.coverCollapsed, isTrue);
        // And back up again.
        await tester.tap(find.textContaining(l.mlDetails));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(shown(), allOf(greaterThan(0), lessThan(96)));
        await tester.pump(const Duration(milliseconds: 300));
        expect(shown(), 96);
      });

      testWidgets("shows only the text when the picture can't be loaded", (
        tester,
      ) async {
        final library = MediaLibrary();
        await library.fill((add, _) async => add(covered));
        await show(
          tester,
          library,
          settings: const LibraryViewSettings(sourceId: "p"),
        );
        await tester.tap(find.text("Alpha"));
        await tester.pump();
        await settle(tester);
        // The picture is loaded, built, and only then found to be no picture.
        await settle(tester);
        await tester.pump();
        expect(find.byType(Image), findsNothing);
        // The panel is still there, with the episode's name (also in the
        // list).
        expect(find.textContaining(l.mlDetails), findsOneWidget);
        expect(find.text("Alpha"), findsNWidgets(2));
      });

      testWidgets("says what is known of the episode, or of the podcast", (
        tester,
      ) async {
        final library = MediaLibrary();
        await library.fill(
          (add, _) async => add([
            TrackTags(
              "a",
              artist: "Host",
              album: "Show",
              title: "Alpha",
              duration: const Duration(minutes: 5, seconds: 30),
              published: DateTime.utc(2023, 1, 1),
              description: "All about alpha.",
              showDescription: "A show about letters.",
              progress: 1,
            ),
            const TrackTags(
              "b",
              artist: "Host",
              album: "Show",
              title: "Bravo",
              showDescription: "A show about letters.",
            ),
            const TrackTags("z", album: "Other", title: "Zulu"),
          ]),
        );
        await show(
          tester,
          library,
          settings: const LibraryViewSettings(sourceId: "p"),
        );
        // Nothing picked, nothing selected: nothing to say.
        expect(find.textContaining(l.mlDetails), findsNothing);
        await tester.tap(find.text("Alpha"));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text("All about alpha."), findsOneWidget);
        expect(find.text("Show  ·  2023-01-01  ·  5:30"), findsOneWidget);
        expect(
          tester.widget<Text>(find.text("Alpha").last).style?.fontWeight,
          FontWeight.bold,
        );
        // Picking the podcast: who makes it, the counts, what it is about.
        await tester.tap(find.widgetWithText(GestureDetector, "Show").first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text("A show about letters."), findsOneWidget);
        expect(find.text("Host  ·  1 (2)"), findsOneWidget);
      });
    });

    testWidgets("dragging the edge of a heading resizes its column, and "
        "double-clicking it resets", (tester) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      final saved = <LibraryViewSettings>[];
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(sourceId: "p"),
        onChanged: saved.add,
      );
      double x(String text) => tester.getTopLeft(find.textContaining(text)).dx;
      final length = find.textContaining(l.mlColumnLength);
      // The title takes what the others leave, so a column after it has its
      // grip on the left edge, the edge that moves.
      final right = tester.getTopRight(length).dx + 3;
      final played = x(l.mlColumnProgress);
      final grip = tester.getTopLeft(length) + const Offset(-1, 5);
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      // (A heading's text is its column less the space either side.)
      expect(tester.getSize(length).width, 30 - 6);
      expect(tester.getTopRight(length).dx + 3, right);
      expect(x(l.mlColumnProgress), played);
      expect(saved.last.columnWidths[LibraryColumn.length], 30);
      // The rows follow the heading.
      expect(tester.getTopRight(find.text("20:00")).dx + 3, right);
      // Never narrower than a sliver.
      final again = await tester.startGesture(
        tester.getTopLeft(length) + const Offset(-1, 5),
      );
      await again.moveBy(const Offset(500, 0));
      await again.up();
      await tester.pump();
      expect(tester.getSize(length).width, 24 - 6);
      // Wider the other way.
      final wider = await tester.startGesture(
        tester.getTopLeft(length) + const Offset(-1, 5),
      );
      await wider.moveBy(const Offset(-40, 0));
      await wider.up();
      await tester.pump();
      expect(tester.getSize(length).width, 64 - 6);
      // Double-clicking the edge goes back to the usual width.
      final edge = tester.getTopLeft(length) + const Offset(-1, 5);
      await tester.tapAt(edge);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(edge);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(length).width, 60 - 6);
      expect(saved.last.columnWidths, isEmpty);
    });

    testWidgets("a column before the title is resized from its right edge", (
      tester,
    ) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(sourceId: "p"),
      );
      final number = find.textContaining(l.mlColumnNumber);
      final start = tester.getTopLeft(number).dx;
      final gesture = await tester.startGesture(
        tester.getTopRight(number) + const Offset(1, 5),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(number).width, 56 - 6);
      expect(tester.getTopLeft(number).dx, start);
    });

    testWidgets("the title can be given a width too", (tester) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(
          sourceId: "p",
          columnWidths: {LibraryColumn.title: 150},
        ),
      );
      expect(
        tester.getSize(find.textContaining(l.mlColumnEpisode)).width,
        150 - 6,
      );
    });

    testWidgets("headings and their edges have their own cursors", (
      tester,
    ) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(sourceId: "p"),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      const device = 1;
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      MouseCursor cursor() => RendererBinding.instance.mouseTracker
          .debugDeviceActiveCursor(device)!;
      final length = find.textContaining(l.mlColumnLength);
      await mouse.moveTo(tester.getTopLeft(length) + const Offset(8, 5));
      expect(cursor(), SystemMouseCursors.grab);
      await mouse.moveTo(tester.getTopLeft(length) + const Offset(-1, 5));
      expect(cursor(), SystemMouseCursors.resizeColumn);
    });

    testWidgets("starts as it was left", (tester) async {
      final library = MediaLibrary();
      await library.fill((add, _) async => add(tracks));
      await show(
        tester,
        library,
        settings: const LibraryViewSettings(
          sourceId: "p",
          sortColumn: LibraryColumn.title,
          sortAscending: true,
          columns: [
            LibraryColumn.length,
            LibraryColumn.title,
            LibraryColumn.number,
            LibraryColumn.album,
            LibraryColumn.published,
            LibraryColumn.progress,
          ],
        ),
      );
      expect(find.text("${l.mlColumnEpisode} ▲"), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining(l.mlColumnLength)).dx,
        lessThan(tester.getTopLeft(find.textContaining(l.mlColumnNumber)).dx),
      );
      final ys = [
        for (final name in ["Alpha", "Bravo", "Charlie"])
          tester.getTopLeft(find.text(name)).dy,
      ];
      expect(ys, [...ys]..sort());
    });

    test(
      "settings survive the preferences, and bad ones are ignored",
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        expect(LibraryViewSettings.load(prefs).sourceId, localSourceId);
        await const LibraryViewSettings(
          sourceId: "p",
          albums: {"Show"},
          sortColumn: LibraryColumn.length,
          sortAscending: true,
          columns: [LibraryColumn.length, LibraryColumn.title],
          columnWidths: {LibraryColumn.title: 222.5},
          collapsed: {"videos"},
        ).save(prefs);
        final loaded = LibraryViewSettings.load(prefs);
        expect(loaded.sourceId, "p");
        expect(loaded.albums, {"Show"});
        expect(loaded.sortColumn, LibraryColumn.length);
        expect(loaded.sortAscending, isTrue);
        expect(loaded.collapsed, {"videos"});
        expect(loaded.columnWidths, {LibraryColumn.title: 222.5});
        // Columns the saved order lacks come after it.
        expect(loaded.columns.take(2), [
          LibraryColumn.length,
          LibraryColumn.title,
        ]);
        expect(loaded.columns.toSet(), LibraryColumn.podcast.toSet());
        expect(loaded.musicColumns, LibraryColumn.music);
        await prefs.setString("amped.library_view", "{nonsense");
        expect(LibraryViewSettings.load(prefs).sourceId, localSourceId);
      },
    );
  });

  group("episode counts", () {
    Future<void> pumpCounts(
      WidgetTester tester, {
      PodcastCompletion completion = const PodcastCompletion(),
    }) async {
      final library = MediaLibrary();
      await library.fill(
        (add, _) async => add([
          ...tracks, // "Show": 100%, 40% and none
          const TrackTags("y", album: "Show", title: "Yankee", progress: 0.95),
          const TrackTags("z", album: "Other", title: "Zulu", progress: 1),
        ]),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 300)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 800,
                height: 300,
                child: LibraryView(
                  library: MediaLibrary(),
                  settings: const LibraryViewSettings(sourceId: "p"),
                  sections: [
                    LibrarySourceSection(
                      id: "podcasts",
                      kind: LibrarySourceKind.podcasts,
                      sources: [
                        LibrarySource(
                          id: "p",
                          label: "Server",
                          library: library,
                          podcast: true,
                          completion: completion,
                        ),
                      ],
                    ),
                  ],
                  colors: const PlEditConfig(),
                  localizations: l,
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
      await tester.pump(const Duration(seconds: 1));
    }

    // The count of a row: "new (total)", read from its rich text.
    Finder count(String text) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == text,
    );

    testWidgets("are new (total), the new ones in bold, and an episode "
        "played to the completion percentage is not new", (tester) async {
      await pumpCounts(tester);
      // Show: 4 episodes, two of them (100% and 95%) heard enough.
      // Other: its one is heard. All: 2 new of 5.
      expect(count("2 (4)"), findsOneWidget);
      expect(count("0 (1)"), findsOneWidget);
      expect(count("2 (5)"), findsOneWidget);
      // (Text wraps the spans it was given.)
      final root = tester.widget<RichText>(count("2 (4)")).text as TextSpan;
      final span = (root.children!.single as TextSpan).children!;
      expect((span.first as TextSpan).text, "2");
      expect((span.first as TextSpan).style?.fontWeight, FontWeight.bold);
      expect((span.last as TextSpan).style?.fontWeight, isNull);
      // At the right edge of the pane, which is 160 wide.
      expect(
        tester.getTopRight(count("2 (5)")).dx,
        greaterThan(tester.getTopRight(find.text("All Podcasts")).dx),
      );
    });

    testWidgets("can go by the time left instead", (tester) async {
      // Yankee (95%) has no length, so only played to the end counts; give
      // the others lengths: Alpha 100%, Bravo (40% of 10 minutes) has six
      // minutes left, Charlie has none played.
      await pumpCounts(
        tester,
        completion: const PodcastCompletion(
          mode: CompletionMode.remaining,
          remaining: Duration(minutes: 7),
        ),
      );
      // Bravo's 6 minutes left are within 7: played. Yankee's length is
      // unknown: new. Charlie's 20 minutes: new. Alpha: played.
      expect(count("2 (4)"), findsOneWidget);
    });

    testWidgets("follow the percentage that counts as played", (tester) async {
      await pumpCounts(
        tester,
        completion: const PodcastCompletion(percent: 100),
      );
      // The 95% one is new again.
      expect(count("3 (4)"), findsOneWidget);
      expect(count("0 (1)"), findsOneWidget);
      expect(count("3 (5)"), findsOneWidget);
    });
  });

  testWidgets("columns have a little space between them, lengths drop "
      "leading zeros and numbers line up on the right", (tester) async {
    final library = MediaLibrary();
    await library.fill(
      (add, _) async => add([
        TrackTags(
          "a",
          album: "Show",
          title: "Alpha",
          trackNumber: 7,
          duration: const Duration(hours: 1),
          published: DateTime.utc(2023, 1, 1),
        ),
        const TrackTags(
          "b",
          album: "Show",
          title: "Bravo",
          trackNumber: 8,
          duration: Duration(minutes: 5, seconds: 30),
        ),
      ]),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 300)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 300,
              child: LibraryView(
                library: MediaLibrary(),
                settings: const LibraryViewSettings(sourceId: "p"),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Server",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("1:00:00"), findsOneWidget);
    expect(find.text("5:30"), findsOneWidget);
    // Numbers are right aligned under a heading that is left aligned.
    expect(tester.widget<Text>(find.text("7")).textAlign, TextAlign.right);
    expect(
      tester.widget<Text>(find.textContaining(l.mlColumnNumber)).textAlign,
      isNull,
    );
    // Lengths too, and their heading is left aligned.
    expect(tester.widget<Text>(find.text("5:30")).textAlign, TextAlign.right);
    expect(
      tester.widget<Text>(find.textContaining(l.mlColumnLength)).textAlign,
      isNull,
    );
    // Six pixels between one column's text and the next's.
    expect(
      tester.getTopLeft(find.text("2023-01-01")).dx -
          tester.getTopRight(find.text("Alpha")).dx,
      6,
    );
  });

  testWidgets("All Podcasts is in bold", (tester) async {
    final library = MediaLibrary();
    await library.fill(
      (add, _) async => add(const [
        TrackTags("a", album: "Show", title: "Alpha"),
        TrackTags("z", album: "Other", title: "Zulu"),
      ]),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 300)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 300,
              child: LibraryView(
                library: MediaLibrary(),
                settings: const LibraryViewSettings(sourceId: "p"),
                sections: [
                  LibrarySourceSection(
                    id: "podcasts",
                    kind: LibrarySourceKind.podcasts,
                    sources: [
                      LibrarySource(
                        id: "p",
                        label: "Server",
                        library: library,
                        podcast: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
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
    await tester.pump(const Duration(seconds: 1));
    FontWeight? weight(String text) =>
        tester.widget<Text>(find.text(text).first).style?.fontWeight;
    expect(weight(l.mlAllPodcasts), FontWeight.bold);
    expect(weight("Other"), isNull);
  });
}
