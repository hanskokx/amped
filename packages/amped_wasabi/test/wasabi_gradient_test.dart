import "package:amped_wasabi/src/wasabi_gradient.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a linear gradient runs from its first stop to its last", () {
    final pixels = renderWasabiGradient(
      width: 100,
      height: 4,
      mode: "linear",
      x1: 0,
      y1: 0,
      x2: 1,
      y2: 0,
      points: "0.0=0,0,0,255;1.0=255,255,255,255",
    )!;
    int red(int x, int y) => pixels[(y * 100 + x) * 4];
    expect(red(0, 0), lessThan(5));
    expect(red(99, 0), greaterThan(240));
    expect(red(50, 2), inInclusiveRange(120, 135));
    expect(pixels[3], 255);
  });

  test("a circular gradient changes with the distance from its centre", () {
    final pixels = renderWasabiGradient(
      width: 20,
      height: 20,
      mode: "circular",
      x1: 0.5,
      y1: 0.5,
      x2: 1,
      y2: 0.5,
      points: "0=255,255,255,255;1.0=0,0,0,255",
    )!;
    int red(int x, int y) => pixels[(y * 20 + x) * 4];
    expect(red(10, 10), greaterThan(240));
    expect(red(0, 0), lessThan(5));
  });

  test("a stop without alpha is opaque and the pixels are premultiplied", () {
    final pixels = renderWasabiGradient(
      width: 4,
      height: 1,
      mode: "linear",
      x1: 0,
      y1: 0,
      x2: 1,
      y2: 0,
      points: "0.0=200,0,0,0;1.0=200,0,0",
    )!;
    expect(pixels[3], lessThan(10));
    expect(pixels[0], lessThan(10));
    expect(pixels[15], greaterThan(120));
  });
}
