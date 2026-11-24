import "dart:io";

import "package:amped/src/library/media_library.dart";
import "package:amped/src/library/watch_folders.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  late Directory dir;
  late MediaLibrary library;
  late WatchFolders watch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync("watch_test");
    File("${dir.path}/old.mp3").writeAsStringSync("x");
    library = MediaLibrary(
      readTags: (files) async => [for (final f in files) TrackTags(f)],
    );
    watch = WatchFolders(
      library: library,
      settle: const Duration(milliseconds: 50),
    );
  });

  tearDown(() {
    watch.dispose();
    library.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Waits until [done] holds, or fails.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue);
  }

  test("adds a watched folder's files and remembers the folder", () async {
    await watch.add(dir.path);
    expect(library.tracks.map((t) => t.path), ["${dir.path}/old.mp3"]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList("amped.watch_folders"), [dir.path]);
  });

  test("picks up new files, subfolders and deletions", () async {
    await watch.add(dir.path);
    File("${dir.path}/new.flac").writeAsStringSync("x");
    await until(() => library.tracks.length == 2);

    Directory("${dir.path}/sub").createSync();
    File("${dir.path}/sub/deep.ogg").writeAsStringSync("x");
    await until(() => library.tracks.length == 3);

    File("${dir.path}/old.mp3").deleteSync();
    await until(() => library.tracks.length == 2);

    Directory("${dir.path}/sub").deleteSync(recursive: true);
    await until(() => library.tracks.length == 1);
  });

  test("ignores files that are not audio", () async {
    await watch.add(dir.path);
    File("${dir.path}/notes.txt").writeAsStringSync("x");
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(library.tracks.length, 1);
  });

  test("stops watching a removed folder and restores saved ones", () async {
    await watch.add(dir.path);
    await watch.remove(dir.path);
    File("${dir.path}/late.mp3").writeAsStringSync("x");
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(library.tracks.length, 1);
    expect(watch.folders, isEmpty);

    SharedPreferences.setMockInitialValues({
      "amped.watch_folders": [dir.path],
    });
    final again = WatchFolders(library: library);
    await again.restore();
    expect(library.tracks.length, 2);
    again.dispose();
  });

  test("restore forgets tracks deleted while closed", () async {
    await library.add([dir.path]);
    File("${dir.path}/old.mp3").deleteSync();
    SharedPreferences.setMockInitialValues({
      "amped.watch_folders": [dir.path],
    });
    final again = WatchFolders(library: library);
    await again.restore();
    expect(library.tracks, isEmpty);
    again.dispose();
  });

  test("keeps the tracks of a folder that can't be reached", () async {
    final share = Directory("${dir.path}/share")..createSync();
    final track = "${share.path}/song.mp3";
    File(track).writeAsStringSync("x");
    await library.add([share.path]);
    SharedPreferences.setMockInitialValues({
      "amped.watch_folders": [share.path],
    });
    // The share goes away, as an unmounted network share does.
    share.deleteSync(recursive: true);

    final again = WatchFolders(
      library: library,
      retry: const Duration(milliseconds: 50),
    );
    await again.restore();
    expect(library.tracks.map((t) => t.path), [track]);
    expect(again.isOffline(track), isTrue);

    // It is back: it is scanned again and no longer offline.
    share.createSync();
    File(track).writeAsStringSync("x");
    await until(() => !again.isOffline(track));
    expect(library.tracks.map((t) => t.path), [track]);
    again.dispose();
  });
}
