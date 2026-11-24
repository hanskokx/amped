import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";
import "package:custom_cursor/custom_cursor.dart";

import "bmp_decoder.dart";
import "built_in_skin.dart";
import "classic_skin_data.dart";
import "gen_frame.dart";
import "skin_cursors.dart";
import "skin_formats.dart";

/// Names of the bitmaps that make up a classic skin, mirroring the file
/// list the original loader scans for (`draw_LBitmap` in `draw.cpp`).
const baseSkinFiles = <String>[
  "main.bmp",
  "titlebar.bmp",
  "cbuttons.bmp",
  "playpaus.bmp",
  "posbar.bmp",
  "volume.bmp",
  "balance.bmp",
  "monoster.bmp",
  "shufrep.bmp",
  "numbers.bmp",
  "nums_ex.bmp",
  "text.bmp",
  "gen.bmp",
  "eqmain.bmp",
  "eqmain_iso.bmp",
  "eq_ex.bmp",
  "pledit.bmp",
  "video.bmp",
  "video_logo.bmp",
];

/// Bitmaps a built-in base skin is expected to provide.
const bundledSkinFiles = <String>[
  "main.bmp",
  "titlebar.bmp",
  "cbuttons.bmp",
  "playpaus.bmp",
  "posbar.bmp",
  "volume.bmp",
  "balance.bmp",
  "monoster.bmp",
  "shufrep.bmp",
  "numbers.bmp",
  "text.bmp",
  "gen.bmp",
  "eqmain.bmp",
  "eq_ex.bmp",
  "pledit.bmp",
  "video.bmp",
];

/// File extensions a skin bitmap may have, in order of preference.
const skinImageExtensions = <String>[
  "bmp",
  "png",
  "jpg",
  "jpeg",
  "gif",
];

/// Decodes a skin bitmap in any format Flutter can read. BMP goes through
/// the skin's own decoder, which handles the odd files old skins ship.
Future<BmpImage> decodeSkinBitmap(Uint8List bytes) async {
  if (bytes.length > 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    try {
      return decodeBmp(bytes);
    } on Object {
      // fall through to the platform codec
    }
  }
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) throw const FormatException("Unreadable image");
    return BmpImage(
      width: frame.image.width,
      height: frame.image.height,
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    codec.dispose();
  }
}

/// Converts a decoded BMP into a GPU [ui.Image].
Future<ui.Image> bmpToUiImage(BmpImage bmp) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bmp.rgba,
    bmp.width,
    bmp.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// The color that video is drawn over: a skin whose windows are made of it
/// (`#100010`, what the classic player's overlay skins use) shows what is behind it.
const int _overlayArgb = 0xFF100010;

/// Whether [bmp] is mostly the overlay color.
bool isOverlayBitmap(BmpImage bmp) {
  var count = 0;
  for (var i = 0; i < bmp.rgba.length; i += 4) {
    if (_isOverlay(bmp.rgba, i)) count++;
  }
  return count * 2 >= bmp.width * bmp.height;
}

/// Makes the overlay color of [bmp] transparent.
void clearOverlayColor(BmpImage bmp) {
  for (var i = 0; i < bmp.rgba.length; i += 4) {
    if (_isOverlay(bmp.rgba, i)) bmp.rgba[i + 3] = 0;
  }
}

bool _isOverlay(Uint8List rgba, int at) =>
    rgba[at] == 0x10 && rgba[at + 1] == 0x00 && rgba[at + 2] == 0x10;

/// Loads the built-in base skin from the application's `assets/skins`.
Future<ClassicSkinData> loadBaseSkin({
  SkinFormats formats = const SkinFormats(),
}) async {
  return loadSkinFromArchive(
    ClassicSkinData(name: baseSkinName, images: const {}),
    await AmpedClassicSkinLoader.loadBase(),
    name: baseSkinName,
    formats: formats,
  );
}

/// Loads a skin archive on top of [base], so any file the archive omits falls
/// back to the base skin (mirroring the original `draw_LBitmap` behavior).
/// Cursors are the exception: a skin only carries the cursors it ships,
/// leaving other slots on the OS cursor.
Future<ClassicSkinData> loadSkinFromArchive(
  ClassicSkinData base,
  Uint8List archiveBytes, {
  String? name,
  SkinFormats formats = const SkinFormats(),
}) async {
  final archive = decodeSkinArchive(archiveBytes, formats: formats);
  final files = await skinArchiveContents(archive, formats: formats);
  return _buildSkin(
    base,
    files,
    name: name ?? skinDisplayName(archive),
    formats: formats,
  );
}

