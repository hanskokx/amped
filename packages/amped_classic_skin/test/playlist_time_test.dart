import "package:amped_classic_skin/src/windows/playlist_window.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("playlist times read m:ss under an hour", () {
    expect(formatPlaylistTime(0), "0:00");
    expect(formatPlaylistTime(168), "2:48");
    expect(formatPlaylistTime(3599), "59:59");
  });

  test("playlist times read h:mm:ss from an hour, hours uncapped", () {
    expect(formatPlaylistTime(3600), "1:00:00");
    expect(formatPlaylistTime(3600 + 5 * 60 + 7), "1:05:07");
    // 25 days: the classic player keeps counting hours rather than adding days.
    expect(formatPlaylistTime(2163084), "600:51:24");
  });
}
