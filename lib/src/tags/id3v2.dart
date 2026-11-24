import "dart:convert";
import "dart:typed_data";

import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";

/// One ID3v2 frame as stored: its id, flags and data (after tag-level
/// unsynchronisation was undone).
class Id3Frame {
  Id3Frame(this.id, this.flags, this.data);

  final String id;
  final int flags;
  final Uint8List data;
}

/// An ID3v2 tag that can be edited field by field: frames that are not
/// edited are written back exactly as read (pictures, lyrics, private
/// frames, ReplayGain...).
class Id3v2Tag {
  Id3v2Tag._(this.version, this.frames, this.originalSize);

  /// A new, empty ID3v2.3 tag (what the classic player's in_mp3 writes).
  Id3v2Tag.empty() : version = 3, frames = [], originalSize = 0;

  /// The major version: 3 or 4 (a v2.2 tag is converted to 2.3 on read).
  final int version;

  final List<Id3Frame> frames;

  /// The size the tag took in the file, header and footer included, or 0.
  final int originalSize;

  /// Whether [bytes] start with an ID3v2 tag header.
  static bool isAt(List<int> bytes, int offset) =>
      bytes.length >= offset + 10 &&
      hasAscii(bytes, offset, "ID3") &&
      bytes[offset + 3] < 0xff &&
      bytes[offset + 6] & 0x80 == 0 &&
      bytes[offset + 7] & 0x80 == 0 &&
      bytes[offset + 8] & 0x80 == 0 &&
      bytes[offset + 9] & 0x80 == 0;

  /// The total size of the tag whose 10-byte header is [header].
  static int sizeFromHeader(List<int> header) =>
      10 +
      syncSafe(header, 6) +
      (header[3] == 4 && header[5] & 0x10 != 0 ? 10 : 0);

  /// Parses the tag at the start of [bytes] (which hold at least the whole
  /// tag).
  factory Id3v2Tag.parse(Uint8List bytes) {
    if (!isAt(bytes, 0)) throw const FormatException("No ID3v2 tag");
    final major = bytes[3];
    final flags = bytes[5];
    final total = sizeFromHeader(bytes);
    if (total > bytes.length) throw const FormatException("Truncated ID3v2");
    var body = Uint8List.sublistView(bytes, 10, 10 + syncSafe(bytes, 6));
    // v2.2 and v2.3 unsynchronise the whole tag; v2.4 does it per frame.
    if (flags & 0x80 != 0 && major < 4) body = _resync(body);
    var o = 0;
    if (flags & 0x40 != 0 && major >= 3 && body.length >= 4) {
      o = major == 3 ? 4 + u32be(body, 0) : syncSafe(body, 0);
    }
    final frames = <Id3Frame>[];
    if (major == 2) {
      while (o + 6 <= body.length && body[o] != 0) {
        final id = String.fromCharCodes(body.sublist(o, o + 3));
        final size = u24be(body, o + 3);
        if (o + 6 + size > body.length) break;
        final frame = _fromV22(
          id,
          Uint8List.fromList(body.sublist(o + 6, o + 6 + size)),
        );
        if (frame != null) frames.add(frame);
        o += 6 + size;
      }
      return Id3v2Tag._(3, frames, total);
    }
    while (o + 10 <= body.length && body[o] != 0) {
      final id = String.fromCharCodes(body.sublist(o, o + 4));
      if (!_validId(id)) break;
      var size = major == 4 ? syncSafe(body, o + 4) : u32be(body, o + 4);
      // Some writers (old iTunes) put plain sizes in v2.4 tags.
      if (major == 4 && !_frameEndsWell(body, o + 10 + size)) {
        final plain = u32be(body, o + 4);
        if (_frameEndsWell(body, o + 10 + plain)) size = plain;
      }
      if (o + 10 + size > body.length) break;
      frames.add(
        Id3Frame(
          id,
          u16be(body, o + 8),
          Uint8List.fromList(body.sublist(o + 10, o + 10 + size)),
        ),
      );
      o += 10 + size;
    }
    return Id3v2Tag._(major == 4 ? 4 : 3, frames, total);
  }

  static bool _validId(String id) => RegExp(r"^[A-Z0-9]{4}$").hasMatch(id);

