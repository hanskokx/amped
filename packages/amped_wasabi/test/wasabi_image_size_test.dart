import "dart:convert";
import "dart:typed_data";

import "package:amped_wasabi/src/wasabi_image_size.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("reads a PNG's size", () {
    // A 1x1 transparent PNG.
    final png = base64Decode(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
    );
    expect(wasabiImageSize(png), (1, 1));
  });

  test("reads a GIF's, BMP's and JPEG's size", () {
    final gif = Uint8List.fromList([
      ...ascii.encode("GIF89a"),
      3,
      0,
      2,
      0,
      0,
      0,
      0,
    ]);
    expect(wasabiImageSize(gif), (3, 2));

    final bmp = Uint8List(54);
    bmp[0] = 0x42;
    bmp[1] = 0x4D;
    ByteData.sublistView(bmp)
      ..setUint32(14, 40, Endian.little)
      ..setInt32(18, 5, Endian.little)
      ..setInt32(22, -4, Endian.little);
    expect(wasabiImageSize(bmp), (5, 4));

    // SOI, an APP0 segment, then SOF0: 7 high, 9 wide.
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xE0, 0, 4, 0, 0, //
      0xFF, 0xC0, 0, 11, 8, 0, 7, 0, 9, 1, 1, 0x11, 0,
    ]);
    expect(wasabiImageSize(jpeg), (9, 7));
  });

  test("anything else has no size", () {
    expect(wasabiImageSize(Uint8List.fromList([1, 2, 3])), isNull);
    expect(wasabiImageSize(Uint8List(0)), isNull);
  });
}