/// Opens [bytes] into the classic file set, recording the skin's family and
/// layout hints. Used at the composition root, where the format of an
/// installed skin is decided.
Future<SkinArchiveContents> openSkinArchive(
  Uint8List bytes, {
  SkinFormats formats = const SkinFormats(),
  String? fileName,
}) async {
  final decoder = formats.decoderFor(bytes);
  final archive = formats.decode(bytes);
  // Identify from the raw files: conversion removes the very layer names a
  // converter looks for, so asking afterwards would lose the skin's origin.
  final rawFiles = {
    for (final entry in skinArchiveFiles(archive).entries)
      entry.key.toLowerCase(): entry.value.content as List<int>,
  };
  final files = await formats.convert(rawFiles);
  final fallback =
      _formatFromFileName(fileName) ?? decoder?.format ?? SkinFormat.classic;
  return SkinArchiveContents(
    archive: archive,
    files: files,
    format: formats.identify(rawFiles, fallback),
    hints: formats.hints(rawFiles),
    displayName: skinDisplayName(archive),
  );
}

SkinFormat? _formatFromFileName(String? fileName) {
  if (fileName == null) return null;
  for (final type in SkinFileType.values) {
    if (!type.matches(fileName)) continue;
    return switch (type) {
      SkinFileType.wal => SkinFormat.wasabi,
      SkinFileType.tar ||
      SkinFileType.tarGz ||
      SkinFileType.tarBz2 => SkinFormat.audacious,
      SkinFileType.zip => null,
    };
  }
  return null;
}

/// Writes the files of a skin archive into [target], for installing a
/// built-in skin through [SkinRegistry.installFolder].
Future<void> extractSkinArchive(
  Uint8List bytes,
  Directory target, {
  SkinFormats formats = const SkinFormats(),
}) => extractSkinFiles(
  decodeSkinArchive(bytes, formats: formats),
  target,
  formats: formats,
);

/// Writes the files of [archive] into [target].
Future<void> extractSkinFiles(
  Archive archive,
  Directory target, {
  SkinFormats formats = const SkinFormats(),
}) async {
  final contents = await skinArchiveContents(archive, formats: formats);
  for (final entry in contents.entries) {
    await File(
      target.uri.resolve(Uri.encodeComponent(entry.key)).toFilePath(),
    ).writeAsBytes(entry.value, flush: true);
  }
}

/// Loads a previously-extracted skin directory (see [SkinRegistry.import])
/// on top of [base]. Only top-level files are read; anything in a
/// subdirectory is ignored, mirroring the flat archive layout.
Future<ClassicSkinData> loadSkinFromDirectory(
  ClassicSkinData base,
  Directory directory, {
  String? name,
  SkinFormats formats = const SkinFormats(),
}) async {
  final raw = <String, List<int>>{};
  for (final entity in directory.listSync()) {
    if (entity is! File) continue;
    final key = entity.uri.pathSegments.last.toLowerCase();
    if (key.contains("\\") || key.contains("/")) continue;
    raw[key] = await entity.readAsBytes();
  }
  final files = await formats.convert(raw);
  return _buildSkin(base, files, name: name, formats: formats);
}

