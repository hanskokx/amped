import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a static frame has no resize handles", (tester) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_static_frame");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="wasabi.standardframe.static" xuitag="Wasabi:StandardFrame:Static">
  <layer id="left" x="0" y="0" w="5" h="50" resize="left"/>
  <layer id="bottom.right" x="0" y="0" w="5" h="5" resize="bottomright"/>
</groupdef>
<groupdef id="wasabi.standardframe.status" xuitag="Wasabi:StandardFrame:Status">
  <layer id="grip" x="0" y="0" w="5" h="5" resize="bottomright"/>
</groupdef>
<container id="main"><layout id="normal" w="100" h="100">
  <Wasabi:StandardFrame:Static id="fixed" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
  <Wasabi:StandardFrame:Status id="free" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final root = skin.container("main")!.layout("normal")!.root;
    final resizes = <String, String?>{};
    void walk(WasabiObject node) {
      final id = node.attributes["id"];
      if (id == "left" || id == "bottom.right" || id == "grip") {
        resizes["$id${resizes.containsKey(id) ? "2" : ""}"] =
            node.attributes["resize"];
      }
      node.children.forEach(walk);
    }

    walk(root);
    // The static frame's are off; the status frame keeps its own.
    expect(resizes["left"], "0");
    expect(resizes["bottom.right"], "0");
    expect(resizes["grip"], "bottomright");
  });
}
