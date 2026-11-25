import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a \$solid bitmap is a picture of its color", (tester) async {
    final directory = Directory.systemTemp.createTempSync("solid_bitmap");
    addTearDown(() => directory.deleteSync(recursive: true));
    File("${directory.path}/skin.xml").writeAsStringSync(r'''
<WasabiXML>
  <elements>
    <color id="shade" value="10,20,30"/>
    <bitmap id="dot" file="$solid" color="192,128,64"/>
    <bitmap id="box" file="$solid" color="shade" w="4" h="3"/>
  </elements>
</WasabiXML>''');

    await tester.runAsync(() async {
      final skin = await WasabiSkinData.load(directory);
      Future<List<int>> firstPixel(String id) async {
        final data = await skin.bitmap(id)!.source.toByteData();
        return data!.buffer.asUint8List(0, 4).toList();
      }

      expect(skin.bitmap("dot")!.size.width, 1);
      expect(skin.bitmap("dot")!.size.height, 1);
      expect(await firstPixel("dot"), [192, 128, 64, 255]);
      expect(skin.bitmap("box")!.size.width, 4);
      expect(skin.bitmap("box")!.size.height, 3);
      expect(await firstPixel("box"), [10, 20, 30, 255]);
    });
  });
}
