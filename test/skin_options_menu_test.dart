import "package:amped/src/app/amped_menus.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("skin options name amped where a skin names Winamp", () {
    expect(AmpedMenus.skinOptionLabel("Winamp Modern"), "Amped Modern");
    expect(AmpedMenus.skinOptionLabel("Drawers"), "Drawers");
    expect(
      AmpedMenus.skinOptionLabel("Equalizer\tAlt+G"),
      "Equalizer\tAlt+G",
    );
    // Only the word, not a name that contains it.
    expect(AmpedMenus.skinOptionLabel("Wasabi 5 skins"), "Wasabi 5 skins");
  });
}
