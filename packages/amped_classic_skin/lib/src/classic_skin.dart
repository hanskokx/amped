import "dart:ui";

import "package:amped_skin/amped_skin.dart";

import "classic_skin_data.dart";

/// A skin drawn from bitmaps: a classic `.wsz`, or Bamp and Audacious zips.
final class ClassicSkin extends Skin {
  ClassicSkin(super.info, this.data);

  /// The loaded bitmaps, regions and settings.
  final ClassicSkinData data;

  @override
  bool hasModernLook(SkinWindow window) => false;

  @override
  bool get ownsNotifier => true;

  @override
  List<List<Offset>>? shape(SkinWindow window) {
    final key = regionKey(window);
    return key == null ? null : data.regions[key]?.polygons;
  }

  @override
  Size? get mainSize => data.mainSize;
}
