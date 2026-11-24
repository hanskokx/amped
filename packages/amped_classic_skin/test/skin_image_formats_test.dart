import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("a PNG named like a skin bitmap stands in for the BMP", () async {
    final png = await _png(7, 5);
    final archive = Archive()..addFile(ArchiveFile.bytes("Main.PNG", png));
    expect(isSkinArchive(archive), isTrue);

    final skin = await loadSkinFromArchive(
      ClassicSkinData(name: "base", images: const {}),
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    final image = skin.images["main.bmp"]!;
    expect(image.width, 7);
    expect(image.height, 5);
  });
}
