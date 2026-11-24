import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/mp3_info.dart";
import "package:amped/src/player/playlist.dart";
import "package:flutter_test/flutter_test.dart";

/// An MPEG-1 layer III frame header: 128 kbps, 44.1 kHz, stereo. Its frame
/// is 417 bytes long.
const _header = [0xff, 0xfb, 0x90, 0x00];
const _frameLength = 417;

Uint8List _frames(int count, {Uint8List? first}) {
  final out = BytesBuilder();
  for (var i = 0; i < count; i++) {
    final frame = Uint8List(_frameLength)..setAll(0, _header);
    if (i == 0 && first != null) frame.setAll(0, first);
    out.add(frame);
  }
  return out.takeBytes();
}

/// A first frame carrying a Xing header with [frames] and [bytes].
Uint8List _xingFrame(int frames, int bytes) {
  final frame = Uint8List(_frameLength)..setAll(0, _header);
  // Stereo MPEG-1: the Xing header follows 32 bytes of side info.
  frame.setAll(36, ascii.encode("Xing"));
  ByteData.sublistView(frame)
    ..setUint32(40, 3) // frames and bytes present
    ..setUint32(44, frames)
    ..setUint32(48, bytes);
  return frame;
}

List<int> _syncsafe(int n) => [
  n >> 21 & 0x7f,
  n >> 14 & 0x7f,
  n >> 7 & 0x7f,
  n & 0x7f,
];

/// An ID3v2.2 tag, as older iTunes versions wrote: 3-letter frame IDs and
/// 3-byte sizes.
Uint8List _id3v22(Map<String, List<int>> frames) {
  final body = BytesBuilder();
  frames.forEach((id, text) {
    final size = text.length;
    body
      ..add(ascii.encode(id))
      ..add([size >> 16 & 0xff, size >> 8 & 0xff, size & 0xff])
      ..add(text);
  });
  body.add(List.filled(16, 0)); // padding
  final bytes = body.takeBytes();
  return Uint8List.fromList([
    ...ascii.encode("ID3"),
    2,
    0,
    0,
    ..._syncsafe(bytes.length),
    ...bytes,
  ]);
}

/// An ID3v2.4 tag with UTF-8 text frames.
Uint8List _id3v24(Map<String, String> frames) {
  final body = BytesBuilder();
  frames.forEach((id, text) {
    final value = [3, ...utf8.encode(text)];
    body
      ..add(ascii.encode(id))
      ..add(_syncsafe(value.length))
      ..add([0, 0])
      ..add(value);
  });
  final bytes = body.takeBytes();
  return Uint8List.fromList([
    ...ascii.encode("ID3"),
    4,
    0,
    0,
    ..._syncsafe(bytes.length),
    ...bytes,
  ]);
}

/// An ID3v2.4 tag whose UTF-16 text frames carry a data length indicator
/// (4 bytes before the text, flagged in the frame header).
Uint8List _id3v24Indicated(Map<String, String> frames) {
  final body = BytesBuilder();
  frames.forEach((id, text) {
    final value = _utf16(text);
    final length = value.length;
    body
      ..add(ascii.encode(id))
      ..add(_syncsafe(length + 4))
      ..add([0, 1])
      ..add(_syncsafe(length))
      ..add(value);
  });
  final bytes = body.takeBytes();
  return Uint8List.fromList([
    ...ascii.encode("ID3"),
    4,
    0,
    0,
    ..._syncsafe(bytes.length),
    ...bytes,
  ]);
}

List<int> _latin1(String text) => [0, ...latin1.encode(text)];