Future<ClassicSkinData> _buildSkin(
  ClassicSkinData base,
  Map<String, List<int>> files, {
  String? name,
  SkinFormats formats = const SkinFormats(),
}) async {
  final images = <String, ui.Image>{...base.images};
  final own = <String>{};
  final decoded = <String, BmpImage>{};
  // Bitmaps are matched by name without the extension, so `main.png` stands
  // in for `main.bmp`; the image is then known by its classic `.bmp` name.
  final bitmapFiles = <String, String>{};
  for (final fname in baseSkinFiles) {
    final stem = fname.substring(0, fname.length - 4);
    for (final extension in skinImageExtensions) {
      if (files.containsKey("$stem.$extension")) {
        bitmapFiles[fname] = "$stem.$extension";
        break;
      }
    }
  }
  for (final MapEntry(key: fname, value: source) in bitmapFiles.entries) {
    try {
      decoded[fname] = await decodeSkinBitmap(
        Uint8List.fromList(files[source]!),
      );
    } catch (_) {
      // keep the base image
    }
  }
  // A skin made to be drawn over video (its windows are the overlay color)
  // lets whatever is behind it show through that color.
  final main = decoded["main.bmp"];
  final overlay = main != null && isOverlayBitmap(main);
  for (final MapEntry(key: fname, value: bmp) in decoded.entries) {
    if (overlay) clearOverlayColor(bmp);
    images[fname] = await bmpToUiImage(bmp);
    own.add(fname);
  }
  // A skin without its own balance.bmp draws the balance slider from its
  // volume.bmp, as the original does.
  if (!own.contains("balance.bmp") && own.contains("volume.bmp")) {
    images["balance.bmp"] = images["volume.bmp"]!;
  }

  // A skin without its own gen.bmp gets a frame in its own colours, built
  // from its playlist editor, instead of the base skin's.
  final hasOwnGen = own.contains("gen.bmp");
  final baseGen = images["gen.bmp"];
  if (!hasOwnGen && own.contains("pledit.bmp") && baseGen != null) {
    final pleditTxt = files["pledit.txt"];
    images["gen.bmp"] = await deriveGenFrame(
      base: baseGen,
      pledit: images["pledit.bmp"]!,
      colors: pleditTxt == null
          ? base.pledit
          : parsePlEditConfig(utf8.decode(pleditTxt)),
    );
  }

  var regions = base.regions;
  final regionTxt = files["region.txt"];
  if (regionTxt != null) {
    regions = parseRegions(utf8.decode(regionTxt));
  }

  var pledit = base.pledit;
  final pleditTxt = files["pledit.txt"];
  if (pleditTxt != null) {
    pledit = parsePlEditConfig(utf8.decode(pleditTxt));
  }
  if (overlay && pledit.normalBg.toARGB32() == _overlayArgb) {
    pledit = pledit.copyWith(normalBg: const ui.Color(0x00000000));
  }

  var visColors = base.visColors;
  final viscolorTxt = files["viscolor.txt"];
  if (viscolorTxt != null) {
    final parsed = parseVisColors(
      utf8.decode(viscolorTxt, allowMalformed: true),
    );
    // A skin may list fewer than 24 colours; the rest keep their defaults.
    if (parsed != null) {
      visColors = [
        for (var i = 0; i < visColors.length; i++)
          i < parsed.length ? parsed[i] : visColors[i],
      ];
    }
  }

  final hints = formats.hints(files);

  // Cursors decode lazily when first shown. A skin carries only the cursors
  // it ships; slots without a file are left for the OS cursor. Slots sharing
  // a file share one cursor so the bytes are decoded only once.
  final cursorFiles = <String, CustomMouseCursor>{};
  final cursors = <SkinCursor, CustomMouseCursor>{};
  for (final slot in SkinCursor.values) {
    final bytes = files[slot.fileName];
    if (bytes == null) continue;
    cursors[slot] = cursorFiles.putIfAbsent(
      slot.fileName,
      () => CustomMouseCursor.memory(Uint8List.fromList(bytes)),
    );
  }

  return ClassicSkinData(
    name: name ?? "Skin",
    images: images,
    cursors: cursors,
    regions: regions,
    regionPaths: {for (final e in regions.entries) e.key: e.value.toPath()!},
    pledit: pledit,
    visColors: visColors,
    hints: hints,
    useGenNums: pledit.useGenNums,
    hasOwnGen: hasOwnGen,
    overlay: overlay,
    numbersExtended:
        !own.contains("numbers.bmp") &&
        images.containsKey("nums_ex.bmp") &&
        own.contains("nums_ex.bmp"),
  );
}

/// Opens a skin archive with [formats]. Zip (`.wsz`, `.zip`) is built in;
/// other containers come from the formats' decoders.
///
/// Throws a [FormatException] when [bytes] is none of those.
Archive decodeSkinArchive(
  Uint8List bytes, {
  SkinFormats formats = const SkinFormats(),
}) => formats.decode(bytes);

