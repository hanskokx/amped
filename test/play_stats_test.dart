import "package:amped/src/library/play_stats.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("most played lists songs by play count", () async {
    final store = MemoryTagCache();
    final stats = PlayStats(() => store);
    await stats.record("a.mp3", PlayKind.music, title: "A", artist: "X");
    await stats.record("b.mp3", PlayKind.music, title: "B");
    await stats.record("b.mp3", PlayKind.music, title: "B");
    await stats.record("v.mp4", PlayKind.video, title: "V");

    final rows = stats.mostPlayed(PlayKind.music);
    expect(rows.map((r) => r.label), ["B", "X - A"]);
    expect(rows.first.plays, 2);
    expect(stats.mostPlayed(PlayKind.video).single.label, "V");
    expect(store.plays["b.mp3"]!.plays, 2);
  });

  test("podcasts are counted by podcast, not by episode", () async {
    final stats = PlayStats(() => MemoryTagCache());
    await stats.record("e1", PlayKind.podcast, title: "E1", album: "Show");
    await stats.record("e2", PlayKind.podcast, title: "E2", album: "Show");
    await stats.record("e3", PlayKind.podcast, title: "E3", album: "Other");

    final rows = stats.mostPlayed(PlayKind.podcast);
    expect(rows.map((r) => (r.label, r.plays)), [("Show", 2), ("Other", 1)]);
    expect(rows.first.location, isNull);
    expect(stats.mostPlayed(PlayKind.music), isEmpty);
  });

  test("counts survive a restart", () async {
    final store = MemoryTagCache();
    await PlayStats(() => store).record("a.mp3", PlayKind.music, title: "A");
    final again = PlayStats(() => store);
    await again.load();
    expect(again.playsOf("a.mp3"), 1);
  });

  test("a sqlite store keeps and increments counts", () async {
    final store = await SqliteTagCache.open(":memory:");
    addTearDown(store.close);
    await store.recordPlay("a.mp3", PlayKind.music, title: "A");
    await store.recordPlay("a.mp3", PlayKind.music);
    final stat = (await store.playStats()).single;
    expect(stat.plays, 2);
    expect(stat.title, "A");
  });

  test("a track counts after half of it, at most four minutes", () {
    expect(
      PlayerState.playedEnough(
        const Duration(seconds: 59),
        const Duration(minutes: 2),
      ),
      isFalse,
    );
    expect(
      PlayerState.playedEnough(
        const Duration(minutes: 1),
        const Duration(minutes: 2),
      ),
      isTrue,
    );
    expect(
      PlayerState.playedEnough(
        const Duration(minutes: 4),
        const Duration(hours: 2),
      ),
      isTrue,
    );
  });
}
