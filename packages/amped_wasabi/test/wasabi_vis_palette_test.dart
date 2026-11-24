import "dart:io";
import "dart:ui" show Color;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a vis takes its band colors lowest first", () async {
    final dir = Directory.systemTemp.createTempSync("vis_palette");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="100" h="60">
    <vis id="a" x="0" y="0" w="76" h="16" colorallbands="10,20,30" colorband1="1,2,3" colorband16="4,5,6" colorallosc="7,8,9" colorosc2="11,12,13" colorbandpeak="14,15,16"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = await WasabiSkinData.load(Directory(dir.path));
    final vis = skin.container("main")!.layout("normal")!.root.children.single;
    final defaults = List<int>.filled(24, 0xFF000000);
    final palette = wasabiVisPalette(vis, skin, defaults);
    int argb(int r, int g, int b) => Color.fromARGB(255, r, g, b).toARGB32();
    // colorband1 is the lowest band (entry 17), colorband16 the highest (2).
    expect(palette[17], argb(1, 2, 3));
    expect(palette[2], argb(4, 5, 6));
    // colorallbands gives the rest.
    expect(palette[9], argb(10, 20, 30));
    // The oscilloscope: all of the first four, then its own.
    expect(palette[18], argb(7, 8, 9));
    expect(palette[19], argb(11, 12, 13));
    expect(palette[21], argb(7, 8, 9));
    expect(palette[23], argb(14, 15, 16));
  });
}
