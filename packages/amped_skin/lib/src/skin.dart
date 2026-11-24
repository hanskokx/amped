import "dart:ui";

import "skin_info.dart";
import "skin_window.dart";

/// The skin the app is showing, which says what each of its windows looks
/// like.
///
/// A classic skin draws every window from bitmaps. A modern skin is a Wasabi
/// skin with its own containers and layouts, backed by a classic base skin
/// for the windows it has no look for. Each skin package supplies its own
/// kind.
abstract base class Skin {
  Skin(this.info);

  /// The installed skin this object was loaded from.
  final SkinInfo info;

  /// The skin's display name.
  String get name => info.name;

  bool Function(SkinWindow window) _isShaded = _never;

  static bool _never(SkinWindow window) => false;

  /// Whether the player has [window] in windowshade mode.
  bool isShaded(SkinWindow window) => _isShaded(window);

  /// Tells the skin how to ask whether the player has a window in
  /// windowshade mode, since the skin does not know the player.
  void followShades(bool Function(SkinWindow window) isShaded) =>
      _isShaded = isShaded;

  /// The skin that draws any window this skin has no look for: a classic
  /// skin is its own base.
  Skin get base => this;

  /// Whether the skin has a modern layout for [window], so the window is not
  /// drawn from bitmaps.
  bool hasModernLook(SkinWindow window);

  /// Whether the app's own notification popup stands in for the skin's
  /// notifier: a classic skin has none.
  bool get ownsNotifier;

  /// The `region.txt` section shaping [window] in its current mode, if the
  /// skin format has one for it (main window and equalizer only).
  String? regionKey(SkinWindow window) => switch (window) {
    SkinWindow.main => isShaded(window) ? "mainWs" : "main",
    SkinWindow.eq => isShaded(window) ? "eqWs" : "eq",
    _ => null,
  };

  /// The polygons, in unscaled skin pixels, that cut [window] to its shape,
  /// or null when it is a plain rectangle.
  List<List<Offset>>? shape(SkinWindow window);

  /// The size the main window has when the skin gives it one of its own
  /// (Audacious skins), or null.
  Size? get mainSize;
}
