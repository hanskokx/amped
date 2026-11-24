import "dart:ui" as ui;

import "package:amped_wasabi/src/skin_region.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a rect outside the mask adds nothing and does not throw", () {
    final mask = RegionMask(10, 4);
    mask.addRect(const ui.Rect.fromLTWH(20, 0, 30, 4));
    mask.addRect(const ui.Rect.fromLTWH(-30, 1, 10, 1));
    mask.addRect(const ui.Rect.fromLTWH(0, 9, 10, 3));
    expect(mask.isEmpty, isTrue);
    mask.addRect(const ui.Rect.fromLTWH(8, 3, 100, 100));
    expect(mask.toRects(), [const ui.Rect.fromLTWH(8, 3, 2, 1)]);
  });
}
