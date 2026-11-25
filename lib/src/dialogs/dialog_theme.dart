import "package:amped_wasabi/amped_wasabi.dart" show wasabiLegible;
import "package:material_ui/material_ui.dart";

/// The app icon's colors, which the app's own windows wear when the skin has
/// none to give them.
abstract final class AppIconColors {
  /// The darkest plum of the icon's background.
  static const background = Color(0xFF1E1125);

  /// The mauve at the light end of the icon's background gradient.
  static const mauve = Color(0xFF90648E);

  /// [mauve] light enough for text and buttons on a dark surface, and as
  /// muted. The generated scheme's own is much brighter.
  static const accent = Color(0xFFC9A0C7);
}

/// The Material theme of the app's own windows: the skin's [accent] on its
/// list [background], and the app icon's colors for the [defaultSkin].
ThemeData dialogTheme({
  required Color background,
  required Color accent,
  bool defaultSkin = false,
}) {
  // A black, white or gray accent has no hue: a scheme seeded with one gets
  // an arbitrary one (black gives pink).
  final hsl = HSLColor.fromColor(accent);
  final iconAccent =
      defaultSkin ||
      hsl.saturation < 0.15 ||
      hsl.lightness < 0.08 ||
      hsl.lightness > 0.95;
  // The skin's hue on a dark surface: a skin's list can be any brightness,
  // and the text of these windows is light.
  final list = HSLColor.fromColor(background);
  final surface = defaultSkin
      ? AppIconColors.background
      : list
            .withLightness(list.lightness.clamp(0.0, 0.16))
            .withSaturation(list.saturation.clamp(0.0, 0.4))
            .toColor();
  final base = ColorScheme.fromSeed(
    seedColor: iconAccent ? AppIconColors.mauve : accent,
    brightness: Brightness.dark,
  );
  // Whatever the skin's colors, text and accents read on the surface.
  final primary = wasabiLegible(
    iconAccent ? AppIconColors.accent : base.primary,
    surface,
    minContrast: 3,
  );
  final scheme = base.copyWith(
    surface: surface,
    onSurface: wasabiLegible(base.onSurface, surface),
    onSurfaceVariant: wasabiLegible(base.onSurfaceVariant, surface),
    primary: primary,
    onPrimary: wasabiLegible(base.onPrimary, primary),
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
  );
}
