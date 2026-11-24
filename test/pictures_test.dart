import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/playlist.dart" show readArtwork;
import "package:amped/src/tags/tag_io.dart";
import "package:flutter_test/flutter_test.dart";

/// Embedded pictures: header parsing, and round trips through real files
/// that ffmpeg encodes, checked with ffprobe/ffmpeg and with the reader the
/// now-playing artwork uses.
void main() {
  final hasFfmpeg = Process.runSync("which", ["ffmpeg"]).exitCode == 0;
  final skip = hasFfmpeg ? false : "ffmpeg not installed";
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("pictures_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  void ffmpeg(List<String> args) {
    final result = Process.runSync("ffmpeg", ["-v", "error", ...args]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
  }

  Uint8List image(String name, String size) {
    final path = "${dir.path}/$name";
    ffmpeg(["-f", "lavfi", "-i", "color=red:s=$size", "-frames:v", "1", path]);
    return File(path).readAsBytesSync();
  }

  String encode(String name, List<String> codec) {
    final path = "${dir.path}/$name";
    ffmpeg([
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=440:duration=1",
      ...codec,
      "-metadata",
      "title=keep me",
      path,
    ]);
    return path;
  }

  /// The number of attached pictures ffprobe finds.
  int probedPictures(String path) {
    final result = Process.runSync("ffprobe", [
      "-v",
      "error",
      "-show_entries",
      "stream=codec_type:stream_disposition=attached_pic",
      "-of",
      "json",
      path,
    ]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    return [
      for (final s in json["streams"] as List)
        if (((s as Map)["disposition"] as Map?)?["attached_pic"] == 1) s,
    ].length;
  }

  void decodes(String path) {
    final result = Process.runSync("ffmpeg", [
      "-v",
      "error",
      "-i",
      path,
      "-map",
      "0:a",
      "-f",
      "null",
      "-",
    ]);
    expect(result.exitCode, 0, reason: "${result.stderr}");
    expect("${result.stderr}".trim(), isEmpty);
  }

  group("image headers", () {
    test("1x1 PNG", () {
      final png = base64.decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwAD"
        "hgGAWjR9awAAAABJRU5ErkJggg==",
      );
      expect(sniffImageMime(png), "image/png");
      expect(imageSize(png), (1, 1));
    });

    test("GIF and BMP", () {
      final gif = Uint8List.fromList([...ascii.encode("GIF89a"), 3, 0, 2, 0]);
      expect(imageSize(gif), (3, 2));
      final bmp = Uint8List(30)
        ..setRange(0, 2, ascii.encode("BM"))
        ..setRange(18, 22, [5, 0, 0, 0])
        ..setRange(22, 26, [0xfa, 0xff, 0xff, 0xff]); // -6: top-down.
      expect(imageSize(bmp), (5, 6));
    });

    test("not an image", () {
      expect(sniffImageMime(ascii.encode("hello")), isNull);
      expect(imageSize(Uint8List.fromList(ascii.encode("hello"))), isNull);
    });

    test("JPEG", () {
      final jpeg = image("a.jpg", "40x24");
      expect(sniffImageMime(jpeg), "image/jpeg");
      expect(imageSize(jpeg), (40, 24));
    }, skip: skip);
  });

  test("FLAC picture block round trip", () {
    final picture = EmbeddedPicture(
      type: ArtworkType.backCover,
      mimeType: "image/png",
      description: "Bäck",
      data: Uint8List.fromList([1, 2, 3]),
    );
    final back = EmbeddedPicture.fromFlacBlock(picture.toFlacBlock());
    expect(back.type, ArtworkType.backCover);
    expect(back.mimeType, "image/png");
    expect(back.description, "Bäck");
    expect(back.data, [1, 2, 3]);
  });

  final formats = {
    "mp3": ["-c:a", "libmp3lame"],
    "flac": ["-c:a", "flac"],
    "ogg": ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"],
    "opus": ["-c:a", "libopus"],
    "wav": ["-c:a", "pcm_s16le"],
  };

  for (final MapEntry(key: ext, value: codec) in formats.entries) {
    test("$ext: adds, replaces and removes pictures", () async {
      final path = encode("a.$ext", codec);
      final before = readFilePictures(path);
      expect(before.error, isNull);
      expect(before.editable, isTrue);
      expect(before.pictures, isEmpty);
      expect(readCoverArt(path), isNull);

      final png = image("cover.png", "16x8");
      final jpeg = image("back.jpg", "8x8");
      writeFileTags(
        path,
        {TagField.artist: "Band"},
        pictures: [
          EmbeddedPicture(
            type: ArtworkType.backCover,
            mimeType: "image/jpeg",
            data: jpeg,
          ),
          EmbeddedPicture(
            type: ArtworkType.frontCover,
            mimeType: "image/png",
            description: "Frönt",
            data: png,
          ),
        ],
      );

      final after = readFilePictures(path);
      expect(after.pictures.map((p) => p.type), [
        ArtworkType.backCover,
        ArtworkType.frontCover,
      ]);
      final cover = readCoverArt(path)!;
      expect(cover.type, ArtworkType.frontCover);
      expect(cover.mimeType, "image/png");
      expect(cover.description, "Frönt");
      expect(cover.data, png);
      expect(cover.size, (16, 8));
      expect(after.pictures.first.data, jpeg);
      // Tags written alongside, and untouched ones, are there.
      expect(readFileTags(path)[TagField.artist], "Band");
      expect(readFileTags(path)[TagField.title], "keep me");
      decodes(path);
      if (ext == "mp3" || ext == "flac") {
        expect(probedPictures(path), 2);
        // The reader behind the now-playing artwork finds the front cover.
        expect(await readArtwork(path), png);
      }

      // Tag edits alone leave the pictures be.
      writeFileTags(path, {TagField.artist: "Other"});
      expect(readFilePictures(path).pictures, hasLength(2));

      writeFileTags(path, const {}, pictures: const []);
      expect(readFilePictures(path).pictures, isEmpty);
      expect(readFileTags(path)[TagField.artist], "Other");
      decodes(path);
    }, skip: skip);
  }

  test("a large cover spreads Ogg headers over many pages", () {
    final path = encode("big.ogg", formats["ogg"]!);
    // Noise doesn't compress: a picture of about 1 MB.
    final noise = "${dir.path}/noise.png";
    ffmpeg([
      "-f",
      "lavfi",
      "-i",
      "nullsrc=s=600x600,geq=random(1)*255:128:128",
      "-frames:v",
      "1",
      noise,
    ]);
    final data = File(noise).readAsBytesSync();
    expect(data.length, greaterThan(500000));
    writeFileTags(
      path,
      const {},
      pictures: [
        EmbeddedPicture(
          type: ArtworkType.frontCover,
          mimeType: "image/png",
          data: data,
        ),
      ],
    );
    expect(readCoverArt(path)!.data, data);
    decodes(path);
  }, skip: skip);

  test("WAV: a picture added to a file with only INFO tags", () {
    final path = encode("plain.wav", formats["wav"]!);
    expect(readFileTags(path).tagTypes, ["RIFF INFO"]);
    final png = image("c.png", "4x4");
    writeFileTags(
      path,
      {TagField.title: "New"},
      pictures: [
        EmbeddedPicture(
          type: ArtworkType.frontCover,
          mimeType: "image/png",
          data: png,
        ),
      ],
    );
    final tags = readFileTags(path);
    expect(tags.tagTypes, ["RIFF INFO", "ID3v2"]);
    expect(tags[TagField.title], "New");
    expect(readCoverArt(path)!.data, png);
    decodes(path);
  }, skip: skip);

  test("unsupported files are unreadable", () {
    final path = "${dir.path}/x.txt";
    File(path).writeAsStringSync("not audio");
    final pictures = readFilePictures(path);
    expect(pictures.error, isNotNull);
    expect(pictures.editable, isFalse);
  });
}
