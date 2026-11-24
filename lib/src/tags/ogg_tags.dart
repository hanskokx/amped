import "dart:io";
import "dart:typed_data";

import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";
import "vorbis_comment.dart";

/// One Ogg page.
class _Page {
  _Page(this.offset, this.bytes);

  final int offset;
  final Uint8List bytes;

  int get headerType => bytes[5];
  int get serial => u32le(bytes, 14);
  int get sequence => u32le(bytes, 18);
  int get segmentCount => bytes[26];
  List<int> get lacing => bytes.sublist(27, 27 + segmentCount);
  Uint8List get body => Uint8List.sublistView(bytes, 27 + segmentCount);
  int get length => bytes.length;
}

/// The comment header of the first logical stream of an Ogg Vorbis, Opus,
/// Speex or FLAC file, and where its header pages are.
class OggComments {
  OggComments._(
    this.format,
    this.comment,
    this._pages,
    this._headerPages,
    this._packets, [
    this.flacPictures = const [],
  ]);

  final TagFormat format;
  final VorbisComment comment;

  /// The stream's pages read so far: the header pages, then one more.
  final List<_Page> _pages;

  /// How many pages hold the header packets (the first holds only the
  /// identification header).
  final int _headerPages;

  /// The header packets after the identification header.
  final List<Uint8List> _packets;

  /// An Ogg FLAC stream's `PICTURE` blocks' pictures.
  final List<EmbeddedPicture> flacPictures;

  /// The page prefix of the comment packet for [format].
  static List<int> _magic(TagFormat format) => switch (format) {
    TagFormat.oggOpus => "OpusTags".codeUnits,
    // Speex's comment packet is the bare comment structure, and Ogg FLAC's
    // a metadata block.
    TagFormat.oggSpeex || TagFormat.oggFlac => const [],
    _ => [3, ..."vorbis".codeUnits],
  };

  static const int _flacComment = 4;
  static const int _flacPicture = 6;

  static _Page? _readPage(RandomAccessFile raf, int offset) {
    final head = readAt(raf, offset, 27);
    if (head.length < 27 || !hasAscii(head, 0, "OggS")) return null;
    final segments = readAt(raf, offset + 27, head[26]);
    if (segments.length < head[26]) return null;
    final bodyLength = segments.fold(0, (a, b) => a + b);
    final rest = readAt(raf, offset + 27, head[26] + bodyLength);
    if (rest.length < head[26] + bodyLength) return null;
    return _Page(offset, Uint8List.fromList([...head, ...rest]));
  }

  /// Reads the header packets of the first stream of the Ogg file open in
  /// [raf].
  factory OggComments.read(RandomAccessFile raf) {
    final pages = <_Page>[];
    final packets = <Uint8List>[];
    var current = BytesBuilder(copy: false);
    var offset = 0;
    TagFormat? format;
    int? serial;
    var needed = 3;
    var flacHeaders = 0;
    while (packets.length < needed) {
      final page = _readPage(raf, offset);
      if (page == null) throw const FormatException("Truncated Ogg stream");
      offset += page.length;
      serial ??= page.serial;
      if (page.serial != serial) {
        throw const TagWriteException(
          "Multiplexed Ogg streams aren't supported",
        );
      }
      pages.add(page);
      var o = 0;
      final body = page.body;
      for (final lace in page.lacing) {
        current.add(body.sublist(o, o + lace));
        o += lace;
        if (lace < 255) {
          packets.add(current.takeBytes());
          current = BytesBuilder(copy: false);
          if (packets.length == 1) {
            final first = packets.first;
            if (hasAscii(first, 0, "OpusHead")) {
              format = TagFormat.oggOpus;
              needed = 2;
            } else if (first.isNotEmpty &&
                first[0] == 1 &&
                hasAscii(first, 1, "vorbis")) {
              format = TagFormat.oggVorbis;
            } else if (hasAscii(first, 0, "Speex   ")) {
              format = TagFormat.oggSpeex;
              needed = 2;
            } else if (first.length >= 13 &&
                first[0] == 0x7f &&
                hasAscii(first, 1, "FLAC")) {
              format = TagFormat.oggFlac;
              flacHeaders = u16be(first, 7);
              // 0 counts the blocks until one is flagged as the last.
              needed = first[13] & 0x80 != 0
                  ? 1
                  : flacHeaders > 0
                  ? 1 + flacHeaders
                  : 1 << 30;
            } else {
              throw const TagWriteException("Unsupported Ogg codec");
            }
          } else if (format == TagFormat.oggFlac &&
              flacHeaders == 0 &&
              packets.last.isNotEmpty &&
              packets.last[0] & 0x80 != 0) {
            needed = packets.length;
          }
        }
      }
      // Pictures can make the comment header run over many pages.
      if (offset > 64 << 20) throw const FormatException("Bad Ogg headers");
    }
    final firstLacing = pages.first.lacing;
    if (current.isNotEmpty ||
        packets.length != needed ||
        firstLacing.isEmpty ||
        firstLacing.last == 255 ||
        firstLacing.where((l) => l < 255).length != 1) {
      // Audio shares the last header page; it could not be repaged safely.
      throw const TagWriteException("Unusual Ogg header layout");
    }
    if (format == TagFormat.oggFlac) {
      return OggComments._flac(pages, packets);
    }
    final magic = _magic(format!);
    final commentPacket = packets[1];
    if (!hasAscii(commentPacket, 0, String.fromCharCodes(magic))) {
      throw const FormatException("Missing Ogg comment header");
    }
    final (comment, end) = VorbisComment.parse(commentPacket, magic.length);
    final withTrailing = VorbisComment(
      comment.vendor,
      comment.comments,
      Uint8List.sublistView(commentPacket, end),
    );
    return OggComments._(
      format,
      withTrailing,
      pages,
      pages.length,
      packets.sublist(1),
    );
  }

