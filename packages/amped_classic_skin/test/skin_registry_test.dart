import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

Uint8List _encode(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encode(archive));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp("skin_registry_test");
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test("empty registry lists only the bundled base skin", () async {
    final registry = await SkinRegistry.load(tempDir);
    expect(registry.skins.map((s) => s.name), ["Base"]);
    expect(registry.skins.first.isBundled, isTrue);
  });

  test("a zip that is not a skin is refused and installs nothing", () async {
    final registry = await SkinRegistry.load(tempDir);
    final notes = Archive()
      ..addFile(ArchiveFile("notes.txt", 5, utf8.encode("hello")))
      ..addFile(ArchiveFile("main.bmp", 4, utf8.encode("nope")));
    for (final bytes in [
      _encode(Archive()),
      _encode(notes),
      Uint8List.fromList([1, 2, 3]),
    ]) {
      await expectLater(
        registry.importArchive(bytes, fileName: "junk.zip"),
        throwsFormatException,
      );
    }
    expect(registry.skins.map((s) => s.name), ["Base"]);
    expect(tempDir.listSync(), isEmpty);
  });

  test(
    "a folder copied in by hand is named by its skin.xml or folder",
    () async {
      Directory("${tempDir.path}/Plain Folder").createSync();
      Directory("${tempDir.path}/TEST_resin").createSync();
      File("${tempDir.path}/TEST_resin/skin.xml").writeAsStringSync(
        "<WinampAbstractionLayer><skininfo><name>Resin</name></skininfo>"
        "</WinampAbstractionLayer>",
      );
      final registry = await SkinRegistry.load(tempDir);
      expect(
        registry.skins.map((s) => s.name).toSet(),
        {"Base", "Plain Folder", "Resin"},
      );
    },
  );
}
