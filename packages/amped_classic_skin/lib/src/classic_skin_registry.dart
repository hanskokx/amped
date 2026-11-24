import "dart:typed_data";

import "package:amped_skin/amped_skin.dart";

import "classic_skin_data.dart";
import "skin_formats.dart";
import "skin_loader.dart";

/// How the registry opens and installs classic-format skins.
extension ClassicSkinRegistry on SkinRegistry {
  /// Loads [info] on top of the bundled base skin. A modern skin has no
  /// classic bitmaps, so its windows without a modern look use the base.
  Future<ClassicSkinData> loadSkin(
    SkinInfo info, {
    SkinFormats formats = const SkinFormats(),
  }) async {
    final base = await loadBaseSkin(formats: formats);
    final directory = info.directory;
    if (directory == null || info.modern) return base;
    return loadSkinFromDirectory(
      base,
      directory,
      name: info.name,
      formats: formats,
    );
  }

  /// Extracts a skin archive into the skins directory and returns its
  /// [SkinInfo]. [name] overrides the display name; otherwise the archive's
  /// own name is used, falling back to [fileName] or a generic label.
  ///
  /// The archive's [SkinFormat] is written to the manifest, so a Bamp or
  /// Audacious skin stays identifiable after its files are converted to a
  /// classic file set.
  ///
  /// Throws a [FormatException] when [bytes] is not a skin; nothing is
  /// installed then. Re-importing the same skin replaces its previous folder.
  Future<SkinInfo> importArchive(
    Uint8List bytes, {
    String? name,
    String? fileName,
    SkinFormats formats = const SkinFormats(),
  }) async {
    final SkinArchiveContents contents;
    try {
      contents = await openSkinArchive(
        bytes,
        formats: formats,
        fileName: fileName,
      );
    } on Object {
      throw const FormatException("Not a skin archive");
    }
    if (!isSkinArchive(contents.archive, formats: formats)) {
      throw const FormatException("Not a skin");
    }
    final resolvedName =
        name ?? contents.displayName ?? _labelFromFileName(fileName);
    return installFolder(
      resolvedName,
      (target) => extractSkinFiles(
        contents.archive,
        target,
        formats: formats,
      ),
      format: contents.format,
    );
  }
}

/// Removes the extension [fileName] was imported with, using the same
/// [SkinFileType] enum the loaders match against.
String _labelFromFileName(String? fileName) {
  if (fileName == null) return "Imported Skin";
  final file = fileName.split(RegExp(r"[\\/]")).last;
  for (final type in SkinFileType.values) {
    for (final suffix in type.suffixes) {
      if (file.toLowerCase().endsWith(suffix)) {
        return file.substring(0, file.length - suffix.length);
      }
    }
  }
  return file;
}
