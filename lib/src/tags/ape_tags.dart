import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "id3v1.dart";
import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";

/// One item of an APE tag: a key and its value as stored.
class ApeItem {
  ApeItem(this.key, this.value, {this.flags = 0});

  /// A text item.
  factory ApeItem.text(String key, String text) =>
      ApeItem(key, Uint8List.fromList(utf8.encode(text)));

  final String key;
  final Uint8List value;

  /// The item flags: bit 0 read-only, bits 1-2 the kind (0 text, 1 binary,
  /// 2 a locator of external text).
  final int flags;

  bool get isBinary => (flags >> 1) & 3 == 1;
  bool get isText => (flags >> 1) & 3 != 1;

  /// A text item's value; several values are NUL-separated in the file and
  /// shown here joined by [separator].
  String text([String separator = "; "]) => [
    for (final part in _split(value))
      if (part.isNotEmpty) decodeText(part),
  ].join(separator);

  static List<List<int>> _split(Uint8List bytes) {
    final parts = <List<int>>[];
    var from = 0;
    for (var i = 0; i <= bytes.length; i++) {
      if (i == bytes.length || bytes[i] == 0) {
        parts.add(bytes.sublist(from, i));
        from = i + 1;
      }
    }
    return parts;
  }
}

/// An APEv1 or APEv2 tag, found at the end of an MP3, FLAC, Monkey's Audio,
/// Musepack, WavPack, TTA or TAK file (before an ID3v1 tag when there is
/// one).
class ApeTag {
  ApeTag(this.items, {this.version = 2000, this.start = 0, this.end = 0});

  /// A tag with nothing in it.
  ApeTag.empty() : this([]);

  final List<ApeItem> items;

  /// 1000 for APEv1, 2000 for APEv2.
  final int version;

  /// Where the tag lies in the file it was read from (header to footer).
  final int start;
  final int end;

  static const int _blockSize = 32;
  static const int _maxSize = 16 << 20;

  /// The name shown for the tag kind.
  String get name => version >= 2000 ? "APEv2" : "APEv1";

  /// Finds the APE tag that ends at [end] of the file open in [raf].
  static ApeTag? find(RandomAccessFile raf, int end) {
    if (end < _blockSize) return null;
    final footer = readAt(raf, end - _blockSize, _blockSize);
    if (footer.length < _blockSize || !hasAscii(footer, 0, "APETAGEX")) {
      return null;
    }
    final version = u32le(footer, 8);
    final size = u32le(footer, 12);
    final count = u32le(footer, 16);
    final flags = u32le(footer, 20);
    // Bit 29 marks a header (a tag at the start of the file).
    if (flags & 0x20000000 != 0) return null;
    final hasHeader = flags & 0x80000000 != 0;
    if (size < _blockSize || size > _maxSize) return null;
    final total = size + (hasHeader ? _blockSize : 0);
    final start = end - total;
    if (start < 0) return null;
    final body = readAt(
      raf,
      start + (hasHeader ? _blockSize : 0),
      size - _blockSize,
    );
    if (body.length < size - _blockSize) return null;
    if (hasHeader && !hasAscii(readAt(raf, start, 8), 0, "APETAGEX")) {
      return null;
    }
    final items = <ApeItem>[];
    var o = 0;
    for (var i = 0; i < count; i++) {
      if (o + 8 > body.length) break;
      final length = u32le(body, o);
      final itemFlags = u32le(body, o + 4);
      var keyEnd = o + 8;
      while (keyEnd < body.length && body[keyEnd] != 0) {
        keyEnd++;
      }
      if (keyEnd >= body.length) break;
      final valueStart = keyEnd + 1;
      if (valueStart + length > body.length) break;
      items.add(
        ApeItem(
          latin1.decode(body.sublist(o + 8, keyEnd), allowInvalid: true),
          Uint8List.fromList(body.sublist(valueStart, valueStart + length)),
          flags: itemFlags,
        ),
      );
      o = valueStart + length;
    }
    return ApeTag(items, version: version, start: start, end: end);
  }

