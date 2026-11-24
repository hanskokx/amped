import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// Log lines are searched for, so a message is a fixed sentence and every
/// value it is about goes in `metadata`.
void main() {
  test("no Arcane.log message has a value interpolated into it", () {
    final calls = RegExp(r'Arcane\.log\(\s*((?:"(?:[^"\\]|\\.)*"\s*)+)');
    final offenders = <String>[];
    for (final file in _sources()) {
      final text = file.readAsStringSync();
      for (final match in calls.allMatches(text)) {
        if (match.group(1)!.contains(r"$")) {
          final line = text.substring(0, match.start).split("\n").length;
          offenders.add("${file.path}:$line");
        }
      }
    }
    expect(offenders, isEmpty, reason: "Move the values to metadata.");
  });

  test("nothing logs with print or debugPrint", () {
    final calls = RegExp(r"(?<![\w.])(?:debugPrint|print)\(");
    final offenders = [
      for (final file in _sources())
        if (calls.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: "Use Arcane.log.");
  });
}

/// The app's code, not its command line tools. (The packages are in their own
/// repositories.)
Iterable<File> _sources() sync* {
  for (final file in Directory("lib").listSync(recursive: true)) {
    if (file is File && file.path.endsWith(".dart")) yield file;
  }
}