  /// An Ogg FLAC stream: the packets after the first are FLAC metadata
  /// blocks.
  factory OggComments._flac(List<_Page> pages, List<Uint8List> packets) {
    VorbisComment? comment;
    final pictures = <EmbeddedPicture>[];
    for (final packet in packets.skip(1)) {
      if (packet.length < 4) continue;
      final type = packet[0] & 0x7f;
      final data = Uint8List.sublistView(packet, 4);
      if (type == _flacComment && comment == null) {
        comment = VorbisComment.parse(data).$1;
      } else if (type == _flacPicture) {
        try {
          pictures.add(EmbeddedPicture.fromFlacBlock(data));
        } on FormatException {
          // Leave an unreadable picture out.
        }
      }
    }
    return OggComments._(
      TagFormat.oggFlac,
      comment ?? VorbisComment("amped", []),
      pages,
      pages.length,
      packets.sublist(1),
      pictures,
    );
  }

  /// Applies [changes] to [file] and, when given, replaces its pictures
  /// with [pictures]. The header pages are rebuilt; when their number
  /// changes, the stream's later pages are renumbered (and their checksums
  /// redone).
  static void write(
    File file,
    Map<TagField, String> changes, {
    List<EmbeddedPicture>? pictures,
  }) {
    final raf = file.openSync();
    final OggComments ogg;
    final int length;
    try {
      ogg = OggComments.read(raf);
      length = raf.lengthSync();
    } finally {
      raf.closeSync();
    }
    changes.forEach(ogg.comment.set);
    final first = ogg._pages.first;
    final isFlac = ogg.format == TagFormat.oggFlac;
    final List<Uint8List> packets;
    // What replaces the stream's first page: nothing for Vorbis, Opus and
    // Speex; Ogg FLAC counts its header packets there.
    var firstPage = Uint8List(0);
    if (isFlac) {
      if (pictures != null) ogg.comment.setPictures(const []);
      final blocks = ogg._flacBlocks(pictures);
      packets = [
        for (final (i, b) in blocks.indexed) _flacPacket(b, i, blocks),
      ];
      final head = Uint8List.fromList(first.body);
      if (blocks.isNotEmpty) {
        // The header count, and STREAMINFO is no longer the last block.
        head.setRange(7, 9, [blocks.length >> 8, blocks.length & 0xff]);
        head[13] &= 0x7f;
      }
      firstPage = _paginate([head], first.serial, 0, bos: true).single;
    } else {
      if (pictures != null) ogg.comment.setPictures(pictures);
      packets = [
        Uint8List.fromList([..._magic(ogg.format), ...ogg.comment.toBytes()]),
        ...ogg._packets.skip(1),
      ];
    }
    final newPages = _paginate(packets, first.serial, 1);
    final delta = newPages.length - (ogg._headerPages - 1);
    final headerEnd =
        ogg._pages[ogg._headerPages - 1].offset +
        ogg._pages[ogg._headerPages - 1].length;
    final rebuilt = BytesBuilder(copy: false)..add(firstPage);
    for (final page in newPages) {
      rebuilt.add(page);
    }
    final editStart = isFlac ? 0 : first.length;
    if (delta == 0) {
      editFile(file, [
        (start: editStart, end: headerEnd, bytes: rebuilt.toBytes()),
      ]);
      return;
    }
    // Renumber the rest of this stream's pages.
    final source = file.openSync();
    try {
      var offset = headerEnd;
      while (offset < length) {
        final page = _readPage(source, offset);
        if (page == null) {
          rebuilt.add(readAt(source, offset, length - offset));
          break;
        }
        final bytes = page.bytes;
        if (page.serial == first.serial) {
          bytes.setRange(18, 22, le32(page.sequence + delta));
          _setCrc(bytes);
        }
        rebuilt.add(bytes);
        offset += page.length;
      }
    } finally {
      source.closeSync();
    }
    editFile(file, [
      (start: editStart, end: length, bytes: rebuilt.toBytes()),
    ]);
  }

