import "dart:io";
import "dart:isolate";
import "dart:typed_data";

import "package:audio_metadata_reader/audio_metadata_reader.dart";

import "../player/playlist.dart" show readChannelCount, readFlacStreamInfo;
import "ape_tags.dart";
import "flac_tags.dart";
import "id3v1.dart";
import "id3v2.dart";
import "ogg_tags.dart";
import "picture.dart";
import "riff_tags.dart";
import "tag_bytes.dart";
import "tag_model.dart";

export "multi_tags.dart";
export "picture.dart";
export "tag_model.dart";

/// Tells the container format of the file at [path] from its first bytes.
TagFormat detectFormat(String path) {
  final Uint8List head;
  try {
    final raf = File(path).openSync();
    try {
      head = readAt(raf, 0, 12);
      if (Id3v2Tag.isAt(head, 0)) {
        // FLAC with a leading ID3v2 tag, or (usually) MP3.
        final after = readAt(raf, Id3v2Tag.sizeFromHeader(head), 4);
        if (hasAscii(after, 0, "fLaC")) return TagFormat.flac;
        return _isApeTaggedHead(after, path)
            ? TagFormat.apeTagged
            : TagFormat.mp3;
      }
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return TagFormat.unknown;
  }
  if (hasAscii(head, 0, "fLaC")) return TagFormat.flac;
  if (hasAscii(head, 0, "RIFF") && hasAscii(head, 8, "WAVE")) {
    return TagFormat.wav;
  }
  if (hasAscii(head, 0, "OggS")) {
    final raf = File(path).openSync();
    try {
      final page = readAt(raf, 0, 27 + 255 + 16);
      final body = 27 + (page.length > 26 ? page[26] : 0);
      if (hasAscii(page, body, "OpusHead")) return TagFormat.oggOpus;
      if (hasAscii(page, body + 1, "vorbis")) return TagFormat.oggVorbis;
      if (hasAscii(page, body, "Speex   ")) return TagFormat.oggSpeex;
      if (page.length > body &&
          page[body] == 0x7f &&
          hasAscii(page, body + 1, "FLAC")) {
        return TagFormat.oggFlac;
      }
    } finally {
      raf.closeSync();
    }
    return TagFormat.unknown;
  }
  if (_isApeTaggedHead(head, path)) return TagFormat.apeTagged;
  // MPEG audio frame sync, or a .mp3 without a recognisable start.
  if (head.length >= 2 && head[0] == 0xff && head[1] & 0xe0 == 0xe0) {
    return TagFormat.mp3;
  }
  return path.toLowerCase().endsWith(".mp3")
      ? TagFormat.mp3
      : TagFormat.unknown;
}

const List<String> _apeTaggedExtensions = [
  ".ape",
  ".mac",
  ".mpc",
  ".mp+",
  ".mpp",
  ".wv",
  ".tak",
  ".tta",
  ".ofr",
  ".ofs",
];

/// Whether a file starting with [head] is one of the formats tagged with
/// APEv2: Monkey's Audio, Musepack, WavPack, TTA, TAK or OptimFROG, by
/// their signatures or, failing that, the extension of [path].
bool _isApeTaggedHead(List<int> head, String path) {
  if (hasAscii(head, 0, "MAC ") ||
      hasAscii(head, 0, "MPCK") ||
      hasAscii(head, 0, "MP+") ||
      hasAscii(head, 0, "wvpk") ||
      hasAscii(head, 0, "TTA1") ||
      hasAscii(head, 0, "tBaK") ||
      hasAscii(head, 0, "OFR ")) {
    return true;
  }
  final lower = path.toLowerCase();
  return _apeTaggedExtensions.any(lower.endsWith) &&
      !(head.length >= 2 && head[0] == 0xff && head[1] & 0xe0 == 0xe0);
}

/// Reads the tags and stream properties of the file at [path].
FileTags readFileTags(String path) {
  final format = detectFormat(path);
  final stream = _streamInfo(path);
  try {
    final raf = File(path).openSync();
    try {
      return switch (format) {
        TagFormat.mp3 => _readMp3(raf, stream),
        TagFormat.flac => _readFlac(raf, stream),
        TagFormat.oggVorbis ||
        TagFormat.oggOpus ||
        TagFormat.oggSpeex ||
        TagFormat.oggFlac => _readOgg(raf, stream),
        TagFormat.apeTagged => _readApe(raf, stream),
        TagFormat.wav => _readWav(raf, stream),
        TagFormat.unknown => FileTags.unreadable(
          format,
          "Unsupported file type",
          stream: stream,
        ),
      };
    } finally {
      raf.closeSync();
    }
  } on Object catch (error) {
    return FileTags.unreadable(format, "$error", stream: stream);
  }
}

/// Writes [changes] (field -> new value; empty removes the field) to the
/// file at [path]. Fields not in [changes] are left as they are. When
/// [pictures] is given, the file's embedded pictures are replaced with it
/// (empty removes them all).
///
/// For an MP3, [id3] changes its ID3v1 and ID3v2 tags apart from each
/// other, and can add or remove either.
void writeFileTags(
  String path,
  Map<TagField, String> changes, {
  List<EmbeddedPicture>? pictures,
  Id3Edit? id3,
}) {
  if (changes.isEmpty && pictures == null && (id3?.isEmpty ?? true)) return;
  final file = File(path);
  switch (detectFormat(path)) {
    case TagFormat.mp3:
      _writeMp3(file, changes, pictures, id3 ?? const Id3Edit());
      // An APEv2 tag the file has is kept in step.
      ApeTag.update(file, changes, pictures: pictures, create: false);
    case TagFormat.flac:
      FlacMetadata.write(file, changes, pictures: pictures);
      ApeTag.update(file, changes, pictures: pictures, create: false);
    case TagFormat.oggVorbis ||
        TagFormat.oggOpus ||
        TagFormat.oggSpeex ||
        TagFormat.oggFlac:
      OggComments.write(file, changes, pictures: pictures);
    case TagFormat.apeTagged:
      ApeTag.update(file, changes, pictures: pictures, create: true);
    case TagFormat.wav:
      RiffTags.write(file, changes, pictures: pictures);
    case TagFormat.unknown:
      throw const TagWriteException("Unsupported file type");
  }
}

/// [readFileTags] in a background isolate.
Future<FileTags> readFileTagsInBackground(String path) =>
    Isolate.run(() => readFileTags(path));

/// [writeFileTags] in a background isolate.
Future<void> writeFileTagsInBackground(
  String path,
  Map<TagField, String> changes, {
  List<EmbeddedPicture>? pictures,
  Id3Edit? id3,
}) => Isolate.run(
  () => writeFileTags(path, changes, pictures: pictures, id3: id3),
);

/// Reads the pictures embedded in the file at [path] (ID3v2 `APIC` frames,
/// FLAC `PICTURE` blocks, Vorbis `METADATA_BLOCK_PICTURE` comments).
FilePictures readFilePictures(String path) {
  final format = detectFormat(path);
  try {
    final raf = File(path).openSync();
    try {
      switch (format) {
        case TagFormat.mp3:
          final v2 = _mp3Tags(raf).$1?.pictures ?? const [];
          return FilePictures(
            v2.isNotEmpty ? v2 : ApeTag.read(raf)?.pictures ?? const [],
            editable: true,
          );
        case TagFormat.flac:
          final flac = FlacMetadata.read(raf).pictures;
          return FilePictures(
            flac.isNotEmpty ? flac : ApeTag.read(raf)?.pictures ?? const [],
            editable: true,
          );
        case TagFormat.oggVorbis ||
            TagFormat.oggOpus ||
            TagFormat.oggSpeex ||
            TagFormat.oggFlac:
          final ogg = OggComments.read(raf);
          return FilePictures(
            [...ogg.flacPictures, ...ogg.comment.pictures],
            editable: true,
          );
        case TagFormat.apeTagged:
          return FilePictures(
            ApeTag.read(raf)?.pictures ?? const [],
            editable: true,
          );
        case TagFormat.wav:
          return FilePictures(
            RiffTags.read(raf).id3?.pictures ?? const [],
            editable: true,
          );
        case TagFormat.unknown:
          return const FilePictures.unreadable("Unsupported file type");
      }
    } finally {
      raf.closeSync();
    }
  } on Object catch (error) {
    return FilePictures.unreadable("$error");
  }
}

/// [readFilePictures] in a background isolate.
Future<FilePictures> readFilePicturesInBackground(String path) =>
    Isolate.run(() => readFilePictures(path));

/// The embedded cover of the file at [path]: its front cover, else its
/// first picture; `null` when it has none or can't be read.
EmbeddedPicture? readCoverArt(String path) => readFilePictures(path).cover;

/// [readCoverArt] in a background isolate.
Future<EmbeddedPicture?> readCoverArtInBackground(String path) =>
    Isolate.run(() => readCoverArt(path));

// --- Formats -------------------------------------------------------------------

(Id3v2Tag?, Id3v1Tag?) _mp3Tags(RandomAccessFile raf) {
  final head = readAt(raf, 0, 10);
  Id3v2Tag? v2;
  if (Id3v2Tag.isAt(head, 0)) {
    v2 = Id3v2Tag.parse(readAt(raf, 0, Id3v2Tag.sizeFromHeader(head)));
  }
  final length = raf.lengthSync();
  final v1 = length >= Id3v1Tag.size + (v2?.originalSize ?? 0)
      ? Id3v1Tag.parse(readAt(raf, length - Id3v1Tag.size, Id3v1Tag.size))
      : null;
  return (v2, v1);
}

FileTags _readMp3(RandomAccessFile raf, StreamInfo stream) {
  final (v2, v1) = _mp3Tags(raf);
  final ape = ApeTag.read(raf);
  return FileTags(
    format: TagFormat.mp3,
    tagTypes: [
      if (v2 != null) "ID3v2.${v2.version}",
      if (ape != null) ape.name,
      if (v1 != null) "ID3v1",
    ],
    // ID3v2 wins, then APEv2; ID3v1 fills in what they lack.
    fields: {...?v1?.fields, ...?ape?.fields, ...?v2?.fields},
    raw: [...?v2?.entries, ...?ape?.entries, ...?v1?.entries],
    editable: TagField.values.toSet(),
    id3v1: v1?.fields,
    id3v2: v2?.fields,
    stream: _withReplayGain(stream, [
      ...?v2?.entries,
      ...?ape?.entries,
    ]),
  );
}

void _writeMp3(
  File file,
  Map<TagField, String> changes,
  List<EmbeddedPicture>? pictures,
  Id3Edit id3,
) {
  final raf = file.openSync();
  final Id3v2Tag? existing;
  final Id3v1Tag? v1;
  final int length;
  try {
    (existing, v1) = _mp3Tags(raf);
    length = raf.lengthSync();
  } finally {
    raf.closeSync();
  }
  // Like in_mp3: write ID3v2 (adding one when missing), and keep an
  // existing ID3v1 tag in step; the ID3v1 and ID3v2 tabs set each apart and
  // can leave either tag out.
  final oldSize = existing?.originalSize ?? 0;
  final edits = <FileEdit>[];
  if (id3.includeV2 == false) {
    if (existing != null)
      edits.add((start: 0, end: oldSize, bytes: Uint8List(0)));
  } else if (existing != null ||
      id3.includeV2 == true ||
      changes.isNotEmpty ||
      pictures != null ||
      id3.v2.isNotEmpty) {
    final v2 = existing ?? Id3v2Tag.empty();
    changes.forEach(v2.set);
    id3.v2.forEach(v2.set);
    if (pictures != null) v2.setPictures(pictures);
    edits.add((start: 0, end: oldSize, bytes: v2.toBytes(fitTo: oldSize)));
  }
  final Id3v1Tag? newV1 = id3.includeV1 == false
      ? null
      : v1 ?? (id3.includeV1 == true ? Id3v1Tag.empty() : null);
  if (newV1 != null) {
    changes.forEach(newV1.set);
    id3.v1.forEach(newV1.set);
    edits.add(
      v1 != null
          ? (start: length - Id3v1Tag.size, end: length, bytes: newV1.bytes)
          : (start: length, end: length, bytes: newV1.bytes),
    );
  } else if (v1 != null) {
    edits.add(
      (start: length - Id3v1Tag.size, end: length, bytes: Uint8List(0)),
    );
  }
  editFile(file, edits);
}

FileTags _readFlac(RandomAccessFile raf, StreamInfo stream) {
  final meta = FlacMetadata.read(raf);
  final ape = ApeTag.read(raf);
  final entries = [...meta.entries, ...?ape?.entries];
  return FileTags(
    format: TagFormat.flac,
    tagTypes: [if (meta.comment != null) "Vorbis comment", ?ape?.name],
    fields: {...?ape?.fields, ...?meta.comment?.fields},
    raw: entries,
    editable: TagField.values.toSet(),
    stream: _withReplayGain(stream, entries),
  );
}

FileTags _readOgg(RandomAccessFile raf, StreamInfo stream) {
  final ogg = OggComments.read(raf);
  final entries = [
    ...ogg.comment.entries,
    for (final _ in ogg.flacPictures) const TagEntry("PICTURE", "[picture]"),
  ];
  return FileTags(
    format: ogg.format,
    tagTypes: const ["Vorbis comment"],
    fields: ogg.comment.fields,
    raw: entries,
    editable: TagField.values.toSet(),
    stream: _withReplayGain(stream, entries),
  );
}

FileTags _readApe(RandomAccessFile raf, StreamInfo stream) {
  final ape = ApeTag.read(raf);
  return FileTags(
    format: TagFormat.apeTagged,
    tagTypes: [?ape?.name],
    fields: ape?.fields ?? const {},
    raw: ape?.entries ?? const [],
    editable: TagField.values.toSet(),
    stream: _withReplayGain(stream, ape?.entries ?? const []),
  );
}

FileTags _readWav(RandomAccessFile raf, StreamInfo stream) {
  final tags = RiffTags.read(raf);
  return FileTags(
    format: TagFormat.wav,
    tagTypes: [
      if (tags.info.isNotEmpty) "RIFF INFO",
      if (tags.id3 != null) "ID3v2",
    ],
    fields: tags.fields,
    raw: tags.entries,
    editable: tags.editable,
    stream: _withReplayGain(stream, tags.id3?.entries ?? const []),
  );
}

// --- Stream properties ------------------------------------------------------

StreamInfo _streamInfo(String path) {
  int? size;
  try {
    size = File(path).lengthSync();
  } on FileSystemException {
    return const StreamInfo();
  }
  final flac = readFlacStreamInfo(path);
  Duration? duration = flac?.duration;
  int? bitrate = flac?.bitrate;
  int? sampleRate = flac?.sampleRate;
  try {
    final metadata = readMetadata(File(path));
    duration ??= metadata.duration;
    final bps = metadata.bitrate;
    bitrate ??= bps == null ? null : (bps >= 10000 ? bps ~/ 1000 : bps);
    sampleRate ??= metadata.sampleRate;
  } on Object {
    // Format info is best effort.
  }
  if (bitrate == null && duration != null && duration.inMilliseconds > 0) {
    bitrate = (size * 8 / duration.inMilliseconds).round();
  }
  return StreamInfo(
    fileSize: size,
    duration: duration,
    bitrate: bitrate,
    sampleRate: sampleRate,
    channels: readChannelCount(path),
  );
}

/// [stream] with the ReplayGain values found among [entries] (Vorbis
/// `REPLAYGAIN_*` fields or ID3 `TXXX` frames).
StreamInfo _withReplayGain(StreamInfo stream, List<TagEntry> entries) {
  final gain = <String, String>{};
  for (final entry in entries) {
    var name = entry.name.toLowerCase();
    var value = entry.value;
    if (name == "txxx") {
      final colon = value.indexOf(": ");
      if (colon < 0) continue;
      name = value.substring(0, colon).toLowerCase();
      value = value.substring(colon + 2);
    }
    if (name.startsWith("replaygain_")) {
      gain.putIfAbsent(name.substring("replaygain_".length), () => value);
    }
  }
  if (gain.isEmpty) return stream;
  return StreamInfo(
    fileSize: stream.fileSize,
    duration: stream.duration,
    bitrate: stream.bitrate,
    sampleRate: stream.sampleRate,
    channels: stream.channels,
    replayGain: gain,
  );
}

/// [readFileTags] of each of [paths], in a background isolate.
Future<List<FileTags>> readAllFileTagsInBackground(List<String> paths) =>
    Isolate.run(() => [for (final path in paths) readFileTags(path)]);
