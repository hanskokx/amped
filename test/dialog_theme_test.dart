import "package:amped/src/dialogs/dialog_theme.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  const black = Color(0xFF000000);
  const blue = Color(0xFF0000C6);

  test("the default skin wears the app icon's colors", () {
    final scheme = dialogTheme(
      background: black,
      accent: blue,
      defaultSkin: true,
    ).colorScheme;

    expect(scheme.surface, AppIconColors.background);
    expect(scheme.primary, AppIconColors.accent);
  });

  test("an accent without a hue gives way to the icon's", () {
    for (final accent in [black, Colors.white, const Color(0xFF808080)]) {
      final scheme = dialogTheme(background: black, accent: accent).colorScheme;

      expect(scheme.primary, AppIconColors.accent, reason: "$accent");
      expect(scheme.surface, black, reason: "$accent");
    }
  });

  test("another skin's accent is kept", () {
    final scheme = dialogTheme(background: black, accent: blue).colorScheme;

    expect(
      scheme.primary,
      ColorScheme.fromSeed(
        seedColor: blue,
        brightness: Brightness.dark,
      ).primary,
    );
  });
}
