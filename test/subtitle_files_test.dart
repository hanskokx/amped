import "dart:io";

import "package:amped/src/player/subtitle_files.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("subtitles are matched by the video's name, with language tags", () {
    final found = matchSubtitles(
      "Heat (1995).mkv",
      [
        "Heat (1995).srt",
        "Heat (1995).en.srt",
        "Heat (1995).fr.forced.ass",
        "Heat (1995).sub",
        "Heat (1995) extras.srt",
        "Alien.srt",
        "Heat (1995).mkv",
      ],
      (name) => "/m/$name",
    );
    expect(
      [for (final e in found) e.key],
      [
        "Heat (1995).en.srt",
        "Heat (1995).fr.forced.ass",
        "Heat (1995).srt",
      ],
    );
    expect(found[0].value.language, "en");
    expect(found[1].value.language, "fr");
    expect(found[2].value.language, isNull);
    expect(found[0].value.location, "/m/Heat (1995).en.srt");
  });

  test(
    "local subtitles come from beside the video and a Subs folder",
    () async {
      final dir = Directory.systemTemp.createTempSync("subs");
      addTearDown(() => dir.deleteSync(recursive: true));
      File("${dir.path}/Movie.mkv").createSync();
      File("${dir.path}/Movie.en.srt").createSync();
      File("${dir.path}/Other.srt").createSync();
      Directory("${dir.path}/Subs").createSync();
      File("${dir.path}/Subs/Movie.de.srt").createSync();
      final found = await localSubtitles("${dir.path}/Movie.mkv");
      expect(
        [for (final f in found) f.title],
        ["Movie.en.srt", "Movie.de.srt"],
      );
      expect(found.last.location, "${dir.path}/Subs/Movie.de.srt");
    },
  );
}