  /// The FLAC metadata blocks to write: the old ones with the comment
  /// block replaced by [comment] and, when [pictures] is given, the
  /// picture blocks by its pictures (after the comment).
  List<(int, Uint8List)> _flacBlocks(List<EmbeddedPicture>? pictures) {
    final blocks = <(int, Uint8List)>[];
    var commentAt = -1;
    var pictureAt = -1;
    for (final packet in _packets) {
      if (packet.length < 4) continue;
      final type = packet[0] & 0x7f;
      if (type == _flacComment && commentAt < 0) {
        commentAt = blocks.length;
        blocks.add((type, comment.toBytes()));
      } else if (type == _flacPicture && pictures != null) {
        if (pictureAt < 0) pictureAt = blocks.length;
      } else {
        blocks.add((type, Uint8List.sublistView(packet, 4)));
      }
    }
    if (commentAt < 0) {
      commentAt = 0;
      blocks.insert(0, (_flacComment, comment.toBytes()));
      if (pictureAt >= 0) pictureAt++;
    }
    if (pictures != null) {
      if (pictureAt < 0) {
        pictureAt = commentAt + 1;
      }
      blocks.insertAll(pictureAt, [
        for (final p in pictures) (_flacPicture, p.toFlacBlock()),
      ]);
    }
    for (final (_, data) in blocks) {
      if (data.length >= 1 << 24) {
        throw const TagWriteException("Block too large for Ogg FLAC");
      }
    }
    return blocks;
  }

  static Uint8List _flacPacket(
    (int, Uint8List) block,
    int index,
    List<(int, Uint8List)> all,
  ) => Uint8List.fromList([
    block.$1 | (index == all.length - 1 ? 0x80 : 0),
    ...be24(block.$2.length),
    ...block.$2,
  ]);

  /// Lays [packets] out in pages of up to 255 segments, numbered from
  /// [sequence].
  static List<Uint8List> _paginate(
    List<Uint8List> packets,
    int serial,
    int sequence, {
    bool bos = false,
  }) {
    // Each segment: (bytes, ends a packet).
    final segments = <(Uint8List, bool)>[];
    for (final packet in packets) {
      var o = 0;
      while (packet.length - o >= 255) {
        segments.add((Uint8List.sublistView(packet, o, o + 255), false));
        o += 255;
      }
      segments.add((Uint8List.sublistView(packet, o), true));
    }
    final pages = <Uint8List>[];
    var continued = false;
    for (var i = 0; i < segments.length; i += 255) {
      final chunk = segments.sublist(
        i,
        i + 255 > segments.length ? segments.length : i + 255,
      );
      final endsPacket = chunk.any((s) => s.$2);
      final page = BytesBuilder(copy: false)
        ..add("OggS".codeUnits)
        ..addByte(0)
        ..addByte((continued ? 1 : 0) | (bos && i == 0 ? 2 : 0))
        // Header pages have granule 0; -1 when no packet ends on the page.
        ..add(endsPacket ? Uint8List(8) : List.filled(8, 0xff))
        ..add(le32(serial))
        ..add(le32(sequence++))
        ..add(Uint8List(4))
        ..addByte(chunk.length)
        ..add([for (final s in chunk) s.$1.length]);
      for (final s in chunk) {
        page.add(s.$1);
      }
      final bytes = page.toBytes();
      _setCrc(bytes);
      pages.add(bytes);
      continued = !chunk.last.$2;
    }
    return pages;
  }

  static final List<int> _crcTable = List.generate(256, (i) {
    var r = i << 24;
    for (var j = 0; j < 8; j++) {
      r = r & 0x80000000 != 0 ? (r << 1) ^ 0x04c11db7 : r << 1;
    }
    return r & 0xffffffff;
  });

  /// Computes the page checksum (CRC-32, polynomial 0x04c11db7, no
  /// reflection) with the CRC field zeroed, and stores it.
  static void _setCrc(Uint8List page) {
    page.fillRange(22, 26, 0);
    var crc = 0;
    for (final byte in page) {
      crc = ((crc << 8) & 0xffffffff) ^ _crcTable[((crc >> 24) ^ byte) & 0xff];
    }
    page.setRange(22, 26, le32(crc));
  }

  /// Whether [page] has a valid checksum (for tests).
  static bool checksumValid(Uint8List page) {
    final copy = Uint8List.fromList(page);
    _setCrc(copy);
    return u32le(copy, 22) == u32le(page, 22);
  }
}
