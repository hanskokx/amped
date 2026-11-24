import "dart:async";
import "dart:io";
import "dart:math";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/widgets.dart";
import "package:shared_preferences/shared_preferences.dart";

import "media_library.dart";

/// The folders Preferences > Media Library watches. Their audio files are
/// in the Local source, and files that appear, change or go away under
/// them are added, re-read or removed in the background.
class WatchFolders extends ChangeNotifier {
  WatchFolders({
    required this.library,
    this.videos,
    this.settle = const Duration(milliseconds: 750),
    this.retry = const Duration(seconds: 30),
  });

  static const String _key = "amped.watch_folders";

  final MediaLibrary library;

  /// The library of the video files under the folders, when there is one.
  final MediaLibrary? videos;

  List<MediaLibrary> get _libraries => [library, ?videos];

  /// How long the folders must stay quiet before their changes are taken,
  /// so a copy in progress is read once and not on every write.
  final Duration settle;

  /// How long to wait before looking again for a folder that could not be
  /// reached, such as a network share that is not mounted.
  final Duration retry;

  final Map<String, StreamSubscription<FileSystemEvent>> _watches = {};
  final Set<String> _offline = {};
  Timer? _retryTimer;
  final Set<String> _changed = {};
  final Set<String> _gone = {};
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  List<String> _folders = const [];

  /// The watched folders, in the order they were added.
  List<String> get folders => List.unmodifiable(_folders);

  /// Whether [path] is under a watched folder that could not be reached.
  /// Its tracks stay in the library, shown greyed out, until it is back.
  bool isOffline(String path) => _isUnder(path, _offline.toList());

