import "package:amped/src/library/cover_grid.dart";
import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/library_view.dart";
import "package:amped/src/library/library_view_settings.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  final l = lookupAppLocalizations(const Locale("en"));

  const movies = [
    TrackTags(
      "/v/a",
      title: "Heat",
      year: 1995,
      genres: ["Crime", "Drama"],
      duration: Duration(hours: 2, minutes: 50),
    ),
    TrackTags(
      "/v/b",
      title: "Alien",
      year: 1979,
      genres: ["Horror"],
      duration: Duration(hours: 1, minutes: 57),
    ),
  ];
  const episodes = [
    TrackTags(
      "/v/e1",
      artist: "Severance",
      album: "Season 1",
      title: "Good News",
      discNumber: 1,
      trackNumber: 3,
      duration: Duration(minutes: 50),
    ),
    TrackTags(
      "/v/e2",
      artist: "Severance",
      album: "Season 2",
      title: "Hello",
      discNumber: 2,
      trackNumber: 1,
      duration: Duration(minutes: 52),
    ),
  ];

  Future<void> show(
    WidgetTester tester,
    List<TrackTags> videos,
    LibrarySource Function(MediaLibrary library) source,
  ) async {
    final library = MediaLibrary.videos();
    await library.fill((add, _) async => add(videos));
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
                sections: [
                  LibrarySourceSection(
                    id: "videos",
                    kind: LibrarySourceKind.videos,
                    sources: [source(library)],
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
    await tester.tap(find.text("Plex"));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets("movies have video columns, not artist and album", (
    tester,
  ) async {
    await show(
      tester,
      movies,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    for (final heading in [
      l.mlColumnTitle,
      l.mlColumnYear,
      l.mlColumnLength,
      l.mlColumnGenre,
    ]) {
      expect(find.textContaining(heading), findsWidgets, reason: heading);
    }
    expect(find.textContaining(l.mlColumnArtist), findsNothing);
    expect(find.textContaining(l.mlColumnAlbum), findsNothing);
    expect(find.text("1995"), findsOneWidget);
    expect(find.text("Heat"), findsOneWidget);
  });

  testWidgets("episodes have show, season and episode columns", (
    tester,
  ) async {
    await show(
      tester,
      episodes,
      (library) =>
          LibrarySource(id: "s", label: "Plex", library: library, shows: true),
    );
    await tester.tap(find.text("≡"));
    await tester.pump(const Duration(milliseconds: 400));
    for (final heading in [
      l.mlColumnShow,
      l.mlColumnSeason,
      l.mlColumnEpisode,
      l.mlColumnTitle,
    ]) {
      expect(find.textContaining(heading), findsWidgets, reason: heading);
    }
    expect(find.textContaining(l.mlColumnArtist), findsNothing);
    // The title is the episode's own.
    expect(find.text("Good News"), findsOneWidget);
  });

  testWidgets("the movie panels list categories and playlists, and narrow "
      "the movies", (tester) async {
    await show(
      tester,
      movies,
      (library) => LibrarySource(
        id: "m",
        label: "Plex",
        library: library,
        movies: true,
        lists: const {
          "Favourites": ["/v/b"],
        },
      ),
    );
    await tester.tap(find.text("▤"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(l.mlColumnCategory), findsOneWidget);
    expect(find.textContaining(l.mlColumnPlaylist), findsOneWidget);
    expect(find.text("All (3 categories)"), findsOneWidget);
    expect(find.text("All (1 playlist)"), findsOneWidget);
    await tester.tap(find.text("Favourites"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Heat"), findsNothing);
    expect(find.text("Alien"), findsWidgets);
    // Back to everything, then one genre.
    await tester.tap(find.text("All (1 playlist)"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("Crime"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Alien"), findsNothing);
    expect(find.text("Heat"), findsWidgets);
  });

  final watched = [
    TrackTags(
      "/v/old",
      title: "Seen Long Ago",
      progress: 1,
      lastWatched: DateTime.utc(2020),
      published: DateTime.utc(2001),
    ),
    TrackTags(
      "/v/new",
      title: "Seen Lately",
      progress: 0.4,
      lastWatched: DateTime.utc(2025),
      published: DateTime.utc(1999),
    ),
    const TrackTags("/v/never", title: "Never Seen"),
  ];

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text).first).dy;

  testWidgets("movies are ordered by when they were last watched, and "
      "listed by whether they were watched", (tester) async {
    await show(
      tester,
      watched,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    // By name to begin with.
    expect(y(tester, "Never Seen"), lessThan(y(tester, "Seen Lately")));
    await tester.tap(find.textContaining(l.mlVideoSortName));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(l.mlVideoSortWatched), findsOneWidget);
    // The last watched first; what was never watched last.
    expect(y(tester, "Seen Lately"), lessThan(y(tester, "Seen Long Ago")));
    expect(y(tester, "Seen Long Ago"), lessThan(y(tester, "Never Seen")));
    await tester.tap(find.text(l.mlVideoFilterAll));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l.mlVideoFilterInProgress), findsOneWidget);
    expect(find.text("Seen Lately"), findsOneWidget);
    expect(find.text("Seen Long Ago"), findsNothing);
    expect(find.text("Never Seen"), findsNothing);
  });

  testWidgets("movie covers go under the categories, where the list was", (
    tester,
  ) async {
    await show(
      tester,
      movies,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    await tester.tap(find.text("▤"));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("▦"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(l.mlColumnCategory), findsOneWidget);
    final grid = find.byType(CoverGrid);
    expect(grid, findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining(l.mlColumnCategory)).dy,
      lessThan(tester.getTopLeft(grid).dy),
    );
    expect(
      find.descendant(of: grid, matching: find.text("Heat")),
      findsOneWidget,
    );
  });

  testWidgets("show covers fill the show, season and episode panels", (
    tester,
  ) async {
    await show(
      tester,
      episodes,
      (library) =>
          LibrarySource(id: "s", label: "Plex", library: library, shows: true),
    );
    await tester.tap(find.text("▦"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CoverGrid), findsNWidgets(3));
    Finder inGrid(int i, String text) => find.descendant(
      of: find.byType(CoverGrid).at(i),
      matching: find.text(text),
    );
    expect(inGrid(0, "Severance"), findsOneWidget);
    expect(inGrid(1, "Season 1"), findsOneWidget);
    expect(inGrid(1, "Season 2"), findsOneWidget);
    expect(inGrid(2, "Good News"), findsOneWidget);
    // A season narrows the episodes.
    await tester.tap(inGrid(1, "Season 2"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(inGrid(2, "Good News"), findsNothing);
    expect(inGrid(2, "Hello"), findsOneWidget);
  });

  testWidgets("one show or season needs no column to say which", (
    tester,
  ) async {
    await show(
      tester,
      episodes,
      (library) =>
          LibrarySource(id: "s", label: "Plex", library: library, shows: true),
    );
    await tester.tap(find.text("▤"));
    await tester.pump(const Duration(milliseconds: 400));
    // Several shows and seasons: the table's columns say which.
    expect(find.text(l.mlColumnShow), findsOneWidget);
    expect(find.text(l.mlColumnSeason), findsOneWidget);
    await tester.tap(find.text("Severance").first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text("Season 2").first);
    await tester.pump(const Duration(milliseconds: 400));
    // The panels' headings (with their sort arrow) stay; the table's go.
    expect(find.text(l.mlColumnShow), findsNothing);
    expect(find.text(l.mlColumnSeason), findsNothing);
    expect(find.text(l.mlColumnEpisode), findsOneWidget);
  });

  testWidgets("the cover size slider is saved for what is shown", (
    tester,
  ) async {
    final saved = <LibraryViewSettings>[];
    final library = MediaLibrary.videos();
    await library.fill((add, _) async => add(movies));
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
                sections: [
                  LibrarySourceSection(
                    id: "videos",
                    kind: LibrarySourceKind.videos,
                    sources: [
                      LibrarySource(
                        id: "m",
                        label: "Plex",
                        library: library,
                        movies: true,
                      ),
                    ],
                  ),
                ],
                colors: const PlEditConfig(),
                localizations: l,
                onSettingsChanged: saved.add,
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
    await tester.tap(find.text("Plex"));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text("▾"));
    await tester.pump(const Duration(milliseconds: 400));
    // Pressing at the left end of the slider makes the covers smallest.
    final slider = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == "_SizeSlider",
    );
    expect(slider, findsOneWidget);
    final box = tester.getTopLeft(slider);
    await tester.tapAt(box + const Offset(1, 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(saved.last.coverSizes["movies"], CoverGrid.minTileWidth);
  });

  Future<void> hover(
    WidgetTester tester,
    TestGesture mouse,
    Finder finder,
  ) async {
    await mouse.moveTo(tester.getCenter(finder));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets("the layout tooltips say what the media is", (tester) async {
    await show(
      tester,
      movies,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await hover(tester, mouse, find.text("▦"));
    expect(find.text(l.mlLayoutMovieCovers), findsOneWidget);
    await hover(tester, mouse, find.text("▤"));
    expect(find.text(l.mlLayoutMovieCategories), findsOneWidget);
    await hover(tester, mouse, find.text("≡"));
    expect(find.text(l.mlLayoutMovies), findsOneWidget);
  });

  testWidgets("what can be pressed shows the pointing hand", (tester) async {
    await show(
      tester,
      movies,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    for (final target in [
      find.text("▤"),
      find.text("Plex"),
      find.text("Heat"),
    ]) {
      await mouse.moveTo(tester.getCenter(target));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: "$target",
      );
    }
  });

  testWidgets("hide watched leaves out the movies that were watched", (
    tester,
  ) async {
    await show(
      tester,
      watched,
      (library) =>
          LibrarySource(id: "m", label: "Plex", library: library, movies: true),
    );
    expect(find.text("Seen Long Ago"), findsOneWidget);
    await tester.tap(find.text(l.mlHideWatched));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Seen Long Ago"), findsNothing);
    expect(find.text("Seen Lately"), findsOneWidget);
    expect(find.text("Never Seen"), findsOneWidget);
  });

  testWidgets("hide watched takes away watched seasons and shows", (
    tester,
  ) async {
    const seen = [
      TrackTags(
        "/v/s1",
        artist: "Done",
        album: "Season 1",
        title: "Pilot",
        progress: 1,
      ),
      TrackTags(
        "/v/s2",
        artist: "Ongoing",
        album: "Season 1",
        title: "First",
        progress: 1,
      ),
      TrackTags(
        "/v/s3",
        artist: "Ongoing",
        album: "Season 2",
        title: "Second",
      ),
    ];
    await show(
      tester,
      seen,
      (library) =>
          LibrarySource(id: "s", label: "Plex", library: library, shows: true),
    );
    await tester.tap(find.text("▤"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Done"), findsWidgets);
    await tester.tap(find.text(l.mlHideWatched));
    await tester.pump(const Duration(milliseconds: 400));
    // The show whose episodes are all watched is gone, and so is a
    // watched season.
    expect(find.text("Done"), findsNothing);
    expect(find.text("Ongoing"), findsWidgets);
    expect(find.text("Pilot"), findsNothing);
    expect(find.text("First"), findsNothing);
    expect(find.text("Second"), findsWidgets);
  });
}
