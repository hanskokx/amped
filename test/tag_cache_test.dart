import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";

/// A minimal FLAC: just STREAMINFO (44.1 kHz, stereo, 16 bits, 1 s).
final _flac = [
  ..."fLaC".codeUnits,
  0x80, 0, 0, 34, // the last block, STREAMINFO
  ...List.filled(10, 0),
  44100 >> 12, 44100 >> 4 & 0xff, (44100 & 0x0f) << 4 | 1 << 1,
  15 << 4, 0, 0, 44100 >> 8, 44100 & 0xff,
  ...List.filled(16, 0),
];

/// A cache whose every call fails, like a database that broke after opening.
class _BrokenTagCache implements TagCache {
  @override
  Future<Map<String, TrackTags>> lookup(List<String> paths) =>
      Future.error(const TagCacheException("database disk image is malformed"));

  @override
  Future<void> store(List<TrackTags> tags) =>
      Future.error(const TagCacheException("database disk image is malformed"));

  @override
  Future<void> close() async {}
}

void main() {
  late Directory dir;

  String flac(String name) =>
      (File("${dir.path}/$name")..writeAsBytesSync(_flac)).path;

  /// Waits until every tag read [playlist] has started is applied (a tag
  /// sort reads them all and waits for the rest).
  Future<void> settle(Playlist playlist) => playlist.sort(PlaylistSort.artist);

  setUp(() => dir = Directory.systemTemp.createTempSync("tag_cache_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  test("the SQLite cache keeps covers apart from the size limit", () async {
    final cache = await SqliteTagCache.open(":memory:", maxBytes: 1);
    addTearDown(cache.close);
    expect(await cache.storedArtwork("/m/a.wav"), isNull);
    await cache.storeArtwork("/m/a.wav", Uint8List.fromList([1, 2, 3]));
    await cache.store([const TrackTags("/m/a.wav", title: "A")]);
    await cache.storeArtwork("/m/a.wav", Uint8List.fromList([4, 5]));
    expect(await cache.storedArtwork("/m/a.wav"), [4, 5]);
  });

  test("the SQLite cache keeps rows by path and replaces them", () async {
    final cache = await SqliteTagCache.open(":memory:");
    addTearDown(cache.close);
    await cache.store([
      const TrackTags(
        "/m/a.flac",
        artist: "Wire",
        album: "Pink Flag",
        title: "Reuters",
        trackNumber: 1,
        discNumber: 1,
        duration: Duration(milliseconds: 183500),
        bitrate: 900,
        sampleRate: 44100,
        channels: 2,
        genres: ["Punk", "Art Rock"],
      ),
      const TrackTags("/m/b.mp3", title: "Untitled"),
    ]);
    await cache.store([const TrackTags("/m/b.mp3", title: "Field Day")]);

    final rows = await cache.lookup(["/m/a.flac", "/m/b.mp3", "/m/c.ogg"]);

    expect(rows.keys, unorderedEquals(["/m/a.flac", "/m/b.mp3"]));
    final a = rows["/m/a.flac"]!;
    expect(
      (a.artist, a.album, a.title, a.trackNumber, a.discNumber),
      ("Wire", "Pink Flag", "Reuters", 1, 1),
    );
    expect(a.duration, const Duration(milliseconds: 183500));
    expect((a.bitrate, a.sampleRate, a.channels), (900, 44100, 2));
    expect(a.genres, ["Punk", "Art Rock"]);
    expect(rows["/m/b.mp3"]!.genres, isEmpty);
    expect(rows["/m/b.mp3"]!.title, "Field Day");
    expect(rows["/m/b.mp3"]!.artist, isNull);
  });

  test("the SQLite cache removes the oldest rows only when too big", () async {
    final cache = await SqliteTagCache.open(
      "${dir.path}/tags.sqlite",
      maxBytes: 64 * 1024,
    );
    addTearDown(cache.close);
    String path(int i) => "/Volumes/Music/Some Artist/Some Album/$i.flac";
    TrackTags row(int i) =>
        TrackTags(path(i), artist: "Some Artist", title: "Track $i");

    // Well under the limit: everything is kept.
    await cache.store([for (var i = 0; i < 50; i++) row(i)]);
    expect(
      await cache.lookup([for (var i = 0; i < 50; i++) path(i)]),
      hasLength(50),
    );

    for (var batch = 1; batch < 40; batch++) {
      await cache.store([for (var i = 0; i < 50; i++) row(batch * 50 + i)]);
    }
    final all = [for (var i = 0; i < 2000; i++) path(i)];
    final kept = await cache.lookup(all);

    expect(kept.length, lessThan(2000));
    expect(kept.length, greaterThan(100));
    // The newest are kept and the oldest went first.
    expect(kept.containsKey(path(1999)), isTrue);
    expect(kept.containsKey(path(0)), isFalse);
    final oldestKept = all.indexWhere(kept.containsKey);
    expect(kept.length, 2000 - oldestKept);
  });

  test(
    "the SQLite cache keeps the library, and its rows when trimming",
    () async {
      final db = "${dir.path}/library.sqlite";
      final cache = await SqliteTagCache.open(db, maxBytes: 64 * 1024);
      String path(int i) => "/Volumes/Music/Some Artist/Some Album/$i.flac";
      TrackTags row(int i) =>
          TrackTags(path(i), artist: "Some Artist", title: "Track $i");

      await cache.store([row(0)]);
      await cache.addToLibrary([path(0), path(0)]);
      for (var batch = 0; batch < 40; batch++) {
        await cache.store([
          for (var i = 0; i < 50; i++) row(1 + batch * 50 + i),
        ]);
      }
      // Far too much was stored for the oldest row to survive, but it is in
      // the library.
      expect((await cache.lookup([path(0)])).keys, [path(0)]);

      await cache.addToLibrary([path(1)]);
      await cache.removeFromLibrary([path(1)]);
      expect(await cache.libraryPaths(), [path(0)]);
      await cache.close();

      final reopened = await SqliteTagCache.open(db);
      addTearDown(reopened.close);
      expect(await reopened.libraryPaths(), [path(0)]);
    },
  );

  test("a cached entry takes its tags from the cache, not its file", () async {
    final path = flac("a.flac");
    final cache = MemoryTagCache();
    cache.rows[path] = TrackTags(
      path,
      artist: "Cached",
      title: "Song",
      sampleRate: 48000,
    );
    final playlist = Playlist(tagCache: cache);

    await playlist.add([path]);
    await settle(playlist);

    final entry = playlist.entries.single;
    expect(entry.title, "Cached - Song");
    expect(entry.sampleRate, 48000);
    // Reading the file would have cached its 44.1 kHz.
    expect(cache.rows[path]!.sampleRate, 48000);
  });

  test("a file with no cached tags is read, then cached", () async {
    final paths = [for (var i = 0; i < 20; i++) flac("$i.flac")];
    final db = "${dir.path}/tags.sqlite";
    final cache = await SqliteTagCache.open(db);
    final playlist = Playlist(tagCache: cache);

    await playlist.add(paths);
    await settle(playlist);
    expect(playlist.entries.every((e) => e.sampleRate == 44100), isTrue);
    await cache.close();

    // With the files gone, the tags can only come from the cache.
    for (final path in paths) {
      File(path).deleteSync();
    }
    final reopened = await SqliteTagCache.open(db);
    addTearDown(reopened.close);
    final next = Playlist(tagCache: reopened);
    await next.add(paths);
    while (next.entries.any((e) => e.sampleRate == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(next.entries.every((e) => e.channels == 2), isTrue);
  });

  test("the background reader gets cached tags without a sort", () async {
    final paths = [for (var i = 0; i < 1200; i++) "${dir.path}/gone$i.mp3"];
    final cache = MemoryTagCache();
    for (final path in paths) {
      cache.rows[path] = TrackTags(path, sampleRate: 22050);
    }
    // Playlist entries for files that don't exist come from a list.
    final list = File("${dir.path}/list.m3u")
      ..writeAsStringSync(["#EXTM3U", ...paths].join("\n"));
    final playlist = Playlist(tagCache: cache);

    await playlist.load(list.path);
    while (playlist.entries.any((e) => e.sampleRate == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(cache.lookups, hasLength(paths.length));
  });

  test("a file that can't be read is not cached", () async {
    final cache = MemoryTagCache();
    final playlist = Playlist(tagCache: cache);
    final list = File("${dir.path}/list.m3u")
      ..writeAsStringSync("#EXTM3U\n${dir.path}/missing.flac\n");

    await playlist.load(list.path);
    await settle(playlist);

    expect(cache.rows, isEmpty);
  });

  test(
    "Rebuild titles re-reads the selected files and updates the cache",
    () async {
      final a = flac("Reuters.flac");
      final b = flac("Field Day.flac");
      final cache = MemoryTagCache();
      for (final path in [a, b]) {
        cache.rows[path] = TrackTags(
          path,
          artist: "Old",
          title: "Title",
          sampleRate: 48000,
        );
      }
      final list = File("${dir.path}/list.m3u")
        ..writeAsStringSync(
          "#EXTM3U\n#EXTINF:5,Listed A\n$a\n#EXTINF:5,Listed B\n$b\n",
        );
      final playlist = Playlist(tagCache: cache);
      await playlist.load(list.path);
      await settle(playlist);
      expect(playlist.entries.map((e) => e.sampleRate), [48000, 48000]);

      playlist.select({0});
      await playlist.rebuildSelectedTitles();

      final [first, second] = playlist.entries;
      // The FLAC has no title tag, so the title falls back to the file name.
      expect(first.title, "Reuters");
      expect(first.artist, isNull);
      expect(first.sampleRate, 44100);
      expect(first.duration, const Duration(seconds: 1));
      expect(cache.rows[a]!.sampleRate, 44100);
      expect(cache.rows[a]!.artist, isNull);
      expect(playlist.modified, isTrue);
      // The unselected entry is left alone.
      expect(second.title, "Listed B");
      expect(second.sampleRate, 48000);
      expect(cache.rows[b]!.sampleRate, 48000);
    },
  );

  test("playing an entry re-reads its file, storing only changes", () async {
    final path = flac("Reuters.flac");
    final cache = MemoryTagCache();
    cache.rows[path] = TrackTags(path, artist: "Old", sampleRate: 48000);
    final list = File("${dir.path}/list.m3u")
      ..writeAsStringSync("#EXTM3U\n#EXTINF:5,Listed\n$path\n");
    final playlist = Playlist(tagCache: cache);
    await playlist.load(list.path);
    await settle(playlist);
    final entry = playlist.entries.single;
    // The decoder's length, which the re-read keeps.
    playlist.updateEntry(entry, duration: const Duration(seconds: 2));

    await playlist.refreshTags(entry);

    expect(entry.title, "Reuters");
    expect(entry.artist, isNull);
    expect(entry.sampleRate, 44100);
    expect(entry.duration, const Duration(seconds: 2));
    expect(cache.rows[path]!.sampleRate, 44100);
    expect(cache.stores, [path]);

    // Played again, unchanged: the row isn't written.
    await playlist.refreshTags(entry);
    expect(cache.stores, [path]);
  });

  test("edited file tags update the entry and the cache row", () async {
    final inList = flac("a.flac");
    final notInList = flac("b.flac");
    final cache = MemoryTagCache();
    for (final path in [inList, notInList]) {
      cache.rows[path] = TrackTags(path, title: "Old", sampleRate: 48000);
    }
    final playlist = Playlist(tagCache: cache);
    await playlist.add([inList]);
    await settle(playlist);
    expect(playlist.entries.single.title, "Old");

    await playlist.fileTagsChanged(inList);
    await playlist.fileTagsChanged(notInList);

    expect(playlist.entries.single.title, "a");
    expect(playlist.entries.single.sampleRate, 44100);
    expect(cache.rows[inList]!.sampleRate, 44100);
    expect(cache.rows[notInList]!.sampleRate, 44100);
    expect(cache.rows[notInList]!.title, isNull);
  });

  test("a database that can't be opened reads the files instead", () async {
    final db = File("${dir.path}/tags.sqlite")
      ..writeAsStringSync("this is not a SQLite database, " * 100);

    await expectLater(
      SqliteTagCache.open(db.path),
      throwsA(isA<TagCacheException>()),
    );
    final cache = await SqliteTagCache.tryOpen(db.path);
    expect(cache, isNull);

    final playlist = Playlist(tagCache: cache);
    await playlist.add([flac("a.flac")]);
    await settle(playlist);
    expect(playlist.entries.single.sampleRate, 44100);
  });

  test("a cache that fails is dropped and the files are read", () async {
    final playlist = Playlist(tagCache: _BrokenTagCache());

    await playlist.add([flac("a.flac"), flac("b.flac")]);
    await settle(playlist);

    expect(playlist.entries.every((e) => e.sampleRate == 44100), isTrue);
    expect(playlist.tagCache, isNull);
  });
}
