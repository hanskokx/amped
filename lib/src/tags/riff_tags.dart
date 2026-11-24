import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "id3v2.dart";
import "picture.dart";
import "tag_bytes.dart";
import "tag_model.dart";

/// The tags of a WAV file: the `LIST`/`INFO` chunk, and an `id3 ` chunk
/// when there is one.
class RiffTags {
  RiffTags._(
    this._infoChunk,
    this.info,
    this._id3Chunk,
    this.id3,
    this._length,
  );

  /// The offset and total size (header included) of the LIST/INFO chunk.
  final (int, int)? _infoChunk;

  /// The INFO items as (id, value), in file order.
  final List<(String, String)> info;

  final (int, int)? _id3Chunk;
  final Id3v2Tag? id3;

  /// The RIFF size the file claims, plus 8.
  final int _length;

  /// The INFO ids of the Basic Info fields (the ones libsndfile, which
  /// The classic player's in_wave uses, maps), preferred first.
  static const Map<TagField, List<String>> ids = {
    TagField.title: ["INAM"],
    TagField.artist: ["IART"],
    TagField.album: ["IPRD"],
    TagField.year: ["ICRD"],
    TagField.genre: ["IGNR"],
    TagField.comment: ["ICMT"],
    TagField.track: ["ITRK", "IPRT"],
  };

  /// Reads the chunk list of the WAV file open in [raf].
  factory RiffTags.read(RandomAccessFile raf) {
    final head = readAt(raf, 0, 12);
    if (!hasAscii(head, 0, "RIFF") || !hasAscii(head, 8, "WAVE")) {
      throw const FormatException("Not a WAV file");
    }
    final fileLength = raf.lengthSync();
    (int, int)? infoChunk;
    final info = <(String, String)>[];
    (int, int)? id3Chunk;
    Id3v2Tag? id3;
    var o = 12;
    while (o + 8 <= fileLength) {
      final header = readAt(raf, o, 12);
      final id = String.fromCharCodes(header.sublist(0, 4));
      final size = u32le(header, 4);
      final total = 8 + size + (size & 1);
      if (id == "LIST" && header.length >= 12 && hasAscii(header, 8, "INFO")) {
        infoChunk = (o, total);
        final data = readAt(raf, o + 12, size - 4);
        var p = 0;
        while (p + 8 <= data.length) {
          final itemId = String.fromCharCodes(data.sublist(p, p + 4));
          final itemSize = u32le(data, p + 4);
          final end = p + 8 + itemSize > data.length
              ? data.length
              : p + 8 + itemSize;
          info.add((
            itemId,
            trimNuls(decodeText(data.sublist(p + 8, end))).trim(),
          ));
          p = end + (itemSize & 1);
        }
      } else if (id == "id3 " || id == "ID3 ") {
        final data = readAt(raf, o + 8, size);
        if (Id3v2Tag.isAt(data, 0)) {
          id3Chunk = (o, total);
          id3 = Id3v2Tag.parse(data);
        }
      }
      o += total;
    }
    return RiffTags._(infoChunk, info, id3Chunk, id3, u32le(head, 4) + 8);
  }

  Map<TagField, String> get fields {
    final result = <TagField, String>{...?id3?.fields};
    for (final MapEntry(:key, value: names) in ids.entries) {
      for (final name in names) {
        final value = [
          for (final (id, v) in info)
            if (id == name) v,
        ].firstOrNull;
        if (value != null && value.isNotEmpty) {
          result.putIfAbsent(key, () => value);
          break;
        }
      }
    }
    return result;
  }

  List<TagEntry> get entries => [
    for (final (id, value) in info) TagEntry(id, value),
    ...?id3?.entries.map((e) => TagEntry("ID3 ${e.name}", e.value)),
  ];

  /// The fields that can be written: the INFO ones, or all with an ID3
  /// chunk.
  Set<TagField> get editable =>
      id3 != null ? TagField.values.toSet() : ids.keys.toSet();

  /// Applies [changes] to [file] and, when given, replaces its pictures
  /// with [pictures] (in the ID3 chunk, which is added when missing).
  static void write(
    File file,
    Map<TagField, String> changes, {
    List<EmbeddedPicture>? pictures,
  }) {
    final raf = file.openSync();
    final RiffTags tags;
    final int fileLength;
    try {
      tags = RiffTags.read(raf);
      fileLength = raf.lengthSync();
    } finally {
      raf.closeSync();
    }
    final edits = <FileEdit>[];
    var growth = 0;
    // New chunks, added at the end.
    final appended = BytesBuilder(copy: false);
    final infoChanges = {
      for (final MapEntry(:key, :value) in changes.entries)
        if (ids.containsKey(key)) key: value,
    };
    if (infoChanges.isNotEmpty) {
      final info = [...tags.info];
      infoChanges.forEach((field, value) {
        final names = ids[field]!;
        final index = info.indexWhere((item) => names.contains(item.$1));
        final name = index < 0 ? names.first : info[index].$1;
        info.removeWhere((item) => names.contains(item.$1));
        if (value.isNotEmpty) {
          info.insert(index < 0 || index > info.length ? info.length : index, (
            name,
            value,
          ));
        }
      });
      final chunk = _infoChunkBytes(info);
      if (tags._infoChunk case (final start, final size)) {
        edits.add((start: start, end: start + size, bytes: chunk));
        growth += chunk.length - size;
      } else if (info.isNotEmpty) {
        appended.add(chunk);
      }
    }
    var id3 = tags.id3;
    // A file without an ID3 chunk gets one for its pictures (INFO has no
    // place for them).
    if (id3 == null && pictures != null && pictures.isNotEmpty) {
      id3 = Id3v2Tag.empty();
    }
    if (id3 != null) {
      if (tags.id3 != null) changes.forEach(id3.set);
      if (pictures != null) id3.setPictures(pictures);
      final (start, size) = tags._id3Chunk ?? (-1, 0);
      final tag = id3.toBytes(fitTo: size - 8);
      final chunk = BytesBuilder(copy: false)
        ..add("id3 ".codeUnits)
        ..add(le32(tag.length))
        ..add(tag);
      if (tag.length.isOdd) chunk.addByte(0);
      final bytes = chunk.toBytes();
      if (start < 0) {
        appended.add(bytes);
      } else {
        edits.add((start: start, end: start + size, bytes: bytes));
        growth += bytes.length - size;
      }
    }
    if (appended.isNotEmpty) {
      // An odd-length file gets the pad byte its last chunk lacked.
      final bytes = [if (fileLength.isOdd) 0, ...appended.takeBytes()];
      edits.add((start: fileLength, end: fileLength, bytes: bytes));
      growth += bytes.length;
    }
    if (edits.isEmpty) return;
    if (growth != 0) {
      edits.add((start: 4, end: 8, bytes: le32(tags._length - 8 + growth)));
    }
    editFile(file, edits);
  }

  static Uint8List _infoChunkBytes(List<(String, String)> info) {
    final body = BytesBuilder(copy: false)..add("INFO".codeUnits);
    for (final (id, value) in info) {
      final text = [...utf8.encode(value), 0];
      body
        ..add(latin1.encode(id))
        ..add(le32(text.length))
        ..add(text);
      if (text.length.isOdd) body.addByte(0);
    }
    final data = body.toBytes();
    return Uint8List.fromList([
      ..."LIST".codeUnits,
      ...le32(data.length),
      ...data,
    ]);
  }
}