List<int> _utf16(String text) => [
  1,
  0xff,
  0xfe,
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

void main() {
  late Directory dir;

  String write(String name, List<List<int>> parts) {
    final file = File("${dir.path}/$name")
      ..writeAsBytesSync([for (final part in parts) ...part]);
    return file.path;
  }

  setUp(() => dir = Directory.systemTemp.createTempSync("mp3_info_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  test("a CBR file's length is its audio size over its bitrate", () {
    final path = write("cbr.mp3", [
      _id3v22({"TT2": _latin1("Song")}),
      _frames(100),
      [...ascii.encode("TAG"), ...List.filled(125, 0)], // ID3v1
    ]);
    final info = readMp3StreamInfo(path)!;
    // 100 frames of 417 bytes at 128 kbps; the ID3 tags don't count.
    expect(info.duration.inMicroseconds, 2606250);
    expect(info.bitrate, 128);
    expect(info.sampleRate, 44100);
    expect(info.channels, 2);
  });

  test("a VBR file's length comes from its Xing frame count", () {
    final path = write("vbr.mp3", [
      _frames(10, first: _xingFrame(1000, 1000 * _frameLength)),
    ]);
    final info = readMp3StreamInfo(path)!;
    // 1000 frames of 1152 samples at 44.1 kHz.
    expect(info.duration.inMilliseconds, 26122);
    expect(info.bitrate, 128);
  });

  test("a file with no MPEG frames has no stream info", () {
    final path = write("junk.mp3", [List.filled(4096, 0x41)]);
    expect(readMp3StreamInfo(path), isNull);
  });

  test("reads ID3v2.2 text frames, Latin-1 and UTF-16", () {
    final path = write("v22.mp3", [
      _id3v22({
        "TT2": _latin1("Eighteen"),
        "TP1": _latin1("I Fight Dragons"),
        "COM": [0, ...ascii.encode("eng"), 0, ...ascii.encode("iTunPGAP")],
        "TAL": _utf16("The Near Future — Café"),
      }),
      _frames(4),
    ]);
    final text = readId3Text(path)!;
    expect(text.title, "Eighteen");
    expect(text.artist, "I Fight Dragons");
    expect(text.album, "The Near Future — Café");
  });

  test("reads ID3v2.4 UTF-8 text frames", () {
    final path = write("v24.mp3", [
      _id3v24({"TIT2": "Can’t You Hear Me", "TPE1": "Crooked Still"}),
      _frames(4),
    ]);
    final text = readId3Text(path)!;
    expect(text.title, "Can’t You Hear Me");
    expect(text.artist, "Crooked Still");
    expect(text.album, isNull);
  });

  test("a file without an ID3v2 tag has no ID3 text", () {
    expect(readId3Text(write("bare.mp3", [_frames(4)])), isNull);
  });

  test("the playlist reads an ID3v2.2 MP3's tags and length", () async {
    final path = write("01 Eighteen.mp3", [
      _id3v22({
        "TT2": _latin1("Eighteen"),
        "TP1": _latin1("I Fight Dragons"),
        "TAL": _latin1("The Near Future"),
      }),
      _frames(100),
    ]);
    final playlist = Playlist();
    await playlist.add([path]);
    final entry = playlist.entries.single;
    for (var i = 0; i < 100 && entry.duration == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(entry.duration, const Duration(microseconds: 2606250));
    expect(entry.bitrate, 128);
    expect(entry.sampleRate, 44100);
    expect(entry.artist, "I Fight Dragons");
    expect(entry.album, "The Near Future");
    expect(entry.title, "I Fight Dragons - Eighteen");
  });

  test("reads ID3v2.4 frames with a data length indicator", () async {
    final path = write("02 Hunger.mp3", [
      _id3v24Indicated({
        "TIT2": "Hunger",
        "TPE1": "Florence + The Machine",
        "TALB": "High As Hope",
      }),
      _frames(100),
    ]);
    final text = readId3Text(path)!;
    expect(text.title, "Hunger");
    expect(text.artist, "Florence + The Machine");
    expect(text.album, "High As Hope");
    final playlist = Playlist();
    await playlist.add([path]);
    final entry = playlist.entries.single;
    for (var i = 0; i < 100 && entry.duration == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(entry.title, "Florence + The Machine - Hunger");
    expect(entry.album, "High As Hope");
  });
}
