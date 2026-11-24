import "dart:async";
import "dart:collection";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/foundation.dart";

import "webamp_skin_library.dart";

/// Unpacks the modern skin archive [bytes] into [target]; false when the
/// bytes aren't a modern skin.
typedef SkinUnpackFn = Future<bool> Function(Uint8List bytes, Directory target);

Future<bool> _unpackWasabi(Uint8List bytes, Directory target) async {
  final archive = WasabiArchive.tryOpen(bytes);
  if (archive == null) return false;
  await archive.extractTo(target);
  return true;
}

/// Previews of the library's modern (`.wal`) skins, which have no
/// screenshot: each is downloaded into a temporary folder, unpacked and run
/// on its own.
///
/// A preview is shared by everyone looking at the same skin and kept only
/// while someone is ([acquire] to [release]); the last release disposes it
/// and deletes its folder. [dispose] deletes everything, and [purgeStale]
/// (run when the app starts) removes what a quit or crash left behind.
class ModernPreviewCache {
  ModernPreviewCache(
    this.library, {
    Directory? root,
    this.unpack = _unpackWasabi,
    this.maxConcurrent = 2,
  }) : root = root ?? defaultRoot;

  /// Where previews are unpacked.
  static Directory get defaultRoot =>
      Directory("${Directory.systemTemp.path}/amped_skin_previews");

  /// Deletes every unpacked preview of an earlier run.
  static Future<void> purgeStale({Directory? root}) async {
    final directory = root ?? defaultRoot;
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Object catch (error) {
      Arcane.log(
        "Could not clear the skin preview cache",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "ModernPreviewCache",
      );
    }
  }

  final WebampSkinLibrary library;
  final Directory root;

  /// How a downloaded archive is unpacked.
  final SkinUnpackFn unpack;

  /// How many previews download and load at once.
  final int maxConcurrent;

  final Map<String, _Entry> _entries = {};
  final Queue<Completer<void>> _waiting = Queue();
  int _running = 0;
  int _counter = 0;
  bool _disposed = false;

  /// The preview of [skin], null when it can't be made. Pair every call with
  /// a [release].
  Future<WasabiSkinPreviewController?> acquire(WebampSkin skin) {
    if (_disposed) return Future.value();
    final entry = _entries.putIfAbsent(skin.md5, () {
      final entry = _Entry(skin.md5);
      entry.preview = _load(skin, entry);
      return entry;
    });
    entry.refs++;
    return entry.preview;
  }

  void release(WebampSkin skin) {
    final entry = _entries[skin.md5];
    if (entry == null || --entry.refs > 0) return;
    _entries.remove(skin.md5);
    entry.released = true;
    unawaited(_discard(entry));
  }

  Future<void> _discard(_Entry entry) async {
    final controller = await entry.preview;
    controller?.dispose();
    await _delete(entry.directory);
  }

  /// Disposes every preview and deletes the unpacked files.
  Future<void> dispose() async {
    _disposed = true;
    final entries = _entries.values.toList();
    _entries.clear();
    for (final entry in entries) {
      entry.released = true;
      await _discard(entry);
    }
  }

  Future<void> _delete(Directory? directory) async {
    if (directory == null) return;
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Object catch (error) {
      Arcane.log(
        "Could not delete a skin preview",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "ModernPreviewCache",
      );
    }
  }

  Future<void> _acquireSlot() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _releaseSlot() {
    if (_waiting.isNotEmpty) {
      // The slot passes straight on to the next in line.
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  Future<WasabiSkinPreviewController?> _load(
    WebampSkin skin,
    _Entry entry,
  ) async {
    await _acquireSlot();
    try {
      // Nobody is looking any more (scrolled past while it waited).
      if (entry.released) return null;
      final bytes = await library.download(skin);
      if (entry.released) return null;
      final directory = Directory("${root.path}/${_counter++}");
      entry.directory = directory;
      await directory.create(recursive: true);
      if (!await unpack(bytes, directory) || entry.released) {
        await _delete(directory);
        entry.directory = null;
        return null;
      }
      return WasabiSkinPreviewController(
        directory: directory,
        name: skin.title,
        title: "Amped",
        settings: () async => (null, const <WasabiGammaSet>[]),
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not preview the skin",
        metadata: {"fileName": skin.fileName, "error": "$error"},
        level: Level.warning,
        module: "ModernPreviewCache",
      );
      await _delete(entry.directory);
      entry.directory = null;
      return null;
    } finally {
      _releaseSlot();
    }
  }
}

class _Entry {
  _Entry(this.md5);

  final String md5;
  late final Future<WasabiSkinPreviewController?> preview;
  Directory? directory;
  int refs = 0;
  bool released = false;
}
