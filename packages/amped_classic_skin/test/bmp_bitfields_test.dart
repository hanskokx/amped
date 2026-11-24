import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

/// A 1×1 BMP: a 40-byte header with BI_BITFIELDS, the three masks after it,
/// and one pixel of [bits] bits.
Uint8List _bitfields(int bits, List<int> masks, int pixel) {
  final out = Uint8List(54 + 12 + 4);
  ByteData.sublistView(out)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, out.length, Endian.little)
    ..setUint32(10, 66, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, 1, Endian.little)
    ..setInt32(22, 1, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, bits, Endian.little)
    ..setUint32(30, 3, Endian.little)
    // Pixels per metre and colours used: not masks.
    ..setUint32(38, 0xB880000, Endian.little)
    ..setUint32(54, masks[0], Endian.little)
    ..setUint32(58, masks[1], Endian.little)
    ..setUint32(62, masks[2], Endian.little);
  if (bits == 16) {
    ByteData.sublistView(out).setUint16(66, pixel, Endian.little);
  } else {
    ByteData.sublistView(out).setUint32(66, pixel, Endian.little);
  }
  return out;
}

void main() {
  test("a 5-6-5 bitmap reads its masks after the header", () {
    // Pure red, then pure green, then pure blue.
    for (final (pixel, rgb) in [
      (0xF800, [255, 0, 0]),
      (0x07E0, [0, 255, 0]),
      (0x001F, [0, 0, 255]),
    ]) {
      final bmp = decodeBmp(_bitfields(16, [0xF800, 0x07E0, 0x001F], pixel));
      expect(bmp.rgba.sublist(0, 3), rgb);
    }
  });

  test("a 32-bit bitfields bitmap scales its 8-bit channels", () {
    final bmp = decodeBmp(
      _bitfields(32, [0xFF0000, 0xFF00, 0xFF], 0xFF336699),
    );
    expect(bmp.rgba.sublist(0, 3), [0x33, 0x66, 0x99]);
  });
}
