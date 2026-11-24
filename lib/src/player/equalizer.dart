import "dart:math";

/// The original equalizer's numbers (`In.cpp`, `eq10dsp.cpp`).
///
/// Slider values are the original's: 0..63, with 0 at the top (+12 dB), 31
/// at 0 dB and 63 at the bottom (-12 dB).
abstract final class Equalizer {
  /// The band centers in Hz (`eq10_freq`, the "classic style" table).
  static const List<double> frequencies = [
    70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000, //
  ];

  /// The 4Front EQ's `Q` (`EQ10_Q`); boosting bands use twice it and
  /// cutting bands half (`eq10_bsetup`).
  static const double q = 1.41;

  /// The bands of the filter that reproduces the original's response: many
  /// narrow bells, log-spaced over the audible range, whose gains are fitted
  /// to the 4Front cascade's curve ([fittedGains]).
  static final List<double> fitFrequencies = [
    for (var i = 0; i < _fitBands; i++)
      20 * pow(1000, i / (_fitBands - 1)).toDouble(),
  ];

  /// The `Q` of each fitted band.
  static const double fitQ = 3;

  static const int _fitBands = 64;

  /// The limiter's trim level (`EQ10_TRIM_CODE`, -0.6 dB) and release
  /// (`EQ10_TRIM_RELEASE`), applied while the EQ runs (`config_eq_limiter`,
  /// on by default).
  static const double limiterThresholdDb = -0.6;
  static const Duration limiterRelease = Duration(milliseconds: 700);

  /// The preamp gains (`eq_lookup1`), by original slider value.
  static const List<double> _preampGains = [
    4.000000, 3.610166, 3.320019, 3.088821, 2.896617, 2.732131, 2.588368, //
    2.460685, 2.345845, 2.241498, 2.145887, 2.057660, 1.975760, 1.899338,
    1.827707, 1.760303, 1.696653, 1.636363, 1.579094, 1.524558, 1.472507,
    1.422724, 1.375019, 1.329225, 1.285197, 1.242801, 1.201923, 1.162456,
    1.124306, 1.087389, 1.051628, 1.000000, 0.983296, 0.950604, 0.918821,
    0.887898, 0.857789, 0.828454, 0.799853, 0.771950, 0.744712, 0.718108,
    0.692110, 0.666689, 0.641822, 0.617485, 0.593655, 0.570311, 0.547435,
    0.525008, 0.503013, 0.481433, 0.460253, 0.439458, 0.419035, 0.398970,
    0.379252, 0.359868, 0.340807, 0.322060, 0.303614, 0.285462, 0.267593,
    0.250000,
  ];

  /// The slider value of 0 dB.
  static const int neutral = 31;

  /// The gain in dB of a band slider at [value] (`VALTODB`).
  static double bandDb(int value) {
    final v = value.clamp(0, 63) - neutral;
    if (v > 0) return -12.0 * (v / 32.0);
    if (v < 0) return -12.0 * (v / 31.0);
    return 0;
  }

  /// The linear gain of a band slider at [value] at its center.
  static double bandGain(int value) => pow(10, bandDb(value) / 20).toDouble();

  /// The magnitude of the original's EQ (`eq10_processf`: the bands in
  /// series, each adding a gain-scaled bandpass of its input) at
  /// [frequency] for the band [values], at [sampleRate].
  static double response(
    List<int> values,
    double frequency, {
    double sampleRate = 44100,
  }) {
    // z^-1 = e^(-jw)
    final w = 2 * pi * frequency / sampleRate;
    final z1r = cos(w), z1i = -sin(w);
    final z2r = cos(2 * w), z2i = -sin(2 * w);
    var hr = 1.0, hi = 0.0;
    for (var k = 0; k < frequencies.length; k++) {
      final gain = bandGain(values[k]) - 1;
      if (gain == 0) continue;
      final bandQ = gain > 0 ? q * 2 : q * 0.5;
      final angle = 2 * pi * frequencies[k] / sampleRate;
      if (frequencies[k] >= sampleRate * 0.499) continue;
      final alpha = sin(angle) / (2 * bandQ);
      final b0 = 1 / (1 + alpha);
      final a0 = b0 * alpha, b1 = b0 * 2 * cos(angle), b2 = b0 * (alpha - 1);
      // 1 + gain * a0 * (1 - z^-2) / (1 - b1 z^-1 - b2 z^-2)
      final nr = gain * a0 * (1 - z2r), ni = gain * a0 * -z2i;
      final dr = 1 - b1 * z1r - b2 * z2r, di = -b1 * z1i - b2 * z2i;
      final d = dr * dr + di * di;
      final fr = 1 + (nr * dr + ni * di) / d, fi = (ni * dr - nr * di) / d;
      final r = hr * fr - hi * fi;
      hi = hr * fi + hi * fr;
      hr = r;
    }
    return sqrt(hr * hr + hi * hi);
  }

  /// The gains of the [fitFrequencies] bands (bells of [fitQ], multiplied
  /// together) that reproduce [response] for the band [values].
  static List<double> fittedGains(
    List<int> values, {
    double sampleRate = 44100,
  }) {
    final n = fitFrequencies.length;
    final target = [
      for (final f in fitFrequencies)
        response(values, f, sampleRate: sampleRate),
    ];
    // weights[i][j]: band j's bell at band i's center.
    final weights = [
      for (final f in fitFrequencies)
        [
          for (final c in fitFrequencies)
            exp(-pow(log(f / c), 2) * 4.16277 * fitQ * fitQ).toDouble(),
        ],
    ];
    final gains = List.of(target);
    for (var iteration = 0; iteration < 40; iteration++) {
      final actual = [
        for (var i = 0; i < n; i++)
          () {
            var total = 1.0;
            for (var j = 0; j < n; j++) {
              total *= 1 + (gains[j] - 1) * weights[i][j];
            }
            return total;
          }(),
      ];
      for (var i = 0; i < n; i++) {
        gains[i] = (gains[i] * sqrt(target[i] / actual[i])).clamp(0.001, 4.0);
      }
    }
    return gains;
  }

  /// The linear gain of the preamp slider at [value].
  static double preampGain(int value) => _preampGains[value.clamp(0, 63)];

  /// Whether the EQ processes audio at all: on, and not entirely flat
  /// (`filter_enabled` in `eq_set`).
  static bool isActive({
    required bool enabled,
    required int preamp,
    required List<int> bands,
  }) => enabled && (preamp != neutral || bands.any((band) => band != neutral));
}
