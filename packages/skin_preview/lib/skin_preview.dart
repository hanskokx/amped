/// Pictures of skins, drawn by the renderer in `native/skin_preview`.
library;

import "dart:ffi";
import "dart:io";
import "dart:isolate";
import "dart:typed_data";

import "package:archive/archive_io.dart";
import "package:ffi/ffi.dart";

import "src/bindings.dart";

/// A rendered skin: straight RGBA, 4 bytes a pixel, rows top-down.
class SkinPicture {
  const SkinPicture(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

/// What a picture of a skin shows.
enum SkinPictureLayout {
  /// The main window alone.
  main,

  /// The main window, equalizer and playlist editor stacked.
  stack,
}

/// The picture of the skin extracted in [directory] (null for the base
/// skin the app carries), the longest side [size] pixels. Shows [title] in
/// the song title display. Null when the skin cannot be drawn.
///
/// [extraFiles] (path in the skin to bytes) are added to the skin's files, for
/// bitmaps the renderer cannot read as they are, given as BMP.
///
/// The work is done in another isolate.
Future<SkinPicture?> renderSkinPicture(
  Directory? directory, {
  required String title,
  int size = 600,
  SkinPictureLayout layout = SkinPictureLayout.stack,
  Map<String, Uint8List> extraFiles = const {},
}) => Isolate.run(
  () => _render(directory?.path, title, size, layout.index, extraFiles),
);

SkinPicture? _render(
  String? directory,
  String title,
  int size,
  int layout,
  Map<String, Uint8List> extraFiles,
) {
  final archive = Archive();
  if (directory != null) {
    final root = Directory(directory);
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      var name = entity.path.substring(root.path.length);
      name = name.replaceAll("\\", "/");
      if (name.startsWith("/")) name = name.substring(1);
      archive.addFile(ArchiveFile.bytes(name, entity.readAsBytesSync()));
    }
  }
  for (final MapEntry(:key, :value) in extraFiles.entries) {
    archive.addFile(ArchiveFile.bytes(key, value));
  }
  // The renderer takes a skin with no main.bmp for a Wasabi 3 skin. A
  // broken main.bmp makes it use its own base skin's, which is the base
  // skin the app carries.
  if (archive.isEmpty) archive.addFile(ArchiveFile.bytes("main.bmp", [0]));
  final zip = ZipEncoder().encode(archive);
  final bytes = calloc<Uint8>(zip.length);
  final cTitle = title.toNativeUtf8();
  final image = calloc<SkinPreviewImage>();
  final fitted = calloc<SkinPreviewImage>();
  try {
    bytes.asTypedList(zip.length).setAll(0, zip);
    if (skinPreviewRender(bytes, zip.length, cTitle, layout, image) != 0) {
      return null;
    }
    if (skinPreviewFit(image, size, fitted) != 0) return null;
    final length = fitted.ref.width * fitted.ref.height * 4;
    return SkinPicture(
      fitted.ref.width,
      fitted.ref.height,
      Uint8List.fromList(fitted.ref.rgba.asTypedList(length)),
    );
  } finally {
    skinPreviewFree(image);
    skinPreviewFree(fitted);
    calloc.free(bytes);
    calloc.free(image);
    calloc.free(fitted);
    malloc.free(cTitle);
  }
}
