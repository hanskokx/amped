import "dart:convert";

import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:archive/archive.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

Uint8List _archive(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("loads every skin archive in the application's assets/skins", () async {
    final named = _archive({
      "skin.xml":
          "<WasabiXML><skininfo><name>Test Modern</name> "
          "</skininfo></WasabiXML>",
    });
    final unnamed = _archive({"readme.txt": "no skin.xml here"});
    final assets = <String, Uint8List>{
      "assets/skins/named.wal": named,
      "assets/skins/plain.wal": unnamed,
      "assets/skins/classic.wsz": unnamed,
      "assets/images/ignored.wal": named,
      "packages/amped_wasabi/assets/skins/ignored.wal": named,
    };
    final manifest = <Object?, Object?>{
      for (final key in assets.keys)
        key: [
          <Object?, Object?>{"asset": key},
        ],
    };
    final encodedManifest = const StandardMessageCodec().encodeMessage(
      manifest,
    )!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler("flutter/assets", (message) async {
      final key = utf8.decode(
        message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (key == "AssetManifest.bin") return encodedManifest;
      final asset = assets[key];
      return asset == null ? null : ByteData.sublistView(asset);
    });
    addTearDown(() {
      messenger.setMockMessageHandler("flutter/assets", null);
    });

    final skins = await AmpedModernSkinLoader.loadAssets();

    expect(skins.keys, unorderedEquals(["Test Modern", "plain"]));
    expect(skins["Test Modern"]!.bytes, named);
    expect(skins["Test Modern"]!.format, SkinFormat.wasabi);
    expect(skins["plain"]!.bytes, unnamed);
    expect(skins["plain"]!.format, SkinFormat.wasabi);
  });
}
