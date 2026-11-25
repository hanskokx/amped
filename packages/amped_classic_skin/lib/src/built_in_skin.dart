import "package:amped_skin/amped_skin.dart";
import "package:flutter/services.dart";

import "skin_formats.dart";
import "skin_loader.dart";

abstract final class AmpedClassicSkinLoader {
  /// Loads the classic skins bundled with the application.
  ///
  /// Every skin archive in `assets/skins` that [formats] can open is keyed by
  /// its display name, or by its file name when the archive has none. The
  /// base skin archive (the first `.wsz` in the folder, by name) is left out: it
  /// is the fallback beneath other skins. Modern `.wal` skins are not matched
  /// here; [AmpedModernSkinLoader] handles them.
  static Future<Map<String, BuiltInSkin>> loadAssets({
    SkinFormats formats = const SkinFormats(),
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final base = _baseSkinAsset(manifest);
    final skins = <String, BuiltInSkin>{};
    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith("assets/skins/") ||
          !formats.matchesFile(asset) ||
          asset == base) {
        continue;
      }
      final bytes = await _loadAsset(asset);
      final contents = await openSkinArchive(
        bytes,
        formats: formats,
        fileName: asset,
      );
      skins[_skinName(asset, contents)] = BuiltInSkin(
        bytes: bytes,
        format: contents.format,
      );
    }
    return skins;
  }

  /// Loads the built-in base skin from the application's `assets/skins`.
  ///
  /// The base skin is the first `.wsz` archive there, by name.
  ///
  /// Throws a [StateError] when there is no such archive.
  static Future<Uint8List> loadBase() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final base = _baseSkinAsset(manifest);
    if (base == null) {
      throw StateError("No base skin archive in assets/skins");
    }
    return _loadAsset(base);
  }

  static Future<Uint8List> _loadAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Whether [asset] is a classic skin archive in the application's assets.
  static bool _isSkinAsset(String asset) {
    if (!asset.startsWith("assets/skins/")) return false;
    return SkinFileType.zip.matches(asset);
  }

  /// The archive the fallback base skin comes from: the first skin archive in
  /// the assets by name, or null when there is none.
  static String? _baseSkinAsset(AssetManifest manifest) {
    final archives = manifest.listAssets().where(_isSkinAsset).toList()..sort();
    return archives.isEmpty ? null : archives.first;
  }

  /// The name to use for the skin in [asset].
  static String _skinName(String asset, SkinArchiveContents contents) {
    final name = contents.displayName;
    if (name != null && name.isNotEmpty) return name;
    final file = asset.split("/").last;
    for (final type in SkinFileType.values) {
      for (final suffix in type.suffixes) {
        if (file.toLowerCase().endsWith(suffix)) {
          return file.substring(0, file.length - suffix.length);
        }
      }
    }
    return file;
  }
}
