import "dart:math";
import "dart:typed_data";

import "package:amped_vis/amped_vis.dart";
import "package:flutter_test/flutter_test.dart";

Float32List _sine(double frequency, double amplitude, [int length = 1024]) =>
    Float32List.fromList([
      for (var i = 0; i < length; i++)
        amplitude * sin(2 * pi * frequency * i / 44100),
    ]);

void main() {
  test("silence draws no bars", () {
    final silence = Float32List(1024);
    expect(ClassicAnalyzer.spectrum(silence, silence), everyElement(0));
    expect(ClassicAnalyzer.oscilloscope(silence, silence), everyElement(0));
  });

  test("a tone lights the bar for its frequency", () {
    // The bars are spaced in semitones: bar x covers bins from
    // (2^(x/12) - 1) * 255 / 2^(75/12) + 1.
    double barOf(double frequency) {
      final bin = frequency / (44100 / 512);
      final bla = 255 / pow(2, 75 / 12);
      return 12 * log(((bin - 1) / bla) + 1) / ln2;
    }

    for (final frequency in [440.0, 2000.0, 8000.0]) {
      final tone = _sine(frequency, 0.1);
      final bars = ClassicAnalyzer.spectrum(tone, tone);
      var loudest = 0;
      for (var x = 1; x < 75; x++) {
        if (bars[x] > bars[loudest]) loudest = x;
      }
      expect(loudest, closeTo(barOf(frequency), 1.5), reason: "$frequency Hz");
      expect(bars[loudest], greaterThan(3));
    }
  });

  test("the oscilloscope follows the waveform at 6-bit resolution", () {
    final tone = _sine(44100 / 576, 1, 576);
    final points = ClassicAnalyzer.oscilloscope(tone, tone);
    // One cycle across the 75 points: up, then down.
    expect(points[0], 0);
    expect(points[18], 15);
    expect(points[56], -16);
  });

  test("bars fall off at the configured speed and leave peaks", () {
    final renderer = ClassicVisRenderer();
    const options = ClassicVisOptions(thinBands: true);
    final loud = Uint8List(75)..fillRange(0, 75, 15);
    renderer.render(loud, options, windowShade: false, draw: true);
    // Bottom row (y 15) shows the bar; the original clips two rows.
    expect(renderer.pixelAt(0, 15, windowShade: false), 15);
    expect(renderer.pixelAt(0, 3, windowShade: false), 3);
    // A peak marker (colour 23) above the bar.
    expect(renderer.pixelAt(0, 2, windowShade: false), 23);

    final quiet = Uint8List(75);
    for (var i = 0; i < 4; i++) {
      renderer.render(quiet, options, windowShade: false, draw: true);
    }
    // Falloff 2 drops 12/16 of a pixel per cycle: 15 -> 12 after 4 cycles.
    expect(renderer.pixelAt(0, 4, windowShade: false), isNot(4));
    expect(renderer.pixelAt(0, 15, windowShade: false), 15);
    // Background dots between black rows where nothing is drawn.
    expect(renderer.pixelAt(1, 0, windowShade: false), anyOf(0, 1));
  });
}
