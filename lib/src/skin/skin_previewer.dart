import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/foundation.dart";
import "package:skin_preview/skin_preview.dart";

/// Renders skin preview images for skin pickers.
///
/// Classic skins fall back to their main window bitmap when a composed preview
/// cannot be drawn. Modern skins show the composed screenshot/main window.
final class SkinPreviewer {
  /// Creates a previewer that loads skins through [registry] using [formats].
  const SkinPreviewer(this._registry, this._formats);

  final SkinRegistry _registry;
  final SkinFormats _formats;

  /// The picture of [info] as the Quick Look preview shows it (the main
  /// window, equalizer and playlist editor; for a modern skin its screenshot or
  /// main window), to preview it without applying it. Falls back to the main
  /// window bitmap of a classic skin; null when there is nothing to show.
  Future<ui.Image?> previewImage(SkinInfo info) async {
    try {
      final picture = await renderSkinPicture(
        info.directory,
        title: info.name.toUpperCase().replaceAll("_", " "),
        extraFiles: await bitmapsAsBmp(info.directory),
      );
      if (picture != null) return await _decode(picture);
    } on Object catch (error) {
      Arcane.log(
        "Could not draw a preview",
        metadata: {"name": info.name, "error": "$error"},
        level: Level.warning,
        module: "SkinPreviewer",
      );
    }
    if (info.modern) return null;
    try {
      return (await _registry.loadSkin(
        info,
        formats: _formats,
      )).image("main.bmp");
    } on Object {
      return null;
    }
  }

  /// The bitmaps of the skin in [directory] that are not BMP (PNG, JPEG
  /// or GIF) as 24-bit BMP files named for the `.bmp` they stand in for, which
  /// is what the native renderer reads. Empty for a skin that has its own BMP
  /// of a bitmap, and for a modern skin, whose pictures are drawn from its
  /// own files.
  @visibleForTesting
  static Future<Map<String, Uint8List>> bitmapsAsBmp(
    Directory? directory,
  ) async {
    final converted = <String, Uint8List>{};
    if (directory == null || !directory.existsSync()) return converted;
    try {
      final root = directory.path;
      final files = directory.listSync(recursive: true).whereType<File>();
      String relative(File file) =>
          file.path.substring(root.length).replaceAll("\\", "/");
      final names = {for (final f in files) relative(f).toLowerCase()};
      if (names.any((n) => n.endsWith("skin.xml"))) return converted;
      final stems = {
        for (final name in baseSkinFiles) name.substring(0, name.length - 4),
      };
      for (final file in files) {
        final path = relative(file);
        final dot = path.lastIndexOf(".");
        final slash = path.lastIndexOf("/");
        if (dot <= slash) continue;
        final extension = path.substring(dot + 1).toLowerCase();
        final stem = path.substring(slash + 1, dot).toLowerCase();
        final folder = path.substring(0, slash + 1);
        if (extension == "bmp" ||
            !skinImageExtensions.contains(extension) ||
            !stems.contains(stem) ||
            names.contains("${folder.toLowerCase()}$stem.bmp") ||
            converted.containsKey("$folder$stem.bmp")) {
          continue;
        }
        try {
          final bmp = await decodeSkinBitmap(await file.readAsBytes());
          converted["$folder$stem.bmp"] = _encodeBmp(bmp);
        } on Object {
          // the renderer falls back to the base skin's bitmap
        }
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not convert a skin's bitmaps",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SkinPreviewer",
      );
    }
    return converted;
  }

  /// [image] as a 24-bit BMP, its transparency dropped as the classic player does.
  static Uint8List _encodeBmp(BmpImage image) {
    final stride = (image.width * 3 + 3) & ~3;
    final size = 54 + stride * image.height;
    final out = Uint8List(size);
    ByteData.sublistView(out)
      ..setUint8(0, 0x42)
      ..setUint8(1, 0x4D)
      ..setUint32(2, size, Endian.little)
      ..setUint32(10, 54, Endian.little)
      ..setUint32(14, 40, Endian.little)
      ..setInt32(18, image.width, Endian.little)
      ..setInt32(22, image.height, Endian.little)
      ..setUint16(26, 1, Endian.little)
      ..setUint16(28, 24, Endian.little);
    for (var y = 0; y < image.height; y++) {
      var to = 54 + (image.height - 1 - y) * stride;
      var from = y * image.width * 4;
      for (var x = 0; x < image.width; x++) {
        out[to++] = image.rgba[from + 2];
        out[to++] = image.rgba[from + 1];
        out[to++] = image.rgba[from];
        from += 4;
      }
    }
    return out;
  }

  /// [picture] as an image: its straight alpha made premultiplied, as the
  /// engine draws it.
  static Future<ui.Image> _decode(SkinPicture picture) {
    final pixels = Uint8List.fromList(picture.rgba);
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final alpha = pixels[i + 3];
      if (alpha == 255) continue;
      pixels[i] = pixels[i] * alpha ~/ 255;
      pixels[i + 1] = pixels[i + 1] * alpha ~/ 255;
      pixels[i + 2] = pixels[i + 2] * alpha ~/ 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      picture.width,
      picture.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
