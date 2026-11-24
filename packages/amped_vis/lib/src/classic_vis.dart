import "dart:math";
import "dart:typed_data";

/// The classic visualization's options (Preferences > Classic skins >
/// Visualization; `config_sa`, `config_safire`, ...), with the original's
/// defaults.
class ClassicVisOptions {
  const ClassicVisOptions({
    this.mode = ClassicVisMode.spectrum,
    this.analyzerStyle = AnalyzerStyle.normal,
    this.thinBands = false,
    this.scopeStyle = ScopeStyle.lines,
    this.peaks = true,
    this.falloff = 2,
    this.peakFalloff = 1,
    this.refresh = 2,
  });

  /// `config_sa`.
  final ClassicVisMode mode;

  /// `config_safire & 3`.
  final AnalyzerStyle analyzerStyle;

  /// `config_safire & 32`: one bar per column instead of bands of four.
  final bool thinBands;

  /// `(config_safire >> 2) & 3`.
  final ScopeStyle scopeStyle;

  /// `config_sa_peaks`.
  final bool peaks;

  /// `config_safalloff`, 0 (slowest) to 4 (fastest).
  final int falloff;

  /// `config_sa_peak_falloff`, 0 (slowest) to 4 (fastest).
  final int peakFalloff;

  /// `config_saref`: draw every this many 16 ms cycles (1 = full rate).
  final int refresh;

  ClassicVisOptions copyWith({
    ClassicVisMode? mode,
    AnalyzerStyle? analyzerStyle,
    bool? thinBands,
    ScopeStyle? scopeStyle,
    bool? peaks,
    int? falloff,
    int? peakFalloff,
    int? refresh,
  }) => ClassicVisOptions(
    mode: mode ?? this.mode,
    analyzerStyle: analyzerStyle ?? this.analyzerStyle,
    thinBands: thinBands ?? this.thinBands,
    scopeStyle: scopeStyle ?? this.scopeStyle,
    peaks: peaks ?? this.peaks,
    falloff: falloff ?? this.falloff,
    peakFalloff: peakFalloff ?? this.peakFalloff,
    refresh: refresh ?? this.refresh,
  );

  /// `config_safire` as the original packs it.
  int get _safire =>
      analyzerStyle.index | (scopeStyle.index << 2) | (thinBands ? 32 : 0);
}

enum ClassicVisMode { off, spectrum, oscilloscope }

enum AnalyzerStyle { normal, fire, line }

enum ScopeStyle { dots, lines, solid }

/// Turns PCM into the 75 values the classic visualization draws
/// (`classic_vis.cpp`).
abstract final class ClassicAnalyzer {
  /// The FFT window (`SABuffer`: 512 samples, Hann).
  static const int windowSize = 512;

  /// The samples the oscilloscope spans (`makeOscData`'s `little_block`).
  static const int scopeSamples = 576;

  static final Float32List _hann = Float32List.fromList([
    for (var i = 0; i < windowSize; i++)
      0.5 - 0.5 * cos(2 * pi * i / (windowSize - 1)),
  ]);

