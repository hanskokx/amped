import "dart:io";

import "package:amped/src/player/playlist.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("library_tags"));
  tearDown(() => dir.deleteSync(recursive: true));

  String mp3(String name, Map<String, String> tags) {
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
        for (final MapEntry(:key, :value) in tags.entries) ...[
          "-metadata",
          "$key=$value",
        ],
        path,
      ]).exitCode,
      0,
    );
    return path;
  }

  test("a file with only a title keeps it, and its length", () async {
    final path = mp3("title_only", {"title": "June"});
    final tags = (await readTagsInBackground([path])).single!;
    expect(tags.title, "June");
    expect(tags.artist, isNull);
    expect(tags.duration, isNotNull);
  });

  test("a fully tagged file is read as it is", () async {
    final path = mp3("full", {
      "title": "June",
      "artist": "Florence + The Machine",
      "album": "High As Hope",
      "track": "1/10",
    });
    final tags = (await readTagsInBackground([path])).single!;
    expect(tags.title, "June");
    expect(tags.artist, "Florence + The Machine");
    expect(tags.album, "High As Hope");
    expect(tags.trackNumber, 1);
  });
}
