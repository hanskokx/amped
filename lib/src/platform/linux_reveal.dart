import "dart:io";

import "package:dbus/dbus.dart";

/// Shows [paths] selected in the desktop's file manager through
/// `org.freedesktop.FileManager1.ShowItems`, as Finder's "Reveal" does on
/// macOS. Where no file manager answers, each folder is opened with
/// `xdg-open` instead.
Future<void> revealInLinuxFileManager(List<String> paths) async {
  final client = DBusClient.session();
  try {
    await client.callMethod(
      destination: "org.freedesktop.FileManager1",
      path: DBusObjectPath("/org/freedesktop/FileManager1"),
      interface: "org.freedesktop.FileManager1",
      name: "ShowItems",
      values: [
        DBusArray.string([for (final path in paths) File(path).uri.toString()]),
        const DBusString(""),
      ],
      replySignature: DBusSignature(""),
    );
    return;
  } on Object {
    // No file manager on the bus: fall back to opening the folders.
  } finally {
    await client.close();
  }
  final folders = {for (final path in paths) File(path).parent.path};
  for (final folder in folders) {
    await Process.start("xdg-open", [folder]);
  }
}
