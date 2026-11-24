import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("CB_NEXT and CB_PREV page the Thinger's own buttons", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_thinger_page");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="200" h="60">
  <componentbucket id="bucket" x="0" y="0" w="60" h="37"/>
  <button id="next" action="CB_NEXT" x="100" y="0" w="10" h="10"/>
  <button id="prev" action="CB_PREV" x="100" y="20" w="10" h="10"/>
</layout></container>
</WasabiXML>""");
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    final root = skin.container("main")!.layout("normal")!.root;
    final bucket = runtime.find(root, "bucket")!;
    expect(bucket.intAttr("#scroll"), 0);
    // The buttons are wider than the bucket: a page on.
    expect(runtime.buttonAction(runtime.find(root, "next")!), isTrue);
    expect(bucket.intAttr("#scroll"), greaterThan(0));
    expect(runtime.buttonAction(runtime.find(root, "prev")!), isTrue);
    expect(bucket.intAttr("#scroll"), 0);
  });
}
