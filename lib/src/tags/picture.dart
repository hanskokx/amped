/// Embedded pictures (cover art): the format-neutral model the File Info
/// dialog's Artwork tab shows and edits, and that anything showing album
/// art can read with `readCoverArt`.
library;

import "dart:convert";
import "dart:typed_data";

import "tag_bytes.dart";

/// What a picture shows: the picture types of ID3v2 `APIC` frames and FLAC
/// `PICTURE` blocks (which share them), in code order.
enum ArtworkType {
  other,
  fileIcon,
  otherFileIcon,
  frontCover,
  backCover,
  leaflet,
  media,
  leadArtist,
  artist,
  conductor,
  band,
  composer,
  lyricist,
  recordingLocation,
  duringRecording,
  duringPerformance,
  videoCapture,
  brightFish,
  illustration,
  bandLogo,
  publisherLogo;

  /// The type stored as [code]; [other] for codes past the list.
  static ArtworkType fromCode(int code) =>
      code >= 0 && code < values.length ? values[code] : other;

  /// The number stored in the file.
  int get code => index;
}

/// One picture embedded in a file. Plain data, so it can cross isolates.
class EmbeddedPicture {
  const EmbeddedPicture({
    required this.type,
    required this.mimeType,
    required this.data,
    this.description = "",
  });

  final ArtworkType type;

  /// E.g. `image/jpeg`; may be empty when the file didn't say.
  final String mimeType;

  final String description;

  /// The encoded image, as stored.
  final Uint8List data;

  /// The width and height the image's header gives, when it can be read.
  (int, int)? get size => imageSize(data);

  /// The sub-type to show (`jpeg` for `image/jpeg`), or the sniffed one.
  String get formatName {
    final mime = mimeType.isNotEmpty ? mimeType : sniffImageMime(data) ?? "";
    final slash = mime.indexOf("/");
    return slash < 0 ? mime : mime.substring(slash + 1);
  }

  EmbeddedPicture copyWith({ArtworkType? type}) => EmbeddedPicture(
    type: type ?? this.type,
    mimeType: mimeType,
    data: data,
    description: description,
  );

  /// The FLAC `PICTURE` block body (also what Ogg's
  /// `METADATA_BLOCK_PICTURE` comment holds, base64-encoded).
  Uint8List toFlacBlock() {
    final mime = latin1.encode(mimeType.isEmpty ? "image/" : mimeType);
    final desc = utf8.encode(description);
    final (width, height) = size ?? (0, 0);
    return (BytesBuilder(copy: false)
          ..add(be32(type.code))
          ..add(be32(mime.length))
          ..add(mime)
          ..add(be32(desc.length))
          ..add(desc)
          ..add(be32(width))
          ..add(be32(height))
          ..add(be32(_colorDepth(data)))
          ..add(be32(0))
          ..add(be32(data.length))
          ..add(data))
        .toBytes();
  }

  /// Parses a FLAC `PICTURE` block body.
  factory EmbeddedPicture.fromFlacBlock(Uint8List block) {
    var o = 0;
    int u32() {
      if (o + 4 > block.length) throw const FormatException("Bad picture");
      final v = u32be(block, o);
      o += 4;
      return v;
    }

    Uint8List bytes(int length) {
      if (o + length > block.length) {
        throw const FormatException("Bad picture");
      }
      final b = Uint8List.sublistView(block, o, o + length);
      o += length;
      return b;
    }

    final type = u32();
    final mime = latin1.decode(bytes(u32()), allowInvalid: true);
    final description = decodeText(bytes(u32()));
    o += 16; // Width, height, depth, colours.
    final data = Uint8List.fromList(bytes(u32()));
    return EmbeddedPicture(
      type: ArtworkType.fromCode(type),
      mimeType: mime,
      description: description,
      data: data,
    );
  }
}

/// What `readFilePictures` found in one file.
class FilePictures {
  const FilePictures(this.pictures, {required this.editable}) : error = null;

  const FilePictures.unreadable(this.error)
    : pictures = const [],
      editable = false;

  final List<EmbeddedPicture> pictures;

  /// Whether pictures can be written to this file.
  final bool editable;

  /// Why reading failed, when it did.
  final String? error;

  /// The front cover, else the first picture.
  EmbeddedPicture? get cover => coverOf(pictures);
}

/// The front cover among [pictures], else the first one.
EmbeddedPicture? coverOf(List<EmbeddedPicture> pictures) {
  for (final picture in pictures) {
    if (picture.type == ArtworkType.frontCover) return picture;
  }
  return pictures.firstOrNull;
}

/// The MIME type of the image in [data], from its first bytes.
String? sniffImageMime(List<int> data) {
  if (data.length >= 3 &&
      data[0] == 0xff &&
      data[1] == 0xd8 &&
      data[2] == 0xff) {
    return "image/jpeg";
  }
  if (hasAscii(data, 1, "PNG") && data[0] == 0x89) return "image/png";
  if (hasAscii(data, 0, "GIF8")) return "image/gif";
  if (hasAscii(data, 0, "BM")) return "image/bmp";
  if (hasAscii(data, 0, "RIFF") && hasAscii(data, 8, "WEBP")) {
    return "image/webp";
  }
  return null;
}

/// The width and height in the header of the image in [data] (JPEG, PNG,
/// GIF, BMP), or `null`.
(int, int)? imageSize(Uint8List data) {
  try {
    switch (sniffImageMime(data)) {
      case "image/png":
        return data.length >= 24 && hasAscii(data, 12, "IHDR")
            ? (u32be(data, 16), u32be(data, 20))
            : null;
      case "image/gif":
        return data.length >= 10
            ? (data[6] | data[7] << 8, data[8] | data[9] << 8)
            : null;
      case "image/bmp":
        if (data.length < 26) return null;
        final height = u32le(data, 22).toSigned(32);
        return (u32le(data, 18).toSigned(32), height.abs());
      case "image/jpeg":
        return _jpegSize(data);
    }
  } on RangeError {
    // A truncated header.
  }
  return null;
}

(int, int)? _jpegSize(Uint8List data) {
  var o = 2;
  while (o + 4 <= data.length) {
    if (data[o] != 0xff) return null;
    final marker = data[o + 1];
    if (marker == 0xff) {
      o++;
      continue;
    }
    // Markers without a length.
    if (marker == 0xd8 ||
        marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      o += 2;
      continue;
    }
    final length = u16be(data, o + 2);
    // SOF0..SOF15, but not DHT (C4), JPG (C8) or DAC (CC).
    if (marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc) {
      if (o + 9 > data.length) return null;
      return (u16be(data, o + 7), u16be(data, o + 5));
    }
    o += 2 + length;
  }
  return null;
}

/// The bits per pixel FLAC's picture block asks for, when easy to tell.
int _colorDepth(Uint8List data) {
  try {
    switch (sniffImageMime(data)) {
      case "image/png" when data.length >= 26:
        final channels = switch (data[25]) {
          2 => 3,
          4 => 2,
          6 => 4,
          _ => 1,
        };
        return data[24] * channels;
      case "image/jpeg":
        return 24;
      case "image/gif":
        return 8;
      case "image/bmp" when data.length >= 30:
        return data[28] | data[29] << 8;
    }
  } on RangeError {
    // Unknown.
  }
  return 0;
}
