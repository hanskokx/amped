import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("Amped Modern's About panel runs its credits", (tester) async {
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(ampedModern),
    ))!;
    expect(WasabiAboutPanel.isIn(skin), isTrue);
    // Its text is light on dark art in every color theme (`gammagroup=""`).
    expect(
      skin.color("font.about.color2"),
      skin.sourceColor("font.about.color2"),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: WasabiAboutPanel.size,
            child: WasabiAboutPanel(skin: skin, host: FakeHost()),
          ),
        ),
      ),
    );
    // The script's timers bring the credits in a line at a time.
    final layout = tester
        .widget<WasabiLayoutView>(find.byType(WasabiLayoutView))
        .layout;
    final lines = [
      for (final object in layout.root.children)
        if (object.id.startsWith("about.text")) object,
    ];
    var credits = false;
    for (var i = 0; i < 200 && !credits; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      credits = lines.any(
        (line) => line.attributes.values.any(
          (value) => value.contains("by Sven Kistner"),
        ),
      );
    }
    expect(credits, isTrue);

    // Closing it stops the scripts: no timer of theirs is left running.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a skin without the group has no panel", (tester) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_about");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="200" h="50"/></container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    expect(WasabiAboutPanel.isIn(skin), isFalse);
  });
}
