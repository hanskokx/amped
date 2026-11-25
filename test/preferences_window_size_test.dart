import "package:amped/src/app/amped_dialog.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  test("Preferences can't be made smaller than its pages fit in", () {
    expect(AmpedDialog.preferences.resizable, isTrue);
    expect(AmpedDialog.preferences.minSize, const Size(860, 560));
    expect(AmpedDialog.preferences.size, AmpedDialog.preferences.minSize);
  });
}
