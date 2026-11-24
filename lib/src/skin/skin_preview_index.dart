import "dart:convert";
import "dart:io";

/// What the picture store knows of the skin files it has looked at, kept next
/// to the pictures: a file whose size and modification time are as they were
/// is not read, hashed or drawn again. The file lives in the pictures'
/// versioned folder, so a new picture version starts without it and every
/// skin is looked at once more.
class SkinPreviewIndex {
  SkinPreviewIndex(this.file, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final File file;
  final DateTime Function() _now;
  final Map<String, SkinPreviewEntry> _entries = {};
  bool _dirty = false;

  /// How long a skin that could not be drawn is left alone, unless its file
  /// changes: a failure may only have been the app being busy.
  static const Duration retryFailuresAfter = Duration(days: 7);

  /// Reads the file; a missing or damaged one is an empty index.
  Future<void> load() async {
    _entries.clear();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return;
      for (final MapEntry(:key, :value) in json.entries) {
        final entry = SkinPreviewEntry._fromJson(value);
        if (entry != null) _entries[key] = entry;
      }
    } on Object {
      _entries.clear();
    }
  }

  /// What was found of the skin at [path] if its [size] and [modified] time
  /// are still those it was found with.
  SkinPreviewEntry? lookup(String path, int size, DateTime modified) {
    final entry = _entries[path];
    if (entry == null ||
        entry.size != size ||
        entry.modified != modified.millisecondsSinceEpoch) {
      return null;
    }
    if (!entry.drawn &&
        _now().millisecondsSinceEpoch - entry.checked >
            retryFailuresAfter.inMilliseconds) {
      return null;
    }
    return entry;
  }

  /// Remembers the skin at [path]: [key] is its archive's hash, [drawn]
  /// whether its picture was made.
  void record(
    String path,
    int size,
    DateTime modified,
    String key, {
    required bool drawn,
  }) {
    _entries[path] = SkinPreviewEntry._(
      size: size,
      modified: modified.millisecondsSinceEpoch,
      key: key,
      drawn: drawn,
      checked: _now().millisecondsSinceEpoch,
    );
    _dirty = true;
  }

  /// Writes what changed since the last [load] or [save].
  Future<void> save() async {
    if (!_dirty) return;
    _dirty = false;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({for (final e in _entries.entries) e.key: e.value._toJson()}),
      flush: true,
    );
  }
}

/// A skin file as the index remembers it.
class SkinPreviewEntry {
  const SkinPreviewEntry._({
    required this.size,
    required this.modified,
    required this.key,
    required this.drawn,
    required this.checked,
  });

  final int size;

  /// Milliseconds since the epoch.
  final int modified;

  /// The SHA-256 of the archive, the name of its picture.
  final String key;

  /// Whether the picture was made.
  final bool drawn;

  /// When it was looked at, in milliseconds since the epoch.
  final int checked;

  static SkinPreviewEntry? _fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final size = json["size"], modified = json["modified"];
    final key = json["key"], drawn = json["drawn"], checked = json["checked"];
    if (size is int &&
        modified is int &&
        key is String &&
        drawn is bool &&
        checked is int) {
      return SkinPreviewEntry._(
        size: size,
        modified: modified,
        key: key,
        drawn: drawn,
        checked: checked,
      );
    }
    return null;
  }

  Map<String, Object?> _toJson() => {
    "size": size,
    "modified": modified,
    "key": key,
    "drawn": drawn,
    "checked": checked,
  };
}
