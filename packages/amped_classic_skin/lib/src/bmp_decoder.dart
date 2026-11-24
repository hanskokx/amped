import "dart:typed_data";

/// Decoded bitmap in RGBA8888 format, stored top-down (row 0 is the top).
class BmpImage {
  const BmpImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// length == width * height * 4.
  final Uint8List rgba;
}

class BmpDecodeException implements Exception {
  BmpDecodeException(this.message);
  final String message;

  @override
  String toString() => "BmpDecodeException: $message";
}

/// Decodes a BMP (device-independent bitmap) file.
///
/// Supports 1/4/8/16/24/32 bit depths, palette images, bottom-up and
/// top-down rows, and BI_RGB / BI_RLE8 / BI_RLE4 / BI_BITFIELDS
/// compression. Classic skins ship 8-bit palette bitmaps (frequently
/// RLE8-compressed) so this decoder is self-contained rather than relying on
/// packages that do not decode RLE bitmaps.
BmpImage decodeBmp(Uint8List data) {
  final in_ = ByteData.sublistView(data);
  if (data.length < 18) {
    throw BmpDecodeException("Not a bitmap file (too short).");
  }
  if (in_.getUint8(0) != 0x42 || in_.getUint8(1) != 0x4D) {
    throw BmpDecodeException("Not a bitmap file (bad signature).");
  }

  final dataOffset = in_.getUint32(10, Endian.little);

  final dibSize = in_.getUint32(14, Endian.little);

  int width;
  int height;
  int bitsPerPixel;
  int compression = 0;
  int colorsUsed = 0;
  int redMask = 0;
  int greenMask = 0;
  int blueMask = 0;
  int alphaMask = 0;
  int paletteOffset;
  int paletteEntrySize;

  if (dibSize >= 40) {
    width = in_.getInt32(18, Endian.little);
    height = in_.getInt32(22, Endian.little);
    final planes = in_.getUint16(26, Endian.little);
    bitsPerPixel = in_.getUint16(28, Endian.little);
    compression = in_.getUint32(30, Endian.little);
    colorsUsed = in_.getUint32(46, Endian.little);
    if (planes != 1) {
      throw BmpDecodeException("Unsupported plane count: $planes");
    }
    // The channel masks follow the 40 bytes every header starts with: right
    // after a plain BITMAPINFOHEADER (BI_BITFIELDS), or inside a longer one.
    if ((dibSize >= 52 || compression == 3) && data.length >= 14 + 52) {
      redMask = in_.getUint32(54, Endian.little);
      greenMask = in_.getUint32(58, Endian.little);
      blueMask = in_.getUint32(62, Endian.little);
    }
    if (dibSize >= 56 && data.length >= 14 + 56) {
      alphaMask = in_.getUint32(66, Endian.little);
    }
    paletteOffset = 14 + dibSize;
    paletteEntrySize = 4;
  } else if (dibSize == 12) {
    width = in_.getUint16(18, Endian.little);
    height = in_.getUint16(20, Endian.little);
    final planes = in_.getUint16(22, Endian.little);
    bitsPerPixel = in_.getUint16(24, Endian.little);
    if (planes != 1) {
      throw BmpDecodeException("Unsupported plane count: $planes");
    }
    paletteOffset = 14 + dibSize;
    paletteEntrySize = 3;
  } else {
    throw BmpDecodeException("Unsupported DIB header size: $dibSize");
  }

  if (width <= 0 || width > 16384) {
    throw BmpDecodeException("Invalid width: $width");
  }
  final absHeight = height.abs();
  if (absHeight <= 0 || absHeight > 16384) {
    throw BmpDecodeException("Invalid height: $height");
  }
  final bottomUp = height > 0;

  // Palette
  final palette = _readPalette(
    data,
    paletteOffset,
    dataOffset,
    paletteEntrySize,
    bitsPerPixel,
    colorsUsed,
  );

  switch (bitsPerPixel) {
    case 1:
    case 4:
    case 8:
      if (compression == 1) {
        return _decodeIndexedRle(
          data,
          dataOffset,
          width,
          absHeight,
          bottomUp,
          bitsPerPixel,
          palette,
        );
      }
      if (compression == 0 || compression == 3) {
        return _decodeIndexed(
          data,
          dataOffset,
          width,
          absHeight,
          bottomUp,
          bitsPerPixel,
          palette,
        );
      }
      throw BmpDecodeException(
        "Unsupported compression $compression for $bitsPerPixel bpp",
      );
    case 16:
      return _decode16(
        in_,
        dataOffset,
        width,
        absHeight,
        bottomUp,
        compression,
        redMask,
        greenMask,
        blueMask,
        alphaMask,
      );
    case 24:
      if (compression == 0) {
        return _decode24(data, dataOffset, width, absHeight, bottomUp);
      }
      throw BmpDecodeException(
        "Unsupported compression $compression for 24 bpp",
      );
    case 32:
      return _decode32(
        in_,
        dataOffset,
        width,
        absHeight,
        bottomUp,
        compression,
        redMask,
        greenMask,
        blueMask,
        alphaMask,
      );
    default:
      throw BmpDecodeException("Unsupported bits per pixel: $bitsPerPixel");
  }
}

