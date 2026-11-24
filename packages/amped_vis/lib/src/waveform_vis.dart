import "package:amped_vis_api/amped_vis_api.dart";

/// A very simple visualization plug-in: the waveform as one line. The app
/// always has it, so there is something to show when it is built without a
/// bigger plug-in.
class WaveformVis implements VisPlugin {
  WaveformVis();

  @override
  String get id => "waveform";

  @override
  String get description => "Waveform";

  @override
  late final List<VisModule> modules = [_WaveformModule()];

  @override
  Object? saveConfig() => null;

  @override
  void loadConfig(Object? config) {}
}

class _WaveformModule implements VisModule {
  static const int _background = 0xFF1A1020;
  static const int _line = 0xFF9ABBF4; // 0xAABBGGRR: a peach.

  @override
  String get description => "Waveform";

  @override
  List<VisSetting> get settings => const [];

  @override
  int get spectrumChannels => 0;

  @override
  int get waveformChannels => 1;

  @override
  Duration get delay => const Duration(milliseconds: 25);

  @override
  bool get fullscreen => false;

  @override
  (int, int)? get resolution => null;

  @override
  bool init(VisContext context) => true;

  @override
  bool render(VisFrame frame, VisSurface surface) {
    final width = surface.width;
    final height = surface.height;
    surface.pixels.fillRange(0, surface.pixels.length, _background);
    final samples = frame.waveform[0];
    var previousX = 0;
    var previousY = _y(samples[0], height);
    for (var x = 1; x < width; x++) {
      final y = _y(samples[x * (samples.length - 1) ~/ (width - 1)], height);
      _segment(surface, previousX, previousY, x, y);
      previousX = x;
      previousY = y;
    }
    return true;
  }

  /// The row of a signed sample byte: 0 is the middle, 127 the top.
  static int _y(int sample, int height) =>
      ((127 - sample.toSigned(8)) * (height - 1) / 255).round().clamp(
        0,
        height - 1,
      );

  /// A vertical run of pixels in column [x1], joining [y0] to [y1].
  static void _segment(VisSurface surface, int x0, int y0, int x1, int y1) {
    final low = y0 < y1 ? y0 : y1;
    final high = y0 < y1 ? y1 : y0;
    for (var y = low; y <= high; y++) {
      surface.pixels[y * surface.width + x1] = _line;
    }
  }

  @override
  void quit() {}
}
