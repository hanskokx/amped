import "dart:convert";
import "dart:io";
import "dart:ui" show Color, Offset, Size;

import "package:amped_wasabi/amped_wasabi.dart";

import "package:flutter_test/flutter_test.dart";

void main() {
  test("elementalias and embed_xui", () async {
    final dir = Directory.systemTemp.createTempSync("alias_embed");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/px.png").writeAsBytesSync(
      base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
      ),
    );
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<elements>
  <elementalias id="old.texture" target="new.texture"/>
  <elementalias id="old.fg" target="new.fg"/>
  <bitmap id="old.texture" file="px.png"/>
  <color id="old.fg" value="10,20,30"/>
  <color id="plain" value="1,2,3"/>
  <elementalias id="old.cursor" target="new.cursor"/>
  <bitmap id="px" file="px.png"/>
  <cursor id="old.cursor" bitmap="px" hotspot_x="1" hotspot_y="2"/>
</elements>
<groupdef id="my.text" xuitag="My:Text" embed_xui="inner">
  <text id="inner" x="0" y="0" w="40" h="10"/>
</groupdef>
<container id="main">
  <layout id="normal" w="80" h="60">
    <snappoint id="top" x="17" y="27"/>
    <snappoint id="edge" x="-5" y="0" relatx="0"/>
    <My:Text id="one" x="5" y="6" w="50" h="12" text="Hello" fontsize="20"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = await WasabiSkinData.load(Directory(dir.path));
    // A definition under an alias is kept under its target, and the alias
    // finds it.
    expect(skin.bitmap("new.texture"), isNotNull);
    expect(skin.bitmap("old.texture"), isNotNull);
    expect(skin.sourceColor("new.fg"), const Color(0xFF0A141E));
    expect(skin.sourceColor("old.fg"), const Color(0xFF0A141E));
    expect(skin.sourceColor("plain"), const Color(0xFF010203));

    // A cursor from a bitmap, found under its alias and its target.
    expect(skin.cursor("new.cursor"), isNotNull);
    expect(skin.cursor("old.cursor"), isNotNull);
    expect(skin.cursor("nope"), isNull);

    final layout = skin.container("main")!.layout("normal")!;
    // The layout's snap points: from the top left, or from the right edge
    // when `relatx="0"`.
    final points = layout.snapPoints;
    expect(points.map((p) => p.id), ["top", "edge"]);
    expect(points[0].at(const Size(80, 60)), const Offset(17, 27));
    expect(points[1].at(const Size(80, 60)), const Offset(75, 0));

    final group = layout.root.children.firstWhere((c) => c.tag == "group");
    // The group keeps its place; its text parameters went to the text.
    expect(group["x"], "5");
    final inner = group.children.single;
    expect(inner["text"], "Hello");
    expect(inner["fontsize"], "20");
    expect(inner["x"], "0");
  });
}
