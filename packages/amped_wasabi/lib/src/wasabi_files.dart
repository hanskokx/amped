import "dart:io";
import "dart:typed_data";

import "package:archive/archive.dart";

/// Files kept in memory beside the ones on disk: the plugins the app
/// carries inside itself (ClassicPro), which skins reach through the classic player's
/// `@WINAMPPATH@` as if they were in an original install.
///
/// They live under [virtualRoot], a path no disk has, so one `/`-separated
/// string names a file either way and nothing is written to the file
/// system. Names are matched without regard to case, as on the Windows the
/// skins were made on.
final class WasabiFiles {
  const WasabiFiles._();

  /// Where the in-memory files appear to be.
  static const String virtualRoot = "/__winamp__";

  static final Map<String, (String, Uint8List)> _files = {};
  static final Map<String, String> _directories = {};

  /// Whether anything is mounted.
  static bool get mounted => _files.isNotEmpty;

  /// Whether [path] is under [virtualRoot].
  static bool isVirtual(String path) =>
      path == virtualRoot || path.startsWith("$virtualRoot/");

  /// Mounts the files of the zip [bytes] under [virtualRoot].
  static void mountZip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    _directories[virtualRoot.toLowerCase()] = virtualRoot;
    for (final entry in archive) {
      final segments = entry.name
          .replaceAll("\\", "/")
          .split("/")
          .where((s) => s.isNotEmpty && s != "." && s != "..")
          .toList();
      var current = virtualRoot;
      for (var i = 0; i < segments.length; i++) {
        current = "$current/${segments[i]}";
        if (i < segments.length - 1 || !entry.isFile) {
          _directories[current.toLowerCase()] = current;
        }
      }
      if (entry.isFile && segments.isNotEmpty) {
        _files[current.toLowerCase()] = (
          current,
          Uint8List.fromList(entry.content as List<int>),
        );
      }
    }
  }

  /// Forgets every mounted file.
  static void unmount() {
    _files.clear();
    _directories.clear();
  }

  /// [path] with `.` and `..` segments folded away.
  ///
  /// As on Windows, an empty segment (`a//..`) is a level too, which a `..`
  /// removes: the skins write `@COLORTHEMESPATH@\..\..\Plugins`, a folder
  /// name that ends in a separator followed by another.
  static String normalize(String path) {
    final parts = <String>[];
    final segments = path.split("/");
    for (var i = 0; i < segments.length; i++) {
      final part = segments[i];
      if (part == "..") {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part == ".") {
        continue;
      } else if (part.isNotEmpty || (i > 0 && i < segments.length - 1)) {
        parts.add(part);
      }
    }
    return "/${parts.where((p) => p.isNotEmpty).join("/")}";
  }

  /// The file at virtual [path], in the case it was stored in, or null.
  static String? findFile(String path) =>
      _files[normalize(path).toLowerCase()]?.$1;

  /// The folder at virtual [path], in the case it was stored in, or null.
  static String? findDirectory(String path) =>
      _directories[normalize(path).toLowerCase()];

  /// The files directly in virtual folder [path].
  static List<String> filesIn(String path) {
    final folder = normalize(path).toLowerCase();
    return [
      for (final entry in _files.values)
        if (_parent(entry.$1).toLowerCase() == folder) entry.$1,
    ];
  }

  static String _parent(String path) =>
      path.substring(0, path.lastIndexOf("/"));

  /// The bytes of the file at [path], on disk or mounted.
  static Uint8List readBytes(String path) {
    if (!isVirtual(path)) return File(path).readAsBytesSync();
    final entry = _files[normalize(path).toLowerCase()];
    if (entry == null) throw FileSystemException("No such file", path);
    return entry.$2;
  }

  /// [readBytes] without blocking on disk.
  static Future<Uint8List> readBytesAsync(String path) async =>
      isVirtual(path) ? readBytes(path) : await File(path).readAsBytes();

  /// The size of the file at [path].
  static int length(String path) => readBytes(path).length;
}
