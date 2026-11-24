import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a component holder's noshowcmdbar reaches its component", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("holder_flags");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="100" h="60">
    <component id="a" x="0" y="0" w="100" h="30" param="guid:ml" noshowcmdbar="1"/>
    <component id="b" x="0" y="30" w="100" h="30" param="guid:avs"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    bool? ml;
    bool? vis;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 60,
            child: WasabiLayoutView(
              skin: skin,
              host: FakeHost(),
              container: "main",
              layout: skin.container("main")!.layout("normal")!,
              components: {
                "ml": Builder(
                  builder: (context) {
                    ml = WasabiComponentOptions.maybeOf(context)?.noCommandBar;
                    return const SizedBox.shrink();
                  },
                ),
                "vis": Builder(
                  builder: (context) {
                    vis = WasabiComponentOptions.maybeOf(context)?.noCommandBar;
                    return const SizedBox.shrink();
                  },
                ),
              },
            ),
          ),
        ),
      ),
    );
    expect(ml, isTrue);
    expect(vis, isFalse);
  });
}
