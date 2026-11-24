import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:archive/archive.dart";

/// The application's built-in skin assets, served to tests from fixtures.
final Map<String, Uint8List> builtInSkinAssets = {
  "assets/skins/named.wsz": namedSkinBytes,
  "assets/skins/plain.wsz": unnamedSkinBytes,
  "assets/skins/base-amped.wsz": baseSkinBytes,
  "assets/skins/modern.wal": namedSkinBytes,
  "assets/images/ignored.wsz": unnamedSkinBytes,
  "packages/amped_classic_skin/assets/skins/ignored.wsz": unnamedSkinBytes,
};

/// The base `.wsz` copied from the application's `assets/skins`.
final Uint8List baseSkinBytes = File(
  "test/fixtures/base.wsz",
).readAsBytesSync();

/// An archive with a `skin.xml` display name.
final Uint8List namedSkinBytes = _archive({
  "skin.xml": '<skin id="Test Classic" />',
});

/// An archive without a `skin.xml`, named after its file.
final Uint8List unnamedSkinBytes = _archive({
  "readme.txt": "no skin.xml here",
});

Uint8List _archive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
