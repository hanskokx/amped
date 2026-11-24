import "dart:typed_data";
import "dart:ui" as ui;

/// The side of the "file icon" picture, in pixels (ID3v2 and FLAC want a
/// 32x32 PNG for that picture type).
const fileIconSize = 32;

/// Scales the cover in [data] down to a [fileIconSize] square PNG, or null
/// when the engine can't read the image.
Future<Uint8List?> scaleToFileIcon(Uint8List data) async {
  try {
    final codec = await ui.instantiateImageCodec(
      data,
      targetWidth: fileIconSize,
      targetHeight: fileIconSize,
    );
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        return png?.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  }
}
