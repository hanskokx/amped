import "dart:convert";
import "dart:io";
import "dart:typed_data";

/// What the MPEG audio stream of an MP3 file says about itself, read from
/// its frame headers rather than its tags.
typedef Mp3StreamInfo = ({
  int sampleRate,
  int channels,
  Duration duration,
  int bitrate,
});

/// The artist, title and album in an MP3's ID3v2 tag.
typedef Id3Text = ({String? artist, String? title, String? album});

/// The length, average bitrate (kbps), sample rate and channel count of the
/// MP3 at [path], from its first MPEG frame: the frame count in a Xing,
/// Info or VBRI header when there is one (VBR files), else the audio size
/// over the frame's bitrate (CBR). `null` when no MPEG frame is found.
Mp3StreamInfo? readMp3StreamInfo(String path) {
  try {
    final file = File(path).openSync();
    try {
      final size = file.lengthSync();
      final start = _skipId3v2(file);
      file.setPositionSync(start);
      final head = file.readSync(16 * 1024);
      var end = size;
      if (size >= 128) {
        file.setPositionSync(size - 128);
        final tail = file.readSync(3);
        if (String.fromCharCodes(tail) == "TAG") end -= 128; // ID3v1
      }
      return _streamInfo(head, start, end);
    } finally {
      file.closeSync();
    }
  } on Object {
    return null;
  }
}

/// The artist, title and album in the ID3v2 tag (versions 2.2 to 2.4) at the
/// start of the file at [path], or `null` when it has none or it can't be
/// read. A fallback for tags the general tag reader can't parse, such as the
/// ID3v2.2 tags older iTunes versions wrote.
Id3Text? readId3Text(String path) {
  try {
    final file = File(path).openSync();
    try {
      final header = file.readSync(10);
      if (header.length < 10 || String.fromCharCodes(header, 0, 3) != "ID3") {
        return null;
      }
      final version = header[3];
      final flags = header[5];
      // ID3v2.2's compression flag: no scheme was ever defined for it.
      if (version == 2 && flags & 0x40 != 0) return null;
      var tag = _readFully(file, _syncsafe(header, 6));
      if (flags & 0x80 != 0 && version < 4) tag = _resynchronise(tag);
      return _textFrames(tag, version, flags);
    } finally {
      file.closeSync();
    }
  } on Object {
    return null;
  }
}

/// [length] bytes from [file]'s position; a network share may answer a read
/// with fewer than asked, which would cut a big tag short.
Uint8List _readFully(RandomAccessFile file, int length) {
  final out = BytesBuilder(copy: false);
  while (out.length < length) {
    final chunk = file.readSync(length - out.length);
    if (chunk.isEmpty) break;
    out.add(chunk);
  }
  return out.takeBytes();
}

int _syncsafe(List<int> b, int o) =>
    (b[o] & 0x7f) << 21 |
    (b[o + 1] & 0x7f) << 14 |
    (b[o + 2] & 0x7f) << 7 |
    (b[o + 3] & 0x7f);

int _u32(List<int> b, int o) =>
    b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

/// The offset just past any ID3v2 tags at the start of [file].
int _skipId3v2(RandomAccessFile file) {
  var offset = 0;
  while (true) {
    file.setPositionSync(offset);
    final header = file.readSync(10);
    if (header.length < 10 || String.fromCharCodes(header, 0, 3) != "ID3") {
      return offset;
    }
    final footer = header[3] == 4 && header[5] & 0x10 != 0 ? 10 : 0;
    offset += 10 + _syncsafe(header, 6) + footer;
  }
}

/// Undoes ID3 unsynchronisation: every 0xFF 0x00 pair becomes 0xFF.
Uint8List _resynchronise(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    out.addByte(bytes[i]);
    if (bytes[i] == 0xff && i + 1 < bytes.length && bytes[i + 1] == 0) i++;
  }
  return out.takeBytes();
}

