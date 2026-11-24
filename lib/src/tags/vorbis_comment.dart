import "dart:convert";
import "dart:typed_data";

import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";

/// A Vorbis comment block (FLAC, Ogg Vorbis, Opus): a vendor string and
/// `NAME=value` pairs, kept in order so untouched ones are written back as
/// they were.
class VorbisComment {
  VorbisComment(this.vendor, this.comments, [Uint8List? trailing])
    : trailing = trailing ?? Uint8List(0);

  String vendor;
  final List<(String, String)> comments;

  /// Bytes after the comment list that must be kept (Opus allows binary
  /// data there).
  final Uint8List trailing;

  /// Parses the comment structure starting at [offset] of [data]; returns
  /// it and the offset just past the comment list.
  static (VorbisComment, int) parse(Uint8List data, [int offset = 0]) {
    var o = offset;
    int u32() {
      if (o + 4 > data.length) throw const FormatException("Truncated");
      final v = u32le(data, o);
      o += 4;
      return v;
    }

    String str() {
      final length = u32();
      if (o + length > data.length) throw const FormatException("Truncated");
      final s = decodeText(data.sublist(o, o + length));
      o += length;
      return s;
    }

    final vendor = str();
    final count = u32();
    final comments = <(String, String)>[];
    for (var i = 0; i < count; i++) {
      final comment = str();
      final eq = comment.indexOf("=");
      comments.add(
        eq < 0
            ? (comment, "")
            : (comment.substring(0, eq), comment.substring(eq + 1)),
      );
    }
    return (VorbisComment(vendor, comments), o);
  }

  /// The comment structure as bytes (without any packet prefix or framing
  /// bit), followed by [trailing].
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    void str(String s) {
      final bytes = utf8.encode(s);
      out
        ..add(le32(bytes.length))
        ..add(bytes);
    }

