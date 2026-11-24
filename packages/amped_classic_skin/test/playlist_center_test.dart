import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("centers the playing row", () {
    expect(centeredOffset(50, 10, 100), 45);
  });

  test("stays at the top near the start", () {
    expect(centeredOffset(2, 10, 100), 0);
  });

  test("stays at the bottom near the end", () {
    expect(centeredOffset(99, 10, 100), 90);
  });

  test("short lists do not scroll", () {
    expect(centeredOffset(3, 10, 5), 0);
  });
}