Id3Text? _textFrames(Uint8List tag, int version, int flags) {
  final idLength = version == 2 ? 3 : 4;
  final headerLength = version == 2 ? 6 : 10;
  var o = 0;
  // An ID3v2.3/2.4 extended header comes before the frames.
  if (version >= 3 && flags & 0x40 != 0 && tag.length >= 4) {
    o = version == 4 ? _syncsafe(tag, 0) : 4 + _u32(tag, 0);
  }
  String? artist;
  String? title;
  String? album;
  while (o + headerLength <= tag.length && tag[o] != 0) {
    final id = String.fromCharCodes(tag, o, o + idLength);
    final size = switch (version) {
      2 => tag[o + 3] << 16 | tag[o + 4] << 8 | tag[o + 5],
      4 => _syncsafe(tag, o + 4),
      _ => _u32(tag, o + 4),
    };
    final body = o + headerLength;
    if (size <= 0 || body + size > tag.length) break;
    var data = Uint8List.sublistView(tag, body, body + size);
    // What the frame's format flags put around the text.
    var usable = true;
    if (version >= 3) {
      final format = tag[o + 9];
      if (version == 4) {
        // Grouping (a byte), compression and encryption (unreadable), then
        // unsynchronisation and a data length indicator (4 bytes) in front.
        final grouped = format & 0x40 != 0;
        final compressed = format & 0x08 != 0;
        final encrypted = format & 0x04 != 0;
        final unsynchronised = format & 0x02 != 0;
        final lengthIndicated = format & 0x01 != 0;
        usable = !compressed && !encrypted;
        if (grouped && data.isNotEmpty) data = Uint8List.sublistView(data, 1);
        if (lengthIndicated && data.length >= 4) {
          data = Uint8List.sublistView(data, 4);
        }
        if (unsynchronised) data = _resynchronise(data);
      } else {
        // ID3v2.3: compression and encryption, then grouping.
        usable = format & 0xc0 == 0;
        if (format & 0x20 != 0 && data.isNotEmpty) {
          data = Uint8List.sublistView(data, 1);
        }
      }
    }
    final text = switch (id) {
      "TT2" ||
      "TP1" ||
      "TAL" ||
      "TIT2" ||
      "TPE1" ||
      "TALB" => usable ? _text(data) : null,
      _ => null,
    };
    switch (id) {
      case "TT2" || "TIT2":
        title = text;
      case "TP1" || "TPE1":
        artist = text;
      case "TAL" || "TALB":
        album = text;
    }
    o = body + size;
  }
  if (artist == null && title == null && album == null) return null;
  return (artist: artist, title: title, album: album);
}

/// A text frame's value: an encoding byte, then the text. Multiple values
/// (ID3v2.4 separates them with NULs) are joined with "/".
String? _text(Uint8List frame) {
  if (frame.isEmpty) return null;
  final bytes = Uint8List.sublistView(frame, 1);
  final String decoded;
  switch (frame[0]) {
    case 1 || 2:
      decoded = _utf16(bytes, bigEndian: frame[0] == 2);
    case 3:
      decoded = utf8.decode(bytes, allowMalformed: true);
    default:
      decoded = latin1.decode(bytes);
  }
  final values = decoded
      .split("\u0000")
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty);
  return values.isEmpty ? null : values.join("/");
}

/// UTF-16 text, honouring a byte order mark wherever one starts a value.
String _utf16(Uint8List bytes, {required bool bigEndian}) {
  final units = <int>[];
  var big = bigEndian;
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final unit = big
        ? bytes[i] << 8 | bytes[i + 1]
        : bytes[i] | bytes[i + 1] << 8;
    if (unit == 0xfeff) continue;
    if (unit == 0xfffe) {
      big = !big;
      continue;
    }
    units.add(unit);
  }
  return String.fromCharCodes(units);
}

// --- MPEG frames --------------------------------------------------------

