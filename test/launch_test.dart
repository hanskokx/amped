import "dart:async";
import "dart:io";

import "package:amped/src/platform/file_dialogs.dart";
import "package:amped/src/platform/single_instance.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("launch_test"));
  tearDown(() => dir.deleteSync(recursive: true));

  test("reads /ADD and keeps existing paths and URLs", () {
    final track = File("${dir.path}/a.mp3")..createSync();
    final request = parseLaunchArguments([
      "/add",
      track.path,
      "/NOSUCHFLAG",
      "http://example.com/stream",
    ]);
    expect(request.add, isTrue);
    expect(request.paths, [track.path, "http://example.com/stream"]);
    expect(parseLaunchArguments([track.path]).add, isFalse);
  });

  test("a second launch hands its files to the first", () async {
    final file = File("${dir.path}/instance");
    final first = await SingleInstance.claim((
      paths: const [],
      add: false,
    ), file: file);
    expect(first, isNotNull);
    final received = Completer<LaunchRequest>();
    first!.onRequest = received.complete;

    final second = await SingleInstance.claim((
      paths: const ["/x/a.m3u"],
      add: true,
    ), file: file);
    expect(second, isNull);
    final request = await received.future;
    expect(request.paths, ["/x/a.m3u"]);
    expect(request.add, isTrue);

    await first.close();
    final third = await SingleInstance.claim((
      paths: const [],
      add: false,
    ), file: file);
    expect(third, isNotNull, reason: "a stale file is taken over");
    await third!.close();
  });

  test("saved files get the chosen type's extension", () {
    expect(FileDialogs.withExtension("/a/List", ["pls"]), "/a/List.pls");
    expect(FileDialogs.withExtension("/a/List.PLS", ["pls"]), "/a/List.PLS");
    expect(
      FileDialogs.withExtension(r"C:\a.b\List", ["m3u8"]),
      r"C:\a.b\List.m3u8",
    );
    expect(FileDialogs.withExtension("/a/x.txt", ["m3u8"]), "/a/x.txt.m3u8");
    expect(
      FileDialogs.withExtension(
        "/a/x.m3u",
        ["m3u8"],
        [
          ("M3U", ["m3u"]),
          ("M3U8", ["m3u8"]),
        ],
      ),
      "/a/x.m3u",
    );
  });
}
