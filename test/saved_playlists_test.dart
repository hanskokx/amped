import "dart:io";

import "package:amped/src/library/library_view.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/library/saved_playlists.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

const _items = [
  SavedPlaylistItem(
    "/music/a.mp3",
    title: "Artist - A",
    duration: Duration(seconds: 61),
  ),
  SavedPlaylistItem("http://example.com/stream"),
];

void main() {
  group("SqliteTagCache", () {
    test("keeps saved playlists with their entries in order", () async {
      final dir = Directory.systemTemp.createTempSync("saved_playlists_db");
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = "${dir.path}/tags.sqlite";
      final first = await SqliteTagCache.open(path);
      final id = await first.createPlaylist("Road trip", _items);
      final other = await first.createPlaylist("Other", const []);
      await first.renamePlaylist(other, "Renamed");
      await first.deletePlaylist(other);
      await first.close();

      final second = await SqliteTagCache.open(path);
      addTearDown(second.close);
      final playlists = await second.savedPlaylists();
      expect(playlists, hasLength(1));
      expect(playlists.single.id, id);
      expect(playlists.single.name, "Road trip");
      expect(playlists.single.items, _items);
    });

    test("replaces a playlist's entries", () async {
      final dir = Directory.systemTemp.createTempSync("saved_playlists_db");
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = "${dir.path}/tags.sqlite";
      final first = await SqliteTagCache.open(path);
      final id = await first.createPlaylist("Road trip", _items);
      await first.setPlaylistItems(id, [_items.last]);
      await first.close();

      final second = await SqliteTagCache.open(path);
      addTearDown(second.close);
      expect((await second.savedPlaylists()).single.items, [_items.last]);
    });
  });

  group("SavedPlaylists", () {
    test("creates, renames and deletes, keeping them in the store", () async {
      final cache = MemoryTagCache();
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      await saved.open(cache);
      var notified = 0;
      saved.addListener(() => notified++);

      final playlist = await saved.create("Mix", _items);
      expect(saved.playlists.single.name, "Mix");
      expect(cache.playlists[playlist.id]?.items, _items);

      await saved.rename(playlist.id, "Better mix");
      expect(saved.byId(playlist.id)?.name, "Better mix");
      expect(cache.playlists[playlist.id]?.name, "Better mix");

      await saved.delete(playlist.id);
      expect(saved.playlists, isEmpty);
      expect(cache.playlists, isEmpty);
      expect(notified, 3);
    });

    test("moves entries, one place or to where they are dropped", () async {
      final cache = MemoryTagCache();
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      await saved.open(cache);
      final list = await saved.create("Mix", [
        for (final n in ["a", "b", "c", "d"]) SavedPlaylistItem("/$n.mp3"),
      ]);
      List<String> order() =>
          saved.byId(list.id)!.items.map((i) => i.location).toList();

      await saved.move(list.id, [0], 3);
      expect(order(), ["/b.mp3", "/c.mp3", "/a.mp3", "/d.mp3"]);
      await saved.move(list.id, [3, 0], 2);
      expect(order(), ["/c.mp3", "/b.mp3", "/d.mp3", "/a.mp3"]);
      await saved.nudge(list.id, [3], -1);
      expect(order(), ["/c.mp3", "/b.mp3", "/a.mp3", "/d.mp3"]);
      await saved.nudge(list.id, [0], 1);
      expect(order(), ["/b.mp3", "/c.mp3", "/a.mp3", "/d.mp3"]);
      // At an end there is nowhere to go.
      await saved.nudge(list.id, [0], -1);
      await saved.nudge(list.id, [3], 1);
      expect(order(), ["/b.mp3", "/c.mp3", "/a.mp3", "/d.mp3"]);
      expect(cache.playlists[list.id]!.items.map((i) => i.location), order());
    });

    test("duplicates, appends and removes entries in the store", () async {
      final cache = MemoryTagCache();
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      await saved.open(cache);
      final a = await saved.create("Mix", _items);

      final copy = await saved.duplicate(a.id, "Mix copy");
      expect(copy!.name, "Mix copy");
      expect(cache.playlists[copy.id]?.items, _items);
      expect(await saved.duplicate(999, "x"), isNull);

      await saved.append(copy.id, ["/music/b.mp3"]);
      expect(saved.byId(copy.id)!.items.map((i) => i.location), [
        "/music/a.mp3",
        "http://example.com/stream",
        "/music/b.mp3",
      ]);
      expect(saved.byId(a.id)!.items, _items);
      expect(cache.playlists[copy.id]!.items, hasLength(3));

      await saved.removeAt(copy.id, [0, 2]);
      expect(
        saved.byId(copy.id)!.items.single.location,
        "http://example.com/stream",
      );
      expect(cache.playlists[copy.id]!.items, hasLength(1));
    });

    test("loads what the store holds", () async {
      final cache = MemoryTagCache();
      await cache.createPlaylist("Old", _items);
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      await saved.open(cache);
      expect(saved.playlists.single.name, "Old");
    });

    test("works in memory without a store", () async {
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      final a = await saved.create("A", _items);
      final b = await saved.create("B", _items);
      expect(a.id, isNot(b.id));
      expect(saved.playlists, hasLength(2));
    });

    test("exports and imports M3U8 and PLS", () async {
      final dir = Directory.systemTemp.createTempSync("saved_playlists_io");
      addTearDown(() => dir.deleteSync(recursive: true));
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      final playlist = await saved.create("Mix", _items);

      for (final extension in ["m3u", "m3u8", "pls"]) {
        final path = "${dir.path}/Mix.$extension";
        await saved.export(playlist, path);
        final text = await File(path).readAsString();
        expect(text, contains("/music/a.mp3"));
        final imported = await saved.import(path);
        expect(imported?.name, "Mix");
        expect(
          [for (final i in imported!.items) i.location],
          [
            "/music/a.mp3",
            "http://example.com/stream",
          ],
        );
        expect(imported.items.first.title, "Artist - A");
        expect(imported.items.first.duration, const Duration(seconds: 61));
      }
      expect(
        SavedPlaylists.format(playlist, extension: "m3u8"),
        startsWith("﻿#EXTM3U\n#EXTINF:61,Artist - A\n/music/a.mp3\n"),
      );
    });

    test("an empty or missing file imports nothing", () async {
      final saved = SavedPlaylists();
      addTearDown(saved.dispose);
      expect(await saved.import("/does/not/exist.m3u"), isNull);
      expect(saved.playlists, isEmpty);
    });
  });

  group("LibraryView", () {
    final localizations = lookupAppLocalizations(const Locale("en"));
    late SavedPlaylists saved;
    late List<List<String>> played;
    late List<int> menus;
    var savedCurrent = 0;
    var imports = 0;
    var created = 0;
    late List<(int, List<int>)> removed;
    late List<(int, List<int>, int)> moved;
    late List<(int, List<String>)> dropped;

    setUp(() {
      saved = SavedPlaylists();
      played = [];
      menus = [];
      savedCurrent = 0;
      imports = 0;
      created = 0;
      removed = [];
      moved = [];
      dropped = [];
    });
    tearDown(() => saved.dispose());

    Widget host() => _overlaid(
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
                colors: const PlEditConfig(),
                localizations: localizations,
                onPlay: played.add,
                onEnqueue: (_) {},
                onAddMedia: () {},
                onContextMenu: (_) {},
                playlists: saved,
                onSavePlaylist: () => savedCurrent++,
                onImportPlaylists: () => imports++,
                onNewPlaylist: () => created++,
                onRemoveFromPlaylist: (id, indices) =>
                    removed.add((id, indices)),
                onMoveInPlaylist: (id, indices, to) =>
                    moved.add((id, indices, to)),
                onDropOnPlaylist: (id, paths) => dropped.add((id, paths)),
                onPlaylistMenu: menus.add,
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets("lists the saved playlists in the tree", (tester) async {
      await tester.pumpWidget(host());
      expect(find.textContaining("Playlists"), findsOneWidget);
      expect(find.text(localizations.mlSavePlaylistRow), findsOneWidget);
      expect(find.text(localizations.mlImportPlaylistRow), findsOneWidget);

      await tester.runAsync(() => saved.create("Road trip", _items));
      await tester.pump();
      expect(find.text("Road trip"), findsOneWidget);

      await tester.tap(find.text(localizations.mlSavePlaylistRow));
      await tester.tap(find.text(localizations.mlImportPlaylistRow));
      expect(savedCurrent, 1);
      expect(imports, 1);
    });

    testWidgets("shows a playlist's tracks and plays them", (tester) async {
      await tester.runAsync(() => saved.create("Road trip", _items));
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      expect(find.text("Artist - A"), findsOneWidget);
      expect(find.text("1:01"), findsOneWidget);

      await tester.tap(find.text(localizations.play));
      expect(played.single, ["/music/a.mp3", "http://example.com/stream"]);
    });

    testWidgets("the New playlist row asks to create one", (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.text(localizations.mlNewPlaylistRow));
      expect(created, 1);
    });

    testWidgets("Delete removes the selected entries", (tester) async {
      final playlist = await tester.runAsync(
        () => saved.create("Road trip", _items),
      );
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      await tester.tap(find.text("Artist - A"));
      // The row waits out a double-tap before it counts a single one.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(removed.single.$1, playlist!.id);
      expect(removed.single.$2, [0]);
    });

    testWidgets("right-clicking a playlist asks for its menu", (tester) async {
      final playlist = await tester.runAsync(
        () => saved.create("Road trip", _items),
      );
      await tester.pumpWidget(host());
      final gesture = await tester.startGesture(
        tester.getCenter(find.text("Road trip")),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      expect(menus, [playlist!.id]);
    });

    testWidgets("deleting the shown playlist returns to the library", (
      tester,
    ) async {
      final playlist = await tester.runAsync(
        () => saved.create("Road trip", _items),
      );
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      await tester.runAsync(() => saved.delete(playlist!.id));
      await tester.pump();
      expect(find.text(localizations.mlEmpty), findsOneWidget);
    });

    testWidgets("Alt+Down moves the selected entry down", (tester) async {
      final playlist = await tester.runAsync(
        () => saved.create("Road trip", _items),
      );
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      await tester.tap(find.text("Artist - A"));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(moved.single.$1, playlist!.id);
      expect(moved.single.$2, [0]);
      expect(moved.single.$3, 2);
    });

    testWidgets("dragging an entry onto a later one reorders", (tester) async {
      final playlist = await tester.runAsync(
        () => saved.create("Road trip", _items),
      );
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text("Artist - A")),
      );
      await gesture.moveBy(const Offset(0, 5));
      await gesture.moveTo(
        tester.getCenter(find.text("stream")),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(moved.single.$1, playlist!.id);
      expect(moved.single.$2, [0]);
      expect(moved.single.$3, 2);
    });

    testWidgets("dragging an entry onto another playlist adds it", (
      tester,
    ) async {
      final target = await tester.runAsync(() async {
        await saved.create("Road trip", _items);
        return saved.create("Other", const []);
      });
      await tester.pumpWidget(host());
      await tester.tap(find.text("Road trip"));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text("Artist - A")),
      );
      await gesture.moveBy(const Offset(0, 5));
      await gesture.moveTo(tester.getCenter(find.text("Other")));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(dropped.single.$1, target!.id);
      expect(dropped.single.$2, ["/music/a.mp3"]);
    });
  });
}

/// A host with the overlay that dragging a track needs.
Widget _overlaid(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Overlay(
    initialEntries: [OverlayEntry(builder: (context) => child)],
  ),
);
