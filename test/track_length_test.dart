import "package:amped/src/player/player_state.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("track lengths read m:ss under an hour", () {
    expect(formatTrackLength(const Duration(seconds: 168)), "2:48");
    expect(formatTrackLength(const Duration(seconds: 3599)), "59:59");
  });

  test("track lengths read h:mm:ss from an hour", () {
    expect(formatTrackLength(const Duration(hours: 1)), "1:00:00");
    expect(
      formatTrackLength(const Duration(hours: 2, minutes: 3, seconds: 4)),
      "2:03:04",
    );
  });
}
