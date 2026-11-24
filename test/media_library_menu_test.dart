import "dart:ui" show Locale;

import "package:amped/src/app/amped_menus.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  final localizations = lookupAppLocalizations(const Locale("en"));

  List<String> run({required bool open}) {
    final calls = <String>[];
    final items = AmpedMenus.mediaLibraryFileItems(
      localizations: localizations,
      libraryOpen: open,
      onNew: () => calls.add("new"),
      onImport: () => calls.add("import"),
      onExport: () => calls.add("export"),
      onAddMedia: () => calls.add("addMedia"),
      onAddPlaylist: () => calls.add("addPlaylist"),
      onToggleLibrary: () => calls.add("toggle"),
    );
    for (final item in items) {
      if (item.enabled) item.onSelected?.call();
    }
    return calls;
  }

  test("ML_File runs its playlist and library entries", () {
    expect(run(open: true), [
      "new",
      "import",
      "export",
      "addMedia",
      "addPlaylist",
      "toggle",
    ]);
  });

  test("ML_File offers closing the library when it is open", () {
    final items = AmpedMenus.mediaLibraryFileItems(
      localizations: localizations,
      libraryOpen: true,
      onNew: () {},
      onImport: () {},
      onExport: () {},
      onAddMedia: () {},
      onAddPlaylist: () {},
      onToggleLibrary: () {},
    );
    expect(items.last.label, localizations.mlCloseLibrary);
  });

  test("the Media Library's menu words follow how many are selected", () {
    expect(localizations.mlMenuEnqueue(1), "Enqueue item");
    expect(localizations.mlMenuEnqueue(3), "Enqueue items");
    expect(localizations.mlMenuPlay(1), "Play item");
    expect(localizations.mlMenuPlay(2), "Play items");
  });
}
