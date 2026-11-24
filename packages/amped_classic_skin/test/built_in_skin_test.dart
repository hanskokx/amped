import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter_test/flutter_test.dart";

import "test_assets.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("loads `.wsz` skins but not the base or other assets", () async {
    final skins = await AmpedClassicSkinLoader.loadAssets();

    expect(skins.keys, unorderedEquals(["Test Classic", "plain"]));
    expect(skins["Test Classic"]!.bytes, namedSkinBytes);
    expect(skins["Test Classic"]!.format, SkinFormat.classic);
    expect(skins["plain"]!.bytes, unnamedSkinBytes);
    expect(await AmpedClassicSkinLoader.loadBase(), baseSkinBytes);
  });
}
