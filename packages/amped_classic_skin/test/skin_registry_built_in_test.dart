import "dart:io";

import "package:amped_skin/amped_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("built-in skins are marked, versioned and never removed", () async {
    final dir = await Directory.systemTemp.createTemp("registry");
    addTearDown(() => dir.delete(recursive: true));
    final registry = await SkinRegistry.load(dir);
    final info = await registry.installFolder(
      "Built In",
      (target) => File("${target.path}/skin.xml").writeAsString("<WasabiXML/>"),
      format: SkinFormat.wasabi,
      builtInVersion: "1",
    );
    expect(info.isBundled, isTrue);

    // A fresh scan finds it as built-in and modern, at its version.
    final rescanned = await SkinRegistry.load(dir);
    final found = rescanned.byName("Built In")!;
    expect(found.builtIn, isTrue);
    expect(found.modern, isTrue);
    expect(rescanned.builtInVersion("Built In"), "1");

    await rescanned.remove(found);
    expect(found.directory!.existsSync(), isTrue);
    expect(rescanned.byName("Built In"), isNotNull);
  });
}
