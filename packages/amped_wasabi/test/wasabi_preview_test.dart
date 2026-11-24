import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a skin preview shows its main window and playlist editor", (
    tester,
  ) async {
    late WasabiSkinPreviewController controller;
    await tester.runAsync(() async {
      controller = WasabiSkinPreviewController(
        directory: Directory("test/fixtures/amped"),
        name: "Amped",
        title: "Amped",
        settings: () async => (null, const <WasabiGammaSet>[]),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WasabiSkinPreview(controller: controller),
        ),
      );
      // The skin loads in real time.
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    addTearDown(controller.dispose);
    await tester.pump();
    expect(controller.loaded, isTrue);
    expect(find.byType(WasabiLayoutView), findsAtLeastNWidgets(2));
    // Nothing is changed yet.
    expect(controller.themeDirty, isFalse);
  });

  test(
    "a preview host reads real settings but writes them only on request",
    () {
      final storage = FakeHost()..private["Skin/config/Opt"] = "1";
      final host = WasabiPreviewHost(title: "Amped", storage: storage);
      expect(host.songTitle, "Amped");
      expect(host.visRunning, isFalse);
      expect(host.readPrivate("Skin/config", "Opt"), "1");

      // What the skin does by itself on starting stays here.
      host.writePrivate("Skin/config", "Opt", "0");
      expect(host.readPrivate("Skin/config", "Opt"), "0");
      expect(storage.private["Skin/config/Opt"], "1");

      host.writeThrough = true;
      host.writePrivate("Skin/config", "Opt", "2");
      expect(storage.private["Skin/config/Opt"], "2");
    },
  );
}
