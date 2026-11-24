import "dart:async";
import "dart:io";
import "dart:isolate";

import "package:amped_logging/amped_logging.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:crypto/crypto.dart";
import "package:flutter/foundation.dart";

import "skin_preview_index.dart";
import "skin_preview_renderer.dart";

/// The pictures of modern skins as the app draws them, kept where the file
/// manager previews (Quick Look) can read them: they cannot run a skin's
/// scripts, so a skin they have no picture of is drawn by their own, simpler
/// renderer.
///
/// A picture is named by the SHA-256 of the skin's archive, which the
/// previewer computes from the file it is asked about.
class SkinPreviewStore {
  SkinPreviewStore(this.directory, {this.whenIdle})
    : _index = SkinPreviewIndex(File("${directory.path}/index.json"));

  final Directory directory;

  /// Completes when the app is quiet enough to draw: drawing a skin runs its
  /// scripts on the UI thread, so it waits for the person to stop using the
  /// app, before each skin and before each step of drawing one.
  final Future<void> Function()? whenIdle;

  final SkinPreviewIndex _index;
  Future<void>? _indexLoaded;

  /// Names the folder of the pictures; changes when how the app draws a skin
  /// does, so pictures drawn the old way are drawn again. The Quick Look
  /// extension reads the same folder (`AmpedSkinImage.m`) and shows the
  /// previous version's picture until the new one is made: when this changes,
  /// add the old name to the list there.
  static const String version = "v4";

  final Set<String> _folders = {};
  Future<void> _queue = Future.value();

  /// The key of the skin archive [bytes].
  static String keyOf(List<int> bytes) => sha256.convert(bytes).toString();

  File fileFor(String key) => File("${directory.path}/$key.png");

  /// Makes the pictures of the modern skins in [folder] that have none,
  /// one after the other. A folder is looked at once a run.
  Future<void> indexFolder(Directory folder) {
    if (!_folders.add(folder.path)) return _queue;
    return _queue = _queue.then((_) => _makeAll(folder));
  }

  /// How long after the app starts the pictures begin to be made: drawing a
  /// skin runs its scripts on the UI thread, which should not compete with
  /// the app opening.
  static const Duration startDelay = Duration(seconds: 30);

  /// The `.wal` skins in [folder] and the folders in it, [depth] levels down:
  /// skins are kept in sorted subfolders ("Working", "Favorites"), and the
  /// previews are asked for by whatever file is looked at.
  @visibleForTesting
  static List<File> skinsIn(Directory folder, {int depth = 2}) {
    final skins = <File>[];
    for (final entity in folder.listSync()) {
      if (entity is File) {
        if (entity.path.toLowerCase().endsWith(".wal")) skins.add(entity);
      } else if (entity is Directory && depth > 0) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith(".")) {
          skins.addAll(skinsIn(entity, depth: depth - 1));
        }
      }
    }
    return skins;
  }

  Future<void> _makeAll(Directory folder) async {
    await Future<void>.delayed(startDelay);
    final List<File> skins;
    try {
      skins = skinsIn(folder);
    } on FileSystemException {
      return;
    }
    // A folder of thousands is not a skin folder to go through.
    if (skins.length > 400) return;
    await (_indexLoaded ??= _index.load());
    for (final skin in skins) {
      var worked = false;
      try {
        worked = await _makeFor(skin);
      } on Object catch (error) {
        Arcane.log(
          "Could not make a preview",
          metadata: {"path": skin.path, "error": "$error"},
          level: Level.warning,
          module: "SkinPreviewStore",
        );
      }
      // Let the app breathe after a skin that was read or drawn; one that was
      // already known cost a look at its file's size and date.
      if (worked) {
        // Kept as it goes: the app may be quit before the folder is done.
        await _index.save();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// The SHA-256 of the file at [path], read and hashed off the UI thread.
  static Future<String> _hashOf(String path) => Isolate.run(
    () => sha256.convert(File(path).readAsBytesSync()).toString(),
  );

  /// Makes the picture of [archive] unless it is there, or its file is as it
  /// was when it was looked at. Whether it read the file.
  Future<bool> _makeFor(File archive) async {
    final stat = await archive.stat();
    final known = _index.lookup(archive.path, stat.size, stat.modified);
    if (known != null && (!known.drawn || fileFor(known.key).existsSync())) {
      return false;
    }
    final key = await _hashOf(archive.path);
    if (fileFor(key).existsSync()) {
      _index.record(archive.path, stat.size, stat.modified, key, drawn: true);
      return true;
    }
    await whenIdle?.call();
    final bytes = Uint8List.fromList(await archive.readAsBytes());
    final wal = WasabiArchive.tryOpen(bytes);
    var drawn = false;
    if (wal != null) {
      final temp = await Directory.systemTemp.createTemp("amped_skin_preview");
      try {
        await wal.extractTo(temp);
        final png = await SkinPreviewRenderer.render(
          temp,
          name: wal.displayName,
          whenIdle: whenIdle,
        );
        if (png != null) {
          await directory.create(recursive: true);
          await fileFor(key).writeAsBytes(png, flush: true);
          drawn = true;
        }
      } finally {
        unawaited(temp.delete(recursive: true).catchError((_) => temp));
      }
    }
    _index.record(archive.path, stat.size, stat.modified, key, drawn: drawn);
    return true;
  }
}