  /// The spectrum analyzer's 75 bars, 0..255 (`makeSpecData`), from the
  /// last [windowSize] samples of [left] and [right] (-1..1).
  static Uint8List spectrum(Float32List left, Float32List right) {
    final re = Float64List(windowSize);
    final im = Float64List(windowSize);
    final lo = left.length - windowSize;
    final ro = right.length - windowSize;
    for (var i = 0; i < windowSize; i++) {
      final l = lo + i >= 0 ? left[lo + i] : 0.0;
      final r = ro + i >= 0 ? right[ro + i] : 0.0;
      re[i] = (l + r) * _hann[i];
    }
    _fft(re, im);
    // Magnitudes of the first 256 bins; bin 0 pairs DC with Nyquist, as the
    // packed real FFT the original reads does.
    final wavetrum = Float64List(256);
    wavetrum[0] = sqrt(re[0] * re[0] + re[256] * re[256]) * 0.5;
    for (var i = 1; i < 256; i++) {
      wavetrum[i] = sqrt(re[i] * re[i] + im[i] * im[i]) * 0.5;
    }
    double at(int i) => i >= 0 && i < 256 ? wavetrum[i] : 0;

    final bla = 255 / _sapow(75);
    double warp(int x) => (_sapow(x.toDouble()) - 1) * bla;
    final out = Uint8List(75);
    var next = warp(0) + 1;
    for (var x = 0; x < 75; x++) {
      var binF = next;
      next = warp(x + 1) + 1;
      var value = 0.0;
      var bin = binF.floor();
      final end = min(next.floor(), 255);
      var mult = (bin + 1) - binF;
      var herm = true;
      do {
        if (bin == end) {
          mult = next - binF;
          herm = true;
        }
        if (herm) {
          final c = bin < 255 ? at(bin + 1) : 0.0;
          final d = bin < 254 ? at(bin + 2) : 0.0;
          value += _hermite(binF - bin, at(bin - 1), at(bin), c, d) * mult;
        } else {
          value += at(bin);
        }
        herm = false;
        bin++;
        binF = bin.toDouble();
      } while (bin <= end);
      out[x] = min(value, 255.0).toInt().clamp(0, 255);
    }
    return out;
  }

  /// The oscilloscope's 75 points, -16..15 (`makeOscData`: the nearest
  /// sample, averaged over the channels, at 6-bit resolution), from the
  /// last [scopeSamples] samples.
  static Int8List oscilloscope(Float32List left, Float32List right) {
    final out = Int8List(75);
    final lo = left.length - scopeSamples;
    final ro = right.length - scopeSamples;
    for (var x = 0; x < 75; x++) {
      final index = (x * scopeSamples / 75).toInt();
      // The most significant byte of a 16-bit sample, divided by 8.
      double msb(Float32List samples, int i) => i >= 0 && i < samples.length
          ? ((samples[i] * 32767).clamp(-32768, 32767).toInt() >> 8) / 8
          : 0;
      final value = (msb(left, lo + index) + msb(right, ro + index)) / 2;
      out[x] = value.toInt();
    }
    return out;
  }

  /// `SAPOW`: 2^(x/12).
  static double _sapow(double x) => pow(2, x / 12).toDouble();

  static double _hermite(double x, double y0, double y1, double y2, double y3) {
    final c0 = y1;
    final c1 = 0.5 * (y2 - y0);
    final c3 = 1.5 * (y1 - y2) + 0.5 * (y3 - y0);
    final c2 = y0 - y1 + c1 - c3;
    return ((c3 * x + c2) * x + c1) * x + c0;
  }

  /// In-place radix-2 FFT (unnormalized, as the original's).
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var length = 2; length <= n; length <<= 1) {
      final angle = -2 * pi / length;
      final wr = cos(angle), wi = sin(angle);
      for (var start = 0; start < n; start += length) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < length ~/ 2; k++) {
          final a = start + k, b = a + length ~/ 2;
          final xr = re[b] * cr - im[b] * ci;
          final xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final nr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nr;
        }
      }
    }
  }
}

/// Draws the classic visualization as `draw_sa` does (single size), keeping
/// its falloff state between frames.
///
/// The picture is a buffer of viscolor indices (0..23) in the original's
/// bottom-up 152×32 layout; [pixelAt] reads it the right way up.
class ClassicVisRenderer {
  static const int _stride = 76 * 2;

  final Uint8List _buffer = Uint8List(_stride * 32);
  final List<int> _bx = List.filled(75, 0);
  final List<int> _peak = List.filled(75, 0);
  final List<double> _peakSpeed = List.filled(75, 0);

  static const List<int> _falloffs = [3, 6, 12, 16, 32];
  static const List<double> _peakFalloffs = [1.05, 1.1, 1.2, 1.4, 1.6];

  /// The viscolor index of the pixel at [x], [y] (from the top left) of
  /// the visualization area: 76×16, or 38×5 with [windowShade].
  int pixelAt(int x, int y, {required bool windowShade}) =>
      _buffer[(31 - y) * _stride + x];

