import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:dbus/dbus.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";

/// Posts a notification through the operating system: Notification Center
/// on macOS, a toast on Windows, and the desktop's notification daemon
/// (`org.freedesktop.Notifications`) on Linux.
class NativeNotifier {
  NativeNotifier(this._channel);

  final MethodChannel _channel;

  /// Called with the locations a notification carried when the user clicks
  /// it.
  void Function(List<String> locations)? onClicked;

  DBusClient? _bus;
  StreamSubscription<DBusSignal>? _actions;
  List<String> _lastLocations = const [];
  int _lastId = 0;
  String? _lastImage;

  /// Asks the system for permission to post notifications, where it wants
  /// one (macOS), so the prompt appears when the user opts in rather than
  /// with the first track.
  Future<void> requestPermission() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>("requestNotificationPermission");
    } on Object catch (error) {
      Arcane.log(
        "Could not ask for notification permission",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "NativeNotifier",
      );
    }
  }

  /// Shows [title] with [body] below it; a new call replaces the previous
  /// notification, so skipping through tracks does not pile them up.
  ///
  /// [artwork] (an embedded cover, JPEG or PNG) is shown with it on macOS
  /// and Linux.
  ///
  /// [locations] are handed to [onClicked] when the user clicks the
  /// notification (macOS and Linux).
  Future<void> show({
    required String title,
    required String body,
    Uint8List? artwork,
    List<String> locations = const [],
  }) async {
    try {
      final image = Platform.isWindows ? null : await _saveArtwork(artwork);
      if (Platform.isLinux) {
        await _showLinux(title, body, image, locations);
      } else if (Platform.isMacOS || Platform.isWindows) {
        await _channel.invokeMethod<void>("showNotification", {
          "title": title,
          "body": body,
          "image": ?image,
          "locations": locations,
        });
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not show a system notification",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "NativeNotifier",
      );
    }
  }

  /// Writes [artwork] to a file the notification daemon or Notification
  /// Center can read, or returns null when there is none.
  Future<String?> _saveArtwork(Uint8List? artwork) async {
    if (artwork == null || artwork.isEmpty) return null;
    final png = artwork.length > 3 && artwork[0] == 0x89 && artwork[1] == 0x50;
    final directory = await getTemporaryDirectory();
    // A new name each time: Notification Center moves an attachment's file.
    final file = File(
      "${directory.path}/amped-cover-${DateTime.now().microsecondsSinceEpoch}"
      ".${png ? "png" : "jpg"}",
    );
    await file.writeAsBytes(artwork);
    // The previous cover is no longer needed.
    final old = _lastImage;
    _lastImage = file.path;
    if (old != null) unawaited(File(old).delete().catchError((_) => File(old)));
    return file.path;
  }

  Future<void> _showLinux(
    String title,
    String body,
    String? image,
    List<String> locations,
  ) async {
    final bus = _bus ??= DBusClient.session();
    if (_actions == null) _listenForClicks(bus);
    _lastLocations = locations;
    final reply = await bus.callMethod(
      destination: "org.freedesktop.Notifications",
      path: DBusObjectPath("/org/freedesktop/Notifications"),
      interface: "org.freedesktop.Notifications",
      name: "Notify",
      values: [
        const DBusString("Amped"),
        DBusUint32(_lastId),
        const DBusString("amped"),
        DBusString(title),
        DBusString(body),
        // The "default" action is what clicking the notification invokes.
        DBusArray.string(locations.isEmpty ? const [] : const ["default", ""]),
        DBusDict.stringVariant({
          if (image != null) "image-path": DBusString(image),
        }),
        const DBusInt32(-1),
      ],
      replySignature: DBusSignature("u"),
    );
    _lastId = reply.returnValues.first.asUint32();
  }

  void _listenForClicks(DBusClient bus) {
    final signals = DBusRemoteObjectSignalStream(
      object: DBusRemoteObject(
        bus,
        name: "org.freedesktop.Notifications",
        path: DBusObjectPath("/org/freedesktop/Notifications"),
      ),
      interface: "org.freedesktop.Notifications",
      name: "ActionInvoked",
      signature: DBusSignature("us"),
    );
    _actions = signals.listen((signal) {
      final id = signal.values[0].asUint32();
      final action = signal.values[1].asString();
      if (id == _lastId && action == "default") onClicked?.call(_lastLocations);
    });
  }

  Future<void> dispose() async {
    await _actions?.cancel();
    _actions = null;
    await _bus?.close();
    _bus = null;
  }
}
