import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("double and right click actions of a text, wrapped text", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("text_actions");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="100" h="60">
    <text id="song" x="0" y="0" w="100" h="14" text="Title"
      dblclickaction="trackinfo" rightclickaction="trackmenu"/>
    <text id="note" x="0" y="20" w="60" h="40" text="one two three four five six" wrap="1"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 60,
            child: WasabiLayoutView(
              skin: skin,
              host: host,
              container: "main",
              layout: skin.container("main")!.layout("normal")!,
            ),
          ),
        ),
      ),
    );
    final at =
        tester.getTopLeft(find.byType(WasabiLayoutView)) + const Offset(10, 5);
    // A right press runs the action.
    final right = await tester.startGesture(at, buttons: kSecondaryButton);
    await right.up();
    expect(host.secondaryActions, ["TRACKMENU"]);
    // A double click runs the double-click action.
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump();
    expect(host.actions.map((a) => a.action), contains("TRACKINFO"));
  });
}
