import "dart:math";
import "dart:typed_data";

import "package:amped_vis/amped_vis.dart";
import "package:flutter_test/flutter_test.dart";

/// A plug-in of one module that fills its surface, for the worker to run.
class _TestPlugin implements VisPlugin {
  @override
  String get id => "test";

  @override
  String get description => "Test plug-in";

  @override
  late final List<VisModule> modules = [_TestModule()];

  @override
  Object? saveConfig() => null;

  @override
  void loadConfig(Object? config) {}
}

class _TestModule implements VisModule {
  @override
  String get description => "Fill";

  @override
  List<VisSetting> get settings => const [];

  @override
  int get spectrumChannels => 1;

  @override
  int get waveformChannels => 1;

  @override
  Duration get delay => const Duration(milliseconds: 20);

  @override
  bool get fullscreen => false;

  @override
  (int, int)? get resolution => null;

  @override
  bool init(VisContext context) => true;

  @override
  bool render(VisFrame frame, VisSurface surface) {
    surface.pixels.fillRange(0, surface.pixels.length, 0xFF8040FF);
    return true;
  }

  @override
  void quit() {}
}

List<VisPlugin> _testPlugins() => [_TestPlugin()];

Float32List _tone() => Float32List.fromList([
  for (var i = 0; i < 1024; i++) 0.5 * sin(2 * pi * 440 * i / 44100),
]);

void main() {
  classicTests();
  waveformTests();
  test("a worker draws a module's frames in its own isolate", () async {
    final plugin = _testPlugins().first;
    final worker = await VisWorker.start(
      plugins: _testPlugins,
      pluginId: plugin.id,
      module: 0,
      config: plugin.saveConfig(),
    );
    expect(worker, isNotNull);
    final tone = _tone();
    VisWorkerFrame? frame;
    for (var i = 0; i < 5; i++) {
      frame = await worker!.render(
        left: tone,
        right: tone,
        spectrumChannels: 1,
        waveformChannels: 1,
        width: 320,
        height: 200,
        title: "1. Artist - Song",
        positionSeconds: 1,
        lengthSeconds: 100,
      );
    }
    expect(frame, isNotNull);
    expect(frame!.keepRunning, isTrue);
    expect(frame.pixels.length, 320 * 200 * 4);
    expect(frame.pixels.any((b) => b != 0), isTrue);
    // A new size is drawn at once.
    final resized = await worker!.render(
      left: null,
      right: null,
      spectrumChannels: 1,
      waveformChannels: 1,
      width: 160,
      height: 100,
      title: "",
      positionSeconds: 0,
      lengthSeconds: 0,
    );
    expect(resized!.pixels.length, 160 * 100 * 4);
    worker.dispose();
    // Nothing answers after disposal.
    expect(
      await worker.render(
        left: null,
        right: null,
        spectrumChannels: 1,
        waveformChannels: 1,
        width: 8,
        height: 8,
        title: "",
        positionSeconds: 0,
        lengthSeconds: 0,
      ),
      isNull,
    );
  });

  test("an unknown plug-in or module gives no worker", () async {
    expect(
      await VisWorker.start(
        plugins: _testPlugins,
        pluginId: "nope",
        module: 0,
        config: null,
      ),
      isNull,
    );
    final plugin = _testPlugins().first;
    expect(
      await VisWorker.start(
        plugins: _testPlugins,
        pluginId: plugin.id,
        module: 99,
        config: null,
      ),
      isNull,
    );
  });
}

void classicTests() {
  test("the classic visualization draws in a worker too", () async {
    final worker = await VisWorker.startClassic();
    final tone = _tone();
    const options = ClassicVisOptions(refresh: 1);
    ClassicVisPicture? picture;
    for (var i = 0; i < 4; i++) {
      picture = await worker.classic(
        left: tone,
        right: tone,
        options: options,
        windowShade: false,
        draw: true,
      );
    }
    var lit = 0;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 76; x++) {
        if (picture!.pixelAt(x, y) > 1) lit++;
      }
    }
    expect(lit, greaterThan(0));
    // A cycle that doesn't draw gives no picture.
    expect(
      await worker.classic(
        left: tone,
        right: tone,
        options: options,
        windowShade: false,
        draw: false,
      ),
      isNull,
    );
    worker.dispose();
  });

  test("the controller shows pictures and blanks when stopped", () async {
    final controller = ClassicVisController();
    final tone = _tone();
    void tick({required bool running}) => controller.tick(
      running: running,
      keepPicture: false,
      options: const ClassicVisOptions(refresh: 1),
      windowShade: false,
      left: tone,
      right: tone,
    );
    for (var i = 0; i < 4; i++) {
      tick(running: true);
    }
    while (!controller.showing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.picture, isNotNull);
    tick(running: false);
    expect(controller.showing, isFalse);
    controller.dispose();
  });
}

void waveformTests() {
  /// The rows of [surface] that differ from its background (its first pixel).
  Set<int> litRows(VisSurface surface) => {
    for (var i = 0; i < surface.pixels.length; i++)
      if (surface.pixels[i] != surface.pixels[0]) i ~/ surface.width,
  };

  test("the waveform plug-in draws a line over its background", () {
    final module = WaveformVis().modules.single;
    expect(module.init(_NoContext()), isTrue);

    final flat = VisSurface(200, 80);
    expect(module.render(VisFrame.silent(), flat), isTrue);
    expect(litRows(flat), hasLength(1), reason: "silence is a flat line");

    final surface = VisSurface(200, 80);
    final tone = _tone();
    final frame = VisFrame.compute(tone, tone, waveformChannels: 1);
    expect(module.render(frame, surface), isTrue);
    expect(litRows(surface).length, greaterThan(10));
  });
}

class _NoContext implements VisContext {
  @override
  String get title => "";

  @override
  int get positionSeconds => 0;

  @override
  int get lengthSeconds => 0;
}
