import "dart:convert";
import "dart:io";
import "dart:typed_data";
import "dart:ui";

import "package:amped_audacious_skin/amped_audacious_skin.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

const formats = SkinFormats(
  decoders: {AudaciousSkinDecoder()},
  converters: {AudaciousSkinConverter()},
);

/// A 2x2, 24-bit BMP: a stand-in for a skin's main bitmap.
Uint8List _bmp() {
  final data = ByteData(70);
  data.setUint8(0, 0x42);
  data.setUint8(1, 0x4D);
  data.setUint32(2, 70, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, 2, Endian.little);
  data.setInt32(22, 2, Endian.little);
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, 16, Endian.little);
  for (var i = 54; i < 70; i++) {
    data.setUint8(i, 0x80);
  }
  return data.buffer.asUint8List();
}

Uint8List _tar() {
  final bmp = _bmp();
  final archive = Archive()
    ..addFile(ArchiveFile.bytes("Audacious Skin/main.bmp", bmp));
  return Uint8List.fromList(TarEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tar = _tar();
  final archives = <String, Uint8List>{
    "tar": tar,
    "tar.gz": Uint8List.fromList(const GZipEncoder().encode(tar)),
    "tar.bz2": Uint8List.fromList(BZip2Encoder().encode(tar)),
  };

  for (final entry in archives.entries) {
    test("opens a ${entry.key} skin", () {
      final archive = decodeSkinArchive(entry.value, formats: formats);
      expect(isSkinArchive(archive, formats: formats), isTrue);
      expect(skinArchiveFiles(archive).keys, ["main.bmp"]);
    });
  }

  test("rejects bytes that are no archive", () {
    expect(
      () => decodeSkinArchive(
        Uint8List.fromList(List.filled(600, 7)),
        formats: formats,
      ),
      throwsFormatException,
    );
  });

  test("imports a tarball skin with its format recorded", () async {
    final dir = Directory.systemTemp.createTempSync("audacious_skin_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    final registry = await SkinRegistry.load(dir);
    final info = await registry.importArchive(
      archives["tar.gz"]!,
      fileName: "Blue Thing.tar.gz",
      formats: formats,
    );
    expect(info.name, "Blue Thing");
    expect(info.format, SkinFormat.audacious);
    expect(File("${info.directory!.path}/main.bmp").existsSync(), isTrue);

    final manifest =
        jsonDecode(
              File("${info.directory!.path}/manifest.json").readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest["format"], "audacious");

    final rescanned = await SkinRegistry.load(dir);
    expect(rescanned.byName("Blue Thing")!.format, SkinFormat.audacious);
  });

  testWidgets("converts PNG bitmaps to BMPs", (tester) async {
    final archive = Archive()
      ..addFile(ArchiveFile.bytes("Skin/Volume.PNG", _onePixelPng()))
      ..addFile(ArchiveFile.bytes("Skin/main.bmp", tar.sublist(0, 4)));
    expect(isSkinArchive(archive, formats: formats), isTrue);
    final files = await tester.runAsync(
      () => skinArchiveContents(archive, formats: formats),
    );
    final bmp = decodeBmp(Uint8List.fromList(files!["volume.bmp"]!));
    expect([bmp.width, bmp.height], [1, 1]);
    expect(bmp.rgba.sublist(0, 3), [10, 20, 30]);
  });

  test("parses skin.hints, ignoring comments, case and other lines", () {
    final hints = SkinHintsParser.parse(
      "[skin]\r\nskinDescription=Reflex\r\nmainwinVisX=476   //osiloskop\r\n"
      "MainwinVisY=59\r\nmainwinWidth=675\r\nmainwinHeight=168\r\n"
      "mainwinMenurowVisible=0\r\n",
    );
    expect(
      hints.point("mainwinVis", const Offset(0, 0)),
      const Offset(476, 59),
    );
    expect(hints.flag("mainwinMenurowVisible", fallback: true), isFalse);
    expect(hints.flag("mainwinTextVisible", fallback: true), isTrue);
    expect(hints.value("mainwinNumber0X", 36), 36);
  });

  test("a converter supplies the hints of a skin.hints file", () {
    const converter = AudaciousSkinConverter();
    final hints = converter.hints({
      "skin.hints": utf8.encode("mainwinWidth=675\nmainwinHeight=168"),
    })!;
    expect(
      ClassicSkinData(name: "wide", images: const {}, hints: hints).mainSize,
      const Size(675, 168),
    );
  });

  test("recognises an Audacious skin from file names alone", () {
    SkinFormat detect(Iterable<String> names) =>
        formats.identifyNames(names, SkinFormat.classic);
    expect(
      detect(["MAIN.BMP", "Balance.PNG", "titlebar.jpg", "dialogs.txt"]),
      SkinFormat.audacious,
    );
    expect(detect(["main.bmp", "skin.hints"]), SkinFormat.audacious);
    expect(detect(["main.bmp", "notes.txt"]), SkinFormat.classic);
  });

  test("repairs the manifest of an old Audacious install", () async {
    final dir = Directory.systemTemp.createTempSync("audacious_migrate_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    final skin = Directory("${dir.path}/ReBrushed Reflex")..createSync();
    File("${skin.path}/main.bmp").writeAsBytesSync(tar.sublist(0, 4));
    File("${skin.path}/main.png").writeAsBytesSync(_onePixelPng());
    File("${skin.path}/skin.hints").writeAsStringSync("mainwinWidth=675");
    File(
      "${skin.path}/manifest.json",
    ).writeAsStringSync('{"name":"ReBrushed Reflex","importedAt":"old"}');

    SkinFormat detect(Set<String> names) =>
        formats.identifyNames(names, SkinFormat.classic);
    final registry = await SkinRegistry.load(dir);
    expect(
      registry.byName("ReBrushed Reflex")!.format,
      SkinFormat.classic,
    );
    expect(await registry.migrateFormats(detect), 1);
    expect(
      registry.byName("ReBrushed Reflex")!.format,
      SkinFormat.audacious,
    );

    final manifest =
        jsonDecode(
              File("${skin.path}/manifest.json").readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(manifest["format"], "audacious");
    expect(manifest["name"], "ReBrushed Reflex");
    expect(manifest["importedAt"], "old");

    expect(await registry.migrateFormats(detect), 0);
    final rescanned = await SkinRegistry.load(dir);
    expect(
      rescanned.byName("ReBrushed Reflex")!.format,
      SkinFormat.audacious,
    );
  });
}

// A 1x1 RGB (10, 20, 30) PNG.
Uint8List _onePixelPng() => Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  2,
  0,
  0,
  0,
  144,
  119,
  83,
  222,
  0,
  0,
  0,
  12,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  224,
  18,
  145,
  3,
  0,
  0,
  104,
  0,
  61,
  84,
  8,
  163,
  247,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);
