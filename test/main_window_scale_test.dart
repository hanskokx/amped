import "dart:ui";

import "package:amped/src/app/main_window_scale.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const base = Size(275, 116);

  group("fromCorner", () {
    test("a corner on the skin's diagonal gives that scale", () {
      expect(
        MainWindowScale.fromCorner(base, const Offset(412.5, 174)),
        closeTo(1.5, 0.005),
      );
    });

    test("scales continuously between whole numbers", () {
      final scale = MainWindowScale.fromCorner(base, const Offset(360, 152));
      expect(scale, greaterThan(1.2));
      expect(scale, lessThan(1.4));
    });

    test("keeps the aspect ratio when the corner is off the diagonal", () {
      // Dragged far right but not down: somewhere in between.
      final scale = MainWindowScale.fromCorner(base, const Offset(550, 116));
      expect(scale, greaterThan(1));
      expect(scale, lessThan(2));
    });

    test("the window is a whole number of pixels wide", () {
      final scale = MainWindowScale.fromCorner(base, const Offset(371, 157));
      final width = base.width * scale;
      expect(width, closeTo(width.roundToDouble(), 1e-9));
    });

    test("snaps to a whole scale when close", () {
      expect(MainWindowScale.fromCorner(base, const Offset(555, 234)), 2);
      expect(MainWindowScale.fromCorner(base, const Offset(545, 230)), 2);
    });

    test("never shrinks below the skin's native size", () {
      expect(MainWindowScale.fromCorner(base, const Offset(10, 10)), 1);
      expect(MainWindowScale.fromCorner(base, const Offset(-50, -50)), 1);
    });

    test("stops at the limit", () {
      expect(
        MainWindowScale.fromCorner(base, const Offset(5000, 5000), limit: 3),
        3,
      );
      expect(
        MainWindowScale.fromCorner(base, const Offset(50000, 50000)),
        MainWindowScale.maxScale,
      );
    });
  });

  group("windowSize", () {
    test("is a whole number of pixels at any scale", () {
      for (var scale = 1.0; scale <= 3; scale += 0.013) {
        final size = MainWindowScale.windowSize(base, scale);
        expect(size.width, size.width.roundToDouble());
        expect(size.height, size.height.roundToDouble());
        expect(size.width, closeTo(base.width * scale, 0.5));
        expect(size.height, closeTo(base.height * scale, 0.5));
      }
    });

    test("is exact at whole scales", () {
      expect(MainWindowScale.windowSize(base, 2), const Size(550, 232));
    });

    test("is whole for every scale a drag produces", () {
      for (var x = 275.0; x < 900; x += 7.3) {
        final scale = MainWindowScale.fromCorner(base, Offset(x, x * 0.42));
        final size = MainWindowScale.windowSize(base, scale);
        expect(size.height, size.height.roundToDouble());
      }
    });
  });

  group("limitFor", () {
    test("is what fits on the screen", () {
      const area = Rect.fromLTWH(0, 0, 1100, 1000);
      expect(MainWindowScale.limitFor(base, area), 4);
    });

    test("is the maximum without a screen", () {
      expect(MainWindowScale.limitFor(base, null), MainWindowScale.maxScale);
    });

    test("is never below the native size", () {
      const area = Rect.fromLTWH(0, 0, 200, 100);
      expect(MainWindowScale.limitFor(base, area), 1);
    });
  });
}
