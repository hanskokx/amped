import "package:amped/src/tags/path_hints.dart";
import "package:amped/src/tags/tag_lookup.dart";
import "package:amped/src/tags/tag_model.dart";
import "package:flutter_test/flutter_test.dart";

TagCandidate _c(String album, String track, {String year = "1989"}) =>
    TagCandidate(
      fields: {
        TagField.title: "I'm Over Dreaming (Over You)",
        TagField.artist: "Kylie Minogue",
        TagField.album: album,
        TagField.track: track,
        TagField.year: year,
      },
      score: 0.98,
      recordingId: "r",
      releaseId: null,
    );

void main() {
  test("parses artist, album, year, track and title from the path", () {
    final h = PathHints.parse(
      "/Volumes/Music/Kylie Minogue/Enjoy Yourself (1989)/07. I'm Over Dreaming (Over You).mp3",
    );
    expect(h.artist, "Kylie Minogue");
    expect(h.album, "Enjoy Yourself");
    expect(h.year, "1989");
    expect(h.track, 7);
    expect(h.title, "I'm Over Dreaming (Over You)");
  });

  test("reads a track number between dashes in the file name", () {
    final h = PathHints.parse(
      "/m/Florence + the Machine/High as Hope (2018)/Florence + the Machine - High as Hope - 01 - June.mp3",
    );
    expect(h.track, 1);
    expect(h.title, "June");
    expect(h.album, "High as Hope");
  });

  test("a title that starts with digits isn't a track number", () {
    expect(PathHints.parse("/m/a/b/1979.mp3").track, isNull);
  });

  test("candidates matching the path come first, otherwise in order", () {
    final ranked = rankByPath([
      _c("Divertite", "7/10", year: "1989"),
      _c("Other Hits", "3/12", year: "2005"),
      _c("Enjoy Yourself", "8/11"),
      _c("Enjoy Yourself", "7/10"),
    ], "/m/Kylie Minogue/Enjoy Yourself (1989)/07. I'm Over Dreaming.mp3");
    expect(
      [for (final c in ranked) "${c[TagField.album]} ${c[TagField.track]}"],
      [
        "Enjoy Yourself 7/10",
        "Enjoy Yourself 8/11",
        "Divertite 7/10",
        "Other Hits 3/12",
      ],
    );
  });
}
