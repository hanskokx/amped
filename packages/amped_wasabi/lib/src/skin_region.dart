import "dart:typed_data";
import "dart:ui" as ui;

import "wasabi_skin_data.dart";

/// The opaque part of [bitmap] as rectangles (polygons of four points), the
/// way a per-pixel-alpha window lets clicks on fully transparent pixels fall
/// through to what is underneath. Null when the bitmap is fully opaque.
Future<List<List<ui.Offset>>?> alphaRegion(WasabiBitmap bitmap) async {
  final rects = await alphaRects(bitmap);
  return rects == null ? null : rectPolygons(rects);
}

/// The pixels of [bitmap] with any alpha, as rectangles in bitmap pixels.
/// Null when the bitmap is fully opaque (or cannot be read).
///
/// Rows are scanned for runs of non-transparent pixels and equal runs on
/// consecutive rows are merged into one rectangle.
Future<List<ui.Rect>?> alphaRects(WasabiBitmap bitmap) async {
  final data = await bitmap.source.toByteData();
  if (data == null) return null;
  final imageWidth = bitmap.source.width;
  final imageHeight = bitmap.source.height;
  final left = bitmap.src.left.toInt();
  final top = bitmap.src.top.toInt();
  final width = bitmap.src.width.toInt();
  final height = bitmap.src.height.toInt();
  var fullyOpaque = true;
  final rects = _runRects(width, height, (x, y) {
    // Skins crop past the edge of their images (Wasabi 5's drawer
    // regions); nothing is drawn there.
    final ix = left + x;
    final iy = top + y;
    final opaque =
        ix >= 0 &&
        iy >= 0 &&
        ix < imageWidth &&
        iy < imageHeight &&
        data.getUint8((iy * imageWidth + ix) * 4 + 3) != 0;
    if (!opaque) fullyOpaque = false;
    return opaque;
  });
  return fullyOpaque ? null : rects;
}

/// [rects] as polygons of four points, the shape native windows take.
List<List<ui.Offset>> rectPolygons(List<ui.Rect> rects) => [
  for (final r in rects) [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
];

/// Rectangles covering the pixels of a [width] by [height] area where
/// [inside] holds: runs on each row, merged with equal runs below.
List<ui.Rect> _runRects(
  int width,
  int height,
  bool Function(int x, int y) inside,
) {
  final rects = <ui.Rect>[];
  // Runs of the previous row still growing downward: (x0, x1) -> top.
  var open = <(int, int), int>{};
  for (var y = 0; y <= height; y++) {
    final runs = <(int, int)>[];
    if (y < height) {
      var x = 0;
      while (x < width) {
        while (x < width && !inside(x, y)) {
          x++;
        }
        if (x >= width) break;
        final start = x;
        while (x < width && inside(x, y)) {
          x++;
        }
        runs.add((start, x));
      }
    }
    final next = <(int, int), int>{};
    for (final run in runs) {
      next[run] = open.remove(run) ?? y;
    }
    for (final MapEntry(key: run, value: runTop) in open.entries) {
      rects.add(
        ui.Rect.fromLTRB(
          run.$1.toDouble(),
          runTop.toDouble(),
          run.$2.toDouble(),
          y.toDouble(),
        ),
      );
    }
    open = next;
  }
  return rects;
}

/// A window region as a pixel mask, for combining the regions of a
/// layout's objects (`api_region` `addRegion`, `andRegion`, `subtractRgn`).
class RegionMask {
  RegionMask(this.width, this.height) : _bits = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List _bits;

  bool get isEmpty => !_bits.contains(1);

  bool get isFull => !_bits.contains(0);

  /// Adds [rect] (layout pixels; clipped to the mask).
  void addRect(ui.Rect rect) {
    // A rect can lie wholly outside the mask (a drawer group as wide as the
    // screen in a layout that is not yet).
    final x0 = rect.left.round().clamp(0, width);
    final y0 = rect.top.round().clamp(0, height);
    final x1 = rect.right.round().clamp(0, width);
    final y1 = rect.bottom.round().clamp(0, height);
    if (x1 <= x0) return;
    for (var y = y0; y < y1; y++) {
      _bits.fillRange(y * width + x0, y * width + x1, 1);
    }
  }

  /// Adds [rects] given in the pixels of a [source] sized area, stretched
  /// onto [target] (`RegionI::scale` then `offset`).
  void addScaled(List<ui.Rect> rects, ui.Size source, ui.Rect target) {
    final sx = source.width == 0 ? 1.0 : target.width / source.width;
    final sy = source.height == 0 ? 1.0 : target.height / source.height;
    for (final r in rects) {
      addRect(
        ui.Rect.fromLTRB(
          target.left + r.left * sx,
          target.top + r.top * sy,
          target.left + r.right * sx,
          target.top + r.bottom * sy,
        ),
      );
    }
  }

  void or(RegionMask other) {
    for (var i = 0; i < _bits.length; i++) {
      _bits[i] |= other._bits[i];
    }
  }

  void and(RegionMask other) {
    for (var i = 0; i < _bits.length; i++) {
      _bits[i] &= other._bits[i];
    }
  }

  void subtract(RegionMask other) {
    for (var i = 0; i < _bits.length; i++) {
      if (other._bits[i] != 0) _bits[i] = 0;
    }
  }

  /// The mask as rectangles.
  List<ui.Rect> toRects() =>
      _runRects(width, height, (x, y) => _bits[y * width + x] != 0);
}

/// The pixels of [bitmap] a region map keeps at [threshold], as rectangles
/// in bitmap pixels (`RegionI(bitmap, ..., dothreshold, threshold,
/// thinverse)`, which `Layer::setRegionFromMap` builds): the pixels with
/// any alpha whose red, green and blue are all at least [threshold], or
/// all at most [threshold] when [reversed]. [pixels] are the RGBA bytes
/// (premultiplied, as Wasabi's bitmaps are) of the bitmap's whole image.
List<ui.Rect> thresholdRects(
  WasabiBitmap bitmap,
  ByteData pixels,
  int threshold, {
  required bool reversed,
}) {
  final imageWidth = bitmap.source.width;
  final imageHeight = bitmap.source.height;
  final left = bitmap.src.left.toInt();
  final top = bitmap.src.top.toInt();
  return _runRects(bitmap.src.width.toInt(), bitmap.src.height.toInt(), (
    x,
    y,
  ) {
    final ix = left + x;
    final iy = top + y;
    if (ix < 0 || iy < 0 || ix >= imageWidth || iy >= imageHeight) {
      return false;
    }
    final p = (iy * imageWidth + ix) * 4;
    if (pixels.getUint8(p + 3) == 0) return false;
    for (var c = 0; c < 3; c++) {
      final value = pixels.getUint8(p + c);
      if (reversed ? value > threshold : value < threshold) return false;
    }
    return true;
  });
}
