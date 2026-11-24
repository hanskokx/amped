import "dart:ui";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a skin's main window size comes from its hints", () {
    final skin = ClassicSkinData(
      name: "wide",
      images: const {},
      hints: const SkinHints({
        "mainwinwidth": 675,
        "mainwinheight": 168,
      }),
    );
    expect(skin.mainSize, const Size(675, 168));
    expect(
      ClassicSkinData(name: "plain", images: const {}).mainSize,
      const Size(275, 116),
    );
  });

  test("half a size is no size", () {
    final skin = ClassicSkinData(
      name: "odd",
      images: const {},
      hints: const SkinHints({"mainwinwidth": 675}),
    );
    expect(skin.mainSize, const Size(275, 116));
  });
}
