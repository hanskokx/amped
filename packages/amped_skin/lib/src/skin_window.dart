import "dart:ui";

/// The top-level windows a skin draws: the player's own, and the extra
/// windows a modern skin defines. The same list serves classic and modern
/// skins.
enum SkinWindow {
  main("main"),
  eq("eq"),
  pl("pl"),
  video("video"),
  library("library"),

  /// The Wasabi 3 component bar, shown only by modern skins that have a
  /// `thinger` container.
  thinger("thinger"),

  /// The window visualization plug-ins draw in (an embedded window in the
  /// `gen.bmp` frame), while one runs and is not fullscreen.
  vis("vis"),

  /// The playing item's cover art (Wasabi 5's Album Art window, Alt+A), in
  /// the `gen.bmp` frame for classic skins (gen_classicart) or a modern
  /// skin's `winamp.albumart` container.
  albumArt("albumart"),

  /// A modern skin's pop-up for track changes (Amped Modern's `notifier`
  /// container): shown over the corner of the screen for a few seconds.
  /// Never docks, never takes the keyboard and has no place of its own.
  notifier("notifier"),

  /// Windows a modern skin defines beyond the player's own (Resin's "Color
  /// and Opacity", HARMONIA's control and song display panels, AudioRack's
  /// VU meters): the active skin's other containers, in the order it lists
  /// them. A skin gets as many as there are slots.
  extra0("extra0"),
  extra1("extra1"),
  extra2("extra2"),
  extra3("extra3"),
  extra4("extra4"),
  extra5("extra5");

  const SkinWindow(this.key);

  /// Whether this is one of the slots for a skin's own extra windows.
  bool get isExtra => index >= extra0.index;

  /// The extra window slots.
  static List<SkinWindow> get extras => [
    for (final window in values)
      if (window.isExtra) window,
  ];

  /// The preference-key fragment (`amped.window_<key>_x`, ...).
  final String key;

  /// Whether the user can resize the window from its bottom-right corner.
  bool get resizable =>
      this == pl ||
      this == video ||
      this == library ||
      this == vis ||
      this == albumArt;

  /// The unscaled size of a fixed-size window, or the default size of a
  /// resizable one.
  Size get defaultSize => switch (this) {
    main || eq => const Size(275, 116),
    pl || video => const Size(275, 232),
    vis => const Size(325, 232),
    library => const Size(500, 348),
    // A 256×256 picture inside the frame.
    albumArt => const Size(275, 290),
    thinger => const Size(364, 72),
    notifier => const Size(275, 116),
    extra0 || extra1 || extra2 || extra3 || extra4 || extra5 => const Size(
      275,
      116,
    ),
  };

  /// The least width of [this] when resized: the visualization window's
  /// bottom strip holds five buttons, which need more than the usual 275.
  double get minWidth => this == vis ? 325 : minResizableSize.width;

  /// The smallest size of a resizable window (`do_size` in Peui.cpp/embwnd.cpp).
  static const Size minResizableSize = Size(275, 20 + 38 + 29 + 29);

  /// The windowshade strip height.
  static const double shadeHeight = 14;
}
