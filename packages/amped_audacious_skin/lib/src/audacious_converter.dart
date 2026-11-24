import "dart:convert";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";

import "skin_hints_parser.dart";

/// Converts the files of an Audacious skin into a classic skin's file set.
///
/// Audacious skins may replace any classic bitmap with a PNG or JPEG of the
/// same stem; those are re-encoded as 24-bit BMPs. `skin.hints` is parsed
/// into layout hints here rather than in the renderer.
final class AudaciousSkinConverter implements SkinFileConverter {
  const AudaciousSkinConverter();

  @override
  SkinFormat get format => SkinFormat.audacious;

  @override
  bool appliesToNames(Set<String> names) =>
      names.contains("skin.hints") || names.any(_isRasterBitmap);

  @override
  bool appliesTo(Map<String, List<int>> files) =>
      appliesToNames(files.keys.toSet());

  @override
  Future<Map<String, List<int>>> convert(
    Map<String, List<int>> files,
  ) async {
    final result = Map<String, List<int>>.of(files);
    for (final key in files.keys) {
      final stem = _bitmapStem(key);
      if (stem == null || result.containsKey("$stem.bmp")) continue;
      try {
        result["$stem.bmp"] = await _imageToBmp(
          Uint8List.fromList(files[key]!),
        );
      } on Object {
        // Not a readable image; the base skin's bitmap stays.
      }
    }
    return result;
  }

  @override
  SkinHints? hints(Map<String, List<int>> files) {
    final text = files["skin.hints"];
    if (text == null) return null;
    return SkinHintsParser.parse(
      utf8.decode(text, allowMalformed: true),
    );
  }
}

final _rasterName = RegExp(r"^(.+)\.(png|jpe?g)$");

String? _bitmapStem(String fileName) {
  final match = _rasterName.firstMatch(fileName);
  if (match == null) return null;
  final stem = "${match.group(1)}.bmp";
  return baseSkinFiles.contains(stem) ? match.group(1) : null;
}

bool _isRasterBitmap(String fileName) => _bitmapStem(fileName) != null;

/// Re-encodes a PNG or JPEG as a 24-bit BMP, transparency drawn over black.
Future<Uint8List> _imageToBmp(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = image.width;
  final height = image.height;
  image.dispose();
  codec.dispose();
  if (data == null) throw const FormatException("Unreadable image");
  final stride = (width * 3 + 3) & ~3;
  final out = Uint8List(54 + stride * height);
  ByteData.sublistView(out)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, out.length, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, stride * height, Endian.little);
  for (var y = 0; y < height; y++) {
    var o = 54 + (height - 1 - y) * stride;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = data.getUint8(i + 3);
      out[o++] = data.getUint8(i + 2) * a ~/ 255;
      out[o++] = data.getUint8(i + 1) * a ~/ 255;
      out[o++] = data.getUint8(i) * a ~/ 255;
    }
  }
  return out;
}
