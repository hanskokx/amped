import "dart:convert";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/services.dart" show rootBundle;

/// Support for Bamp skins (https://github.com/dp-mason/bamp).
///
/// A Bamp skin is a folder (or zip) of 275x348 PNG layers (`00.png` ..
/// `37.png`, plus `font_and_palette.png`) laid out like the finished UI, with
/// every element that shares a place stacked on its own layer. Loading one
/// means doing what the Bamp converter does: composite the layers in order,
/// splice the mapped regions into the classic bitmaps, and read `viscolor.txt`
/// / `pledit.txt` from the swatches in `font_and_palette.png`. The result is
/// the file set of a classic skin, so everything downstream is unchanged.

/// The layer a folder must have to be a Bamp skin.
const String bampBaseLayer = "00.png";

/// The layer carrying the font, visualizer colours and playlist colours.
const String bampPaletteLayer = "font_and_palette.png";

/// Whether [files] (keyed by lower-case name) hold a Bamp skin.
bool isBampSkin(Map<String, List<int>> files) =>
    isBampSkinNames(files.keys.toSet());

/// Whether [names] (lower-case file names) are the layers of a Bamp skin.
bool isBampSkinNames(Set<String> names) =>
    names.contains(bampBaseLayer) && names.contains(bampPaletteLayer);

