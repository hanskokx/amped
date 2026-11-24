// Takes the YouTube feature out of the app: the amped_youtube and amped_ytdlp
// dependencies become inert stand-ins (tool/no_youtube), the yt-dlp bundling
// step of the macOS build goes, and so do the tests of the feature.
//
//   dart run tool/strip_youtube.dart
//
// Run from the repository root before `flutter pub get`. The working tree is
// changed in place (it is meant for a CI checkout).
import "dart:io";

/// The text of [file] with LF line ends (a Windows checkout has CRLF).
String _read(File file) => file.readAsStringSync().replaceAll("\r\n", "\n");

void main() {
  var pubspec = _read(File("pubspec.yaml"));
  for (final name in ["amped_youtube", "amped_ytdlp"]) {
    final dependency = RegExp(
      "^  $name:\n(?:    .*\n)+",
      multiLine: true,
    );
    if (!dependency.hasMatch(pubspec)) {
      stderr.writeln("error: $name is not a dependency in pubspec.yaml");
      exit(1);
    }
    pubspec = pubspec.replaceFirst(
      dependency,
      "  $name:\n    path: tool/no_youtube/$name\n",
    );
  }
  File("pubspec.yaml").writeAsStringSync(pubspec);

  // macOS: no "Bundle yt-dlp" build phase.
  final project = File("macos/Runner.xcodeproj/project.pbxproj");
  var text = _read(project);
  text = text.replaceAll(
    RegExp(r"^\t+[0-9A-F]+ /\* Bundle yt-dlp \*/,\n", multiLine: true),
    "",
  );
  text = text.replaceFirst(
    RegExp(
      r"^\t\t[0-9A-F]+ /\* Bundle yt-dlp \*/ = \{\n.*?^\t\t\};\n",
      multiLine: true,
      dotAll: true,
    ),
    "",
  );
  project.writeAsStringSync(text);
  if (text.contains("yt-dlp")) {
    stderr.writeln("error: the Xcode project still mentions yt-dlp");
    exit(1);
  }
  final bundle = File("macos/bundle_yt_dlp.sh");
  if (bundle.existsSync()) bundle.deleteSync();

  for (final file in Directory("test").listSync()) {
    final name = file.uri.pathSegments.last;
    if (file is File && name.startsWith("youtube_")) file.deleteSync();
  }

  final lock = File("pubspec.lock");
  if (lock.existsSync()) lock.deleteSync();
  stdout.writeln("YouTube support removed.");
}
