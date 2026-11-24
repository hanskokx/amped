import "dart:io";

import "package:archive/archive.dart";

/// The Amped Modern skin the app ships (`assets/skins/Amped-Modern.wal`),
/// extracted to a temporary folder once per test process.
final Directory ampedModern = _extract();

Directory _extract() {
  final wal = File("../../assets/skins/Amped-Modern.wal");
  final directory = Directory.systemTemp.createTempSync("amped_modern");
  final archive = ZipDecoder().decodeBytes(wal.readAsBytesSync());
  for (final entry in archive) {
    if (!entry.isFile) continue;
    File("${directory.path}/${entry.name}")
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.content);
  }
  return directory;
}
