import "package:amped_skin/amped_skin.dart";
import "package:flutter/painting.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("the extra slots are the ones after the notifier", () {
    expect(SkinWindow.extras, hasLength(6));
    expect(SkinWindow.extras.every((window) => window.isExtra), isTrue);
    expect(SkinWindow.notifier.isExtra, isFalse);
  });

  test("only the windows the user can drag larger are resizable", () {
    expect(
      SkinWindow.values.where((window) => window.resizable),
      [
        SkinWindow.pl,
        SkinWindow.video,
        SkinWindow.library,
        SkinWindow.vis,
        SkinWindow.albumArt,
      ],
    );
  });

  test("the visualization window needs more width than the others", () {
    expect(SkinWindow.vis.minWidth, 325);
    expect(SkinWindow.pl.minWidth, SkinWindow.minResizableSize.width);
    expect(SkinWindow.main.defaultSize, const Size(275, 116));
  });
}
