import "dart:math";

import "package:amped/src/library/playlist_generator.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const a1 = TrackTags("a1", artist: "A", album: "X", genres: ["Rock"]);
  const a2 = TrackTags("a2", artist: "a ", album: "Y", genres: ["Pop"]);
  const b1 = TrackTags("b1", artist: "B", album: "X", genres: ["Jazz"]);
  const c1 = TrackTags("c1", artist: "C", album: "Z", genres: ["rock"]);
  const d1 = TrackTags("d1", artist: "D", album: "W", genres: ["Jazz"]);
  const none = TrackTags("n");
  const library = [a1, a2, b1, c1, d1, none];

  List<String> run(
    PlaylistCriterion criterion, {
    List<TrackTags> seeds = const [a1],
    int limit = 50,
  }) => PlaylistGenerator.generate(
    library: library,
    seeds: seeds,
    criterion: criterion,
    limit: limit,
    random: Random(1),
  );

  test("same artist ignores case and spacing, seeds come first", () {
    expect(run(PlaylistCriterion.artist), ["a1", "a2"]);
  });

  test("same album and same genre", () {
    expect(run(PlaylistCriterion.album), ["a1", "b1"]);
    expect(run(PlaylistCriterion.genre), ["a1", "c1"]);
  });

  test("similar puts the closest first", () {
    // a2: artist (3); b1: album (1); c1: genre (2).
    expect(run(PlaylistCriterion.similar), ["a1", "a2", "c1", "b1"]);
  });

  test("untagged tracks never match, several seeds combine", () {
    expect(run(PlaylistCriterion.genre, seeds: [none]), ["n"]);
    expect(run(PlaylistCriterion.genre, seeds: [a1, b1]), [
      "a1",
      "b1",
      ...run(PlaylistCriterion.genre, seeds: [a1, b1]).skip(2),
    ]);
    expect(
      run(PlaylistCriterion.genre, seeds: [a1, b1]).toSet(),
      {"a1", "b1", "c1", "d1"},
    );
  });

  test("the limit counts the seeds, no seeds make nothing", () {
    expect(run(PlaylistCriterion.similar, limit: 2), ["a1", "a2"]);
    expect(run(PlaylistCriterion.similar, seeds: []), isEmpty);
  });
}