  /// The APE tag of the file open in [raf], looking before an ID3v1 tag
  /// when the file ends in one.
  static ApeTag? read(RandomAccessFile raf) {
    final length = raf.lengthSync();
    var end = length;
    if (length >= Id3v1Tag.size &&
        hasAscii(readAt(raf, length - Id3v1Tag.size, 3), 0, "TAG")) {
      end = length - Id3v1Tag.size;
    }
    return find(raf, end);
  }

  /// The names read for each Basic Info field, the one written first.
  static const Map<TagField, List<String>> names = {
    TagField.title: ["Title"],
    TagField.artist: ["Artist"],
    TagField.album: ["Album"],
    TagField.albumArtist: ["Album Artist", "AlbumArtist"],
    TagField.year: ["Year", "Date"],
    TagField.genre: ["Genre"],
    TagField.comment: ["Comment", "Description"],
    TagField.composer: ["Composer"],
    TagField.publisher: ["Publisher", "Label"],
    TagField.disc: ["Disc", "DiscNumber"],
    TagField.track: ["Track", "TrackNumber"],
    TagField.bpm: ["BPM"],
    TagField.acoustIdFingerprint: ["ACOUSTID_FINGERPRINT"],
  };

  ApeItem? _item(String key) {
    final lower = key.toLowerCase();
    for (final item in items) {
      if (item.isText && item.key.toLowerCase() == lower) return item;
    }
    return null;
  }

  Map<TagField, String> get fields {
    final result = <TagField, String>{};
    for (final MapEntry(:key, value: keys) in names.entries) {
      for (final name in keys) {
        final value = _item(name)?.text(key == TagField.comment ? "\n" : "; ");
        if (value != null && value.isNotEmpty) {
          result[key] = value;
          break;
        }
      }
    }
    return result;
  }

  List<TagEntry> get entries => [
    for (final item in items)
      if (item.isBinary)
        TagEntry(
          item.key,
          _isCoverKey(item.key)
              ? "[picture, ${item.value.length} bytes]"
              : "[${item.value.length} bytes]",
        )
      else
        TagEntry(item.key, item.text()),
  ];

  /// Sets [field] to [value] (empty removes it), replacing every alias in
  /// the place of the first one and keeping that spelling of the name.
  void set(TagField field, String value) {
    final keys = [for (final k in names[field]!) k.toLowerCase()];
    String? spelling;
    var at = -1;
    final kept = <ApeItem>[];
    for (final item in items) {
      if (item.isText && keys.contains(item.key.toLowerCase())) {
        spelling ??= item.key;
        if (at < 0) at = kept.length;
        continue;
      }
      kept.add(item);
    }
    items
      ..clear()
      ..addAll(kept);
    if (value.isEmpty) return;
    items.insert(
      at < 0 ? items.length : at,
      ApeItem.text(spelling ?? names[field]!.first, value),
    );
  }

  static bool _isCoverKey(String key) =>
      key.toLowerCase().startsWith("cover art");

  static const Map<String, ArtworkType> _coverTypes = {
    "front": ArtworkType.frontCover,
    "back": ArtworkType.backCover,
    "leaflet": ArtworkType.leaflet,
    "media": ArtworkType.media,
    "artist": ArtworkType.artist,
    "band": ArtworkType.band,
    "other": ArtworkType.other,
  };

  static ArtworkType _typeOfKey(String key) {
    final open = key.indexOf("(");
    final close = key.lastIndexOf(")");
    if (open < 0 || close < open) return ArtworkType.frontCover;
    return _coverTypes[key.substring(open + 1, close).trim().toLowerCase()] ??
        ArtworkType.other;
  }

