import "dart:io";

import "package:amped_wasabi/src/wasabi_path.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  final s = Platform.pathSeparator;

  test("a script's Windows path gets this system's separators", () {
    expect(
      wasabiNativePath(r"C:\Music\Rock/a.mp3"),
      "C:${s}Music${s}Rock${s}a.mp3",
    );
    // The folder name ends in a separator and the script adds another.
    expect(wasabiNativePath(r"/Users/x/\a.mp3"), "${s}Users${s}x${s}a.mp3");
  });

  test("a URL is left alone", () {
    expect(wasabiNativePath("http://host/a\\b.mp3"), "http://host/a\\b.mp3");
    expect(wasabiNativePath("cda://1"), "cda://1");
  });

  test("paths that differ in their separators are the same path", () {
    expect(wasabiSamePath(r"/Users/x/\a.mp3", "/Users/x/a.mp3"), isTrue);
    expect(wasabiSamePath(r"C:\a\b", "C:/a/b"), isTrue);
    expect(wasabiSamePath(r"/Users/x/a.mp3", "/Users/x/b.mp3"), isFalse);
    expect(wasabiSamePath(r"http://a\b", "http://a/b"), isFalse);
  });
}
