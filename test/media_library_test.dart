import "dart:io";

import "package:amped/src/library/media_library.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync("library_test");
    for (final name in ["a/one.mp3", "a/two.flac", "b/three.ogg", "b/n.txt"]) {
      File("${dir.path}/$name")
        ..createSync(recursive: true)
        ..writeAsStringSync("x");
    }
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Reads tags from the file name, and records which files it read.
  MediaLibrary make({List<String>? reads}) => MediaLibrary(
    readTags: (files) async {
      reads?.addAll(files);
      return [
        for (final file in files)
          file.endsWith("three.ogg")
              ? null
              : TrackTags(
                  file,
                  artist: file.endsWith("one.mp3") ? "Alpha" : "Beta",
                  album: file.endsWith("one.mp3") ? "First" : "Second",
                  title: file.split("/").last,
                ),
      ];
    },
  );

  test(
    "adds the audio files of a folder, listing unreadable ones too",
    () async {
      final library = make();
      await library.add([dir.path]);
      expect(library.tracks.length, 3);
      expect(library.artists, ["Alpha", "Beta"]);
      expect(library.albums(artist: "Alpha"), ["First"]);
    },
  );

  test("searches artist, album, title and file name", () async {
    final library = make();
    await library.add([dir.path]);
    expect(library.search(query: "alpha first").length, 1);
    expect(library.search(query: "THREE").length, 1);
    expect(library.search(artist: "Alpha").length, 1);
    expect(library.search(album: "Second").length, 1);
    expect(library.search(query: "nothing"), isEmpty);
  });

  test("keeps the tags in the cache and reads each file once", () async {
    final cache = MemoryTagCache();
    final reads = <String>[];
    final library = make(reads: reads);
    await library.open(cache);
    await library.add([dir.path]);
    // The tags went to the cache, the membership to the library table.
    expect(cache.rows.length, 2);
    expect(cache.library.length, 3);

    reads.clear();
    await library.add([dir.path]);
    // Everything is in the library already: nothing is read or added again.
    expect(reads, isEmpty);
    expect(library.tracks, hasLength(3));
    expect(cache.library, hasLength(3));
  });

  test("skips files already in the library, and repeats in one add", () async {
    final reads = <String>[];
    final library = make(reads: reads);
    await library.add(["${dir.path}/a/one.mp3"]);
    reads.clear();
    await library.add([
      "${dir.path}/a/one.mp3",
      "${dir.path}/a/two.flac",
      "${dir.path}/a/two.flac",
      dir.path,
    ]);
    expect(reads.map((r) => r.split("/").last), ["two.flac", "three.ogg"]);
    expect(library.tracks, hasLength(3));
  });

  test("is there on the next start, without reading the files", () async {
    final cache = MemoryTagCache();
    final first = make();
    await first.open(cache);
    await first.add([dir.path]);

    final reads = <String>[];
    final again = make(reads: reads);
    await again.open(cache);
    expect(again.tracks.length, 3);
    expect(again.artists, ["Alpha", "Beta"]);
    // Only the file with no tags is read again.
    expect(reads.map((r) => r.split("/").last), ["three.ogg"]);
  });

  test("removing and clearing update the library table", () async {
    final cache = MemoryTagCache();
    final library = make();
    await library.open(cache);
    await library.add([dir.path]);
    await library.remove(["${dir.path}/a/one.mp3"]);
    expect(library.tracks.length, 2);
    expect(cache.library.length, 2);
    await library.clear();
    expect(library.isEmpty, isTrue);
    expect(cache.library, isEmpty);
  });

  test("refresh reads edited tags again into the cache", () async {
    final cache = MemoryTagCache();
    final library = make();
    await library.open(cache);
    await library.add([dir.path]);
    cache.rows.clear();
    await library.refresh(["${dir.path}/a/one.mp3"]);
    expect(cache.rows.keys, ["${dir.path}/a/one.mp3"]);
  });

  test("works in memory without a cache", () async {
    final library = make();
    await library.add([dir.path]);
    expect(library.tracks.length, 3);
  });

  test(
    "cancel stops a scan after its batch and keeps what was added",
    () async {
      for (var i = 0; i < 100; i++) {
        File("${dir.path}/c/$i.mp3")
          ..createSync(recursive: true)
          ..writeAsStringSync("x");
      }
      late MediaLibrary library;
      var reads = 0;
      library = MediaLibrary(
        readTags: (files) async {
          if (reads++ == 0) library.cancel();
          return [for (final f in files) TrackTags(f, title: f)];
        },
      );
      await library.add(["${dir.path}/c"]);
      expect(library.scanning, isFalse);
      expect(reads, 1);
      expect(library.tracks, hasLength(32));

      // Cancelling with no scan running does nothing to the next one.
      library.cancel();
      await library.add(["${dir.path}/c"]);
      expect(library.tracks, hasLength(100));
    },
  );
}
