import "dart:convert";
import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("Region, TabSheet, Text and System helpers", (tester) async {
    final dir = Directory.systemTemp.createTempSync("maki_batch2");
    addTearDown(() => dir.deleteSync(recursive: true));
    // A 1x1 opaque pixel.
    File("${dir.path}/px.png").writeAsBytesSync(
      base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
      ),
    );
    final source = File("${dir.path}/b2.m")
      ..writeAsStringSync(r'''
Global Text log;
Global Layout lay;
Global TabSheet tabs;
Function note(String what);
note(String what) { log.setText(log.getText() + what + ";"); }
System.onScriptLoaded() {
  lay = getContainer("main").getLayout("normal");
  log = lay.findObject("log");
  tabs = lay.findObject("tabs");

  Region a = new Region;
  a.loadFromBitmap("px");
  a.offset(5, 6);
  Region b = new Region;
  b.loadFromBitmap("px");
  b.offset(10, 0);
  a.add(b);
  note("bbox:" + integertostring(a.getBoundingBoxX()) + "," + integertostring(a.getBoundingBoxY()) + "," + integertostring(a.getBoundingBoxW()) + "," + integertostring(a.getBoundingBoxH()));
  Region c = new Region;
  c.loadFromBitmap("px");
  c.offset(5, 6);
  a.sub(c);
  note("sub:" + integertostring(a.getBoundingBoxX()) + "," + integertostring(a.getBoundingBoxW()));

  tabs.setCurPage(1);
  note("page:" + integertostring(tabs.getCurPage()));
  note("path:" + getPath("c:\\music\\mp3\\test.mp3"));
  note("chr:" + chr(65));
  note("url:" + urlEncode("a b&c"));
  note("frac:" + floattostring(frac(2.25), 2));
  note("int:" + integertostring(integer((255 * 3.5) / 255)));
  note("year:" + integertostring(getDateYear(86400 * 365)));
  note("width:" + integertostring(lay.findObject("t").getTextWidth()));
}
''');
    File("${dir.path}/b2.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<bitmap id="px" file="px.png"/>
<scripts><script file="b2.maki"/></scripts>
<container id="main">
  <layout id="normal" w="80" h="60">
    <text id="log" x="0" y="0" w="80" h="10"/>
    <text id="t" x="0" y="10" w="80" h="10" text="Hello"/>
    <tabsheet id="tabs" x="0" y="20" w="80" h="30">
      <group id="p0" x="0" y="0" w="10" h="10"/>
      <group id="p1" x="0" y="0" w="10" h="10" visible="0"/>
    </tabsheet>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    final layout = skin.container("main")!.layout("normal")!;
    final text = runtime.find(layout.root, "log")!["#text"] ?? "";
    expect(text, contains("bbox:5,0,6,7;"));
    expect(text, contains("sub:10,1;"));
    expect(text, contains("page:1;"));
    expect(text, contains(r"path:c:\music\mp3;"));
    expect(text, contains("chr:A;"));
    expect(text, contains("url:a%20b%26c;"));
    expect(text, contains("frac:0.25;"));
    expect(text, contains("year:71;"));
    expect(text, contains("int:3;"));
    expect(text, matches(RegExp(r"width:[1-9]\d*;")));
    final tabs = runtime.find(layout.root, "tabs")!;
    expect(tabs["#page"], "1");
    expect(tabs.children[1].visible, isTrue);
    expect(tabs.children[0].visible, isFalse);
  });
}
