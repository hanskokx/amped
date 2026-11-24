import "dart:ui";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

double _ratio(Color a, Color b) {
  final hi = a.computeLuminance() > b.computeLuminance() ? a : b;
  final lo = identical(hi, a) ? b : a;
  return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
}

void main() {
  test("legible colours are left alone", () {
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    expect(wasabiLegible(white, black), white);
  });

  test("grey on a slightly darker grey is lightened until it reads", () {
    // GlassAMP's list: 100,100,100 on 42,42,42.
    const text = Color.fromARGB(255, 100, 100, 100);
    const background = Color.fromARGB(255, 42, 42, 42);
    final fixed = wasabiLegible(text, background);
    expect(_ratio(text, background), lessThan(4.5));
    expect(_ratio(fixed, background), greaterThanOrEqualTo(4.5));
    // As little as it takes, still grey.
    expect(fixed.r, closeTo(fixed.b, 0.001));
    expect(fixed.r, lessThan(0.85));
  });

  test("dark text on a dark background is darkened on a light one", () {
    const text = Color.fromARGB(255, 150, 150, 150);
    const background = Color.fromARGB(255, 230, 230, 230);
    final fixed = wasabiLegible(text, background);
    expect(_ratio(fixed, background), greaterThanOrEqualTo(4.5));
    expect(fixed.r, lessThan(text.r));
  });
}
