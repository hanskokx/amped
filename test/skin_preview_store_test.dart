import "dart:io";

import "package:amped/src/skin/skin_preview_store.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a picture is named by the SHA-256 of the skin archive", () {
    // The previewer computes the same from the file it is asked about.
    expect(
      SkinPreviewStore.keyOf("abc".codeUnits),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
    final store = SkinPreviewStore(Directory("/tmp/previews"));
    expect(store.fileFor("k").path, "/tmp/previews/k.png");
  });

  test("skins in the folders of a skin folder get pictures too", () {
    final root = Directory.systemTemp.createTempSync("skin_folders");
    addTearDown(() => root.deleteSync(recursive: true));
    for (final path in [
      "a.wal",
      "a.txt",
      "Working/b.wal",
      "Working/Old/c.wal",
      "Working/Old/Older/d.wal",
      ".hidden/e.wal",
    ]) {
      File("${root.path}/$path")
        ..createSync(recursive: true)
        ..writeAsStringSync("");
    }

    final names = [
      for (final file in SkinPreviewStore.skinsIn(root))
        file.path.substring(root.path.length + 1),
    ]..sort();
    expect(names, ["Working/Old/c.wal", "Working/b.wal", "a.wal"]);
  });
}