Uint8List _readPalette(
  Uint8List data,
  int paletteOffset,
  int dataOffset,
  int entrySize,
  int bitsPerPixel,
  int colorsUsed,
) {
  if (bitsPerPixel > 8) return Uint8List(0);
  final maxEntries = 1 << bitsPerPixel;
  var count = colorsUsed != 0 ? colorsUsed : maxEntries;
  final available = (dataOffset - paletteOffset) ~/ entrySize;
  if (count > available) count = available;
  if (count > maxEntries) count = maxEntries;
  if (count <= 0) return Uint8List(0);

  final palette = Uint8List(4 * count);
  for (var i = 0; i < count; i++) {
    final p = paletteOffset + i * entrySize;
    if (p + entrySize > data.length) break;
    final b = data[p];
    final g = data[p + 1];
    final r = data[p + 2];
    // The 4th palette byte is unused padding that GDI ignores; palette
    // bitmaps are always opaque (windows are shaped via regions instead).
    const a = 255;
    palette[i * 4] = r;
    palette[i * 4 + 1] = g;
    palette[i * 4 + 2] = b;
    palette[i * 4 + 3] = a;
  }
  return palette;
}

int _rowStride(int width, int bitsPerPixel) {
  final bits = width * bitsPerPixel;
  return ((bits + 31) >> 5) << 2;
}

BmpImage _decodeIndexed(
  Uint8List data,
  int dataOffset,
  int width,
  int height,
  bool bottomUp,
  int bitsPerPixel,
  Uint8List palette,
) {
  final stride = _rowStride(width, bitsPerPixel);
  final rgba = Uint8List(width * height * 4);

  for (var row = 0; row < height; row++) {
    final srcRow = bottomUp ? height - 1 - row : row;
    final src = dataOffset + srcRow * stride;
    var x = 0;
    for (var byte = 0; byte < stride && x < width; byte++) {
      if (src + byte >= data.length) break;
      final b = data[src + byte];
      if (bitsPerPixel == 8) {
        _writeIndexedPixel(rgba, width, row, x, b, palette);
        x++;
      } else if (bitsPerPixel == 4) {
        _writeIndexedPixel(rgba, width, row, x, (b >> 4) & 0xF, palette);
        x++;
        if (x < width) {
          _writeIndexedPixel(rgba, width, row, x, b & 0xF, palette);
          x++;
        }
      } else if (bitsPerPixel == 1) {
        for (var bit = 7; bit >= 0 && x < width; bit--) {
          _writeIndexedPixel(rgba, width, row, x, (b >> bit) & 1, palette);
          x++;
        }
      } else {
        throw BmpDecodeException("Unhandled indexed depth $bitsPerPixel");
      }
    }
  }
  return BmpImage(width: width, height: height, rgba: rgba);
}

void _writeIndexedPixel(
  Uint8List rgba,
  int width,
  int row,
  int x,
  int index,
  Uint8List palette,
) {
  if (index >= palette.length ~/ 4) {
    _writeColor(rgba, width, row, x, 0, 0, 0, 255);
    return;
  }
  final o = (row * width + x) * 4;
  rgba[o] = palette[index * 4];
  rgba[o + 1] = palette[index * 4 + 1];
  rgba[o + 2] = palette[index * 4 + 2];
  rgba[o + 3] = palette[index * 4 + 3];
}

