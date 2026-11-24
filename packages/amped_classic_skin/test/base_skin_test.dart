import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:archive/archive.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("loadBaseSkin decodes every bundled bitmap", () async {
    final skin = await loadBaseSkin();
    expect(skin.name, "Base");
    for (final name in bundledSkinFiles) {
      final image = skin.image(name);
      expect(image, isNotNull, reason: "$name should be loaded");
      expect(image!.width, greaterThan(0));
    }
  });

  test("loadBaseSkin decodes MAIN.BMP via case-insensitive lookup", () async {
    final skin = await loadBaseSkin();
    final main = skin.image("MAIN.BMP");
    expect(main, isNotNull);
    expect(main!.width, 275);
    expect(main.height, 116);
  });

  test("loadBaseSkin uses only the cursors in the base archive", () async {
    final skin = await loadBaseSkin();

    // The archive ships these cursor files, so those slots use them.
    expect(skin.cursor(SkinCursor.titleBar), isA<CustomMouseCursor>());
    expect(skin.cursor(SkinCursor.close), isA<CustomMouseCursor>());

    // Slots with no file in the archive use the OS cursor, not another
    // skin cursor standing in for them.
    expect(skin.cursor(SkinCursor.normal), SystemMouseCursors.basic);
    expect(skin.cursor(SkinCursor.eqClose), SystemMouseCursors.basic);
  });

  test(
    "a skin without cursor files leaves every slot on the OS cursor",
    () async {
      final skin = await loadSkinFromArchive(
        await loadBaseSkin(),
        _cursorlessSkin(),
        name: "No cursors",
      );

      for (final slot in SkinCursor.values) {
        expect(
          skin.cursor(slot),
          SystemMouseCursors.basic,
          reason: "$slot should be the OS cursor",
        );
      }
    },
  );
}

Uint8List _cursorlessSkin() {
  final archive = Archive()
    ..addFile(ArchiveFile("readme.txt", 4, const [104, 105, 33, 10]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
