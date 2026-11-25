import "dart:io";
import "dart:typed_data";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.addFile(ArchiveFile.string(key, value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  final skin = _zip({
    "Skin/skin.xml":
        "<WinampAbstractionLayer><skininfo><name>Cut Short</name> "
        "</skininfo></WinampAbstractionLayer>",
    "Skin/xml/player.xml": "<container id='main'/>" * 40,
  });

  test("a skin archive is opened", () {
    expect(WasabiArchive.tryOpen(skin)?.displayName, "Cut Short");
  });

  test("a skin archive that was cut short is still opened", () async {
    // The end of a zip, where the directory of its files is, went missing.
    final cut = Uint8List.sublistView(skin, 0, skin.length - 40);
    final archive = WasabiArchive.tryOpen(cut);
    expect(archive, isNotNull);
    expect(archive!.displayName, "Cut Short");

    final directory = await Directory.systemTemp.createTemp("wasabi_archive");
    addTearDown(() => directory.delete(recursive: true));
    await archive.extractTo(directory);
    expect(
      File("${directory.path}/xml/player.xml").readAsStringSync(),
      "<container id='main'/>" * 40,
    );
  });

  test("bytes that are no skin are not opened", () {
    expect(WasabiArchive.tryOpen(Uint8List(300)), isNull);
    expect(
      WasabiArchive.tryOpen(_zip({"main.bmp": "not a modern skin"})),
      isNull,
    );
  });
}
