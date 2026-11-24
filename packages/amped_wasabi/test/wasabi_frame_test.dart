import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  test("Wasabi:Frame puts its two groups side by side or stacked", () async {
    final dir = Directory.systemTemp.createTempSync("frame");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<WasabiXML version="1.2">
<groupdef id="a"><text id="in.a" w="10" h="10"/></groupdef>
<groupdef id="b"><text id="in.b" w="10" h="10"/></groupdef>
<container id="main"><layout id="normal" w="200" h="100">
  <Wasabi:Frame id="side" left="a" right="b" width="60" fitparent="1"/>
  <Wasabi:Frame id="from.end" left="a" right="b" width="30" from="r"
      orientation="h" fitparent="1"/>
</layout></container>
</WasabiXML>''');
    final skin = await WasabiSkinData.load(dir);
    final root = skin.container("main")!.layout("normal")!.root;
    WasabiObject find(WasabiObject from, String id) {
      for (final child in from.children) {
        if (child.id == id) return child;
        for (final inner in child.children) {
          if (inner.id == id) return inner;
        }
      }
      throw StateError("no $id");
    }

    final side = find(root, "side");
    expect(side.children.map((c) => c.id), ["a", "b", "frame.divider"]);
    expect(side.children[0]["x"], "0");
    expect(side.children[0]["w"], "60");
    expect(side.children[1]["x"], "60");
    expect(side.children[1]["w"], "-60");
    expect(side.children[1]["relatw"], "1");

    // Stacked, sized from the bottom: the bottom group is 30 high.
    final stacked = find(root, "from.end");
    expect(stacked.children[0].id, "b");
    expect(stacked.children[0]["h"], "30");
    expect(stacked.children[0]["y"], "-30");
    expect(stacked.children[0]["relaty"], "1");
    expect(stacked.children[1].id, "a");
    expect(stacked.children[1]["h"], "-30");
  });

  test("a Wasabi:Frame's divider moves within minwidth and maxwidth", () async {
    final dir = Directory.systemTemp.createTempSync("frame_drag");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<WasabiXML version="1.2">
<groupdef id="a"><text id="in.a" w="10" h="10"/></groupdef>
<groupdef id="b"><text id="in.b" w="10" h="10"/></groupdef>
<container id="main"><layout id="normal" w="200" h="100">
  <Wasabi:Frame id="f" x="0" y="0" w="200" h="100" left="a" right="b"
      width="60" minwidth="20" maxwidth="-30"/>
</layout></container>
</WasabiXML>''');
    final skin = await WasabiSkinData.load(dir);
    final root = skin.container("main")!.layout("normal")!.root;
    final frame = root.children.firstWhere((c) => c.id == "f");
    final host = FakeHost();
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    addTearDown(runtime.dispose);

    runtime.frameDragStart(frame);
    runtime.frameDragBy(frame, 25);
    expect(frame.children[0]["w"], "85");
    expect(frame.children[1]["x"], "85");
    // Past either limit the divider stops: 200 - 30 on the far side.
    runtime.frameDragBy(frame, 500);
    expect(frame.children[0]["w"], "170");
    runtime.frameDragBy(frame, -500);
    expect(frame.children[0]["w"], "20");

    // The place it was left at is kept, and a new run starts there.
    runtime.frameDragStart(frame);
    runtime.frameDragBy(frame, 70);
    runtime.frameDragEnd(frame);
    final again = await WasabiSkinData.load(dir);
    final root2 = again.container("main")!.layout("normal")!.root;
    final frame2 = root2.children.firstWhere((c) => c.id == "f");
    expect(frame2.children[0]["w"], "60"); // the skin's own width
    final second = WasabiScriptRuntime(skin: again, host: host, log: (_) {})
      ..start();
    addTearDown(second.dispose);
    expect(frame2.children[0]["w"], "90");
  });
}
