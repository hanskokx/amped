import "dart:convert";
import "dart:typed_data";

import "tag_bytes.dart";
import "tag_model.dart";

/// The 128-byte ID3v1(.1) tag at the end of an MP3 file.
class Id3v1Tag {
  Id3v1Tag._(this.bytes);

  /// The tag's 128 bytes, starting with "TAG".
  final Uint8List bytes;

  static const int size = 128;

  /// A tag with nothing in it.
  factory Id3v1Tag.empty() {
    final bytes = Uint8List(size)
      ..[0] = 0x54
      ..[1] = 0x41
      ..[2] = 0x47
      ..[127] = 0xff;
    return Id3v1Tag._(bytes);
  }

  /// Parses the last 128 bytes of a file, or returns null when they are not
  /// an ID3v1 tag.
  static Id3v1Tag? parse(Uint8List last128) {
    if (last128.length != size || !hasAscii(last128, 0, "TAG")) return null;
    return Id3v1Tag._(Uint8List.fromList(last128));
  }

  String _string(int offset, int length) => trimNuls(
    latin1.decode(bytes.sublist(offset, offset + length)),
  ).trimRight();

  /// Whether this is ID3v1.1 (a track number in the last comment byte).
  bool get _hasTrack => bytes[125] == 0 && bytes[126] != 0;

  Map<TagField, String> get fields {
    final result = <TagField, String>{};
    void put(TagField field, String value) {
      if (value.isNotEmpty) result[field] = value;
    }

    put(TagField.title, _string(3, 30));
    put(TagField.artist, _string(33, 30));
    put(TagField.album, _string(63, 30));
    put(TagField.year, _string(93, 4));
    put(TagField.comment, _string(97, _hasTrack ? 28 : 30));
    if (_hasTrack) put(TagField.track, "${bytes[126]}");
    final genre = bytes[127];
    if (genre < id3Genres.length) put(TagField.genre, id3Genres[genre]);
    return result;
  }

  List<TagEntry> get entries => [
    for (final MapEntry(:key, :value) in fields.entries)
      TagEntry("ID3v1 ${key.name}", value),
  ];

  /// The fields ID3v1 can hold.
  static const Set<TagField> supported = {
    TagField.title,
    TagField.artist,
    TagField.album,
    TagField.year,
    TagField.comment,
    TagField.track,
    TagField.genre,
  };

  void _put(int offset, int length, String value) {
    final encoded = [
      for (final unit in value.codeUnits) unit < 0x100 ? unit : 0x3f,
    ];
    for (var i = 0; i < length; i++) {
      bytes[offset + i] = i < encoded.length ? encoded[i] : 0;
    }
  }

  /// Sets [field]; fields ID3v1 can't hold are ignored.
  void set(TagField field, String value) {
    switch (field) {
      case TagField.title:
        _put(3, 30, value);
      case TagField.artist:
        _put(33, 30, value);
      case TagField.album:
        _put(63, 30, value);
      case TagField.year:
        _put(93, 4, value);
      case TagField.comment:
        final track = _hasTrack ? bytes[126] : 0;
        _put(97, track != 0 ? 28 : 30, value);
        if (track != 0) {
          bytes[125] = 0;
          bytes[126] = track;
        }
      case TagField.track:
        final track = int.tryParse(value.split("/").first.trim()) ?? 0;
        if (track > 0 && track < 256) {
          bytes[125] = 0;
          bytes[126] = track;
        } else if (_hasTrack) {
          bytes[126] = 0;
        }
      case TagField.genre:
        final index = id3Genres.indexWhere(
          (g) => g.toLowerCase() == value.trim().toLowerCase(),
        );
        if (index >= 0) {
          bytes[127] = index;
        } else if (value.trim().isEmpty) {
          bytes[127] = 0xff;
        }
      case TagField.disc ||
          TagField.bpm ||
          TagField.albumArtist ||
          TagField.composer ||
          TagField.publisher ||
          TagField.acoustIdFingerprint:
        break;
    }
  }
}
