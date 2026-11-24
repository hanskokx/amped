import "dart:io";
import "dart:typed_data";

/// The file names (without extension) that hold a folder's cover, best
/// first. Compared case-insensitively.
const coverFileNames = [
  "cover",
  "folder",
  "front",
  "albumart",
  "album",
  "albumartsmall",
  "thumb",
];

/// The image extensions looked for, best first.
const coverFileExtensions = ["jpg", "jpeg", "png", "webp", "bmp", "gif"];

/// A side file bigger than this isn't a cover worth loading.
const _maxCoverBytes = 32 * 1024 * 1024;

/// The cover file beside the music file at [path] (`cover.jpg`,
/// `Folder.PNG`, ...), or null when its folder has none.
Future<File?> findCoverFile(String path) async {
  final names = <String, File>{};
  try {
    await for (final entity in Directory(File(path).parent.path).list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      names[name] = entity;
    }
  } on Object {
    return null;
  }
  for (final base in coverFileNames) {
    for (final extension in coverFileExtensions) {
      final file = names["$base.$extension"];
      if (file != null) return file;
    }
  }
  return null;
}

/// The bytes of the cover file beside the music file at [path], or null
/// when there is none or it can't be read.
Future<Uint8List?> readCoverFile(String path) async {
  final file = await findCoverFile(path);
  if (file == null) return null;
  try {
    if (await file.length() > _maxCoverBytes) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } on Object {
    return null;
  }
}
