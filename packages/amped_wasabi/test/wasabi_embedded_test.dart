import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets(
    "a skin's own components and equalizer are found, and shown by its buttons",
    (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync("wasabi_embedded");
      addTearDown(() => dir.deleteSync(recursive: true));
      File("${dir.path}/skin.xml").writeAsStringSync("""
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main"><layout id="normal" w="400" h="300">
  <slider id="eq1" action="EQ_BAND" param="1" x="0" y="0" w="10" h="50"/>
  <component dynamic="1" id="Video" x="10" y="20" w="100" h="80" autoopen="0" param="guid:{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}"/>
  <component dynamic="1" id="Pledit" x="10" y="20" w="100" h="80" autoopen="1" param="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}"/>
  <component id="MLibrary" x="10" y="150" w="100" h="80" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
</layout></container>
</WasabiXML>""");
      final skin = (await tester.runAsync(
        () => WasabiSkinData.load(Directory(dir.path)),
      ))!;
      expect(skin.hasBuiltInEq, isTrue);
      expect(skin.embeddedComponents("pl"), hasLength(1));
      expect(skin.embeddedComponents("ml"), hasLength(1));
      expect(skin.embeddedComponents("vis"), isEmpty);

      final runtime = WasabiScriptRuntime(
        skin: skin,
        host: FakeHost(),
        log: (_) {},
      )..start();
      addTearDown(runtime.dispose);
      // The video, which does not open by itself, waits; the playlist shows.
      expect(runtime.isEmbeddedComponentShown("video"), isFalse);
      expect(runtime.isEmbeddedComponentShown("pl"), isTrue);

      // Showing the video takes the playlist's place.
      expect(runtime.setEmbeddedComponent("video", true), isTrue);
      expect(runtime.isEmbeddedComponentShown("video"), isTrue);
      expect(runtime.isEmbeddedComponentShown("pl"), isFalse);
      // The library has a place of its own and is left alone.
      expect(runtime.isEmbeddedComponentShown("ml"), isTrue);

      // A component the skin does not have.
      expect(runtime.setEmbeddedComponent("vis", true), isFalse);
    },
  );
}
