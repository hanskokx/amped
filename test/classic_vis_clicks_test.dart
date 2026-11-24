import "package:amped/src/vis/classic_vis_clicks.dart";
import "package:amped_vis/amped_vis.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late DateTime now;
  late ClassicVisClicks clicks;

  setUp(() {
    now = DateTime(2026);
    clicks = ClassicVisClicks(clock: () => now);
  });

  test("a single click cycles the mode", () {
    expect(clicks.click(ClassicVisMode.spectrum), isNull);
    now = now.add(const Duration(seconds: 1));
    expect(clicks.click(ClassicVisMode.oscilloscope), isNull);
  });

  test("a double-click restores the mode from before its first click", () {
    expect(clicks.click(ClassicVisMode.spectrum), isNull);
    now = now.add(const Duration(milliseconds: 200));
    expect(clicks.click(ClassicVisMode.oscilloscope), ClassicVisMode.spectrum);
  });

  test("a third quick click starts a new click, not another double", () {
    clicks.click(ClassicVisMode.spectrum);
    now = now.add(const Duration(milliseconds: 100));
    clicks.click(ClassicVisMode.oscilloscope);
    now = now.add(const Duration(milliseconds: 100));
    expect(clicks.click(ClassicVisMode.spectrum), isNull);
  });
}
