import "dart:convert";
import "dart:io";

import "package:amped/src/player/playlist.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:flutter_test/flutter_test.dart";

/// Round-trips tags through real files that ffmpeg encodes, and checks
/// with ffprobe/ffmpeg that the result still reads and decodes.
void main() {
  final hasFfmpeg = Process.runSync("which", ["ffmpeg"]).exitCode == 0;
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("tags_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  String encode(String name, List<String> codec, {String? title}) {
    final path = "${dir.path}/$name";
    final result = Process.runSync("ffmpeg", [
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=440:duration=1",
      ...codec,
      if (title != null) ...["-metadata", "title=$title"],
      "-metadata",
      "album=keep me",
      "-metadata",
      "encoder_note=x",
      path,
    ]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
    return path;
  }

  Map<String, String> probe(String path) {
    final result = Process.runSync("ffprobe", [
      "-v",
      "error",
      "-show_entries",
      "format_tags:stream_tags",
      "-of",
      "json",
      path,
    ]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final tags = <String, String>{};
    void add(Object? t) {
      if (t is Map) {
        t.forEach((k, v) => tags["$k".toLowerCase()] = "$v");
      }
    }

    add((json["format"] as Map?)?["tags"]);
    for (final s in (json["streams"] as List? ?? [])) {
      add((s as Map)["tags"]);
    }
    return tags;
  }

  void decodes(String path) {
    final result = Process.runSync("ffmpeg", [
      "-v",
      "error",
      "-i",
      path,
      "-f",
      "null",
      "-",
    ]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
    expect("${result.stderr}".trim(), isEmpty);
  }

  final formats = {
    "mp3": (["-c:a", "libmp3lame"], TagFormat.mp3),
    "flac": (["-c:a", "flac"], TagFormat.flac),
    "ogg": (
      ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"],
      TagFormat.oggVorbis,
    ),
    "opus": (["-c:a", "libopus"], TagFormat.oggOpus),
    "wav": (["-c:a", "pcm_s16le"], TagFormat.wav),
  };

  for (final MapEntry(key: ext, value: (codec, format)) in formats.entries) {
    test("$ext: reads, edits and keeps other tags", () {
      final path = encode("a.$ext", codec, title: "Old");
      final before = readFileTags(path);
      expect(before.format, format);
      expect(before.error, isNull);
      expect(before[TagField.title], "Old");

      writeFileTags(path, {
        TagField.title: "Ünïcode Title",
        TagField.artist: "Artist",
        if (format != TagFormat.wav) TagField.albumArtist: "Various",
        TagField.track: "3",
      });

      final after = readFileTags(path);
      expect(after[TagField.title], "Ünïcode Title");
      expect(after[TagField.artist], "Artist");
      expect(after[TagField.track], "3");
      // Untouched fields survive.
      expect(after[TagField.album], "keep me");
      decodes(path);
      final probed = probe(path);
      expect(probed["title"], "Ünïcode Title");
      expect(probed["artist"], "Artist");

      // Clearing removes the field.
      writeFileTags(path, {TagField.artist: ""});
      expect(readFileTags(path)[TagField.artist], "");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");
  }

  for (final ext in ["mp3", "flac", "ogg"]) {
    test("$ext: the AcoustID fingerprint is stored as Picard does", () {
      final (codec, _) = formats[ext]!;
      final path = encode("fp.$ext", codec);
      writeFileTags(path, {TagField.acoustIdFingerprint: "AQADtest"});
      final tags = readFileTags(path);
      expect(tags[TagField.acoustIdFingerprint], "AQADtest");
      expect(tags.editable, contains(TagField.acoustIdFingerprint));
      expect(
        probe(path)[ext == "mp3"
            ? "acoustid fingerprint"
            : "acoustid_fingerprint"],
        "AQADtest",
      );
      // Writing it again replaces it rather than adding another.
      writeFileTags(path, {TagField.acoustIdFingerprint: "AQADnew"});
      expect(readFileTags(path)[TagField.acoustIdFingerprint], "AQADnew");
      expect(
        readFileTags(path).raw.where((e) => e.value.contains("AQAD")),
        hasLength(1),
      );
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");
  }

  test("mp3 without tags gets an ID3v2 tag", () {
    final path = "${dir.path}/plain.mp3";
    expect(
      Process.runSync("ffmpeg", [
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        "-c:a",
        "libmp3lame",
        "-id3v2_version",
        "0",
        "-write_xing",
        "0",
        path,
      ]).exitCode,
      0,
    );
    expect(readFileTags(path).tagTypes, isEmpty);
    writeFileTags(path, {TagField.title: "New"});
    final tags = readFileTags(path);
    expect(tags.tagTypes, ["ID3v2.3"]);
    expect(tags[TagField.title], "New");
    decodes(path);
  }, skip: hasFfmpeg ? false : "ffmpeg not installed");

  group("mp3 ID3v1 and ID3v2 apart", () {
    String both(String name) {
      final path = "${dir.path}/$name.mp3";
      expect(
        Process.runSync("ffmpeg", [
          "-v",
          "error",
          "-f",
          "lavfi",
          "-i",
          "sine=duration=1",
          "-c:a",
          "libmp3lame",
          "-write_id3v1",
          "1",
          "-metadata",
          "title=Old",
          "-metadata",
          "artist=Band",
          path,
        ]).exitCode,
        0,
      );
      return path;
    }

    test("Basic Info changes go to both tags", () {
      final path = both("basic");
      writeFileTags(path, {TagField.title: "New"});
      final tags = readFileTags(path);
      expect(tags.id3v1![TagField.title], "New");
      expect(tags.id3v2![TagField.title], "New");
      expect(tags.id3v2![TagField.artist], "Band");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");

    test("ID3v1 alone", () {
      final path = both("v1");
      writeFileTags(
        path,
        {},
        id3: const Id3Edit(v1: {TagField.title: "Short"}),
      );
      final tags = readFileTags(path);
      expect(tags.id3v1![TagField.title], "Short");
      expect(tags.id3v2![TagField.title], "Old");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");

    test("ID3v2 alone", () {
      final path = both("v2");
      writeFileTags(
        path,
        {},
        id3: const Id3Edit(v2: {TagField.title: "Long title"}),
      );
      final tags = readFileTags(path);
      expect(tags.id3v1![TagField.title], "Old");
      expect(tags.id3v2![TagField.title], "Long title");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");

    test("removing and adding tags", () {
      final path = both("toggle");
      writeFileTags(path, {}, id3: const Id3Edit(includeV1: false));
      var tags = readFileTags(path);
      expect(tags.id3v1, isNull);
      expect(tags.id3v2![TagField.title], "Old");
      decodes(path);

      writeFileTags(path, {}, id3: const Id3Edit(includeV2: false));
      tags = readFileTags(path);
      expect(tags.id3v1, isNull);
      expect(tags.id3v2, isNull);
      decodes(path);

      writeFileTags(
        path,
        {},
        id3: const Id3Edit(
          includeV1: true,
          v1: {TagField.title: "Only v1"},
        ),
      );
      tags = readFileTags(path);
      expect(tags.id3v1![TagField.title], "Only v1");
      expect(tags.id3v2, isNull);
      decodes(path);

      writeFileTags(
        path,
        {},
        id3: const Id3Edit(
          includeV2: true,
          v2: {TagField.title: "And v2"},
        ),
      );
      tags = readFileTags(path);
      expect(tags.id3v1![TagField.title], "Only v1");
      expect(tags.id3v2![TagField.title], "And v2");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");
  });

  test("long comment grows Ogg headers past one page and renumbers", () {
    final path = encode("big.ogg", [
      "-c:a",
      "vorbis",
      "-strict",
      "-2",
      "-ac",
      "2",
    ]);
    writeFileTags(path, {TagField.comment: "x" * 200000});
    expect(readFileTags(path)[TagField.comment], "x" * 200000);
    decodes(path);
  }, skip: hasFfmpeg ? false : "ffmpeg not installed");

  test(
    "after saving, the playlist entry's title follows the new tags",
    () async {
      final path = encode("t.wav", ["-c:a", "pcm_s16le"], title: "Old");
      final playlist = Playlist();
      await playlist.add([path]);
      await playlist.tagsRead(playlist.entries.first);
      expect(playlist.entries.first.title, "Old");

      writeFileTags(path, {TagField.title: "New", TagField.artist: "Band"});
      await playlist.fileTagsChanged(path);

      expect(playlist.entries.first.title, "Band - New");
    },
    skip: hasFfmpeg ? false : "ffmpeg not installed",
  );
}
