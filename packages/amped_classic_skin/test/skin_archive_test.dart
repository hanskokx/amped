import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("rejects bytes that are no archive", () {
    expect(
      () => decodeSkinArchive(Uint8List.fromList(List.filled(600, 7))),
      throwsFormatException,
    );
  });
}