const _bitrates = <List<int>>[
  // MPEG-1 layer I, II, III
  [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  // MPEG-2 and 2.5 layer I, then II and III
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
];

/// A parsed MPEG audio frame header.
typedef _Frame = ({
  bool mpeg1,
  int layer,
  int bitrate,
  int sampleRate,
  int channels,
  int samples,
  int length,
});

_Frame? _frameAt(Uint8List b, int o) {
  if (o + 4 > b.length || b[o] != 0xff || b[o + 1] & 0xe0 != 0xe0) {
    return null;
  }
  final version = b[o + 1] >> 3 & 3; // 3: MPEG-1, 2: MPEG-2, 0: MPEG-2.5
  final layer = 4 - (b[o + 1] >> 1 & 3); // 1, 2 or 3
  final bitrateIndex = b[o + 2] >> 4;
  final rateIndex = b[o + 2] >> 2 & 3;
  if (version == 1 || layer == 4 || rateIndex == 3) return null;
  // 0 is "free format", which has no length we can work out.
  if (bitrateIndex == 0 || bitrateIndex == 15) return null;
  final mpeg1 = version == 3;
  final table = mpeg1 ? layer - 1 : (layer == 1 ? 3 : 4);
  final bitrate = _bitrates[table][bitrateIndex];
  final sampleRate =
      const [44100, 48000, 32000][rateIndex] >>
      (mpeg1 ? 0 : (version == 2 ? 1 : 2));
  final samples = layer == 1 ? 384 : (layer == 3 && !mpeg1 ? 576 : 1152);
  final padding = b[o + 2] >> 1 & 1;
  final length = layer == 1
      ? (12 * bitrate * 1000 ~/ sampleRate + padding) * 4
      : samples ~/ 8 * bitrate * 1000 ~/ sampleRate + padding;
  return (
    mpeg1: mpeg1,
    layer: layer,
    bitrate: bitrate,
    sampleRate: sampleRate,
    channels: b[o + 3] >> 6 == 3 ? 1 : 2,
    samples: samples,
    length: length,
  );
}

/// Stream info from [head], the bytes from [start] (the end of any ID3v2
/// tag) of a file whose audio ends at [end].
Mp3StreamInfo? _streamInfo(Uint8List head, int start, int end) {
  for (var o = 0; o + 4 <= head.length; o++) {
    final frame = _frameAt(head, o);
    if (frame == null) continue;
    // A real frame is followed by another, unless the data runs out first.
    final next = o + frame.length;
    if (next + 4 <= head.length && _frameAt(head, next) == null) continue;

    final mono = frame.channels == 1;
    final xing = o + 4 + (frame.mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17));
    int? frames;
    int? bytes;
    if (_tagAt(head, xing, "Xing") || _tagAt(head, xing, "Info")) {
      final flags = _u32(head, xing + 4);
      var p = xing + 8;
      if (flags & 1 != 0 && p + 4 <= head.length) {
        frames = _u32(head, p);
        p += 4;
      }
      if (flags & 2 != 0 && p + 4 <= head.length) bytes = _u32(head, p);
    } else if (_tagAt(head, o + 36, "VBRI") && o + 36 + 18 <= head.length) {
      bytes = _u32(head, o + 36 + 10);
      frames = _u32(head, o + 36 + 14);
    }

    final audioBytes = bytes ?? (end - start - o);
    final double seconds;
    if (frames != null && frames > 0) {
      seconds = frames * frame.samples / frame.sampleRate;
    } else {
      seconds = audioBytes * 8 / (frame.bitrate * 1000);
    }
    if (seconds <= 0) return null;
    return (
      sampleRate: frame.sampleRate,
      channels: frame.channels,
      duration: Duration(microseconds: (seconds * 1e6).round()),
      bitrate: frames != null && frames > 0
          ? (audioBytes * 8 / seconds / 1000).round()
          : frame.bitrate,
    );
  }
  return null;
}

bool _tagAt(Uint8List b, int o, String text) =>
    o + text.length <= b.length &&
    String.fromCharCodes(b, o, o + text.length) == text;