    str(vendor);
    out.add(le32(comments.length));
    for (final (name, value) in comments) {
      str("$name=$value");
    }
    out.add(trailing);
    return out.toBytes();
  }

  /// The values of [name] (case-insensitive).
  List<String> values(String name) {
    final upper = name.toUpperCase();
    return [
      for (final (n, v) in comments)
        if (n.toUpperCase() == upper) v,
    ];
  }

  /// The field names read for each Basic Info field, preferred first, and
  /// the one written (the first) — `TAG_ALIAS` and the fallbacks removed
  /// on write in in_vorbis/wa2.cpp and in_flac/ExtendedFileInfo.cpp.
  static const Map<TagField, List<String>> names = {
    TagField.title: ["TITLE"],
    TagField.artist: ["ARTIST"],
    TagField.album: ["ALBUM"],
    TagField.albumArtist: ["ALBUMARTIST", "ALBUM ARTIST", "ENSEMBLE"],
    TagField.year: ["DATE", "YEAR"],
    TagField.genre: ["GENRE"],
    TagField.comment: ["COMMENT", "DESCRIPTION"],
    TagField.composer: ["COMPOSER"],
    TagField.publisher: ["PUBLISHER", "ORGANIZATION"],
    TagField.disc: ["DISCNUMBER"],
    TagField.track: ["TRACKNUMBER", "TRACK"],
    TagField.bpm: ["BPM"],
    TagField.acoustIdFingerprint: ["ACOUSTID_FINGERPRINT"],
  };

  Map<TagField, String> get fields {
    final result = <TagField, String>{};
    for (final MapEntry(:key, value: keys) in names.entries) {
      for (final name in keys) {
        final found = values(name);
        if (found.isEmpty) continue;
        var value = found.join(key == TagField.comment ? "\n" : "; ");
        // TRACKNUMBER=3 with TRACKTOTAL=12 shows as 3/12, like ID3.
        if (key == TagField.track && !value.contains("/")) {
          final total = values("TRACKTOTAL") + values("TOTALTRACKS");
          if (total.isNotEmpty) value = "$value/${total.first}";
        }
        if (key == TagField.disc && !value.contains("/")) {
          final total = values("DISCTOTAL") + values("TOTALDISCS");
          if (total.isNotEmpty) value = "$value/${total.first}";
        }
        if (value.isNotEmpty) result[key] = value;
        break;
      }
    }
    return result;
  }

  List<TagEntry> get entries => [
    for (final (name, value) in comments)
      TagEntry(
        name,
        _pictureFields.contains(name.toUpperCase()) && value.length > 64
            ? "[${value.length} bytes, base64]"
            : value,
      ),
  ];

  static const String _blockPicture = "METADATA_BLOCK_PICTURE";

  /// The old unofficial way: base64 image data, with its MIME type in
  /// COVERARTMIME.
  static const Set<String> _pictureFields = {
    _blockPicture,
    "COVERART",
    "COVERARTMIME",
  };

  /// The pictures in `METADATA_BLOCK_PICTURE` fields (and the older
  /// `COVERART` ones), in order; unreadable ones are left out.
  List<EmbeddedPicture> get pictures {
    final coverArtMime = values("COVERARTMIME");
    var coverArt = 0;
    return [
      for (final (name, value) in comments)
        if (name.toUpperCase() == _blockPicture)
          ?_tryParse(() => EmbeddedPicture.fromFlacBlock(_base64(value)))
        else if (name.toUpperCase() == "COVERART")
          ?_tryParse(() {
            final data = _base64(value);
            final mime = coverArt < coverArtMime.length
                ? coverArtMime[coverArt]
                : "";
            coverArt++;
            return EmbeddedPicture(
              type: ArtworkType.frontCover,
              mimeType: mime.isNotEmpty ? mime : sniffImageMime(data) ?? "",
              data: data,
            );
          }),
    ];
  }

  static Uint8List _base64(String value) =>
      base64.decode(base64.normalize(value.replaceAll(RegExp(r"\s"), "")));

  static EmbeddedPicture? _tryParse(EmbeddedPicture Function() parse) {
    try {
      return parse();
    } on FormatException {
      return null;
    }
  }

  /// Replaces every picture field with `METADATA_BLOCK_PICTURE` fields for
  /// [pictures], where the first one was (or at the end).
  void setPictures(List<EmbeddedPicture> pictures) {
    final index = comments.indexWhere(
      (c) => _pictureFields.contains(c.$1.toUpperCase()),
    );
    comments.removeWhere((c) => _pictureFields.contains(c.$1.toUpperCase()));
    comments.insertAll(index < 0 ? comments.length : index, [
      for (final picture in pictures)
        (_blockPicture, base64.encode(picture.toFlacBlock())),
    ]);
  }

  /// Sets [field] to [value] (empty removes it), replacing every alias. The
  /// new entry takes the place of the first one it replaces and keeps that
  /// entry's spelling of the name. When the file keeps the total in its own
  /// field (TRACKTOTAL), "3/12" is split into both.
  void set(TagField field, String value) {
    final keys = names[field]!;
    final totals = switch (field) {
      TagField.track => const ["TRACKTOTAL", "TOTALTRACKS"],
      TagField.disc => const ["DISCTOTAL", "TOTALDISCS"],
      _ => const <String>[],
    };
    String? spelling;
    String? totalSpelling;
    var insertAt = -1;
    final kept = <(String, String)>[];
    for (final comment in comments) {
      final upper = comment.$1.toUpperCase();
      if (keys.contains(upper)) {
        if (spelling == null) {
          spelling = comment.$1;
          if (insertAt < 0) insertAt = kept.length;
        }
        continue;
      }
      if (totals.contains(upper)) {
        totalSpelling ??= comment.$1;
        continue;
      }
      kept.add(comment);
    }
    comments
      ..clear()
      ..addAll(kept);
    if (value.isEmpty) return;
    final at = insertAt < 0 ? comments.length : insertAt;
    final name = spelling ?? keys.first;
    final slash = value.indexOf("/");
    if (totalSpelling != null && slash >= 0) {
      comments.insert(at, (name, value.substring(0, slash).trim()));
      final total = value.substring(slash + 1).trim();
      if (total.isNotEmpty) comments.insert(at + 1, (totalSpelling, total));
    } else {
      comments.insert(at, (name, value));
    }
  }
}