void _writeColor(
  Uint8List rgba,
  int width,
  int row,
  int x,
  int r,
  int g,
  int b,
  int a,
) {
  final o = (row * width + x) * 4;
  rgba[o] = r;
  rgba[o + 1] = g;
  rgba[o + 2] = b;
  rgba[o + 3] = a;
}

/// Decodes RLE8 (bitsPerPixel == 8) or RLE4 (bitsPerPixel == 4) data.
BmpImage _decodeIndexedRle(
  Uint8List data,
  int dataOffset,
  int width,
  int height,
  bool bottomUp,
  int bitsPerPixel,
  Uint8List palette,
) {
  // Stored rows, in the order the stream produces them.
  final stored = Uint8List(width * height);
  // Row fill tracking for absolute-mode row termination.
  var x = 0;
  var y = 0;
  var i = dataOffset;

  final isRle8 = bitsPerPixel == 8;

  while (i < data.length && y < height) {
    final first = data[i];
    i++;
    if (first == 0) {
      if (i >= data.length) break;
      final second = data[i];
      i++;
      if (second == 0) {
        // End of line.
        x = 0;
        y++;
      } else if (second == 1) {
        // End of bitmap.
        break;
      } else if (second == 2) {
        // Delta.
        if (i + 1 >= data.length) break;
        x += data[i];
        i++;
        y += data[i];
        i++;
      } else {
        // Absolute mode: `second` pixels follow.
        if (isRle8) {
          for (var n = 0; n < second && x < width; n++) {
            if (i >= data.length) break;
            stored[y * width + x] = data[i];
            i++;
            x++;
          }
          if ((second & 1) != 0) {
            i++; // word-align absolute runs
          }
        } else {
          // RLE4 absolute: each byte holds two 4-bit indexes.
          for (var n = 0; n < second && x < width; n++) {
            if (i >= data.length) break;
            final b = data[i];
            stored[y * width + x] = (b >> 4) & 0xF;
            x++;
            if (x < width) {
              stored[y * width + x] = b & 0xF;
              x++;
            }
            i++;
          }
          // RLE4 absolute runs are aligned to even byte count.
          if ((((second + 1) >> 1) & 1) != 0) {
            i++;
          }
        }
      }
    } else {
      // Encoded run.
      if (i >= data.length) break;
      final index = data[i];
      i++;
      if (isRle8) {
        for (var n = 0; n < first && x < width; n++) {
          stored[y * width + x] = index;
          x++;
        }
      } else {
        final lo = index & 0xF;
        final hi = (index >> 4) & 0xF;
        for (var n = 0; n < first && x < width; n++) {
          stored[y * width + x] = (n & 1) == 0 ? hi : lo;
          x++;
        }
      }
    }
  }

  final rgba = Uint8List(width * height * 4);
  for (var row = 0; row < height; row++) {
    final storedRow = bottomUp ? height - 1 - row : row;
    for (var x0 = 0; x0 < width; x0++) {
      _writeIndexedPixel(
        rgba,
        width,
        row,
        x0,
        stored[storedRow * width + x0],
        palette,
      );
    }
  }
  return BmpImage(width: width, height: height, rgba: rgba);
}

BmpImage _decode24(
  Uint8List data,
  int dataOffset,
  int width,
  int height,
  bool bottomUp,
) {
  final stride = _rowStride(width, 24);
  final rgba = Uint8List(width * height * 4);
  for (var row = 0; row < height; row++) {
    final srcRow = bottomUp ? height - 1 - row : row;
    final src = dataOffset + srcRow * stride;
    for (var x = 0; x < width; x++) {
      final p = src + x * 3;
      if (p + 2 >= data.length) break;
      _writeColor(rgba, width, row, x, data[p + 2], data[p + 1], data[p], 255);
    }
  }
  return BmpImage(width: width, height: height, rgba: rgba);
}

