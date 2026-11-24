import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";

/// What the app reads from a [Skin] beyond what every skin can be asked.
extension SkinViews on Skin {
  /// This skin as a modern one, or null for a classic skin.
  ModernSkin? get modern {
    final skin = this;
    return skin is ModernSkin ? skin : null;
  }

  /// The windows the skin defines of its own, in their slots.
  List<(SkinWindow, WasabiContainer)> get windows =>
      modern?.windows ?? const [];

  /// The skin's own settings window, when it has one.
  (SkinWindow, WasabiContainer)? get settingsWindow => modern?.settingsWindow;

  /// The Wasabi skin behind this one, or null for a classic skin.
  WasabiSkinData? get wasabi => modern?.data;

  /// The classic skin that draws the windows of this one that have no
  /// modern look (or all of them, for a classic skin).
  ClassicSkinData get classicData => switch (base) {
    ClassicSkin(:final data) => data,
    _ => throw StateError("The base of a skin is a classic skin"),
  };
}
