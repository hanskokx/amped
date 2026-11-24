import "dart:convert";
import "dart:io";

import "package:amped_skin/amped_skin.dart";
import "package:flutter_test/flutter_test.dart";

SkinFormat _detect(Set<String> names) =>
    names.contains("marker.dat") ? SkinFormat.bamp : SkinFormat.classic;

void main() {
  test("format migration only repairs unrecorded classic skins", () async {
    final dir = Directory.systemTemp.createTempSync("skin_registry_test");
    addTearDown(() => dir.deleteSync(recursive: true));

    final foreign = Directory("${dir.path}/Foreign")..createSync();
    File("${foreign.path}/main.bmp").writeAsBytesSync(const [1]);
    File("${foreign.path}/marker.dat").writeAsBytesSync(const [2]);
    File(
      "${foreign.path}/manifest.json",
    ).writeAsStringSync('{"name":"Foreign","importedAt":"old"}');

    final plain = Directory("${dir.path}/Plain")..createSync();
    File("${plain.path}/main.bmp").writeAsBytesSync(const [1]);
    File("${plain.path}/manifest.json").writeAsStringSync('{"name":"Plain"}');

    final known = Directory("${dir.path}/Known")..createSync();
    File("${known.path}/marker.dat").writeAsBytesSync(const [2]);
    File(
      "${known.path}/manifest.json",
    ).writeAsStringSync('{"name":"Known","format":"wasabi"}');

    final modern = Directory("${dir.path}/Modern")..createSync();
    File("${modern.path}/skin.xml").writeAsStringSync("<skin></skin>");
    File("${modern.path}/marker.dat").writeAsBytesSync(const [2]);

    final registry = await SkinRegistry.load(dir);
    expect(registry.byName("Foreign")!.format, SkinFormat.classic);
    expect(registry.byName("Modern")!.format, SkinFormat.wasabi);
    expect(await registry.migrateFormats(_detect), 1);

    expect(registry.byName("Foreign")!.format, SkinFormat.bamp);
    expect(registry.byName("Plain")!.format, SkinFormat.classic);
    expect(registry.byName("Known")!.format, SkinFormat.wasabi);
    expect(registry.byName("Modern")!.format, SkinFormat.wasabi);

    Map<String, dynamic> manifestOf(Directory folder) =>
        jsonDecode(
              File("${folder.path}/manifest.json").readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifestOf(foreign)["format"], "bamp");
    expect(manifestOf(foreign)["importedAt"], "old");
    expect(manifestOf(plain).containsKey("format"), isFalse);
    expect(manifestOf(known)["format"], "wasabi");
    expect(File("${modern.path}/manifest.json").existsSync(), isFalse);

    final rescanned = await SkinRegistry.load(dir);
    expect(rescanned.byName("Foreign")!.format, SkinFormat.bamp);
  });
}