BmpImage _decode32(
  ByteData view,
  int dataOffset,
  int width,
  int height,
  bool bottomUp,
  int compression,
  int redMask,
  int greenMask,
  int blueMask,
  int alphaMask,
) {
  final stride = _rowStride(width, 32);
  final rgba = Uint8List(width * height * 4);
  final total = view.lengthInBytes;

  if (compression == 0) {
    for (var row = 0; row < height; row++) {
      final srcRow = bottomUp ? height - 1 - row : row;
      final src = dataOffset + srcRow * stride;
      for (var x = 0; x < width; x++) {
        final p = src + x * 4;
        if (p + 3 >= total) break;
        final r = view.getUint8(p + 2);
        final g = view.getUint8(p + 1);
        final b = view.getUint8(p);
        // GDI ignores the alpha channel for plain BI_RGB; make it opaque.
        _writeColor(rgba, width, row, x, r, g, b, 255);
      }
    }
  } else if (compression == 3) {
    if (redMask == 0) redMask = 0x00FF0000;
    if (greenMask == 0) greenMask = 0x0000FF00;
    if (blueMask == 0) blueMask = 0x000000FF;
    if (alphaMask == 0) alphaMask = 0xFF000000;
    final rShift = _maskShift(redMask);
    final rScale = _maskScale(redMask);
    final gShift = _maskShift(greenMask);
    final gScale = _maskScale(greenMask);
    final bShift = _maskShift(blueMask);
    final bScale = _maskScale(blueMask);
    final aShift = _maskShift(alphaMask);
    final aScale = _maskScale(alphaMask);
    for (var row = 0; row < height; row++) {
      final srcRow = bottomUp ? height - 1 - row : row;
      final src = dataOffset + srcRow * stride;
      for (var x = 0; x < width; x++) {
        final p = src + x * 4;
        if (p + 3 >= total) break;
        final v = view.getUint32(p, Endian.little);
        _writeColor(
          rgba,
          width,
          row,
          x,
          ((v & redMask) >> rShift) * rScale,
          ((v & greenMask) >> gShift) * gScale,
          ((v & blueMask) >> bShift) * bScale,
          ((v & alphaMask) >> aShift) * aScale,
        );
      }
    }
  } else {
    throw BmpDecodeException("Unsupported compression $compression for 32 bpp");
  }
  return BmpImage(width: width, height: height, rgba: rgba);
}

BmpImage _decode16(
  ByteData view,
  int dataOffset,
  int width,
  int height,
  bool bottomUp,
  int compression,
  int redMask,
  int greenMask,
  int blueMask,
  int alphaMask,
) {
  final stride = _rowStride(width, 16);
  final rgba = Uint8List(width * height * 4);

  // Plain 16-bit bitmaps are 5-5-5; BI_BITFIELDS ones say which bits are
  // which (5-6-5 is common).
  if (compression != 3 || redMask == 0) redMask = 0x7C00;
  if (compression != 3 || greenMask == 0) greenMask = 0x03E0;
  if (compression != 3 || blueMask == 0) blueMask = 0x001F;
  final rShift = _maskShift(redMask);
  final gShift = _maskShift(greenMask);
  final bShift = _maskShift(blueMask);
  final rMax = redMask >> rShift;
  final gMax = greenMask >> gShift;
  final bMax = blueMask >> bShift;

  final total = view.lengthInBytes;
  for (var row = 0; row < height; row++) {
    final srcRow = bottomUp ? height - 1 - row : row;
    final src = dataOffset + srcRow * stride;
    for (var x = 0; x < width; x++) {
      final p = src + x * 2;
      if (p + 1 >= total) break;
      final v = view.getUint16(p, Endian.little);
      _writeColor(
        rgba,
        width,
        row,
        x,
        ((v & redMask) >> rShift) * 255 ~/ rMax,
        ((v & greenMask) >> gShift) * 255 ~/ gMax,
        ((v & blueMask) >> bShift) * 255 ~/ bMax,
        255,
      );
    }
  }
  return BmpImage(width: width, height: height, rgba: rgba);
}

int _maskShift(int mask) {
  var shift = 0;
  while (mask != 0 && (mask & 1) == 0) {
    shift++;
    mask >>= 1;
  }
  return shift;
}

int _maskScale(int mask) {
  if (mask == 0) return 255;
  // The width of the field, not its position.
  mask >>= _maskShift(mask);
  var bits = 0;
  while (mask != 0) {
    bits++;
    mask >>= 1;
  }
  return 255 ~/ ((1 << bits) - 1);
}
