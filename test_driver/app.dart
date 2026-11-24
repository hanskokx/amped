import "package:amped/main.dart";
import "package:flutter_driver/driver_extension.dart";

Future<void> main() async {
  enableFlutterDriverExtension();
  await runAmped();
}
