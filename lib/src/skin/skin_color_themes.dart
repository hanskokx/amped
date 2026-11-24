import "dart:convert";

import "package:amped_logging/amped_logging.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../app/modern_host.dart";

/// Persists the color theme choices of modern skins.
///
/// The selected theme is stored in the same private Wasabi section the modern
/// shell host reads, so a skin comes back the way the user left it. Custom
/// themes live alongside it, keyed by skin name.
final class SkinColorThemes {
  /// Creates the color-theme store.
  const SkinColorThemes();

  /// The color theme the user last switched the modern skin [skinName] to.
  Future<String?> savedTheme(String skinName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? read(String key) => prefs.getString(
        ShellWasabiHost.privateKey(wasabiColorThemesSection, key),
      );
      final bool shared = read(wasabiShareColorThemeKey) != "0";
      return read(shared ? wasabiSharedColorThemeKey : skinName) ??
          read(skinName);
    } on Object {
      return null;
    }
  }

  /// The custom color themes the user made for the modern skin [skinName].
  Future<List<WasabiGammaSet>> savedCustomThemes(String skinName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_customThemesKey(skinName));
      if (json == null) return const [];
      final list = jsonDecode(json);
      if (list is! List) return const [];
      return [
        for (final item in list) ?WasabiGammaSet.fromJson(item),
      ];
    } on Object {
      return const [];
    }
  }

  /// Keeps [theme] as the color theme of the modern skin [skinName], with the
  /// user's own themes [customs].
  Future<void> persist(
    String skinName, {
    required String? theme,
    required List<WasabiGammaSet> customs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _customThemesKey(skinName),
        jsonEncode([for (final set in customs) set.toJson()]),
      );
      if (theme != null) {
        await prefs.setString(
          ShellWasabiHost.privateKey(wasabiColorThemesSection, skinName),
          theme,
        );
        await prefs.setString(
          ShellWasabiHost.privateKey(
            wasabiColorThemesSection,
            wasabiSharedColorThemeKey,
          ),
          theme,
        );
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not save the color themes",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SkinColorThemes",
      );
    }
  }

  static String _customThemesKey(String skinName) =>
      "amped.custom_color_themes.$skinName";
}
