import "dart:convert";
import "dart:io";

import "skin_format.dart";
import "skin_info.dart";

/// The name of the built-in base skin in [skins].
const String baseSkinName = "Amped Classic";

/// What [baseSkinName] used to be, which a saved choice of skin may still say.
const String legacyBaseSkinName = "Base";

/// Indexes the installed skins in a directory.
///
/// The registry scans [Directory] subfolders for extracted skins; each
/// folder may carry a `manifest.json` written by [SkinRegistry.installFolder]
/// with the skin's display name and [SkinFormat]. Folders holding a `skin.xml`
/// without a manifest are modern (`.wal`) skins. Each skin package adds how to
/// open its own format to the registry. The bundled base skin is always
/// listed.
class SkinRegistry {
  SkinRegistry._(this._directory, List<SkinInfo> skins)
    : _skins = List<SkinInfo>.of(skins);

  /// Directory the imported skins live in.
  final Directory _directory;

  final List<SkinInfo> _skins;

  static const String manifestName = "manifest.json";

  /// Scans [directory] for imported skins. The directory is created if it
  /// does not exist yet.
  static Future<SkinRegistry> load(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return SkinRegistry._(directory, _scan(directory));
  }

  static List<SkinInfo> _scan(Directory directory) {
    final result = <SkinInfo>[
      const SkinInfo(name: baseSkinName),
    ];
    for (final entity in directory.listSync()) {
      if (entity is! Directory) continue;
      final name = _displayNameFor(entity);
      final manifest = _manifestOf(entity);
      final modern = File(
        entity.uri.resolve("skin.xml").toFilePath(),
      ).existsSync();
      // A skin converted from another format records its origin in the
      // manifest. Folders copied in by hand can only be told apart by the
      // presence of skin.xml.
      final format =
          _formatOf(manifest) ??
          (modern ? SkinFormat.wasabi : SkinFormat.classic);
      final builtIn = manifest["builtIn"] is String;
      result.add(
        SkinInfo(
          name: name,
          directory: entity,
          format: format,
          builtIn: builtIn,
        ),
      );
    }
    return result;
  }

  static SkinFormat? _formatOf(Map<String, dynamic> manifest) {
    final value = manifest["format"];
    if (value is! String) return null;
    for (final format in SkinFormat.values) {
      if (format.name == value) return format;
    }
    return null;
  }

  static Map<String, dynamic> _manifestOf(Directory directory) {
    final manifest = File(
      directory.uri.resolve(manifestName).toFilePath(),
    );
    if (manifest.existsSync()) {
      try {
        final map = jsonDecode(manifest.readAsStringSync());
        if (map is Map<String, dynamic>) return map;
      } on FormatException {
        // no manifest to go by
      }
    }
    return const {};
  }

  static String _displayNameFor(Directory directory) {
    final name = _manifestOf(directory)["name"];
    if (name is String && name.isNotEmpty) return name;
    // A folder copied in by hand has no manifest: a modern skin names itself
    // in its skin.xml, any other is called after its folder. (A directory
    // URI ends in a slash, so its last path segment is empty.)
    final skinXml = File(directory.uri.resolve("skin.xml").toFilePath());
    if (skinXml.existsSync()) {
      try {
        final match = RegExp(
          r"<name>\s*([^<]*?)\s*</name>",
          caseSensitive: false,
        ).firstMatch(skinXml.readAsStringSync());
        final value = match?[1];
        if (value != null && value.isNotEmpty) return value;
      } on FileSystemException {
        // fall back to the folder name
      }
    }
    return directory.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => "Imported Skin",
    );
  }

  /// The version a built-in skin was installed at (its manifest's
  /// `builtIn`), or null for user skins and missing ones.
  String? builtInVersion(String name) {
    final directory = byName(name)?.directory;
    if (directory == null) return null;
    final version = _manifestOf(directory)["builtIn"];
    return version is String ? version : null;
  }

  /// Repairs the manifests of installed skins that predate the `format`
  /// field. [detect] is handed the lower-case names of a skin's files and
  /// returns the family they belong to.
  ///
  /// Skins that already record a format, and skins whose names reveal no
  /// different family, are left untouched. Returns how many manifests were
  /// updated.
  Future<int> migrateFormats(
    SkinFormat Function(Set<String> names) detect,
  ) async {
    var repaired = 0;
    for (final info in [..._skins]) {
      final directory = info.directory;
      // A hand-copied modern skin has no manifest either, but skin.xml
      // already identifies it, so it must not be rewritten as classic.
      if (directory == null || info.format != SkinFormat.classic) continue;
      final manifest = _manifestOf(directory);
      if (_formatOf(manifest) != null) continue;
      final names = {
        for (final entity in directory.listSync())
          if (entity is File) entity.uri.pathSegments.last.toLowerCase(),
      };
      final detected = detect(names);
      if (detected == SkinFormat.classic) continue;
      await File(
        directory.uri.resolve(manifestName).toFilePath(),
      ).writeAsString(
        jsonEncode({...manifest, "format": detected.name}),
        flush: true,
      );
      _skins[_skins.indexOf(info)] = SkinInfo(
        name: info.name,
        directory: directory,
        format: detected,
        builtIn: info.builtIn,
      );
      repaired++;
    }
    return repaired;
  }

  /// The installed skins, base first, in scan order.
  List<SkinInfo> get skins => List<SkinInfo>.unmodifiable(_skins);

  SkinInfo? byName(String name) {
    for (final info in _skins) {
      if (info.name == name) return info;
    }
    return null;
  }

  /// Deletes the imported skin [info] from the skins directory. Skins that
  /// ship with the app (the base skin, built-in skins) cannot be removed.
  Future<void> remove(SkinInfo info) async {
    final directory = info.directory;
    // Skins that ship with the app (base, built-in) stay.
    if (directory == null || info.isBundled) return;
    if (await directory.exists()) await directory.delete(recursive: true);
    _skins.removeWhere((s) => s.name == info.name);
  }

  /// Drops [info] from the list without touching its files.
  void forget(SkinInfo info) => _skins.removeWhere((s) => s.name == info.name);

  /// Installs a skin whose files [extract] writes into a fresh folder named
  /// after [name] (replacing an earlier copy), for a skin format to unpack itself.
  Future<SkinInfo> installFolder(
    String name,
    Future<void> Function(Directory target) extract, {
    SkinFormat format = SkinFormat.classic,
    String? builtInVersion,
  }) async {
    final target = Directory(
      _directory.uri.resolve("${_safeFolderName(name)}/").toFilePath(),
    );
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    await extract(target);
    await File(target.uri.resolve(manifestName).toFilePath()).writeAsString(
      jsonEncode({
        "name": name,
        "format": format.name,
        "importedAt": DateTime.now().toIso8601String(),
        "builtIn": ?builtInVersion,
      }),
      flush: true,
    );
    final info = SkinInfo(
      name: name,
      directory: target,
      format: format,
      builtIn: builtInVersion != null,
    );
    _skins.removeWhere((s) => s.name == info.name);
    _skins.add(info);
    return info;
  }
}

/// Keeps folder names filesystem-safe while staying human readable.
String _safeFolderName(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r"[^A-Za-z0-9_. -]"), "_");
  if (cleaned.isEmpty) return "skin";
  return cleaned;
}
