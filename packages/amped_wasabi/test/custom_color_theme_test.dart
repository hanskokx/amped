import "dart:convert";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  WasabiGammaSet builtIn() => WasabiGammaSet("Ocean")
    ..add(const WasabiGammaGroup(id: "General", red: -500, blue: 300))
    ..add(const WasabiGammaGroup(id: "Main", gray: 1));

  test("a clone is custom and keeps the groups of the theme", () {
    final clone = builtIn().cloneAs("Mine");
    expect(clone.custom, isTrue);
    expect(clone.name, "Mine");
    expect(clone.general.red, -500);
    expect(clone.groups["main"]?.gray, 1);
    clone.general = clone.general.copyWith(red: 10);
    expect(builtIn().general.red, -500);
  });

  test("a custom theme survives saving as JSON", () {
    final saved = builtIn().cloneAs("Mine");
    final loaded = WasabiGammaSet.fromJson(
      jsonDecode(jsonEncode(saved.toJson())),
    )!;
    expect(loaded.custom, isTrue);
    expect(loaded.name, "Mine");
    expect(loaded.general, saved.general.copyWith());
    expect(loaded.groups["main"], saved.groups["main"]);
    expect(WasabiGammaSet.fromJson("nope"), isNull);
  });

  test("custom themes are added to and removed from the list", () async {
    final themes = WasabiColorThemes(
      sets: [builtIn()],
      images: const [],
      readPixels: (_) async => null,
    );
    await themes.select("Ocean");
    themes.add(builtIn().cloneAs("Mine"));
    expect(themes.names, ["Mine", "Ocean"]);
    await themes.select("Mine");
    expect(themes.current?.name, "Mine");
    await themes.remove("Ocean"); // Not custom: stays.
    expect(themes.names, ["Mine", "Ocean"]);
    await themes.remove("Mine");
    expect(themes.names, ["Ocean"]);
    expect(themes.current?.name, "Ocean");
  });
}
