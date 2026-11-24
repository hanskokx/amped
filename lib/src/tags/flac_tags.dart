import "dart:io";
import "dart:typed_data";

import "id3v2.dart";
import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";
import "vorbis_comment.dart";

/// The metadata blocks of a FLAC file.
class FlacMetadata {
  FlacMetadata._(this.start, this.end, this.blocks);

  /// Where the first block starts (after "fLaC") and the last one ends.
  final int start;
  final int end;

  /// The blocks as (type, data), in file order.
  final List<(int, Uint8List)> blocks;

  static const int _vorbisComment = 4;
  static const int _padding = 1;
  static const int _picture = 6;

  static const List<String> _blockNames = [
    "STREAMINFO",
    "PADDING",
    "APPLICATION",
    "SEEKTABLE",
    "VORBIS_COMMENT",
    "CUESHEET",
    "PICTURE",
  ];

  /// Reads the metadata blocks of the FLAC file open in [raf].
  factory FlacMetadata.read(RandomAccessFile raf) {
    var o = 0;
    final head = readAt(raf, 0, 10);
    // Some encoders put an ID3v2 tag before the stream.
    if (Id3v2Tag.isAt(head, 0)) o = Id3v2Tag.sizeFromHeader(head);
    if (!hasAscii(readAt(raf, o, 4), 0, "fLaC")) {
      throw const FormatException("Not a FLAC file");
    }
    final start = o + 4;
    o = start;
    final blocks = <(int, Uint8List)>[];
    while (true) {
      final header = readAt(raf, o, 4);
      if (header.length < 4) throw const FormatException("Truncated FLAC");
      final size = u24be(header, 1);
      final data = readAt(raf, o + 4, size);
      if (data.length < size) throw const FormatException("Truncated FLAC");
      blocks.add((header[0] & 0x7f, data));
      o += 4 + size;
      if (header[0] & 0x80 != 0) break;
    }
    return FlacMetadata._(start, o, blocks);
  }

  VorbisComment? get comment {
    for (final (type, data) in blocks) {
      if (type == _vorbisComment) return VorbisComment.parse(data).$1;
    }
    return null;
  }

  /// The `PICTURE` blocks' pictures, in file order (unreadable ones left
  /// out).
  List<EmbeddedPicture> get pictures => [
    for (final (type, data) in blocks)
      if (type == _picture) ?_tryPicture(data),
  ];

  static EmbeddedPicture? _tryPicture(Uint8List data) {
    try {
      return EmbeddedPicture.fromFlacBlock(data);
    } on FormatException {
      return null;
    }
  }

  List<TagEntry> get entries => [
    for (final (type, data) in blocks)
      if (type == _vorbisComment)
        ...VorbisComment.parse(data).$1.entries
      else if (type != _padding && type != 0)
        TagEntry(
          type < _blockNames.length ? _blockNames[type] : "BLOCK $type",
          type == _picture
              ? "[picture, ${data.length} bytes]"
              : "[${data.length} bytes]",
        ),
  ];

  /// Applies [changes] to [file] and, when given, replaces its pictures
  /// with [pictures]. Padding is reused so that the audio doesn't move when
  /// the blocks still fit.
  static void write(
    File file,
    Map<TagField, String> changes, {
    List<EmbeddedPicture>? pictures,
  }) {
    final raf = file.openSync();
    final FlacMetadata meta;
    try {
      meta = FlacMetadata.read(raf);
    } finally {
      raf.closeSync();
    }
    final comment = meta.comment ?? VorbisComment("amped", []);
    changes.forEach(comment.set);
    final commentBytes = comment.toBytes();
    if (commentBytes.length >= 1 << 24) {
      throw const TagWriteException("Comments too large for FLAC");
    }
    final kept = <(int, Uint8List)>[];
    var commentAt = -1;
    var pictureAt = -1;
    for (final block in meta.blocks) {
      if (block.$1 == _vorbisComment) {
        commentAt = kept.length;
      } else if (block.$1 == _picture && pictures != null) {
        if (pictureAt < 0) pictureAt = kept.length;
      } else if (block.$1 != _padding) {
        kept.add(block);
      }
    }
    // A new comment block goes right after STREAMINFO.
    if (commentAt < 0) commentAt = 1;
    kept.insert(commentAt, (_vorbisComment, commentBytes));
    if (pictures != null) {
      // Where the old pictures were, or after the comments.
      if (pictureAt < 0) {
        pictureAt = commentAt + 1;
      } else if (pictureAt >= commentAt) {
        pictureAt++;
      }
      final blocks = [
        for (final picture in pictures) (_picture, picture.toFlacBlock()),
      ];
      if (blocks.any((b) => b.$2.length >= 1 << 24)) {
        throw const TagWriteException("Picture too large for FLAC");
      }
      kept.insertAll(pictureAt, blocks);
    }
    final used = kept.fold(0, (sum, b) => sum + 4 + b.$2.length);
    final available = meta.end - meta.start;
    if (available - used >= 4) {
      kept.add((_padding, Uint8List(available - used - 4)));
    } else if (available != used) {
      kept.add((_padding, Uint8List(4096)));
    }
    final out = BytesBuilder(copy: false);
    for (final (i, (type, data)) in kept.indexed) {
      out
        ..addByte(type | (i == kept.length - 1 ? 0x80 : 0))
        ..add(be24(data.length))
        ..add(data);
    }
    editFile(file, [(start: meta.start, end: meta.end, bytes: out.toBytes())]);
  }
}
