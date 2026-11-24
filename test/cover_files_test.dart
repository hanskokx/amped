import "dart:io";

import "package:amped/src/player/cover_files.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("amped_cover"));
  tearDown(() => dir.deleteSync(recursive: true));

  String track() {
    final file = File("${dir.path}/song.mp3")..writeAsBytesSync([1]);
    return file.path;
  }

  void write(String name, [List<int> bytes = const [1, 2, 3]]) =>
      File("${dir.path}/$name").writeAsBytesSync(bytes);

  test("finds nothing without a cover file", () async {
    write("notes.txt");
    expect(await findCoverFile(track()), isNull);
    expect(await readCoverFile(track()), isNull);
  });

  test("finds cover and folder files, whatever their case", () async {
    write("Folder.JPG", [9]);
    expect(await readCoverFile(track()), [9]);
  });

  test("prefers cover over folder, and jpg over png", () async {
    write("folder.jpg", [1]);
    write("cover.png", [2]);
    expect(await readCoverFile(track()), [2]);
    write("cover.jpg", [3]);
    expect(await readCoverFile(track()), [3]);
  });

  test("ignores other images and directories named like covers", () async {
    write("photo.jpg");
    Directory("${dir.path}/cover.jpg").createSync();
    expect(await findCoverFile(track()), isNull);
  });

  test("ignores empty files and a missing folder", () async {
    write("cover.jpg", []);
    expect(await readCoverFile(track()), isNull);
    expect(await readCoverFile("${dir.path}/nope/song.mp3"), isNull);
  });
}
