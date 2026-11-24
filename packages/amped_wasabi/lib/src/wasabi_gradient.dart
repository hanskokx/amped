import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" as ui;

/// A `$gradient` image (Wasabi's `GradientImage` generator): a bitmap element
/// whose `file` is `$gradient` is drawn from `w`, `h`, `mode` (`linear` or
/// `circular`), `gradient_x1`..`gradient_y2` (in fractions of the size),
/// `points` (`position=r,g,b[,a]` separated by `;`) and `antialias`.
///
/// Returns premultiplied RGBA pixels, or null when the size is empty.
Uint8List? renderWasabiGradient({
  required int width,
  required int height,
  required String mode,
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required String points,
  bool antialias = false,
}) {
  final w = width == 0 ? 1 : width;
  final h = height == 0 ? 1 : height;
  if (w < 0 || h < 0 || w * h > 16 * 1024 * 1024) return null;
  final stops = <_Stop>[];
  for (final part in points.split(";")) {
    final pair = part.split("=");
    if (pair.length != 2) continue;
    final position = double.tryParse(pair[0].trim());
    if (position == null) continue;
    final channels = [
      for (final value in pair[1].split(","))
        int.tryParse(value.trim())?.clamp(0, 255) ?? 0,
    ];
    if (channels.length < 3) continue;
    stops.add(
      _Stop(
        position,
        channels.length > 3 ? channels[3] : 255,
        channels[0],
        channels[1],
        channels[2],
      ),
    );
  }
  stops.sort((a, b) => a.position.compareTo(b.position));
  // 0xAARRGGBB, as the original keeps it.
  final argb = Uint32List(w * h)..fillRange(0, w * h, 0xFFFF00FF);
  if (stops.length == 1) {
    argb.fillRange(0, w * h, stops.first.color);
  }
  if (stops.length > 1) {
    if (mode.toLowerCase() == "circular") {
      _circular(argb, w, h, x1, y1, x2, y2, stops, antialias);
    } else {
      _linear(argb, w, h, x1, y1, x2, y2, stops);
    }
  }
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    final c = argb[i];
    final a = c >> 24;
    out[i * 4] = ((c >> 16 & 0xFF) * a / 255).round();
    out[i * 4 + 1] = ((c >> 8 & 0xFF) * a / 255).round();
    out[i * 4 + 2] = ((c & 0xFF) * a / 255).round();
    out[i * 4 + 3] = a;
  }
  return out;
}

/// The image of [renderWasabiGradient]'s pixels.
Future<ui.Image?> wasabiGradientImage(
  int width,
  int height,
  Uint8List? rgba,
) async {
  if (rgba == null) return null;
  final w = width == 0 ? 1 : width;
  final h = height == 0 ? 1 : height;
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

class _Stop {
  _Stop(this.position, this.a, this.r, this.g, this.b);

  final double position;
  final int a;
  final int r;
  final int g;
  final int b;

  int get color => a << 24 | r << 16 | g << 8 | b;
}

int _lerpInt(int a, int b, double p) => (b * p + a * (1 - p)).toInt();

int _colorLerp(int c1, int c2, double p) =>
    _lerpInt(c1 >> 24 & 0xFF, c2 >> 24 & 0xFF, p) << 24 |
    _lerpInt(c1 >> 16 & 0xFF, c2 >> 16 & 0xFF, p) << 16 |
    _lerpInt(c1 >> 8 & 0xFF, c2 >> 8 & 0xFF, p) << 8 |
    _lerpInt(c1 & 0xFF, c2 & 0xFF, p);

/// `Gradient::renderGradient`, linear: each scanline takes the colors where
/// the lines through the stops, across the gradient's direction, cross it.
void _linear(
  Uint32List bits,
  int w,
  int h,
  double x1,
  double y1,
  double x2,
  double y2,
  List<_Stop> stops,
) {
  // A vertical line is forced to a slightly slanted one.
  if ((x1 - x2).abs() < 0.0005) x2 = x1 + 0.0005;
  final px1 = x1 * w;
  final py1 = y1 * h;
  final px2 = x2 * w;
  final py2 = y2 * h;
  var m = (py2 - py1) / (px2 - px1);
  m = -1 / m;
  final xs = [for (final s in stops) px1 * (1 - s.position) + px2 * s.position];
  final ys = [for (final s in stops) py1 * (1 - s.position) + py2 * s.position];
  final positions = List<int>.filled(stops.length, 0);
  for (var y = 0; y < h; y++) {
    for (var i = 0; i < stops.length; i++) {
      // A level gradient's lines across it are straight up and down.
      final x = m.isFinite ? (y - (ys[i] - m * xs[i])) / m : xs[i];
      positions[i] = (x + 0.5).floor();
    }
    for (var i = 0; i < stops.length - 1; i++) {
      var c1 = stops[i].color;
      var c2 = stops[i + 1].color;
      var a = positions[i];
      var z = positions[i + 1];
      if (a == z) continue;
      if (a > z) {
        final t = a;
        a = z;
        z = t;
        final c = c1;
        c1 = c2;
        c2 = c;
      }
      var c = 0.0;
      final length = (z - a + 1).toDouble();
      if (a < 0) {
        c += -a;
        a = 0;
      }
      for (var x = a; x < z; x++, c += 1) {
        if (x >= w) break;
        bits[y * w + x] = _colorLerp(c1, c2, c / length);
      }
    }
  }
}

/// Circular: the color at a distance from (x1, y1), the stops placed along
/// the distance from there to (x2, y2).
void _circular(
  Uint32List bits,
  int w,
  int h,
  double x1,
  double y1,
  double x2,
  double y2,
  List<_Stop> stops,
  bool antialias,
) {
  final total = math.sqrt(math.pow(x1 - x2, 2) + math.pow(y1 - y2, 2));
  final distances = [for (final s in stops) s.position * total];
  int pixel(double fx, double fy) {
    final dist = math.sqrt(math.pow(fx - x1, 2) + math.pow(fy - y1, 2));
    if (dist <= distances.first) return stops.first.color;
    if (dist >= distances.last) return stops.last.color;
    for (var i = 0; i < stops.length - 1; i++) {
      if (distances[i] <= dist && distances[i + 1] >= dist) {
        final span = distances[i + 1] - distances[i];
        final p = (dist - distances[i]) / span;
        final c1 = stops[i].color;
        final c2 = stops[i + 1].color;
        return c1 == c2 ? c1 : _colorLerp(c1, c2, p);
      }
    }
    return 0xFF00FF00;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      int c;
      if (antialias) {
        final ul = pixel((x - 0.5) / w, (y - 0.5) / h);
        final ur = pixel((x + 0.5) / w, (y - 0.5) / h);
        final lr = pixel((x + 0.5) / w, (y + 0.5) / h);
        final ll = pixel((x - 0.5) / w, (y + 0.5) / h);
        c = _colorLerp(_colorLerp(ll, lr, 0.5), _colorLerp(ul, ur, 0.5), 0.5);
      } else {
        c = pixel(x / w, y / h);
      }
      bits[y * w + x] = c;
    }
  }
}