  /// Loads the saved folders, scans them and starts watching.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _folders = [...?prefs.getStringList(_key)];
    if (_disposed) return;
    notifyListeners();
    await Future.wait([for (final folder in _folders) _watch(folder)]);
    await _scan(_folders);
  }

  /// Watches [folder] too, and adds what is in it to the library.
  Future<void> add(String folder) async {
    if (_folders.contains(folder)) return;
    _folders = [..._folders, folder];
    notifyListeners();
    await _save();
    await _watch(folder);
    await _scan([folder]);
  }

  /// Stops watching [folder]. Its tracks stay in the library.
  Future<void> remove(String folder) async {
    if (!_folders.remove(folder)) return;
    _folders = [..._folders];
    await _watches.remove(folder)?.cancel();
    _offline.remove(folder);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _folders);
  }

  /// Adds what [folders] hold now, and forgets the tracks under them whose
  /// files went away while Amped was closed.
  ///
  /// Folders that can't be reached are left alone: their tracks are not
  /// forgotten, as the files are most likely still there.
  Future<void> _scan(List<String> requested) async {
    final folders = await _reachable(requested);
    if (folders.isEmpty) return;
    await _whenIdle(() async {
      for (final library in _libraries) {
        await library.add(folders);
        final missing = await _missing([
          for (final track in library.tracks)
            if (_isUnder(track.path, folders)) track.path,
        ]);
        if (missing.isNotEmpty) await library.remove(missing);
      }
    });
  }

  /// The [folders] that can be reached now. The others are remembered as
  /// offline, and looked for again after [retry].
  Future<List<String>> _reachable(List<String> folders) async {
    final reached = <String>[];
    var changed = false;
    for (final folder in folders) {
      final found = await Directory(folder).exists().timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      if (found) {
        reached.add(folder);
        changed |= _offline.remove(folder);
      } else if (_folders.contains(folder)) {
        changed |= _offline.add(folder);
      }
    }
    if (_disposed) return const [];
    if (changed) notifyListeners();
    if (_offline.isNotEmpty && _retryTimer == null) {
      _retryTimer = Timer(retry, () async {
        _retryTimer = null;
        final back = _offline.toList();
        await Future.wait([for (final folder in back) _watch(folder)]);
        await _scan(back);
      });
    }
    return reached;
  }

  /// The [paths] whose files are gone. The checks are asynchronous and
  /// run a few at a time: on a network share every one is a round trip,
  /// and checking them on the UI thread froze the app.
  static Future<List<String>> _missing(List<String> paths) async {
    const batch = 16;
    final missing = <String>[];
    for (var i = 0; i < paths.length; i += batch) {
      final chunk = paths.sublist(i, min(i + batch, paths.length));
      final found = await Future.wait([
        for (final path in chunk) File(path).exists(),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        if (!found[j]) missing.add(chunk[j]);
      }
    }
    return missing;
  }

  Future<void> _watch(String folder) async {
    if (_watches.containsKey(folder) || !await Directory(folder).exists()) {
      return;
    }
    if (_disposed || _watches.containsKey(folder)) return;
    try {
      _watches[folder] = Directory(folder)
          .watch(recursive: true)
          .listen(_onEvent, onError: (Object error) => _failed(folder, error));
    } on Object catch (error) {
      _failed(folder, error);
    }
  }

  void _failed(String folder, Object error) {
    Arcane.log(
      "Could not watch the folder",
      metadata: {"folder": folder, "error": "$error"},
      level: Level.warning,
      module: "WatchFolders",
    );
    unawaited(_watches.remove(folder)?.cancel());
  }

  void _onEvent(FileSystemEvent event) {
    switch (event) {
      case FileSystemDeleteEvent():
        _gone.add(event.path);
        _changed.remove(event.path);
      case FileSystemMoveEvent(:final destination):
        _gone.add(event.path);
        if (destination != null) {
          _changed.add(destination);
          _gone.remove(destination);
        }
      case FileSystemCreateEvent() || FileSystemModifyEvent():
        _changed.add(event.path);
        _gone.remove(event.path);
    }
    _timer?.cancel();
    _timer = Timer(settle, () => unawaited(flush()));
  }

  /// Takes the changes seen so far into the library.
  @visibleForTesting
  Future<void> flush() => _whenIdle(() async {
    final changed = _changed.toList();
    final gone = _gone.toList();
    _changed.clear();
    _gone.clear();

    for (final library in _libraries) {
      // A deleted or moved folder takes its tracks along.
      final removed = [
        for (final track in library.tracks)
          if (gone.any((path) => _isInside(track.path, path))) track.path,
      ];
      if (removed.isNotEmpty) await library.remove(removed);

      final known = {for (final track in library.tracks) track.path};
      final added = <String>[];
      final edited = <String>[];
      for (final path in changed) {
        if (await FileSystemEntity.isDirectory(path)) {
          added.add(path);
        } else if (!library.accepts(path) || !await File(path).exists()) {
          continue;
        } else if (known.contains(path)) {
          edited.add(path);
        } else {
          added.add(path);
        }
      }
      if (edited.isNotEmpty) await library.refresh(edited);
      if (added.isNotEmpty) await library.add(added);
    }
  });

  /// Runs [action] once nothing else of ours is, and once the library is
  /// not scanning (a scan in progress would drop the call).
  Future<void> _whenIdle(Future<void> Function() action) async {
    while (_busy || _libraries.any((library) => library.scanning)) {
      if (_disposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_disposed) return;
    _busy = true;
    try {
      await action();
    } on Object catch (error) {
      Arcane.log(
        "Watching the folders failed",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "WatchFolders",
      );
    } finally {
      _busy = false;
    }
  }

  static bool _isInside(String path, String folder) =>
      path == folder || path.startsWith("$folder${Platform.pathSeparator}");

  static bool _isUnder(String path, List<String> folders) =>
      folders.any((folder) => _isInside(path, folder));

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _retryTimer?.cancel();
    for (final watch in _watches.values) {
      unawaited(watch.cancel());
    }
    _watches.clear();
    super.dispose();
  }
}

/// Tells the rows below it which tracks are on watched folders that can't be
/// reached, and rebuilds them when that changes.
class OfflineFolders extends InheritedNotifier<WatchFolders> {
  const OfflineFolders({
    required WatchFolders super.notifier,
    required super.child,
    super.key,
  });

  /// Whether the file at [path] is on a folder that can't be reached.
  static bool contains(BuildContext context, String path) =>
      context
          .dependOnInheritedWidgetOfExactType<OfflineFolders>()
          ?.notifier
          ?.isOffline(path) ??
      false;
}
