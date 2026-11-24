import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a window keeps the whole layout while a drawer slides", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_sliding_window");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="100" h="100" snapadjustbottom="40">
  <group id="drawer" x="0" y="60" w="100" h="40"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final layout = skin.container("main")!.layout("normal")!;
    // The room a closed drawer leaves out is not in the window...
    expect(layout.windowSize.height, 60);
    // ...until the drawer slides into it.
    layout.root.attributes["#sliding"] = "1";
    expect(layout.windowSize.height, 100);
    layout.root.attributes.remove("#sliding");
    expect(layout.windowSize.height, 60);
  });
}
