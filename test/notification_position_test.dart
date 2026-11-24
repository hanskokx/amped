import "dart:ui";

import "package:amped/src/app/notification_position.dart";
import "package:amped/src/app/notification_view.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const area = Rect.fromLTWH(0, 0, 1000, 800);
  const size = Size(200, 100);

  test("places the notification in each corner and column", () {
    expect(
      NotificationPosition.topLeft.originIn(area, size),
      const Offset(16, 16),
    );
    expect(
      NotificationPosition.topCenter.originIn(area, size),
      const Offset(400, 16),
    );
    expect(
      NotificationPosition.bottomRight.originIn(area, size),
      const Offset(784, 684),
    );
    expect(
      NotificationPosition.bottomLeft.originIn(area, size),
      const Offset(16, 684),
    );
  });

  test("falls back to bottom right for unknown names", () {
    expect(
      NotificationPosition.fromName(null),
      NotificationPosition.bottomRight,
    );
    expect(
      NotificationPosition.fromName("topCenter"),
      NotificationPosition.topCenter,
    );
  });

  test("the notification text has the position, title, artist and album", () {
    final entry = PlaylistEntry("/music/song.mp3")
      ..trackTitle = "Southern Comfort (Acoustic)"
      ..artist = "Larkin Poe"
      ..album = "An Acoustic Companion"
      ..trackNumber = 3
      ..duration = const Duration(minutes: 3, seconds: 3);
    final text = NotificationText.of(entry, 2, 161);
    expect(text.position, "3 of 161");
    expect(text.title, "Southern Comfort (Acoustic) (3:03)");
    expect(text.artist, "Larkin Poe");
    expect(text.album, "An Acoustic Companion (Track 3)");
  });

  test("an untagged file is named by its file", () {
    final entry = PlaylistEntry("/music/Some Song.mp3")
      ..trackTitle = ""
      ..title = ""
      ..duration = const Duration(minutes: 3, seconds: 34);
    final text = NotificationText.of(entry, 0, 1);
    expect(text.title, "Some Song (3:34)");
    expect(text.artist, isNull);
  });

  group("a podcast episode", () {
    const tags = TrackTags(
      "amped-source://p/x",
      artist: "The New York Times",
      album: "Hard Fork",
      title: "What Jensen Huang's Potential Ouster Could Mean",
      trackNumber: 41,
      duration: Duration(hours: 1, minutes: 2, seconds: 3),
      genres: ["Podcast"],
    );

    test("takes what its source knows when the entry has no tags", () {
      // Restored from a saved playlist, with only its display title.
      final entry = PlaylistEntry("amped-source://p/x")
        ..title = "The New York Times - What Jensen Huang's Potential Ouster";
      final text = NotificationText.of(entry, 0, 1, tags: tags);
      expect(
        text.title,
        "What Jensen Huang's Potential Ouster Could Mean (1:02:03)",
      );
      expect(text.artist, "The New York Times");
      expect(text.album, "Hard Fork (Episode 41)");
    });

    test(
      "is an episode, not a track, and skips an artist that is the show",
      () {
        final entry = PlaylistEntry("amped-source://p/y")
          ..trackTitle = "Episode title"
          ..artist = "Show"
          ..album = "Show"
          ..trackNumber = 7
          ..genres = ["Podcast"];
        final text = NotificationText.of(entry, 0, 3);
        expect(text.artist, isNull);
        expect(text.album, "Show (Episode 7)");
        expect(text.position, "1 of 3");
      },
    );
  });
}
