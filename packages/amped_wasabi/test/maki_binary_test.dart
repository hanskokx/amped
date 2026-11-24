import "dart:io";

import "package:amped_wasabi/src/maki/maki_binary.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";

final Directory _skins = ampedModern;

void main() {
  test("parses Amped Modern's scripts", () {
    final files = _skins
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith(".maki"))
        .toList();
    expect(files, isNotEmpty);
    final unknown = <String>{};
    for (final file in files) {
      final binary = MakiBinary.parse(file.readAsBytesSync());
      expect(binary.code, isNotEmpty, reason: file.path);
      for (final import in binary.imports) {
        if (import.params < 0)
          unknown.add("${import.className}.${import.name}");
      }
    }
    expect(unknown, isEmpty);
  });
}
