import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

void main() {
  test("song info text reads like the classic player's core", () {
    expect(
      wasabiSongInfoText(bitrate: 128, sampleRate: 44100, channels: 2),
      "128kbps stereo 44.1kHz",
    );
    expect(
      wasabiSongInfoText(bitrate: 96, sampleRate: 22050, channels: 1),
      "96kbps mono 22.1kHz",
    );
    expect(
      wasabiSongInfoText(bitrate: 640, sampleRate: 48000, channels: 6),
      "640kbps 6 Channels 48.0kHz",
    );
    expect(wasabiSongInfoText(bitrate: 0, sampleRate: 0, channels: 2), "");
  });

  group("Amped Modern main window", () {
    late WasabiSkinData skin;
    late FakeHost host;
    late WasabiScriptRuntime runtime;
    late WasabiLayout main;

    Future<void> pump(WidgetTester tester) async {
      skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
      host = FakeHost()..songInfoText = "128kbps stereo 44.1kHz";
      runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
        ..start();
      main = skin.container("main")!.layout("normal")!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: skin,
              layout: main,
              host: host,
              container: "main",
              scripts: runtime,
            ),
          ),
        ),
      );
    }

    testWidgets("songinfo.maki fills the kbps and kHz displays", (
      tester,
    ) async {
      await pump(tester);
      final bitrate = runtime.find(main.root, "Bitrate")!;
      final frequency = runtime.find(main.root, "Frequency")!;
      expect(bitrate["#text"], "[128]");
      expect(frequency["#text"], "[44]");

      // The script polls the info once a second while playing.
      host
        ..songInfoText = "320kbps mono 48.0kHz"
        ..notifyListeners();
      await tester.pump(const Duration(seconds: 1));
      expect(bitrate["#text"], "[320]");
      expect(frequency["#text"], "[48]");
      runtime.dispose();
    });
  });
}
