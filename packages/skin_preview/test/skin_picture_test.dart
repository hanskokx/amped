import "dart:io";

import "package:skin_preview/skin_preview.dart";
import "package:test/test.dart";

void main() {
  test(
    "the base skin is drawn with the main window, equalizer and playlist",
    () async {
      final picture = await renderSkinPicture(null, title: "BASE");
      expect(picture, isNotNull);
      expect(picture!.rgba.length, picture.width * picture.height * 4);
      // 275x464 stacked: taller than wide.
      expect(picture.height, greaterThan(picture.width));
      expect(picture.rgba.any((byte) => byte != 0), isTrue);
    },
  );

  test(
    "a folder that is no skin is drawn from the base skin or not at all",
    () async {
      final empty = await Directory.systemTemp.createTemp("skin_picture_test");
      addTearDown(() => empty.delete(recursive: true));
      // Must not throw.
      await renderSkinPicture(empty, title: "EMPTY");
    },
  );
}
