import "dart:io";

import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/playlist_search.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  int? score(String query, PlaylistEntry entry) =>
      PlaylistSearch.scoreEntry(PlaylistSearch.words(query), entry);

  test("every word must be found, in any order, in any case", () {
    final entry = PlaylistEntry("/music/queen/a.mp3")
      ..title = "Queen - Bohemian Rhapsody";
    expect(score("bohemian queen", entry), isNotNull);
    expect(score("RHAPSODY", entry), isNotNull);
    expect(score("queen jazz", entry), isNull);
  });

  test("searches tags, genres and the file name too", () {
    final entry = PlaylistEntry("/music/disc1/07-track.flac")
      ..title = "Seven"
      ..artist = "The Band"
      ..album = "Greatest Hits"
      ..genres = ["Rock"];
    expect(score("band", entry), isNotNull);
    expect(score("greatest", entry), isNotNull);
    expect(score("rock", entry), isNotNull);
    expect(score("07-track", entry), isNotNull);
    // The folder is not part of what the playlist shows.
    expect(score("disc1", entry), isNull);
  });

  test("letters in order find a longer word, but short words stay exact", () {
    final entry = PlaylistEntry("/a.mp3")..title = "Bohemian Rhapsody";
    expect(score("bhmn", entry), isNotNull);
    expect(score("bhy", entry), isNull);
    // Two letters are not enough to be loose with.
    expect(score("bm", entry), isNull);
    expect(score("rh", entry), isNotNull);
  });

  test("a loose match does not reach across a long title", () {
    final entry = PlaylistEntry("/a.mp3")
      ..title = "A very long title that has quite a few words in it indeed";
    expect(score("avqz", entry), isNull);
    expect(score("avxx", entry), isNull);
  });

  test("better matches come first, then playlist order", () async {
    final dir = Directory.systemTemp.createTempSync("playlist_search");
    addTearDown(() => dir.deleteSync(recursive: true));
    final names = ["xlove.mp3", "Love Song.mp3", "Other.mp3", "Love Me.mp3"];
    for (final name in names) {
      File("${dir.path}/$name").createSync();
    }
    final playlist = Playlist();
    await playlist.add([for (final name in names) "${dir.path}/$name"]);

    final matches = PlaylistSearch.search(playlist, "love");
    expect(matches.map((m) => m.index), [1, 3, 0]);
    expect(PlaylistSearch.search(playlist, "  "), isEmpty);
  });
}
