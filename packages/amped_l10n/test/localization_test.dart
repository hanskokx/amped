import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/widgets.dart" show Locale, basicLocaleListResolution;
import "package:flutter_test/flutter_test.dart";

void main() {
  test("unsupported system locales fall back to English", () {
    final locale = basicLocaleListResolution(
      const [Locale("fr", "FR")],
      AppLocalizations.supportedLocales,
    );

    expect(locale, const Locale("en"));
  });

  test("Dart and native menus share the same catalog values", () async {
    final localizations = await AppLocalizations.delegate.load(
      const Locale("en"),
    );

    expect(localizations.playlistEditor, "Playlist Editor");
    expect(localizations.macAboutMenu, "About Amped");
    expect(localizations.enterUrlPrompt, "Enter the URL of a file to play:");
  });
}
