import "dart:typed_data";

import "package:amped/src/app/glass_blur.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  /// A [w] by [h] RGBA image whose alpha is [alphaAt].
  Uint8List image(int w, int h, int Function(int x, int y) alphaAt) {
    final bytes = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        bytes[(y * w + x) * 4 + 3] = alphaAt(x, y);
      }
    }
    return bytes;
  }

  test("only the translucent middle of a window is glass", () {
    // Opaque frame, 80-alpha glass inside, clear corner.
    final rgba = image(40, 30, (x, y) {
      if (x < 6 && y < 6) return 0;
      if (x >= 10 && x < 30 && y >= 8 && y < 24) return 80;
      return 255;
    });
    final mask = GlassBlur.maskOf(rgba, 40, 30, 40, 30)!;
    expect(mask[15 * 40 + 20], greaterThan(128));
    // Opaque and clear pixels are not blurred, nor the glass's rim.
    expect(mask[2 * 40 + 2], 0);
    expect(mask[15 * 40 + 5], 0);
    expect(mask[8 * 40 + 10], 0);
  });

  test("a window with no translucency has no glass", () {
    expect(
      GlassBlur.maskOf(image(20, 20, (x, y) => 255), 20, 20, 20, 20),
      isNull,
    );
    expect(
      GlassBlur.maskOf(image(20, 20, (x, y) => 0), 20, 20, 20, 20),
      isNull,
    );
    // A one-pixel soft edge is not glass.
    expect(
      GlassBlur.maskOf(
        image(20, 20, (x, y) => x == 3 ? 128 : 255),
        20,
        20,
        20,
        20,
      ),
      isNull,
    );
  });
}
