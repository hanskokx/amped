import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test(
    "a layout takes the groupdef defined before it when an id is redefined",
    () async {
      final dir = Directory.systemTemp.createTempSync("wasabi_groupdef_twice");
      addTearDown(() => dir.deleteSync(recursive: true));
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
<groupdef id="buttons"><button id="across" x="10" y="5"/></groupdef>
<layout id="bar" w="100" h="20"><group id="buttons" x="0" y="0"/></layout>
<groupdef id="buttons"><button id="down" x="5" y="10"/></groupdef>
<layout id="strip" w="20" h="100"><group id="buttons" x="0" y="0"/></layout>
</container>
</WasabiXML>""");
      final skin = await WasabiSkinData.load(Directory(dir.path));
      final layouts = skin.container("main")!.layouts;
      String button(String layout) => layouts
          .firstWhere((l) => l.id == layout)
          .root
          .children
          .single
          .children
          .single
          .id;
      expect(button("bar"), "across");
      expect(button("strip"), "down");
    },
  );
}
