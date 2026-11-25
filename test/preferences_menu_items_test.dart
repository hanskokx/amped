import "dart:ui";

import "package:amped/src/app/amped_menus.dart";
import "package:amped/src/app/amped_shell.dart";
import "package:amped/src/app/shell_menu_bar.dart";
import "package:amped/src/features/preferences/preferences_page.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/skin/skin_manager.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

class _Skins implements SkinManager {
  @override
  List<SkinInfo> get sortedSkins => const [];
  @override
  SkinInfo get active => const SkinInfo(name: "Amped Classic");
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Notes where Preferences was asked to open.
class _Shell implements AmpedShell {
  final List<Object?> opened = [];

  @override
  final AppLocalizations localizations = lookupAppLocalizations(
    const Locale("en"),
  );
  @override
  final SkinManager skins = _Skins();
  @override
  final Skin skin = ClassicSkin(
    const SkinInfo(name: "Amped Classic"),
    ClassicSkinData(name: "Amped Classic", images: const {}),
  );
  @override
  final MediaLibrary library = MediaLibrary();

  @override
  void openSkinBrowser() => opened.add("skin browser");
  @override
  void openOnlineSkinBrowser() => opened.add("online skin browser");
  @override
  void showPreferences([PreferencesPage? page]) => opened.add(page);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test("the Skins menu opens each skin browser", () {
    final shell = _Shell();
    final items = AmpedMenus.skins(shell);
    void choose(String label) =>
        items.singleWhere((item) => item.label == label).onSelected!();

    choose("Skin Browser...");
    choose("Online Skin Browser...");

    expect(shell.opened, ["skin browser", "online skin browser"]);
  });

  test("Media Library Preferences opens its own page", () {
    final shell = _Shell();

    AmpedMenus.mediaLibraryView(shell)
        .singleWhere((item) => item.label == "Media Library Preferences...")
        .onSelected!();

    expect(shell.opened, [PreferencesPage.mediaLibrary]);
  });

  test("the macOS menu bar tells the skin browsers apart", () async {
    final shell = _Shell();
    final menuBar = ShellMenuBar(shell);

    await menuBar.handleCall(const MethodCall("skinBrowser"));
    await menuBar.handleCall(const MethodCall("onlineSkinBrowser"));

    expect(shell.opened, ["skin browser", "online skin browser"]);
  });
}
