import "dart:convert";
import "dart:io";
import "dart:typed_data";

/// Byte-level helpers shared by the tag readers and writers.

int u16be(List<int> b, int o) => b[o] << 8 | b[o + 1];
int u24be(List<int> b, int o) => b[o] << 16 | b[o + 1] << 8 | b[o + 2];
int u32be(List<int> b, int o) =>
    b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];
int u32le(List<int> b, int o) =>
    b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24;

/// A 28-bit ID3v2 sync-safe integer.
int syncSafe(List<int> b, int o) =>
    (b[o] & 0x7f) << 21 |
    (b[o + 1] & 0x7f) << 14 |
    (b[o + 2] & 0x7f) << 7 |
    (b[o + 3] & 0x7f);

List<int> syncSafeBytes(int v) => [
  (v >> 21) & 0x7f,
  (v >> 14) & 0x7f,
  (v >> 7) & 0x7f,
  v & 0x7f,
];

List<int> be32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];
List<int> be24(int v) => [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
List<int> le32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

bool hasAscii(List<int> b, int o, String text) {
  if (o < 0 || o + text.length > b.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (b[o + i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

/// [bytes] as UTF-8, or as Latin-1 when they aren't valid UTF-8.
String decodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Removes trailing NULs (C strings in fixed-size or padded fields).
String trimNuls(String s) {
  var end = s.length;
  while (end > 0 && s.codeUnitAt(end - 1) == 0) {
    end--;
  }
  return s.substring(0, end);
}

/// One replacement of bytes `start`..`end` of a file.
typedef FileEdit = ({int start, int end, List<int> bytes});

/// Applies [edits] (non-overlapping) to [file]: in place when none changes
/// the size, otherwise by copying into a temporary file next to it and
/// renaming that over the original, so a failure leaves the original
/// untouched.
void editFile(File file, List<FileEdit> edits) {
  final sorted = [...edits]..sort((a, b) => a.start.compareTo(b.start));
  if (sorted.every((e) => e.bytes.length == e.end - e.start)) {
    final raf = file.openSync(mode: FileMode.append);
    try {
      for (final edit in sorted) {
        raf
          ..setPositionSync(edit.start)
          ..writeFromSync(edit.bytes);
      }
    } finally {
      raf.closeSync();
    }
    return;
  }
  final temp = File("${file.path}.amped-tag");
  try {
    final source = file.openSync();
    final out = temp.openSync(mode: FileMode.write);
    try {
      void copy(int from, int to) {
        source.setPositionSync(from);
        var left = to - from;
        while (left > 0) {
          final chunk = source.readSync(left < 1 << 20 ? left : 1 << 20);
          if (chunk.isEmpty) break;
          out.writeFromSync(chunk);
          left -= chunk.length;
        }
      }

      var at = 0;
      for (final edit in sorted) {
        copy(at, edit.start);
        out.writeFromSync(edit.bytes);
        at = edit.end;
      }
      copy(at, source.lengthSync());
    } finally {
      out.closeSync();
      source.closeSync();
    }
    temp.renameSync(file.path);
  } finally {
    if (temp.existsSync()) temp.deleteSync();
  }
}

/// Reads [length] bytes of [file] at [offset] (fewer at its end).
Uint8List readAt(RandomAccessFile file, int offset, int length) {
  file.setPositionSync(offset);
  return file.readSync(length);
}
