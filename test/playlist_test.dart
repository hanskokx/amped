import "dart:io";
import "dart:math";
import "dart:typed_data";

import "package:amped/src/player/playlist.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory dir;

  String file(String name) {
    final f = File("${dir.path}/$name")..createSync(recursive: true);
    return f.path;
  }

  setUp(() => dir = Directory.systemTemp.createTempSync("playlist_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    "move puts an entry at a position, keeping the current and selected",
    () async {
      final names = [
        for (final n in ["a", "b", "c", "d"]) file("$n.mp3"),
      ];
      final playlist = Playlist();
      await playlist.add(names);
      playlist
        ..setCurrent(1)
        ..select({1});

      playlist.move(0, 3);

      expect(playlist.entries.map((e) => e.location), [
        names[1],
        names[2],
        names[3],
        names[0],
      ]);
      expect(playlist.current, 0);
      expect(playlist.selected, {0});

      // Out-of-range moves do nothing.
      playlist.move(0, 9);
      playlist.move(-1, 2);
      expect(playlist.entries.first.location, names[1]);
    },
  );

  test("adds audio files, folders and lists; skips other files", () async {
    final a = file("b/02 Two.mp3");
    final b = file("b/01 One.flac");
    file("b/cover.jpg");
    final c = file("Three.ogg");
    final list = File("${dir.path}/list.m3u")
      ..writeAsStringSync("#EXTM3U\n#EXTINF:10,Three\nThree.ogg\n");
    final playlist = Playlist();

    expect(await playlist.add(["${dir.path}/b", c, list.path]), 0);

    expect(playlist.entries.map((e) => e.location), [b, a, c, c]);
    expect(playlist.entries.first.title, "01 One");
    expect(playlist.current, 0);
  });

  test("a large folder is added in batches, counting what is found", () async {
    for (var i = 0; i < 1200; i++) {
      file("deep/sub${i % 3}/${i.toString().padLeft(4, "0")}.mp3");
    }
    final playlist = Playlist();
    final counts = <int?>[];
    final lengths = <int>[];
    playlist.addListener(() {
      counts.add(playlist.addingCount);
      lengths.add(playlist.length);
    });

    expect(playlist.addingCount, isNull);
    expect(await playlist.add(["${dir.path}/deep"]), 0);

    expect(playlist.length, 1200);
    expect(playlist.addingCount, isNull);
    expect(counts.whereType<int>().reduce(max), 1200);
    // Entries showed up before the scan ended.
    expect(lengths.where((n) => n > 0 && n < 1200), isNotEmpty);
  });

  test("next and previous wrap only as the original does", () async {
    final playlist = Playlist();
    await playlist.add([file("a.mp3"), file("b.mp3"), file("c.mp3")]);
    playlist.setCurrent(2);
    expect(playlist.nextIndex(shuffle: false, repeat: false), -1);
    expect(playlist.nextIndex(shuffle: false, repeat: true), 0);
    playlist.setCurrent(0);
    expect(playlist.previousIndex(shuffle: false), 2);
    expect(playlist.nextIndex(shuffle: true, repeat: false), isNot(0));
  });

  test("removing keeps the current entry current", () async {
    final playlist = Playlist();
    await playlist.add([file("a.mp3"), file("b.mp3"), file("c.mp3")]);
    playlist
      ..setCurrent(2)
      ..select({0});
    final current = playlist.currentEntry;
    playlist.removeSelected();
    expect(playlist.length, 2);
    expect(playlist.currentEntry, same(current));
    expect(playlist.selected, isEmpty);
  });

  test("crop keeps only the selection; invert flips it", () async {
    final playlist = Playlist();
    await playlist.add([file("a.mp3"), file("b.mp3"), file("c.mp3")]);
    playlist
      ..select({1})
      ..invertSelection();
    expect(playlist.selected, {0, 2});
    playlist.crop();
    expect(playlist.entries.map((e) => e.title), ["a", "c"]);
  });

  test("sorts, reverses and removes duplicates", () async {
    final playlist = Playlist();
    final b = file("b.mp3");
    await playlist.add([b, file("a.mp3"), b]);
    playlist.removeDuplicates();
    expect(playlist.length, 2);
    await playlist.sort(PlaylistSort.title);
    expect(playlist.entries.map((e) => e.title), ["a", "b"]);
    playlist.reverse();
    expect(playlist.entries.map((e) => e.title), ["b", "a"]);
  });

  test("compares strings like the classic player's CompareStringLogical", () {
    int cmp(String a, String b) => Playlist.compareLogical(a, b).sign;
    expect(cmp("Track 2", "Track 10"), -1);
    expect(cmp("track 10", "Track 9"), 1);
    expect(cmp("ABC", "abc"), 0);
    expect(cmp("01 x", "1 x"), 0);
    expect(cmp("9", "a"), -1, reason: "digits sort before other characters");
    expect(cmp("ab", "abc"), -1);
    expect(cmp("99999999999999999999 a", "100000000000000000000 a"), -1);
  });

  test("sorts numbers in titles and file names by value", () async {
    final playlist = Playlist();
    await playlist.add([
      file("Track 10.mp3"),
      file("Track 9.mp3"),
      file("track 1.mp3"),
    ]);
    await playlist.sort(PlaylistSort.title);
    expect(playlist.entries.map((e) => e.title), [
      "track 1",
      "Track 9",
      "Track 10",
    ]);
    await playlist.sort(PlaylistSort.fileName);
    expect(playlist.entries.map((e) => e.title), [
      "track 1",
      "Track 9",
      "Track 10",
    ]);
  });

  test("path sort orders by folder, then file name; URLs first", () async {
    final playlist = Playlist();
    await playlist.add([
      file("a/z.mp3"),
      file("ab.mp3"),
      file("a/b.mp3"),
      file("disc 10/1.mp3"),
      file("disc 2/1.mp3"),
      "http://radio.example/stream",
    ]);
    await playlist.sort(PlaylistSort.path);
    final root = dir.path;
    expect(playlist.entries.map((e) => e.location), [
      "http://radio.example/stream",
      "$root/ab.mp3",
      "$root/a/b.mp3",
      "$root/a/z.mp3",
      "$root/disc 2/1.mp3",
      "$root/disc 10/1.mp3",
    ]);
  });

  test("sorting keeps the current entry current", () async {
    final playlist = Playlist();
    await playlist.add([file("c.mp3"), file("a.mp3"), file("b.mp3")]);
    playlist.setCurrent(0);
    await playlist.sort(PlaylistSort.title);
    expect(playlist.currentEntry?.title, "c");
    expect(playlist.current, 2);
  });

  test("sorts long lists in the background, keeping later additions", () async {
    final playlist = Playlist(random: Random(1));
    final numbers = List.generate(5000, (i) => i)..shuffle(Random(2));
    await playlist.add([for (final n in numbers) "http://radio.example/$n"]);
    final sorted = playlist.sort(PlaylistSort.title);
    expect(playlist.sorting, isTrue);
    await playlist.add(["http://late.example/"]);
    await sorted;
    expect(playlist.sorting, isFalse);
    expect(playlist.entries.map((e) => e.location), [
      for (var n = 0; n < 5000; n++) "http://radio.example/$n",
      "http://late.example/",
    ]);
  });

  test("a sort started during another one wins", () async {
    final playlist = Playlist();
    final numbers = List.generate(3000, (i) => i)..shuffle(Random(3));
    await playlist.add([for (final n in numbers) "http://radio.example/$n"]);
    final first = playlist.sort(PlaylistSort.title);
    playlist.reverse();
    // URLs have no artist: every entry ties, so this keeps the reversed order.
    final second = playlist.sort(PlaylistSort.artist);
    await Future.wait([first, second]);
    expect(playlist.entries.map((e) => e.location), [
      for (final n in numbers.reversed) "http://radio.example/$n",
    ]);
    expect(playlist.sorting, isFalse);
  });

  test("sorts by artist, album, and artist and album", () async {
    final playlist = Playlist();
    await playlist.add([
      for (final name in ["1", "2", "3", "4", "5", "6"]) file("$name.mp3"),
    ]);
    // Reads the (empty) files' tags, so they aren't read over ours below.
    await playlist.sort(PlaylistSort.artist);
    final tags = {
      "1": ("Wire", "Pink Flag", 1, 2),
      "2": ("The Cure", "Disintegration", 1, 1),
      "3": (null, null, null, null),
      "4": ("Wire", "Chairs Missing", 1, 1),
      "5": ("cure", "Disintegration", null, null),
      "6": ("Wire", "Pink Flag", 1, 1),
    };
    for (final entry in playlist.entries) {
      final (artist, album, disc, track) = tags[entry.title]!;
      entry
        ..artist = artist
        ..album = album
        ..discNumber = disc
        ..trackNumber = track;
    }
    List<String> order() => [for (final e in playlist.entries) e.title];

    playlist.setCurrent(0); // "1"
    await playlist.sort(PlaylistSort.artist);
    // "The Cure" and "cure" tie; ties keep their order; untagged last.
    expect(order(), ["2", "5", "1", "4", "6", "3"]);
    expect(playlist.currentEntry?.title, "1");

    await playlist.sort(PlaylistSort.album);
    expect(order(), ["4", "2", "5", "6", "1", "3"]);

    await playlist.sort(PlaylistSort.title);
    await playlist.sort(PlaylistSort.artistAlbum);
    expect(order(), ["2", "5", "4", "6", "1", "3"]);
  });

  test('title and file name sorts ignore a leading "The "', () async {
    final playlist = Playlist();
    await playlist.add([
      file("x/The Cure.mp3"),
      file("y/the Beatles.mp3"),
      file("z/Abba.mp3"),
      file("w/Theatre.mp3"),
    ]);
    await playlist.sort(PlaylistSort.title);
    expect(playlist.entries.map((e) => e.title), [
      "Abba",
      "the Beatles",
      "The Cure",
      "Theatre",
    ]);
    await playlist.sort(PlaylistSort.fileName);
    expect(playlist.entries.map((e) => e.title), [
      "Abba",
      "the Beatles",
      "The Cure",
      "Theatre",
    ]);
    await playlist.sort(PlaylistSort.path);
    expect(playlist.entries.map((e) => e.title), [
      "Theatre",
      "The Cure",
      "the Beatles",
      "Abba",
    ]);
  });

  test("reads titles and lengths from m3u and pls", () async {
    final m3u = File("${dir.path}/x.m3u8")
      ..writeAsStringSync(
        "\uFEFF#EXTM3U\r\n#EXTINF:83,Artist - Song\r\na.mp3\r\n"
        "#EXTINF:-1,Stream\r\nhttp://example.com/s\r\n/abs/b.mp3\r\n",
      );
    final items = await Playlist.readList(m3u.path);
    expect(items.map((i) => i.location), [
      "${dir.path}/a.mp3",
      "http://example.com/s",
      "/abs/b.mp3",
    ]);
    expect(items.map((i) => i.title), ["Artist - Song", "Stream", null]);
    expect(items.map((i) => i.duration?.inSeconds), [83, null, null]);

    final pls = File("${dir.path}/x.pls")
      ..writeAsStringSync(
        "[playlist]\nFile1=a.mp3\nTitle1=A\nLength1=5\nFile2=b.mp3\n"
        "NumberOfEntries=2\n",
      );
    final plsItems = await Playlist.readList(pls.path);
    expect(plsItems.map((i) => i.location), [
      "${dir.path}/a.mp3",
      "${dir.path}/b.mp3",
    ]);
    expect(plsItems.first.title, "A");
    expect(plsItems.first.duration, const Duration(seconds: 5));
  });

  test("saves m3u, m3u8 and pls as the original does", () async {
    final a = file("a.wav");
    final b = file("sub/b.wav");
    final playlist = Playlist();
    await playlist.add([a, b]);
    playlist.entries.first
      ..title = "Song A"
      ..duration = const Duration(seconds: 61);

    await playlist.save("${dir.path}/out.m3u");
    expect(
      File("${dir.path}/out.m3u").readAsStringSync(),
      "#EXTM3U\n#EXTINF:61,Song A\n$a\n$b\n",
    );

    await playlist.save("${dir.path}/out.m3u8");
    final m3u8 = File("${dir.path}/out.m3u8").readAsBytesSync();
    expect(m3u8.take(3), [0xEF, 0xBB, 0xBF]);

    await playlist.save("${dir.path}/out.pls");
    expect(
      File("${dir.path}/out.pls").readAsStringSync(),
      "[playlist]\r\nFile1=a.wav\r\nTitle1=Song A\r\nLength1=61\r\n"
      "File2=sub/b.wav\r\nNumberOfEntries=2\r\nVersion=2\r\n",
    );
  });

  test("list titles survive loading; only edits mark it modified", () async {
    final list = File("${dir.path}/l.m3u")
      ..writeAsStringSync("#EXTM3U\n#EXTINF:3,Kept title\na.wav\nb.wav\n");
    file("a.wav");
    file("b.wav");
    final playlist = Playlist();
    expect(await playlist.load(list.path), isTrue);
    expect(playlist.modified, isFalse);
    expect(playlist.entries.first.title, "Kept title");
    expect(playlist.entries.first.duration, const Duration(seconds: 3));
    expect(playlist.entries.last.title, "b");

    playlist
      ..setCurrent(1)
      ..select({0});
    expect(playlist.modified, isFalse);
    playlist.reverse();
    expect(playlist.modified, isTrue);
    await playlist.save("${dir.path}/saved.m3u8");
    expect(playlist.modified, isFalse);
  });

  test("reads the channel count from file headers", () {
    File wav(String name, int channels) {
      final bytes = BytesBuilder()
        ..add("RIFF".codeUnits)
        ..add([36, 0, 0, 0])
        ..add("WAVEfmt ".codeUnits)
        ..add([16, 0, 0, 0, 1, 0, channels, 0])
        ..add([0x44, 0xac, 0, 0, 0, 0, 0, 0, 4, 0, 16, 0])
        ..add("data".codeUnits)
        ..add([0, 0, 0, 0]);
      return File("${dir.path}/$name")..writeAsBytesSync(bytes.toBytes());
    }

    expect(readChannelCount(wav("m.wav", 1).path), 1);
    expect(readChannelCount(wav("s.wav", 2).path), 2);
    // An MP3 frame header: MPEG-1 layer III, 128 kbps, 44.1 kHz, mono.
    final mp3 = File("${dir.path}/m.mp3")
      ..writeAsBytesSync([0xff, 0xfb, 0x90, 0xc4, ...List.filled(64, 0)]);
    expect(readChannelCount(mp3.path), 1);
    final stereo = File("${dir.path}/s.mp3")
      ..writeAsBytesSync([0xff, 0xfb, 0x90, 0x44, ...List.filled(64, 0)]);
    expect(readChannelCount(stereo.path), 2);
    expect(readChannelCount("${dir.path}/missing.mp3"), isNull);
  });

  test("reads FLAC sample rate, length and average bitrate", () {
    // 44.1 kHz, stereo, 16 bits, 441000 samples (10 s).
    const samples = 441000;
    final streamInfo = [
      ...[0, 16, 0, 16], // min/max block size
      ...[0, 0, 0, 0, 0, 0], // min/max frame size
      // Sample rate (20 bits), channels - 1 (3), bits per sample - 1 (5),
      // total samples (36).
      44100 >> 12,
      44100 >> 4 & 0xff,
      (44100 & 0x0f) << 4 | 1 << 1 | 15 >> 4,
      (15 & 0x0f) << 4 | samples >> 32 & 0x0f,
      samples >> 24 & 0xff,
      samples >> 16 & 0xff,
      samples >> 8 & 0xff,
      samples & 0xff,
      ...List.filled(16, 0), // MD5
    ];
    final bytes = BytesBuilder()
      ..add("fLaC".codeUnits)
      ..add([0, 0, 0, 34])
      ..add(streamInfo)
      // A PADDING block, the last one.
      ..add([0x81, 0, 0, 8])
      ..add(List.filled(8, 0));
    // 100000 bytes over 10 s: 80 kbps.
    bytes.add(List.filled(100000 - bytes.length, 0));
    final flac = File("${dir.path}/t.flac")..writeAsBytesSync(bytes.toBytes());

    final info = readFlacStreamInfo(flac.path)!;
    expect(info.sampleRate, 44100);
    expect(info.duration, const Duration(seconds: 10));
    expect(info.bitrate, 80);
    expect(readChannelCount(flac.path), 2);
    expect(readFlacStreamInfo("${dir.path}/missing.flac"), isNull);
  });

  test("reads tags in batches, the current entry first", () async {
    // A minimal FLAC: just STREAMINFO (44.1 kHz, stereo, 16 bits, 1 s).
    final flac = [
      ..."fLaC".codeUnits,
      0x80, 0, 0, 34, // the last block, STREAMINFO
      ...List.filled(10, 0),
      44100 >> 12, 44100 >> 4 & 0xff, (44100 & 0x0f) << 4 | 1 << 1,
      15 << 4, 0, 0, 44100 >> 8, 44100 & 0xff,
      ...List.filled(16, 0),
    ];
    final paths = [
      for (var i = 0; i < 200; i++)
        (File("${dir.path}/$i.flac")..writeAsBytesSync(flac)).path,
    ];
    final playlist = Playlist();
    await playlist.add(paths);
    playlist.setCurrent(199);
    final entries = playlist.entries;
    while (entries[199].sampleRate == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // The track before it is in the last batch, still waiting.
    expect(entries[198].sampleRate, isNull);
    while (entries.any((entry) => entry.sampleRate == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(entries.every((entry) => entry.sampleRate == 44100), isTrue);
  });
}