/// The skin files in [archive], keyed by base name.
///
/// Many skins keep their files in a folder inside the archive, so files are
/// matched by name wherever they are, like the classic player and Webamp do. When a name
/// appears more than once the shallowest copy wins. macOS resource forks
/// (`__MACOSX/`) and hidden files are skipped.
Map<String, ArchiveFile> skinArchiveFiles(Archive archive) {
  final files = <String, ArchiveFile>{};
  final depths = <String, int>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final segments = file.name
        .split(RegExp(r"[\\/]"))
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) continue;
    if (segments.first == "__MACOSX") continue;
    final baseName = segments.last;
    if (baseName.startsWith(".")) continue;
    final key = baseName.toLowerCase();
    final depth = segments.length;
    if ((depths[key] ?? 1 << 30) <= depth) continue;
    depths[key] = depth;
    files[key] = file;
  }
  return {
    for (final file in files.values)
      file.name.split(RegExp(r"[\\/]")).last: file,
  };
}

/// The bytes of the skin files in [archive], keyed by lower-case file name.
/// [SkinFormats.convert] gives foreign skins a chance to turn their files
/// into classic bitmaps before the rest of the app sees them.
Future<Map<String, List<int>>> skinArchiveContents(
  Archive archive, {
  SkinFormats formats = const SkinFormats(),
}) => formats.convert({
  for (final entry in skinArchiveFiles(archive).entries)
    entry.key.toLowerCase(): entry.value.content as List<int>,
});

/// Whether [archive] holds a skin: at least one readable bitmap a skin is
/// made of ([baseSkinFiles]), or a file set a [SkinFormats] converter claims.
/// A skin may leave out bitmaps; those come from the base skin.
bool isSkinArchive(
  Archive archive, {
  SkinFormats formats = const SkinFormats(),
}) {
  final files = {
    for (final entry in skinArchiveFiles(archive).entries)
      entry.key.toLowerCase(): entry.value,
  };
  for (final name in baseSkinFiles) {
    // Skins may use PNG, JPEG or other bitmaps in place of BMP.
    final stem = name.substring(0, name.length - 4);
    // (A .bmp is read below: one that is not a bitmap makes no skin.)
    if (skinImageExtensions.any(
      (e) => e != "bmp" && files.containsKey("$stem.$e"),
    )) {
      return true;
    }
    final file = files[name];
    if (file == null) continue;
    try {
      decodeBmp(Uint8List.fromList(file.content as List<int>));
      return true;
    } on Object {
      // not a bitmap after all
    }
  }
  return formats.converters.any(
    (converter) => converter.appliesTo({
      for (final entry in files.entries)
        entry.key: entry.value.content as List<int>,
    }),
  );
}

/// Best-effort display name for an archive: the `id` attribute from its
/// `skin.xml`, or null when the archive has none.
String? skinDisplayName(Archive archive) {
  final xml = archive.files.where((f) => f.name.toLowerCase() == "skin.xml");
  if (xml.isNotEmpty) {
    final content = utf8.decode(xml.first.content as List<int>);
    final m = RegExp(r'id\s*=\s*"([^"]+)"').firstMatch(content);
    if (m != null) return m.group(1)!;
  }
  return null;
}

// ---------------------------------------------------------------------------
// region.txt
// ---------------------------------------------------------------------------

/// Parses `region.txt` into window regions. Sections mirror the original:
/// `[Normal]`, `[WindowShade]`, `[Equalizer]`, `[EqualizerWS]`.
Map<String, SkinRegion> parseRegions(String text) {
  final result = <String, SkinRegion>{};
  const sections = <String, String>{
    "Normal": "main",
    "WindowShade": "mainWs",
    "Equalizer": "eq",
    "EqualizerWS": "eqWs",
  };

  final lines = text.split(RegExp(r"[\r\n]+"));
  String? currentSection;
  final sectionLines = <String, List<String>>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith("[")) {
      final m = RegExp(r"\[([^\]]+)\]").firstMatch(line);
      currentSection = m?.group(1);
      sectionLines[currentSection ?? ""] = [];
    } else if (currentSection != null) {
      sectionLines[currentSection]!.add(line);
    }
  }

  for (final entry in sectionLines.entries) {
    final key = sections[entry.key];
    if (key == null) continue;
    String? numPoints;
    String? pointList;
    for (final line in entry.value) {
      final idx = line.indexOf("=");
      if (idx < 0) continue;
      final k = line.substring(0, idx).trim().toLowerCase();
      final v = line.substring(idx + 1).trim();
      if (k == "numpoints") numPoints = v;
      if (k == "pointlist") pointList = v;
    }
    if (numPoints == null || pointList == null) continue;
    final counts = _parseIntList(numPoints);
    final pts = _parseIntList(pointList);
    if (counts.isEmpty || pts.isEmpty || pts.length.isOdd) continue;

    final polygons = <List<ui.Offset>>[];
    var o = 0;
    for (final count in counts) {
      if (count <= 0 || o + count * 2 > pts.length) break;
      final polygon = <ui.Offset>[];
      for (var i = 0; i < count; i++) {
        polygon.add(
          ui.Offset(pts[o + i * 2].toDouble(), pts[o + i * 2 + 1].toDouble()),
        );
      }
      polygons.add(polygon);
      o += count * 2;
    }
    if (polygons.isNotEmpty) result[key] = SkinRegion(polygons);
  }
  return result;
}

