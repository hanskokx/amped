import "dart:io";
import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";

Future<void> main() async {
  final out = Directory("tool/preview");
  if (!out.existsSync()) out.createSync(recursive: true);
  final bytes = await File("test/fixtures/base.wsz").readAsBytes();
  final files = await skinArchiveContents(
    decodeSkinArchive(Uint8List.fromList(bytes)),
  );
  for (final name in ["MAIN.BMP", "titlebar.bmp", "text.bmp", "numbers.bmp"]) {
    final bmp = decodeBmp(Uint8List.fromList(files[name.toLowerCase()]!));
    final buf = StringBuffer("P6\n${bmp.width} ${bmp.height}\n255\n");
    final raw = Uint8List.fromList([
      ...buf.toString().codeUnits,
      ...bmp.rgba,
    ]);
    await File("tool/preview/$name.ppm").writeAsBytes(raw);
  }
  stdout.writeln("wrote PPM previews");
}
