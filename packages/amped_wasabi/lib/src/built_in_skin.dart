import "package:amped_skin/amped_skin.dart";
import "package:flutter/services.dart";

import "wasabi_archive.dart";

abstract final class AmpedModernSkinLoader {
  /// Loads the built-in modern skins bundled with the application.
  ///
  /// Every `.wal` asset in the application's `assets/skins` folder is keyed by
  /// its `<skininfo><name>`, or by its file name when the archive declares no
  /// name. The archive bytes travel with their [SkinFormat] so the composition
  /// root does not have to guess which renderer they belong to.
  static Future<Map<String, BuiltInSkin>> loadAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final skins = <String, BuiltInSkin>{};
    for (final asset in manifest.listAssets()) {
      if (!_isSkinAsset(asset)) continue;
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      skins[WasabiArchive.tryOpen(bytes)?.displayName ?? _assetName(asset)] =
          BuiltInSkin(bytes: bytes, format: SkinFormat.wasabi);
    }
    return skins;
  }

  /// Whether [asset] is a modern skin archive in the application's assets.
  static bool _isSkinAsset(String asset) =>
      asset.startsWith("assets/skins/") && SkinFileType.wal.matches(asset);

  /// The name to use for [asset] when its archive declares none.
  static String _assetName(String asset) {
    final file = asset.split("/").last;
    for (final suffix in SkinFileType.wal.suffixes) {
      if (file.toLowerCase().endsWith(suffix)) {
        return file.substring(0, file.length - suffix.length);
      }
    }
    return file;
  }
}