  /// Whether a frame ending at [end] is followed by the end, padding or
  /// another frame header.
  static bool _frameEndsWell(Uint8List body, int end) {
    if (end == body.length) return true;
    if (end > body.length) return false;
    if (body[end] == 0) return true;
    return end + 4 <= body.length &&
        _validId(String.fromCharCodes(body.sublist(end, end + 4)));
  }

  static Uint8List _resync(Uint8List data) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i++) {
      out.addByte(data[i]);
      if (data[i] == 0xff && i + 1 < data.length && data[i + 1] == 0) i++;
    }
    return out.toBytes();
  }

  static const Map<String, String> _v22Ids = {
    "TT1": "TIT1",
    "TT2": "TIT2",
    "TT3": "TIT3",
    "TP1": "TPE1",
    "TP2": "TPE2",
    "TP3": "TPE3",
    "TP4": "TPE4",
    "TCM": "TCOM",
    "TXT": "TEXT",
    "TAL": "TALB",
    "TYE": "TYER",
    "TCO": "TCON",
    "TRK": "TRCK",
    "TPA": "TPOS",
    "TBP": "TBPM",
    "TPB": "TPUB",
    "TCR": "TCOP",
    "TEN": "TENC",
    "TSS": "TSSE",
    "TOA": "TOPE",
    "TOT": "TOAL",
    "TRC": "TSRC",
    "TLA": "TLAN",
    "TLE": "TLEN",
    "TKE": "TKEY",
    "TDA": "TDAT",
    "TIM": "TIME",
    "TXX": "TXXX",
    "COM": "COMM",
    "ULT": "USLT",
    "WXX": "WXXX",
    "CNT": "PCNT",
    "POP": "POPM",
    "UFI": "UFID",
  };

  /// A v2.2 frame as its v2.3 equivalent, or null when it has none.
  static Id3Frame? _fromV22(String id, Uint8List data) {
    if (id == "PIC" && data.length >= 5) {
      // Encoding, 3-character image format -> MIME type string.
      final format = String.fromCharCodes(data.sublist(1, 4)).toUpperCase();
      final mime = format == "PNG" ? "image/png" : "image/jpeg";
      return Id3Frame(
        "APIC",
        0,
        Uint8List.fromList([
          data[0],
          ...latin1.encode(mime),
          0,
          ...data.sublist(4),
        ]),
      );
    }
    final mapped = _v22Ids[id];
    return mapped == null ? null : Id3Frame(mapped, 0, data);
  }

  // --- Reading ---------------------------------------------------------------

  /// The frame's payload with frame-level extras (grouping byte, data
  /// length, unsynchronisation) removed; null when compressed or
  /// encrypted.
  Uint8List? _payload(Id3Frame frame) {
    var data = frame.data;
    if (version == 4) {
      if (frame.flags & 0x000c != 0) return null;
      var o = 0;
      if (frame.flags & 0x0040 != 0) o += 1;
      if (frame.flags & 0x0001 != 0) o += 4;
      if (o > data.length) return null;
      data = Uint8List.sublistView(data, o);
      if (frame.flags & 0x0002 != 0) data = _resync(data);
    } else {
      if (frame.flags & 0x00c0 != 0) return null;
      if (frame.flags & 0x0020 != 0) {
        if (data.isEmpty) return null;
        data = Uint8List.sublistView(data, 1);
      }
    }
    return data;
  }

  /// Decodes [data] in ID3 text encoding [encoding], splitting at NULs.
  static List<String> _decodeStrings(int encoding, List<int> data) {
    final String text;
    switch (encoding) {
      case 1:
      case 2:
        text = _decodeUtf16(data, bigEndian: encoding == 2);
      case 3:
        text = decodeText(data);
      default:
        text = latin1.decode(data);
    }
    final parts = text.split("\u0000");
    while (parts.length > 1 && parts.last.isEmpty) {
      parts.removeLast();
    }
    return parts;
  }

  static String _decodeUtf16(List<int> data, {required bool bigEndian}) {
    final units = <int>[];
    var be = bigEndian;
    for (var i = 0; i + 1 < data.length; i += 2) {
      final unit = be ? data[i] << 8 | data[i + 1] : data[i + 1] << 8 | data[i];
      if (unit == 0xfeff) continue;
      if (unit == 0xfffe) {
        be = !be;
        continue;
      }
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  /// Splits [data] at the first terminator for [encoding]: the string
  /// before it and the offset after it.
  static (String, int) _terminated(int encoding, List<int> data, int start) {
    final wide = encoding == 1 || encoding == 2;
    var i = start;
    while (wide ? i + 1 < data.length : i < data.length) {
      if (wide ? data[i] == 0 && data[i + 1] == 0 : data[i] == 0) {
        final text = _decodeStrings(encoding, data.sublist(start, i));
        return (text.isEmpty ? "" : text.first, i + (wide ? 2 : 1));
      }
      i += wide ? 2 : 1;
    }
    final text = _decodeStrings(encoding, data.sublist(start));
    return (text.isEmpty ? "" : text.first, data.length);
  }

  /// The text of the first [id] frame, values joined with "; ".
  String? text(String id) {
    for (final frame in frames) {
      if (frame.id != id) continue;
      final data = _payload(frame);
      if (data == null || data.isEmpty) continue;
      final values = _decodeStrings(data[0], data.sublist(1));
      return values.join("; ");
    }
    return null;
  }

  /// The value of the first TXXX frame described as [description]
  /// (case-insensitively).
  String? userText(String description) {
    for (final frame in frames) {
      if (frame.id != "TXXX") continue;
      final data = _payload(frame);
      if (data == null || data.isEmpty) continue;
      final (desc, o) = _terminated(data[0], data, 1);
      if (desc.toLowerCase() != description.toLowerCase()) continue;
      return _decodeStrings(data[0], data.sublist(o)).join("; ");
    }
    return null;
  }

  /// The COMM frames as (description, text, frame).
  Iterable<(String, String, Id3Frame)> _comments() sync* {
    for (final frame in frames) {
      if (frame.id != "COMM") continue;
      final data = _payload(frame);
      if (data == null || data.length < 4) continue;
      final (desc, o) = _terminated(data[0], data, 4);
      yield (desc, _decodeStrings(data[0], data.sublist(o)).join("\n"), frame);
    }
  }

  /// The comment the classic player shows: the one without a description, else the
  /// first that isn't iTunes bookkeeping.
  (String, Id3Frame)? _comment() {
    (String, Id3Frame)? fallback;
    for (final (desc, text, frame) in _comments()) {
      if (desc.isEmpty) return (text, frame);
      if (!desc.startsWith("iTun")) fallback ??= (text, frame);
    }
    return fallback;
  }

  static String _genreName(String raw) {
    // "(17)", "(17)Rock", "17", or a name.
    final match = RegExp(r"^\((\d+)\)(.*)$").firstMatch(raw);
    if (match != null) {
      if (match.group(2)!.isNotEmpty) return match.group(2)!;
      final index = int.parse(match.group(1)!);
      return index < id3Genres.length ? id3Genres[index] : raw;
    }
    final index = int.tryParse(raw);
    if (index != null && index < id3Genres.length) return id3Genres[index];
    return raw;
  }

  /// The Basic Info fields this tag has.
  Map<TagField, String> get fields {
    final result = <TagField, String>{};
    void put(TagField field, String? value) {
      if (value != null && value.isNotEmpty) result[field] = value;
    }

    put(TagField.title, text("TIT2"));
    put(TagField.artist, text("TPE1"));
    put(TagField.album, text("TALB"));
    put(
      TagField.albumArtist,
      text("TPE2") ?? userText("ALBUM ARTIST") ?? userText("ALBUMARTIST"),
    );
    final year = version == 4
        ? text("TDRC") ?? text("TYER")
        : text("TYER") ?? text("TDRC");
    put(TagField.year, year);
    final genre = text("TCON");
    if (genre != null) {
      put(TagField.genre, genre.split("; ").map(_genreName).join("; "));
    }
    put(TagField.comment, _comment()?.$1);
    put(TagField.composer, text("TCOM"));
    put(TagField.publisher, text("TPUB"));
    put(TagField.disc, text("TPOS"));
    put(TagField.track, text("TRCK"));
    put(TagField.bpm, text("TBPM"));
    put(TagField.acoustIdFingerprint, userText(acoustIdFingerprintFrame));
    return result;
  }

  /// Every frame, decoded for display.
  List<TagEntry> get entries => [
    for (final frame in frames) TagEntry(frame.id, _describe(frame)),
  ];

  String _describe(Id3Frame frame) {
    final data = _payload(frame);
    if (data == null) return "[${frame.data.length} bytes, compressed]";
    if (data.isEmpty) return "";
    final id = frame.id;
    final encoding = data[0];
    if (id == "TXXX" || id == "WXXX") {
      final (desc, o) = _terminated(encoding, data, 1);
      final value = id == "WXXX"
          ? latin1.decode(data.sublist(o), allowInvalid: true)
          : _decodeStrings(encoding, data.sublist(o)).join("; ");
      return "$desc: ${trimNuls(value)}";
    }
    if (id.startsWith("T")) {
      return _decodeStrings(encoding, data.sublist(1)).join("; ");
    }
    if (id.startsWith("W")) {
      return trimNuls(latin1.decode(data, allowInvalid: true));
    }
    if ((id == "COMM" || id == "USLT") && data.length >= 4) {
      final (desc, o) = _terminated(encoding, data, 4);
      final value = _decodeStrings(encoding, data.sublist(o)).join("\n");
      return desc.isEmpty ? value : "$desc: $value";
    }
    if (id == "APIC") {
      final (mime, _) = _terminated(0, data, 1);
      return "[$mime, ${data.length} bytes]";
    }
    return "[${data.length} bytes]";
  }

  /// The `APIC` frames' pictures, in file order.
  List<EmbeddedPicture> get pictures => [
    for (final frame in frames)
      if (frame.id == "APIC") ?_picture(frame),
  ];

  EmbeddedPicture? _picture(Id3Frame frame) {
    final data = _payload(frame);
    if (data == null || data.length < 4) return null;
    final encoding = data[0];
    final (mime, typeAt) = _terminated(0, data, 1);
    if (typeAt >= data.length) return null;
    final (description, dataAt) = _terminated(encoding, data, typeAt + 1);
    return EmbeddedPicture(
      type: ArtworkType.fromCode(data[typeAt]),
      // v2.2 "JPG" (converted on read) and bare "jpeg" both happen.
      mimeType: mime.isEmpty || mime.contains("/")
          ? mime
          : "image/${mime.toLowerCase()}",
      description: description,
      data: Uint8List.fromList(data.sublist(dataAt)),
    );
  }

  /// Replaces every `APIC` frame with [pictures], where the first one was
  /// (or at the end).
  void setPictures(List<EmbeddedPicture> pictures) {
    final index = frames.indexWhere((f) => f.id == "APIC");
    _removeAll("APIC");
    frames.insertAll(index < 0 ? frames.length : index, [
      for (final picture in pictures)
        () {
          final (encoding, description) = _encode(picture.description);
          final wide = encoding == 1 || encoding == 2;
          return Id3Frame(
            "APIC",
            0,
            Uint8List.fromList([
              encoding,
              ...latin1.encode(
                picture.mimeType.isEmpty ? "image/" : picture.mimeType,
              ),
              0,
              picture.type.code,
              // An empty description needs no BOM.
              ...(picture.description.isEmpty ? <int>[] : description),
              ...(wide ? [0, 0] : [0]),
              ...picture.data,
            ]),
          );
        }(),
    ]);
  }

  // --- Editing ---------------------------------------------------------------

  /// Sets [field] to [value]; an empty value removes it.
  void set(TagField field, String value) {
    switch (field) {
      case TagField.title:
        _setText("TIT2", value);
      case TagField.artist:
        _setText("TPE1", value);
      case TagField.album:
        _setText("TALB", value);
      case TagField.albumArtist:
        _setText("TPE2", value);
        _removeUserText("ALBUM ARTIST");
        _removeUserText("ALBUMARTIST");
      case TagField.year:
        if (version == 4) {
          _setText("TDRC", value);
          _removeAll("TYER");
        } else {
          _setText("TYER", value);
          _removeAll("TDRC");
        }
      case TagField.genre:
        _setText("TCON", value);
      case TagField.comment:
        _setComment(value);
      case TagField.composer:
        _setText("TCOM", value);
      case TagField.publisher:
        _setText("TPUB", value);
      case TagField.disc:
        _setText("TPOS", value);
      case TagField.track:
        _setText("TRCK", value);
      case TagField.bpm:
        _setText("TBPM", value);
      case TagField.acoustIdFingerprint:
        _setUserText(acoustIdFingerprintFrame, value);
    }
  }

  /// The TXXX description Picard stores the fingerprint under.
  static const String acoustIdFingerprintFrame = "Acoustid Fingerprint";

  /// Replaces the TXXX frame described as [description] in place, or
  /// appends one; an empty value removes it. For ASCII values (UTF-16 would
  /// need a second BOM after the separator).
  void _setUserText(String description, String value) {
    final lower = description.toLowerCase();
    bool matches(Id3Frame frame) {
      if (frame.id != "TXXX") return false;
      final data = _payload(frame);
      if (data == null || data.isEmpty) return false;
      return _terminated(data[0], data, 1).$1.toLowerCase() == lower;
    }

    final index = frames.indexWhere(matches);
    frames.removeWhere(matches);
    if (value.isEmpty) return;
    final (encoding, bytes) = _encode("$description\u0000$value");
    final frame = Id3Frame("TXXX", 0, Uint8List.fromList([encoding, ...bytes]));
    frames.insert(index < 0 ? frames.length : index, frame);
  }

  void _removeAll(String id) => frames.removeWhere((f) => f.id == id);

  void _removeUserText(String description) {
    final lower = description.toLowerCase();
    frames.removeWhere((frame) {
      if (frame.id != "TXXX") return false;
      final data = _payload(frame);
      if (data == null || data.isEmpty) return false;
      return _terminated(data[0], data, 1).$1.toLowerCase() == lower;
    });
  }

  /// Replaces the first [id] frame in place (keeping frame order), or
  /// appends one.
  void _setText(String id, String value) {
    final index = frames.indexWhere((f) => f.id == id);
    frames.removeWhere((f) => f.id == id);
    if (value.isEmpty) return;
    final (encoding, bytes) = _encode(value);
    final frame = Id3Frame(id, 0, Uint8List.fromList([encoding, ...bytes]));
    frames.insert(index < 0 ? frames.length : index, frame);
  }

  void _setComment(String value) {
    final current = _comment()?.$2;
    final index = current == null ? -1 : frames.indexOf(current);
    frames.removeWhere((frame) {
      if (identical(frame, current)) return true;
      if (frame.id != "COMM") return false;
      final data = _payload(frame);
      return data != null &&
          data.length >= 4 &&
          _terminated(data[0], data, 4).$1.isEmpty;
    });
    if (value.isEmpty) return;
    final (encoding, bytes) = _encode(value);
    final frame = Id3Frame(
      "COMM",
      0,
      Uint8List.fromList([
        encoding,
        ...ascii.encode("eng"),
        ...(encoding == 1 ? [0xff, 0xfe, 0, 0] : [0]),
        ...bytes,
      ]),
    );
    frames.insert(
      index < 0 || index > frames.length ? frames.length : index,
      frame,
    );
  }

  /// [value] in this version's text encoding: UTF-8 in v2.4; Latin-1 or,
  /// when it doesn't fit, UTF-16 with a BOM in v2.3.
  (int, List<int>) _encode(String value) {
    if (version == 4) return (3, utf8.encode(value));
    if (value.codeUnits.every((c) => c < 0x100)) {
      return (0, latin1.encode(value));
    }
    final out = <int>[0xff, 0xfe];
    for (final unit in value.codeUnits) {
      out
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    return (1, out);
  }

  // --- Writing ---------------------------------------------------------------

  /// The tag as bytes. When the frames fit in [fitTo] bytes the tag is
  /// padded to exactly that size (so it can be written in place); otherwise
  /// it gets [padding] bytes of padding.
  Uint8List toBytes({int fitTo = 0, int padding = 1024}) {
    final body = BytesBuilder(copy: false);
    for (final frame in frames) {
      body
        ..add(latin1.encode(frame.id))
        ..add(
          version == 4
              ? syncSafeBytes(frame.data.length)
              : be32(frame.data.length),
        )
        ..add([frame.flags >> 8, frame.flags & 0xff])
        ..add(frame.data);
    }
    var size = body.length;
    if (fitTo >= 10 && size <= fitTo - 10) {
      size = fitTo - 10;
    } else {
      size += padding;
    }
    final out = BytesBuilder(copy: false)
      ..add([0x49, 0x44, 0x33, version, 0, 0])
      ..add(syncSafeBytes(size))
      ..add(body.takeBytes());
    final missing = 10 + size - out.length;
    if (missing > 0) out.add(Uint8List(missing));
    return out.toBytes();
  }
}
