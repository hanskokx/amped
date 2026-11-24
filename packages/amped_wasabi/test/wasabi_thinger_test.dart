import "dart:ui";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("the Thinger lists Wasabi 5's components in its order", () {
    expect(
      [for (final item in wasabiThingerItems) (item.param, item.label)],
      const [
        ("guid:pl", "Playlist Editor"),
        ("guid:ml", "Amped Library"),
        ("guid:video", "Video Window"),
        ("guid:vis", "Visualizations"),
      ],
    );
  });

  test("Thinger buttons use the skin's winamp.thinger bitmaps", () {
    final pl = wasabiThingerItems.first;
    expect(
      pl.bitmapFor(selected: false, hilited: false),
      "winamp.thinger.pledit",
    );
    expect(
      pl.bitmapFor(selected: false, hilited: true),
      "winamp.thinger.pledit.hilited",
    );
    // An open window's button stays selected under the pointer.
    expect(
      pl.bitmapFor(selected: true, hilited: true),
      "winamp.thinger.pledit.selected",
    );
  });

  test("buttons line up from the left margin, centred vertically", () {
    final rects = wasabiThingerLayout(const [
      Size(44, 34),
      Size(42, 38),
    ], const Size(300, 35));
    expect(rects, const [
      Rect.fromLTWH(2, 0, 44, 34),
      Rect.fromLTWH(48, -1, 42, 38),
    ]);
  });

  test("buttons much taller or shorter than the bucket are scaled", () {
    final rects = wasabiThingerLayout(
      const [Size(44, 34), Size(44, 34)],
      const Size(300, 17),
      leftMargin: 0,
      spacing: 4,
    );
    expect(rects, const [
      Rect.fromLTWH(0, 0, 22, 17),
      Rect.fromLTWH(26, 0, 22, 17),
    ]);
  });
}
