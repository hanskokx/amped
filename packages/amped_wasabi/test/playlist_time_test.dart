import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("playlist item times read m:ss under an hour", () {
    expect(formatPlaylistItemTime(0), "0:00");
    expect(formatPlaylistItemTime(168000), "2:48");
    expect(formatPlaylistItemTime(3599999), "59:59");
  });

  test("playlist item times read h:mm:ss from an hour", () {
    expect(formatPlaylistItemTime(3600000), "1:00:00");
    expect(formatPlaylistItemTime(3907000), "1:05:07");
  });

  test("an unknown length is blank", () {
    expect(formatPlaylistItemTime(-1), "");
  });
}
