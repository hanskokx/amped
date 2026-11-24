import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:flutter_test/flutter_test.dart";

/// A short silent 16-bit stereo 44.1 kHz WAV with an INFO title.
Uint8List _wav(String title) {
  final pcm = Uint8List(44100); // 0.25 s
  final fmt = ByteData(16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 2, Endian.little)
    ..setUint32(4, 44100, Endian.little)
    ..setUint32(8, 44100 * 4, Endian.little)
    ..setUint16(12, 4, Endian.little)
    ..setUint16(14, 16, Endian.little);
  List<int> le32(int v) => [v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24];
  List<int> chunk(String id, List<int> data) => [
    ...id.codeUnits,
    ...le32(data.length),
    ...data,
    if (data.length.isOdd) 0,
  ];
  final body = [
    ..."WAVE".codeUnits,
    ...chunk("fmt ", fmt.buffer.asUint8List()),
    ...chunk("LIST", [
      ..."INFO".codeUnits,
      ...chunk("INAM", [...title.codeUnits, 0]),
    ]),
    ...chunk("data", pcm),
  ];
  return Uint8List.fromList([...chunk("RIFF", body)]);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("tag_refresh_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  String wav(String name, String title) =>
      (File("${dir.path}/$name")..writeAsBytesSync(_wav(title))).path;

  /// Waits until every tag read [playlist] has started is applied.
  Future<void> settle(Playlist playlist) => playlist.sort(PlaylistSort.artist);

  /// The list an earlier run saved on exit, with [title] as its #EXTINF.
  String savedList(String file, String title) => (File(
    "${dir.path}/Amped.m3u8",
  )..writeAsStringSync("#EXTM3U\n#EXTINF:1,$title\n$file\n")).path;

  test("saving an edit updates the tag cache row", () async {
    final path = wav("a.wav", "Old");
    final cache = MemoryTagCache();
    final playlist = Playlist(tagCache: cache);
    await playlist.add([path]);
    await settle(playlist);
    expect((await cache.lookup([path]))[path]?.title, "Old");

    writeFileTags(path, {TagField.title: "New"});
    await playlist.fileTagsChanged(path);

    expect((await cache.lookup([path]))[path]?.title, "New");
    expect(playlist.entries.single.title, "New");
  });

  test("tags replace stale titles in the restored autosave", () async {
    final path = wav("a.wav", "New");
    final cache = MemoryTagCache();
    await cache.store([TrackTags(path, title: "New")]);
    final list = savedList(path, "Old");

    final playlist = Playlist(tagCache: cache);
    await playlist.load(list, trustListTitles: false);
    await settle(playlist);

    expect(playlist.entries.single.title, "New");
  });

  test(
    "Load list still keeps the list's own titles, as the classic player does",
    () async {
      final path = wav("a.wav", "New");
      final playlist = Playlist(tagCache: MemoryTagCache());
      await playlist.load(savedList(path, "From the list"));
      await settle(playlist);

      expect(playlist.entries.single.title, "From the list");
    },
  );

  test("the startup refresh picks up files changed behind the cache's "
      "back", () async {
    final path = wav("a.wav", "Changed elsewhere");
    final cache = MemoryTagCache();
    await cache.store([TrackTags(path, title: "Cached")]);
    final playlist = Playlist(tagCache: cache);
    await playlist.load(savedList(path, "Cached"), trustListTitles: false);
    await settle(playlist);
    // The cache is trusted at first, so the list shows up fast...
    expect(playlist.entries.single.title, "Cached");

    await playlist.refreshAllTags();

    // ...and then the files are read again.
    expect(playlist.entries.single.title, "Changed elsewhere");
    expect((await cache.lookup([path]))[path]?.title, "Changed elsewhere");
    // The changed title is saved with the list on exit.
    expect(playlist.modified, isTrue);
  });

  test("the refresh leaves unchanged entries and rows alone", () async {
    final path = wav("a.wav", "Same");
    final cache = MemoryTagCache();
    final playlist = Playlist(tagCache: cache);
    await playlist.add([path]);
    await settle(playlist);
    playlist.modified = false;
    final before = (await cache.lookup([path]))[path];

    await playlist.refreshAllTags();

    expect(playlist.modified, isFalse);
    expect((await cache.lookup([path]))[path], before);
  });
}
