import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:archive/archive.dart";

import "xml.dart";

/// A `.wal` archive: a zip holding `skin.xml`, often inside one top folder.
class WasabiArchive {
  WasabiArchive._(this._archive, this._prefix);

  final Archive _archive;

  /// The folder (with trailing `/`) holding `skin.xml`, or empty.
  final String _prefix;

  /// Opens [bytes] as a modern skin, or returns null when the zip has no
  /// `skin.xml` (a classic `.wsz`).
  static WasabiArchive? tryOpen(Uint8List bytes) {
    Archive? archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } on Object {
      archive = null;
    }
    if (archive == null || archive.files.isEmpty) {
      // A download cut short loses the zip's end, where the directory of
      // its files is found; the files themselves are still there.
      archive = _recoverEntries(bytes);
    }
    final prefix = _skinFolder(archive);
    return prefix == null ? null : WasabiArchive._(archive, prefix);
  }

  /// The folder (with trailing `/`) of the shallowest `skin.xml` in
  /// [archive], or null when it has none.
  static String? _skinFolder(Archive archive) {
    String? prefix;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll("\\", "/");
      final lower = name.toLowerCase();
      if (lower == "skin.xml" || lower.endsWith("/skin.xml")) {
        final folder = name.substring(0, name.length - "skin.xml".length);
        if (prefix == null || folder.length < prefix.length) prefix = folder;
      }
    }
    return prefix;
  }

  /// The files of a zip whose directory is missing or damaged, read from
  /// the headers that precede each file's data. A file that cannot be read
  /// (cut short, or a kind of compression other than stored and deflate)
  /// is left out.
  static Archive _recoverEntries(Uint8List bytes) {
    final archive = Archive();
    final data = ByteData.sublistView(bytes);
    var at = 0;
    while (at + 30 <= bytes.length &&
        data.getUint32(at, Endian.little) == 0x04034b50) {
      final flags = data.getUint16(at + 6, Endian.little);
      final method = data.getUint16(at + 8, Endian.little);
      final compressed = data.getUint32(at + 18, Endian.little);
      final nameLength = data.getUint16(at + 26, Endian.little);
      final extraLength = data.getUint16(at + 28, Endian.little);
      final start = at + 30 + nameLength + extraLength;
      // Sizes that come after the data (a data descriptor) cannot be found
      // without the directory.
      if (flags & 8 != 0 || start + compressed > bytes.length) break;
      final name = utf8.decode(
        bytes.sublist(at + 30, at + 30 + nameLength),
        allowMalformed: true,
      );
      final raw = bytes.sublist(start, start + compressed);
      at = start + compressed;
      if (name.endsWith("/")) continue;
      try {
        final content = switch (method) {
          0 => raw,
          8 => Uint8List.fromList(ZLibCodec(raw: true).decode(raw)),
          _ => null,
        };
        if (content != null) archive.add(ArchiveFile.bytes(name, content));
      } on Object {
        continue;
      }
    }
    return archive;
  }

  /// The skin's `<skininfo><name>`, if it has one.
  String? get displayName {
    for (final file in archive.files) {
      final name = file.name.replaceAll("\\", "/");
      if (name.toLowerCase() != "${_prefix}skin.xml".toLowerCase()) continue;
      final text = utf8.decode(file.content as List<int>, allowMalformed: true);
      final match = RegExp(
        r"<name>\s*([^<]*?)\s*</name>",
        caseSensitive: false,
      ).firstMatch(text);
      final value = match?[1];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Archive get archive => _archive;

  /// Writes the skin's files into [target], keeping their folders (relative
  /// to `skin.xml`).
  Future<void> extractTo(Directory target) async {
    for (final file in _archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll("\\", "/");
      if (!name.startsWith(_prefix)) continue;
      final relative = name.substring(_prefix.length);
      final segments = relative
          .split("/")
          .where((s) => s.isNotEmpty && s != "." && s != "..")
          .toList();
      if (segments.isEmpty) continue;
      final out = File([target.path, ...segments].join("/"));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>, flush: true);
    }
  }
}

/// Whether [directory] holds an extracted modern skin (a `skin.xml` whose
/// root is a Wasabi element).
bool isWasabiSkinDirectory(Directory directory) {
  final file = File("${directory.path}/skin.xml");
  if (!file.existsSync()) return false;
  try {
    final nodes = parseXmlFragment(file.readAsStringSync(encoding: latin1));
    return nodes.any(
      (n) => n.tag == "winampabstractionlayer" || n.tag == "wasabixml",
    );
  } on Object {
    return false;
  }
}
