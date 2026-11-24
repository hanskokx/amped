import "package:amped_classic_skin/amped_classic_skin.dart";

/// Parses the `skin.hints` of an Audacious skin.
///
/// Lines are `key=value`; `//` starts a comment. Keys are stored lower-cased
/// and non-integer values are ignored, so a skin without a key gets the
/// classic layout through [SkinHints.value] and friends.
abstract final class SkinHintsParser {
  /// Parses the text of a `skin.hints` file.
  static SkinHints parse(String text) {
    final values = <String, int>{};
    for (final raw in text.split(RegExp(r"[\r\n]+"))) {
      var line = raw;
      final comment = line.indexOf("//");
      if (comment >= 0) line = line.substring(0, comment);
      final eq = line.indexOf("=");
      if (eq < 0) continue;
      final value = int.tryParse(line.substring(eq + 1).trim());
      if (value == null) continue;
      values[line.substring(0, eq).trim().toLowerCase()] = value;
    }
    return SkinHints(values);
  }
}
