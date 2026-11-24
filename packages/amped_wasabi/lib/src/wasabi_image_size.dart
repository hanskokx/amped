import "dart:typed_data";

/// The width and height in pixels of a PNG, GIF, BMP or JPEG image, read
/// from its header without decoding it, or null for anything else.
(int, int)? wasabiImageSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  bool starts(List<int> magic) =>
      bytes.length >= magic.length &&
      [
        for (var i = 0; i < magic.length; i++) bytes[i] == magic[i],
      ].every((e) => e);
  // PNG: the IHDR chunk right after the signature.
  if (starts(const [0x89, 0x50, 0x4E, 0x47]) && bytes.length >= 24) {
    return (data.getUint32(16), data.getUint32(20));
  }
  // GIF: the logical screen, little-endian.
  if (starts(const [0x47, 0x49, 0x46]) && bytes.length >= 10) {
    return (data.getUint16(6, Endian.little), data.getUint16(8, Endian.little));
  }
  // BMP: the info header; a positive height is bottom-up.
  if (starts(const [0x42, 0x4D]) && bytes.length >= 26) {
    final headerSize = data.getUint32(14, Endian.little);
    if (headerSize == 12) {
      return (
        data.getUint16(18, Endian.little),
        data.getUint16(20, Endian.little),
      );
    }
    return (
      data.getInt32(18, Endian.little).abs(),
      data.getInt32(22, Endian.little).abs(),
    );
  }
  // JPEG: the first start-of-frame marker.
  if (starts(const [0xFF, 0xD8])) {
    var at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] != 0xFF) {
        at++;
        continue;
      }
      final marker = bytes[at + 1];
      if (marker == 0xFF) {
        at++;
        continue;
      }
      // Markers without a length: standalone ones and restarts.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      final length = data.getUint16(at + 2);
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        return (data.getUint16(at + 7), data.getUint16(at + 5));
      }
      at += 2 + length;
    }
  }
  return null;
}