List<int> _parseIntList(String s) {
  final result = <int>[];
  final re = RegExp(r"-?\d+");
  for (final m in re.allMatches(s)) {
    result.add(int.parse(m.group(0)!));
  }
  return result;
}

// ---------------------------------------------------------------------------
// pledit.txt
// ---------------------------------------------------------------------------

PlEditConfig parsePlEditConfig(String text) {
  final ini = _parseIni(text);
  final textSection = ini["text"] ?? {};
  ui.Color hex(String key, ui.Color fallback) {
    final v = textSection[key];
    if (v == null || v.isEmpty) return fallback;
    var h = v.trim();
    if (h.startsWith("#")) h = h.substring(1);
    final parsed = int.tryParse(h, radix: 16);
    if (parsed == null) return fallback;
    final r = (parsed >> 16) & 0xFF;
    final g = (parsed >> 8) & 0xFF;
    final b = parsed & 0xFF;
    return ui.Color.fromARGB(255, r, g, b);
  }

  final misc = ini["misc"] ?? {};
  final useGenNums = (misc["usegenums"] ?? "0").trim() == "1";

  return PlEditConfig(
    normal: hex("normal", const ui.Color(0xFF00FF00)),
    current: hex("current", const ui.Color(0xFFFFFFFF)),
    normalBg: hex("normalbg", const ui.Color(0xFF000000)),
    selectedBg: hex("selectedbg", const ui.Color(0xFF0000C6)),
    mbFg: hex("mbfg", const ui.Color(0xFF00FF00)),
    mbBg: hex("mbbg", const ui.Color(0xFF000000)),
    fontName: textSection["font"]?.trim() ?? "",
    useGenNums: useGenNums,
  );
}

Map<String, Map<String, String>> _parseIni(String text) {
  final result = <String, Map<String, String>>{};
  String? section;
  for (final raw in text.split(RegExp(r"[\r\n]+"))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(";") || line.startsWith("#")) continue;
    if (line.startsWith("[")) {
      final m = RegExp(r"\[([^\]]+)\]").firstMatch(line);
      section = m?.group(1)?.trim().toLowerCase() ?? "default";
      result[section] ??= {};
    } else {
      final idx = line.indexOf("=");
      if (idx < 0) continue;
      final k = line.substring(0, idx).trim().toLowerCase();
      final v = line.substring(idx + 1).trim();
      result[section ?? "default"]![k] = v;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// viscolor.txt
// ---------------------------------------------------------------------------

/// Parses `viscolor.txt` (up to 24 lines of `r,g,b`, each optionally
/// followed by a comment) into the spectrum palette, in order. Returns
/// `null` when it holds no colours.
List<int>? parseVisColors(String text) {
  final colors = <int>[];
  for (final raw in text.split(RegExp(r"[\r\n]+"))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final nums = RegExp(
      r"\d+",
    ).allMatches(line).map((m) => int.parse(m.group(0)!)).toList();
    if (nums.length < 3) continue;
    final r = nums[0].clamp(0, 255);
    final g = nums[1].clamp(0, 255);
    final b = nums[2].clamp(0, 255);
    colors.add(0xFF000000 | (r << 16) | (g << 8) | b);
    if (colors.length >= 24) break;
  }
  return colors.isEmpty ? null : colors;
}
