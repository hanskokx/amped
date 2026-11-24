import "dart:io";
import "dart:typed_data";

import "package:amped/src/tags/ape_tags.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:flutter_test/flutter_test.dart";

/// APEv2 tags, and the formats that carry them or that were not read
/// before (Ogg Speex and Ogg FLAC).
void main() {
  bool has(String tool) => Process.runSync("which", [tool]).exitCode == 0;
  final hasFfmpeg = has("ffmpeg");
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("ape_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  void ffmpeg(List<String> args) {
    final result = Process.runSync("ffmpeg", ["-v", "error", "-y", ...args]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
  }

  String encode(String name, List<String> codec) {
    final path = "${dir.path}/$name";
    ffmpeg([
      "-f",
      "lavfi",
      "-i",
      "sine=duration=1",
      "-map_metadata",
      "-1",
      "-bitexact",
      ...codec,
      path,
    ]);
    return path;
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

  String probeTitle(String path) {
    final result = Process.runSync("ffprobe", [
      "-v",
      "error",
      "-show_entries",
      "format_tags=title",
      "-of",
      "default=nw=1:nk=1",
      path,
    ]);
    return "${result.stdout}".trim();
  }

  late Uint8List jpeg;
  late EmbeddedPicture picture;

  setUp(() {
    // A real image, which ffmpeg then also accepts as cover art.
    final image = "${dir.path}/cover.jpg";
    jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0xff, 0xd9]);
    if (hasFfmpeg &&
        Process.runSync("ffmpeg", [
              "-v",
              "error",
              "-f",
              "lavfi",
              "-i",
              "color=c=red:s=16x16",
              "-frames:v",
              "1",
              image,
            ]).exitCode ==
            0) {
      jpeg = File(image).readAsBytesSync();
    }
    picture = EmbeddedPicture(
      type: ArtworkType.frontCover,
      mimeType: "image/jpeg",
      data: jpeg,
    );
  });

  group("ApeTag", () {
    test("round-trips items, multiple values and pictures", () {
      final tag = ApeTag.empty()
        ..set(TagField.title, "Ünï")
        ..set(TagField.track, "3/12")
        ..items.add(ApeItem("Artist", Uint8List.fromList("A\u0000B".codeUnits)))
        ..setPictures([picture]);
      final file = File("${dir.path}/raw.bin")
        ..writeAsBytesSync([1, 2, 3, ...tag.toBytes()]);
      final raf = file.openSync();
      final read = ApeTag.read(raf)!;
      raf.closeSync();
      expect(read.name, "APEv2");
      expect(read.start, 3);
      expect(read.fields, {
        TagField.title: "Ünï",
        TagField.track: "3/12",
        TagField.artist: "A; B",
      });
      expect(read.pictures.single.type, ArtworkType.frontCover);
      expect(read.pictures.single.data, jpeg);
      expect(read.pictures.single.mimeType, "image/jpeg");
    });

    test("set replaces aliases in place and an empty value removes", () {
      final tag = ApeTag([
        ApeItem.text("Date", "1999"),
        ApeItem.text("Genre", "Rock"),
      ])..set(TagField.year, "2001");
      expect(tag.items.map((i) => i.key), ["Date", "Genre"]);
      expect(tag.fields[TagField.year], "2001");
      tag.set(TagField.genre, "");
      expect(tag.items, hasLength(1));
    });
  });

  group("MP3 with an APEv2 tag", () {
    String mp3WithApe(ApeTag tag, {Map<String, String> id3 = const {}}) {
      final path = "${dir.path}/ape.mp3";
      ffmpeg([
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        "-c:a",
        "libmp3lame",
        if (id3.isEmpty) ...["-id3v2_version", "0"],
        for (final MapEntry(:key, :value) in id3.entries) ...[
          "-metadata",
          "$key=$value",
        ],
        "-write_xing",
        "0",
        path,
      ]);
      File(path).writeAsBytesSync(tag.toBytes(), mode: FileMode.append);
      return path;
    }

    test("reads it, ID3v2 winning", () {
      final path = mp3WithApe(
        ApeTag.empty()
          ..set(TagField.title, "From APE")
          ..set(TagField.artist, "APE Artist"),
        id3: {"title": "From ID3"},
      );
      final tags = readFileTags(path);
      expect(tags.tagTypes, contains("APEv2"));
      expect(tags[TagField.title], "From ID3");
      expect(tags[TagField.artist], "APE Artist");
      expect(tags.raw.map((e) => e.name), contains("Artist"));
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");

    test("writes to the APE tag it has, and reads its cover", () {
      final path = mp3WithApe(
        ApeTag.empty()
          ..set(TagField.title, "Old")
          ..setPictures([picture]),
      );
      expect(readFilePictures(path).pictures.single.data, jpeg);
      writeFileTags(path, {
        TagField.title: "New",
        TagField.album: "Alb",
      });
      final tags = readFileTags(path);
      expect(tags[TagField.title], "New");
      expect(tags[TagField.album], "Alb");
      expect(tags.tagTypes, containsAll(["ID3v2.3", "APEv2"]));
      // The cover survives, and the audio still plays.
      expect(readFilePictures(path).pictures, hasLength(1));
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");

    test("an ID3v1 tag after it is kept", () {
      final path = mp3WithApe(ApeTag.empty()..set(TagField.title, "T"));
      final file = File(path);
      final v1 = Uint8List(128)
        ..setRange(0, 3, "TAG".codeUnits)
        ..setRange(3, 6, "Old".codeUnits)
        ..[127] = 0xff;
      file.writeAsBytesSync(v1, mode: FileMode.append);
      expect(readFileTags(path).tagTypes, containsAll(["APEv2", "ID3v1"]));
      writeFileTags(path, {TagField.artist: "Someone"});
      final tags = readFileTags(path);
      expect(tags.tagTypes, containsAll(["APEv2", "ID3v1"]));
      expect(tags[TagField.artist], "Someone");
      expect(tags.id3v1![TagField.artist], "Someone");
      decodes(path);
    }, skip: hasFfmpeg ? false : "ffmpeg not installed");
  });

  group("APE-tagged audio", () {
    final codecs = {
      "wv": ["-c:a", "wavpack"],
      "tta": ["-c:a", "tta"],
    };
    for (final MapEntry(key: ext, value: codec) in codecs.entries) {
      test("$ext: creates, edits and removes tags", () {
        final path = encode("a.$ext", codec);
        final before = readFileTags(path);
        expect(before.format, TagFormat.apeTagged);
        expect(before.error, isNull);
        expect(before.tagTypes, isEmpty);

        writeFileTags(
          path,
          {
            TagField.title: "Ünï Title",
            TagField.artist: "Artist",
            TagField.albumArtist: "Various",
            TagField.track: "4/9",
          },
          pictures: [picture],
        );
        final tags = readFileTags(path);
        expect(tags.tagTypes, ["APEv2"]);
        expect(tags[TagField.title], "Ünï Title");
        expect(tags[TagField.albumArtist], "Various");
        expect(tags[TagField.track], "4/9");
        expect(readFilePictures(path).pictures.single.data, jpeg);
        expect(probeTitle(path), "Ünï Title");
        decodes(path);

        writeFileTags(path, {TagField.artist: ""});
        expect(readFileTags(path)[TagField.artist], "");
        expect(readFileTags(path)[TagField.title], "Ünï Title");
        writeFileTags(path, {
          TagField.title: "",
          TagField.albumArtist: "",
          TagField.track: "",
        }, pictures: const []);
        expect(readFileTags(path).tagTypes, isEmpty);
        expect(readFilePictures(path).pictures, isEmpty);
        decodes(path);
      }, skip: hasFfmpeg ? false : "ffmpeg not installed");
    }

    test("a .mpc with Musepack's signature is recognised", () {
      final path = "${dir.path}/a.mpc";
      File(path).writeAsBytesSync([...("MPCK".codeUnits), ...Uint8List(64)]);
      expect(detectFormat(path), TagFormat.apeTagged);
      writeFileTags(path, {TagField.title: "Mpc"});
      expect(readFileTags(path)[TagField.title], "Mpc");
    });
  });

  group("Ogg Speex", () {
    test("reads and edits the comments", () {
      if (!hasFfmpeg || !has("speexenc")) return;
      final wav = "${dir.path}/s.wav";
      ffmpeg([
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        "-ar",
        "16000",
        "-ac",
        "1",
        wav,
      ]);
      final path = "${dir.path}/a.spx";
      final result = Process.runSync("speexenc", [
        "--title",
        "Old",
        "--comment",
        "ARTIST=Band",
        wav,
        path,
      ]);
      expect(result.exitCode, 0, reason: "${result.stderr}");
      final before = readFileTags(path);
      expect(before.format, TagFormat.oggSpeex);
      expect(before.error, isNull);
      expect(before[TagField.title], "Old");

      writeFileTags(
        path,
        {
          TagField.title: "New ünï",
          TagField.album: "Alb",
        },
        pictures: [picture],
      );
      final after = readFileTags(path);
      expect(after[TagField.title], "New ünï");
      expect(after[TagField.artist], "Band");
      expect(after[TagField.album], "Alb");
      expect(readFilePictures(path).pictures.single.data, jpeg);
      decodes(path);
    });
  });

  group("Ogg FLAC", () {
    test("reads and edits the comments and pictures", () {
      if (!hasFfmpeg || !has("flac")) return;
      final wav = "${dir.path}/f.wav";
      ffmpeg([
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        "-map_metadata",
        "-1",
        "-bitexact",
        wav,
      ]);
      final path = "${dir.path}/a.oga";
      final result = Process.runSync("flac", [
        "-s",
        "--ogg",
        "-T",
        "TITLE=Old",
        "-T",
        "ARTIST=Band",
        "-f",
        wav,
        "-o",
        path,
      ]);
      expect(result.exitCode, 0, reason: "${result.stderr}");
      final before = readFileTags(path);
      expect(before.format, TagFormat.oggFlac);
      expect(before.error, isNull);
      expect(before[TagField.title], "Old");

      void check(String expectedTitle, int pictures) {
        final tags = readFileTags(path);
        expect(tags[TagField.title], expectedTitle);
        expect(tags[TagField.artist], "Band");
        expect(readFilePictures(path).pictures, hasLength(pictures));
        // flac verifies the page checksums and the block layout.
        final test = Process.runSync("flac", ["-t", "-s", path]);
        expect(test.exitCode, 0, reason: "${test.stderr}");
        decodes(path);
      }

      writeFileTags(path, {TagField.title: "New ünï"}, pictures: [picture]);
      check("New ünï", 1);
      writeFileTags(path, {TagField.album: "Alb"});
      check("New ünï", 1);
      expect(readFileTags(path)[TagField.album], "Alb");
      writeFileTags(path, {}, pictures: const []);
      check("New ünï", 0);
    });
  });
}
