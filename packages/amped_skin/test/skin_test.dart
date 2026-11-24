import "dart:ui";

import "package:amped_skin/amped_skin.dart";
import "package:flutter_test/flutter_test.dart";

final class _Plain extends Skin {
  _Plain() : super(const SkinInfo(name: "Plain"));

  @override
  bool hasModernLook(SkinWindow window) => false;

  @override
  bool get ownsNotifier => true;

  @override
  List<List<Offset>>? shape(SkinWindow window) => null;

  @override
  Size? get mainSize => null;
}

void main() {
  test("a skin is its own base", () {
    final skin = _Plain();
    expect(skin.base, same(skin));
  });

  test("the region section follows the shade state the player reports", () {
    final skin = _Plain();
    expect(skin.regionKey(SkinWindow.main), "main");
    expect(skin.regionKey(SkinWindow.pl), isNull);

    skin.followShades((window) => window == SkinWindow.main);
    expect(skin.regionKey(SkinWindow.main), "mainWs");
    expect(skin.regionKey(SkinWindow.eq), "eq");
  });
}
