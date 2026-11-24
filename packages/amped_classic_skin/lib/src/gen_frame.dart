import "dart:async";
import "dart:typed_data";
import "dart:ui" as ui;

import "classic_skin_data.dart";

/// Derives a `gen.bmp` for a skin that ships none, so the frame windows (the
/// notification, library, vis and album art windows, skinned dialogs) look
/// like the skin instead of the base skin's frame.
///
/// The result has the layout of `gen.bmp`, built from [base] with the frame
/// pieces replaced by the matching ones from the skin's own `pledit.bmp`
/// (title bar, side borders, bottom edge, close button and resize grip) and
/// the title-bar letters recoloured to the `pledit.txt` colours.
Future<ui.Image> deriveGenFrame({
  required ui.Image base,
  required ui.Image pledit,
  required PlEditConfig colors,
}) async {
  // A standard `pledit.bmp` is 280 x 186; anything smaller can't be sliced.
  if (pledit.width < 280 || pledit.height < 110) return base;
  final out = _Pixels(
    base.width,
    base.height,
    (await base.toByteData(format: ui.ImageByteFormat.rawRgba))!,
  );
  final src = _Pixels(
    pledit.width,
    pledit.height,
    (await pledit.toByteData(format: ui.ImageByteFormat.rawRgba))!,
  );
  if (out.width < 194 || out.height < 104) return base;

  for (final state in const [0, 21]) {
    out.copy(src, 0, state, 25, 20, 0, state);
    // The title text area and the fills between the caps are plain.
    for (final x in const [26, 52, 78, 104]) {
      out.copy(src, 127, state, 25, 20, x, state);
    }
    out.copy(src, 153, state, 25, 20, 130, state);
  }
  // The close button's pressed state.
  out.copy(src, 52, 42, 9, 9, 148, 42);

  // Side borders.
  out.copy(src, 0, 42, 11, 29, 127, 42);
  out.copy(src, 43, 42, 8, 29, 139, 42);
  out.copy(src, 0, 42, 11, 24, 158, 42);
  out.copy(src, 43, 42, 8, 24, 170, 42);

  // Bottom edge: the lower strip of the playlist's bottom pieces.
  out.copy(src, 0, 96, 125, 14, 0, 42);
  out.copy(src, 179, 24, 25, 14, 127, 72);
  for (var x = 0; x < 125; x += 25) {
    out.copy(src, 179, 24, 25, 14, x, 57);
  }
  out.copy(src, 251, 96, 25, 14, 100, 57);

  // Title-bar letters: dark title-bar colour to the playlist text colours.
  final dark = src.average(127, 5, 25, 10);
  final key = out.at(0, 88);
  out.recolour(88, 95, key, dark, colors.current);
  out.recolour(96, 103, key, dark, colors.normal);

  return out.toImage();
}

class _Pixels {
  _Pixels(this.width, this.height, ByteData data)
    : bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

  final int width;
  final int height;
  final Uint8List bytes;

  int at(int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i] << 24) |
        (bytes[i + 1] << 16) |
        (bytes[i + 2] << 8) |
        bytes[i + 3];
  }

  void copy(_Pixels from, int sx, int sy, int w, int h, int dx, int dy) {
    for (var row = 0; row < h; row++) {
      for (var col = 0; col < w; col++) {
        final s = ((sy + row) * from.width + sx + col) * 4;
        final d = ((dy + row) * width + dx + col) * 4;
        bytes[d] = from.bytes[s];
        bytes[d + 1] = from.bytes[s + 1];
        bytes[d + 2] = from.bytes[s + 2];
        bytes[d + 3] = 255;
      }
    }
  }

  /// The mean colour of a rectangle, as an opaque colour.
  ui.Color average(int x, int y, int w, int h) {
    var r = 0;
    var g = 0;
    var b = 0;
    for (var row = y; row < y + h; row++) {
      for (var col = x; col < x + w; col++) {
        final i = (row * width + col) * 4;
        r += bytes[i];
        g += bytes[i + 1];
        b += bytes[i + 2];
      }
    }
    final n = w * h;
    return ui.Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  /// Maps the brightness of every pixel in rows [top]..[bottom] except the
  /// [key] colour onto a gradient from [dark] to [light].
  void recolour(int top, int bottom, int key, ui.Color dark, ui.Color light) {
    int mix(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
    for (var y = top; y <= bottom; y++) {
      for (var x = 0; x < width; x++) {
        if (at(x, y) == key) continue;
        final i = (y * width + x) * 4;
        final lum =
            (bytes[i] * 0.3 + bytes[i + 1] * 0.59 + bytes[i + 2] * 0.11) / 255;
        bytes[i] = mix((dark.r * 255).round(), (light.r * 255).round(), lum);
        bytes[i + 1] = mix(
          (dark.g * 255).round(),
          (light.g * 255).round(),
          lum,
        );
        bytes[i + 2] = mix(
          (dark.b * 255).round(),
          (light.b * 255).round(),
          lum,
        );
      }
    }
  }

  Future<ui.Image> toImage() {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