/// A decoded Bamp layer: straight (non-premultiplied) RGBA pixels.
class BampLayer {
  const BampLayer({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

/// The Bamp layer-to-bitmap map (`assets/bamp/spec.json`, generated from the
/// Bamp repository's `winamp_skin_specification.yaml` by
/// `tool/bamp_spec_to_json.rb`).
class BampSpec {
  const BampSpec._(this._json);

  /// Reads a spec from its JSON text.
  factory BampSpec.parse(String json) =>
      BampSpec._(jsonDecode(json) as Map<String, dynamic>);

  /// The spec bundled with this package.
  static Future<BampSpec> load() async => BampSpec.parse(
    await rootBundle.loadString(
      "packages/amped_bamp_skin/assets/bamp/spec.json",
    ),
  );

  final Map<String, dynamic> _json;

  List<dynamic> get _layers => _json["layers"] as List<dynamic>;
  Map<String, dynamic> get _classic => _json["classic"] as Map<String, dynamic>;
  Map<String, dynamic> get _extras => _json["extras"] as Map<String, dynamic>;

  /// The `[x0, y0, x1, y1]` layer regions of the optional slider handles.
  Iterable<List<int>> get handleRegions sync* {
    for (final layer in _layers) {
      for (final map in (layer as Map)["maps"] as List) {
        if ((map as Map)["optionalHandle"] == true) {
          yield (map["region"] as List).cast<int>();
        }
      }
    }
  }

  /// Names of the layer files, bottom first.
  List<String> get layerNames => [
    for (final layer in _layers) (layer as Map)["file"] as String,
  ];
}

/// Decodes a PNG layer.
Future<BampLayer> decodeBampLayer(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return BampLayer(
        width: image.width,
        height: image.height,
        rgba: data!.buffer.asUint8List(),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Turns the files of a Bamp skin into those of a classic skin: the bitmaps
/// the layers map to (24-bit `.bmp`) and `viscolor.txt` / `pledit.txt`.
/// Files of [files] that are not layers (a `region.txt`, cursors) are kept.
///
/// A layer that is missing or fails to decode counts as fully transparent, so
/// the skin falls back to what lies beneath (and ultimately to the base skin).
Future<Map<String, List<int>>> bampToClassicFiles(
  Map<String, List<int>> files, {
  BampSpec? spec,
}) async {
  final resolved = spec ?? await BampSpec.load();
  final layers = <String, BampLayer>{};
  for (final name in resolved.layerNames) {
    final bytes = files[name];
    if (bytes == null) continue;
    try {
      layers[name] = await decodeBampLayer(bytes);
    } on Object {
      // treated as an empty layer
    }
  }
  final converted = composeBamp(layers, resolved);
  return {
    for (final entry in files.entries)
      if (!resolved.layerNames.contains(entry.key)) entry.key: entry.value,
    ...converted,
  };
}

/// Does what the Bamp converter's `bamp_to_winamp` does with the decoded
/// [layers] (keyed by file name): returns the classic files, keyed by name.
Map<String, List<int>> composeBamp(
  Map<String, BampLayer> layers,
  BampSpec spec,
) {
  final size = (spec._json["bampResolution"] as List).cast<int>();
  final width = size[0];
  final height = size[1];

  // Every classic bitmap starts as magenta, the transparent colour.
  final outputs = <String, _Canvas>{};
  for (final entry in spec._classic.entries) {
    final resolution = ((entry.value as Map)["resolution"] as List).cast<int>();
    outputs[entry.key] = _Canvas(resolution[0], resolution[1]);
  }
  // Bitmaps whose slider handle was left out of the skin.
  final withoutHandle = <String>{};

  // The composite: opaque, built up layer by layer.
  final stack = Uint8List(width * height * 4);
  var first = true;

  for (final layerEntry in spec._layers) {
    final layerName = (layerEntry as Map)["file"] as String;
    final layer = layers[layerName];

    if (first) {
      // Partial transparency becomes opaque, full transparency magenta.
      for (var i = 0; i < stack.length; i += 4) {
        final a = layer == null ? 0 : _alphaAt(layer, i ~/ 4, width);
        if (a == 0) {
          stack[i] = 255;
          stack[i + 1] = 0;
          stack[i + 2] = 255;
        } else {
          final src = _pixel(layer!, i ~/ 4, width);
          stack[i] = layer.rgba[src];
          stack[i + 1] = layer.rgba[src + 1];
          stack[i + 2] = layer.rgba[src + 2];
        }
        stack[i + 3] = 255;
      }
      first = false;
    } else if (layer != null) {
      _compositeOver(stack, width, height, layer);
    }

    for (final map in layerEntry["maps"] as List) {
      final name = (map as Map)["name"] as String;
      final dest = map["dest"] as String;
      final src = (map["region"] as List).cast<int>();
      final file = spec._classic[dest] as Map;
      final dst = ((file["regions"] as Map)[name] as List).cast<int>();
      final canvas = outputs[dest]!;

      if (map["optionalHandle"] == true) {
        // A handle the artist left transparent is not drawn at all.
        if (layer == null || _isClear(layer, src)) {
          withoutHandle.add(dest);
          continue;
        }
      }

      if (name == "eq_viz_spectrum") {
        // The spectrum is drawn at four times its size in the layer.
        canvas.pasteScaledDown(stack, width, height, src, dst, 4);
      } else {
        canvas.paste(stack, width, height, src, dst);
      }
    }
  }

  final result = <String, List<int>>{};
  for (final entry in outputs.entries) {
    final canvas = entry.value;
    var h = canvas.height;
    if (withoutHandle.contains(entry.key)) {
      final cropped =
          ((spec._classic[entry.key] as Map)["withoutHandle"] as List)
              .cast<int>();
      h = cropped[1];
    }
    result[entry.key] = canvas.toBmp(h);
  }

  final extras = spec._extras;
  final sample = extras["COLOR_SAMPLE_SIZE"] as int;
  final viscolorStart = (extras["VISCOLOR_START"] as List).cast<int>();
  final pleditStart = (extras["PLEDIT_START"] as List).cast<int>();

  int rgbAt(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    final i = (y * width + x) * 4;
    return (stack[i] << 16) | (stack[i + 1] << 8) | stack[i + 2];
  }

  final viscolor = StringBuffer();
  for (var i = 0; i < (extras["VISCOLOR_TOTAL"] as int); i++) {
    final c = rgbAt(
      viscolorStart[0] + sample ~/ 2,
      viscolorStart[1] + sample ~/ 2 + sample * i,
    );
    viscolor.writeln("${c >> 16}, ${(c >> 8) & 255}, ${c & 255}");
  }
  result["viscolor.txt"] = utf8.encode(viscolor.toString());

  final pledit = StringBuffer("[Text]\n");
  final fields = (extras["PLEDIT_FIELDS"] as List).cast<String>();
  for (var i = 0; i < fields.length; i++) {
    if (fields[i] == "Font") {
      pledit.writeln("Font=${extras["PLEDIT_FONT"]}");
      continue;
    }
    final c = rgbAt(
      pleditStart[0] + sample ~/ 2,
      pleditStart[1] + sample ~/ 2 + sample * i,
    );
    pledit.writeln(
      "${fields[i]}=#${c.toRadixString(16).padLeft(6, "0").toUpperCase()}",
    );
  }
  result["pledit.txt"] = utf8.encode(pledit.toString());

  return result;
}

int _pixel(BampLayer layer, int index, int stackWidth) {
  final x = index % stackWidth;
  final y = index ~/ stackWidth;
  if (x >= layer.width || y >= layer.height) return -1;
  return (y * layer.width + x) * 4;
}

int _alphaAt(BampLayer layer, int index, int stackWidth) {
  final i = _pixel(layer, index, stackWidth);
  return i < 0 ? 0 : layer.rgba[i + 3];
}

/// Alpha-composites [layer] over the opaque [stack].
void _compositeOver(Uint8List stack, int width, int height, BampLayer layer) {
  final w = layer.width < width ? layer.width : width;
  final h = layer.height < height ? layer.height : height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final s = (y * layer.width + x) * 4;
      final a = layer.rgba[s + 3];
      if (a == 0) continue;
      final d = (y * width + x) * 4;
      if (a == 255) {
        stack[d] = layer.rgba[s];
        stack[d + 1] = layer.rgba[s + 1];
        stack[d + 2] = layer.rgba[s + 2];
        continue;
      }
      for (var c = 0; c < 3; c++) {
        stack[d + c] =
            (layer.rgba[s + c] * a + stack[d + c] * (255 - a) + 127) ~/ 255;
      }
    }
  }
}

/// Whether [region] of [layer] has no opaque pixel at all.
bool _isClear(BampLayer layer, List<int> region) {
  for (var y = region[1]; y < region[3] && y < layer.height; y++) {
    for (var x = region[0]; x < region[2] && x < layer.width; x++) {
      if (layer.rgba[(y * layer.width + x) * 4 + 3] != 0) return false;
    }
  }
  return true;
}

/// An RGB canvas that becomes one classic `.bmp`.
class _Canvas {
  _Canvas(this.width, this.height) : _rgb = Uint8List(width * height * 3) {
    for (var i = 0; i < _rgb.length; i += 3) {
      _rgb[i] = 255;
      _rgb[i + 2] = 255;
    }
  }

  final int width;
  final int height;
  final Uint8List _rgb;

  void paste(
    Uint8List stack,
    int stackWidth,
    int stackHeight,
    List<int> src,
    List<int> dst,
  ) {
    final w = src[2] - src[0];
    final h = src[3] - src[1];
    for (var y = 0; y < h; y++) {
      final sy = src[1] + y;
      final dy = dst[1] + y;
      if (sy < 0 || sy >= stackHeight || dy < 0 || dy >= height) continue;
      for (var x = 0; x < w; x++) {
        final sx = src[0] + x;
        final dx = dst[0] + x;
        if (sx < 0 || sx >= stackWidth || dx < 0 || dx >= width) continue;
        final s = (sy * stackWidth + sx) * 4;
        final d = (dy * width + dx) * 3;
        _rgb[d] = stack[s];
        _rgb[d + 1] = stack[s + 1];
        _rgb[d + 2] = stack[s + 2];
      }
    }
  }

  /// Pastes [src] shrunk by [factor], averaging each block of pixels.
  void pasteScaledDown(
    Uint8List stack,
    int stackWidth,
    int stackHeight,
    List<int> src,
    List<int> dst,
    int factor,
  ) {
    final w = (src[2] - src[0]) ~/ factor;
    final h = (src[3] - src[1]) ~/ factor;
    for (var y = 0; y < h; y++) {
      final dy = dst[1] + y;
      if (dy < 0 || dy >= height) continue;
      for (var x = 0; x < w; x++) {
        final dx = dst[0] + x;
        if (dx < 0 || dx >= width) continue;
        final sum = [0, 0, 0];
        var count = 0;
        for (var by = 0; by < factor; by++) {
          for (var bx = 0; bx < factor; bx++) {
            final sx = src[0] + x * factor + bx;
            final sy = src[1] + y * factor + by;
            if (sx < 0 || sx >= stackWidth || sy < 0 || sy >= stackHeight) {
              continue;
            }
            final s = (sy * stackWidth + sx) * 4;
            sum[0] += stack[s];
            sum[1] += stack[s + 1];
            sum[2] += stack[s + 2];
            count++;
          }
        }
        if (count == 0) continue;
        final d = (dy * width + dx) * 3;
        _rgb[d] = sum[0] ~/ count;
        _rgb[d + 1] = sum[1] ~/ count;
        _rgb[d + 2] = sum[2] ~/ count;
      }
    }
  }

  /// Encodes the top [rows] rows as a 24-bit bottom-up BMP.
  Uint8List toBmp(int rows) {
    final stride = (width * 3 + 3) & ~3;
    final dataSize = stride * rows;
    final out = Uint8List(54 + dataSize);
    final view = ByteData.sublistView(out);
    out[0] = 0x42;
    out[1] = 0x4D;
    view.setUint32(2, out.length, Endian.little);
    view.setUint32(10, 54, Endian.little);
    view.setUint32(14, 40, Endian.little);
    view.setInt32(18, width, Endian.little);
    view.setInt32(22, rows, Endian.little);
    view.setUint16(26, 1, Endian.little);
    view.setUint16(28, 24, Endian.little);
    view.setUint32(34, dataSize, Endian.little);
    for (var y = 0; y < rows; y++) {
      var o = 54 + (rows - 1 - y) * stride;
      for (var x = 0; x < width; x++) {
        final s = (y * width + x) * 3;
        out[o++] = _rgb[s + 2];
        out[o++] = _rgb[s + 1];
        out[o++] = _rgb[s];
      }
    }
    return out;
  }
}
