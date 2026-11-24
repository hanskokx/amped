import "dart:io" show Platform;

/// Whether [text] is a URL (`http://...`, `cda://`), which is not a path.
bool _isUrl(String text) => text.contains("://");

/// [path], a file path as a skin script wrote or built it (Windows
/// separators, a separator doubled where a folder name already ended in
/// one), with this system's separator and no doubled ones. A URL stays as
/// it is.
///
/// The scripts of Windows skins say `getPath(file) + "\" + name`; on macOS
/// and Linux that has to reach the player as `/folder/name`.
String wasabiNativePath(String path) {
  if (_isUrl(path)) return path;
  final separator = Platform.pathSeparator;
  final folded = path.replaceAll(RegExp(r"[\\/]+"), separator);
  // A network path (`\\server\share`) keeps its two.
  final network = path.startsWith(r"\\") || path.startsWith("//");
  return network && Platform.isWindows ? "$separator$folded" : folded;
}

/// Whether [a] and [b] name the same path, whatever separators they use
/// (`/Users/x/a.mp3` and `/Users/x/\a.mp3` do, as the scripts build them).
bool wasabiSamePath(String a, String b) {
  if (_isUrl(a) || _isUrl(b)) return a == b;
  String fold(String path) => path.replaceAll(RegExp(r"[\\/]+"), "/");
  return fold(a) == fold(b);
}