  /// A copy of the picture drawn so far.
  ClassicVisPicture snapshot() =>
      ClassicVisPicture(Uint8List.fromList(_buffer));

  /// One cycle from the latest samples (silence when null): the
  /// [ClassicAnalyzer]'s values, then [render]. Returns the picture when this cycle [draw]s, else null.
  ClassicVisPicture? cycle(
    Float32List? left,
    Float32List? right,
    ClassicVisOptions options, {
    required bool windowShade,
    required bool draw,
  }) {
    final Uint8List values;
    if (left == null || right == null) {
      values = Uint8List(75);
    } else if (options.mode == ClassicVisMode.oscilloscope) {
      values = Uint8List.sublistView(ClassicAnalyzer.oscilloscope(left, right));
    } else {
      values = ClassicAnalyzer.spectrum(left, right);
    }
    render(values, options, windowShade: windowShade, draw: draw);
    return draw ? snapshot() : null;
  }

  /// Forgets the bars' falloff (when the visualization is blanked).
  void reset() {
    _bx.fillRange(0, 75, 0);
    _buffer.fillRange(0, _buffer.length, 0);
  }

  /// One 16 ms cycle: updates the falloff from [values] (75 spectrum values
  /// 0..255, or 75 signed oscilloscope values) and, with [draw], redraws.
  void render(
    Uint8List values,
    ClassicVisOptions options, {
    required bool windowShade,
    required bool draw,
  }) {
    final safire = options._safire;
    final dbx = _falloffs[options.falloff.clamp(0, 4)];
    final spfo = _peakFalloffs[options.peakFalloff.clamp(0, 4)];
    final b = _buffer;
    if (draw) {
      if (!windowShade) {
        // Rows of dots (colour 1 on even columns) between black rows.
        var row = _stride * 16;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 76; x++) {
            b[row + x] = x.isEven ? 1 : 0;
          }
          row += _stride;
          b.fillRange(row, row + 76, 0);
          row += _stride;
        }
      } else {
        var row = _stride * (16 - 5) + _stride * 16;
        for (var y = 0; y < 5; y++) {
          b.fillRange(row, row + 38, 0);
          row += _stride;
        }
      }
    }
    final signed = Int8List.sublistView(values);
    final scope = options.mode == ClassicVisMode.oscilloscope;
    if (!windowShade) {
      if (scope) {
        if (!draw) return;
        const base = _stride * 14;
        final style = (safire >> 2) & 3;
        var last = -1;
        for (var x = 0; x < 75; x++) {
          final v = (signed[x] + 8).clamp(0, 15);
          final c = (v ~/ 2 - 4).abs() + 18;
          switch (style) {
            case 0:
              b[base + v * _stride + x] = c;
            case 1:
              if (last == -1) last = v;
              final from = last;
              last = v;
              if (v >= from) {
                for (var y = v; y >= from; y--) {
                  b[base + y * _stride + x] = c;
                }
              } else {
                for (var y = v; y < from; y++) {
                  b[base + y * _stride + x] = c;
                }
              }
            default:
              if (v > 7) {
                for (var y = v; y > 7; y--) {
                  b[base + y * _stride + x] = c;
                }
              } else {
                for (var y = v; y <= 7; y++) {
                  b[base + y * _stride + x] = c;
                }
              }
          }
        }
        return;
      }
      for (var x = 0; x < 75; x++) {
        var v = _band(values, x, safire);
        if (v > 15) v = 15;
        if ((v << 4) < _bx[x]) {
          v = (_bx[x] -= dbx) >> 4;
        } else {
          _bx[x] = v << 4;
        }
        if (_bx[x] < 0) _bx[x] = 0;
        if (v < 0) v = 0;
        final color = switch (safire & 3) {
          1 => v + 2,
          2 => 17 - v,
          _ => 17,
        };
        if (_peak[x] <= v * 256) {
          _peak[x] = v * 256;
          _peakSpeed[x] = 3;
        }
        if (draw && (safire & 32 != 0 || x & 3 != 3)) {
          var at = _stride * 14 + x;
          for (var y = 0; y < v; y++) {
            b[at] = (safire & 3) != 2 ? color - y : color;
            at += _stride;
          }
          final p = _peak[x] ~/ 256;
          if (options.peaks && p >= 0 && p <= 15) {
            b[_stride * 14 + p * _stride + x] = 23;
          }
        }
        _peak[x] -= _peakSpeed[x].toInt();
        _peakSpeed[x] *= spfo;
        if (_peak[x] < 0) _peak[x] = 0;
      }
      return;
    }
    // Window shade.
    const base = _stride * (32 - 5);
    if (scope) {
      if (!draw) return;
      final style = (safire >> 2) & 3;
      var last = -5;
      for (var x = 0; x < 38; x++) {
        final v = ((signed[x] + 8) * 5 ~/ 16).clamp(0, 4);
        if (style == 0 || last == -5) {
          last = v;
          b[base + x + v * _stride] = 18;
        } else if (style == 1) {
          final from = last;
          last = v;
          if (v >= from) {
            for (var y = v; y >= from; y--) {
              b[base + x + y * _stride] = 18;
            }
          } else {
            for (var y = v; y <= from; y++) {
              b[base + x + y * _stride] = 18;
            }
          }
        } else if (v >= 2) {
          for (var y = v; y >= 2; y--) {
            b[base + x + y * _stride] = 18;
          }
        } else {
          for (var y = v; y <= 2; y++) {
            b[base + x + y * _stride] = 18;
          }
        }
      }
      return;
    }
    for (var x = 0; x < 37; x++) {
      final i = x * 2;
      int at(int j) => j < values.length ? values[j] : 0;
      final t = (x & ~3) * 2;
      var v = safire & 32 != 0
          ? (at(i) + at(i + 1)) ~/ 2
          : (at(t) + at(t + 1) + at(t + 2) + at(t + 3)) ~/ 4;
      if (v > 15) v = 15;
      if ((v << 4) < _bx[i]) {
        v = (_bx[i] -= dbx) >> 4;
      } else {
        _bx[i] = v << 4;
      }
      if (_bx[i] < 0) _bx[i] = 0;
      if (v < 0) v = 0;
      final color = switch (safire & 3) {
        1 => v + 2,
        2 => 17 - v,
        _ => 17,
      };
      if (_peak[i] <= v * 256) {
        _peak[i] = v * 256;
        _peakSpeed[i] = 3;
      }
      v = min(v * 5 ~/ 15, 5);
      if (draw && (safire & 32 != 0 || x & 3 != 3)) {
        final p = _peak[i] * 5 ~/ 15 ~/ 256;
        var at = base + x;
        for (var y = 0; y < v; y++) {
          b[at] = (safire & 3) != 2 ? color - (y * 15) ~/ 5 : color;
          at += _stride;
        }
        if (options.peaks && p >= 0 && p <= 4) {
          b[base + p * _stride + x] = 23;
        }
      }
      _peak[i] -= _peakSpeed[i].toInt();
      _peakSpeed[i] *= spfo;
      if (_peak[i] < 0) _peak[i] = 0;
    }
  }

  /// A bar's value: the average of its band of four, or its own with thin
  /// bands.
  static int _band(Uint8List values, int x, int safire) {
    if (safire & 32 != 0) return values[x];
    final t = x & ~3;
    int at(int i) => i < values.length ? values[i] : 0;
    return (at(t) + at(t + 1) + at(t + 2) + at(t + 3)) ~/ 4;
  }
}

/// A picture the classic visualization drew: viscolor indices (0..23) in
/// the original's bottom-up 152×32 layout.
class ClassicVisPicture {
  const ClassicVisPicture(this.buffer);

  static const int _stride = 76 * 2;

  final Uint8List buffer;

  /// The viscolor index of the pixel at [x], [y] (from the top left) of
  /// the visualization area: 76×16, or 38×5 in window shade.
  int pixelAt(int x, int y) => buffer[(31 - y) * _stride + x];
}
