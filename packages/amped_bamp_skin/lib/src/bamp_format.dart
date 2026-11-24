import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";

import "bamp_skin.dart";

/// Converts Bamp's layered PNG files into a classic skin's file set.
///
/// Bamp archives are ordinary zips, so no [SkinArchiveDecoder] is needed:
/// the classic decoder opens them and this converter claims the file set.
final class BampSkinFormat implements SkinFileConverter {
  const BampSkinFormat();

  @override
  SkinFormat get format => SkinFormat.bamp;

  @override
  bool appliesToNames(Set<String> names) => isBampSkinNames(names);

  @override
  bool appliesTo(Map<String, List<int>> files) =>
      appliesToNames(files.keys.toSet());

  @override
  Future<Map<String, List<int>>> convert(
    Map<String, List<int>> files,
  ) => bampToClassicFiles(files);

  @override
  SkinHints? hints(Map<String, List<int>> files) => null;
}
