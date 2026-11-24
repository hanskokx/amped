import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("reads colours with comments, CRLF and a short file", () {
    // MacOS8AmpColor's file: 23 colours, comments, no final newline.
    final text = [
      "192,192,192\t// MUI-grey bgcolor no. 1",
      "192,192,192    \t// MUI-blue bgcolor no. 2",
      for (var i = 0; i < 21; i++) "135,135,218\t// $i",
    ].join("\r\n");
    final colors = parseVisColors(text)!;
    expect(colors, hasLength(23));
    expect(colors.first, 0xFFC0C0C0);
    expect(colors.last, 0xFF8787DA);
  });

  test("a file without colours gives none", () {
    expect(parseVisColors("// nothing here\n"), isNull);
  });
}
