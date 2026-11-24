import "dart:io";
import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";

Future<void> main(List<String> args) async {
  final bytes = await File("test/fixtures/base.wsz").readAsBytes();
  final files = await skinArchiveContents(
    decodeSkinArchive(Uint8List.fromList(bytes)),
  );
  for (final name in args) {
    final content = files[name.toLowerCase()];
    if (content == null) {
      stderr.writeln("No $name in base.wsz");
      continue;
    }
    final img = decodeBmp(Uint8List.fromList(content));
    await File("tool/preview/$name.rgba").writeAsBytes(img.rgba);
    stdout.writeln("$name -> ${img.width}x${img.height}");
  }
}