  static String _keyOfType(ArtworkType type) => switch (type) {
    ArtworkType.frontCover => "Cover Art (Front)",
    ArtworkType.backCover => "Cover Art (Back)",
    ArtworkType.leaflet => "Cover Art (Leaflet)",
    ArtworkType.media => "Cover Art (Media)",
    ArtworkType.artist => "Cover Art (Artist)",
    ArtworkType.band => "Cover Art (Band)",
    _ => "Cover Art (Other)",
  };

  /// The pictures in the `Cover Art (...)` items: a file name, a NUL, then
  /// the image.
  List<EmbeddedPicture> get pictures => [
    for (final item in items)
      if (item.isBinary && _isCoverKey(item.key) && item.value.contains(0))
        _picture(item),
  ];

  static EmbeddedPicture _picture(ApeItem item) {
    final nul = item.value.indexOf(0);
    final data = Uint8List.fromList(item.value.sublist(nul + 1));
    return EmbeddedPicture(
      type: _typeOfKey(item.key),
      mimeType: sniffImageMime(data) ?? "",
      description: decodeText(item.value.sublist(0, nul)),
      data: data,
    );
  }

  /// Replaces every cover item with ones for [pictures], where the first
  /// old one was (or at the end).
  void setPictures(List<EmbeddedPicture> pictures) {
    final at = items.indexWhere((i) => i.isBinary && _isCoverKey(i.key));
    items.removeWhere((i) => i.isBinary && _isCoverKey(i.key));
    items.insertAll(at < 0 ? items.length : at, [
      for (final picture in pictures)
        ApeItem(
          _keyOfType(picture.type),
          Uint8List.fromList([
            ...utf8.encode(
              picture.description.isNotEmpty
                  ? picture.description
                  : "cover.${_extension(picture)}",
            ),
            0,
            ...picture.data,
          ]),
          flags: 2,
        ),
    ]);
  }

  static String _extension(EmbeddedPicture picture) {
    final name = picture.formatName;
    return name == "jpeg" || name.isEmpty ? "jpg" : name;
  }

  /// The tag as APEv2 bytes, with header and footer.
  Uint8List toBytes() {
    final body = BytesBuilder(copy: false);
    for (final item in items) {
      body
        ..add(le32(item.value.length))
        ..add(le32(item.flags))
        ..add(latin1.encode(item.key))
        ..addByte(0)
        ..add(item.value);
    }
    final itemBytes = body.toBytes();
    Uint8List block(int flags) =>
        (BytesBuilder(copy: false)
              ..add("APETAGEX".codeUnits)
              ..add(le32(2000))
              ..add(le32(itemBytes.length + _blockSize))
              ..add(le32(items.length))
              ..add(le32(flags))
              ..add(Uint8List(8)))
            .toBytes();
    return (BytesBuilder(copy: false)
          ..add(block(0xa0000000))
          ..add(itemBytes)
          ..add(block(0x80000000)))
        .toBytes();
  }

  /// Applies [changes] (and [pictures], when given) to the APE tag of
  /// [file]. With [create], a file without a tag gets one; otherwise it is
  /// left as it is. A tag left without items is removed.
  static void update(
    File file,
    Map<TagField, String> changes, {
    required bool create,
    List<EmbeddedPicture>? pictures,
  }) {
    final raf = file.openSync();
    final ApeTag? existing;
    final int length;
    final bool hasV1;
    try {
      existing = read(raf);
      length = raf.lengthSync();
      hasV1 =
          length >= Id3v1Tag.size &&
          hasAscii(readAt(raf, length - Id3v1Tag.size, 3), 0, "TAG");
    } finally {
      raf.closeSync();
    }
    if (existing == null && !create) return;
    if (changes.isEmpty && pictures == null) return;
    final tag = existing ?? ApeTag.empty();
    changes.forEach(tag.set);
    if (pictures != null) tag.setPictures(pictures);
    final at = hasV1 ? length - Id3v1Tag.size : length;
    editFile(file, [
      (
        start: existing?.start ?? at,
        end: existing?.end ?? at,
        bytes: tag.items.isEmpty ? Uint8List(0) : tag.toBytes(),
      ),
    ]);
  }
}
