import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";

/// What a launch asks for: files to open, and whether to add them to the
/// playlist (`/ADD`, the Enqueue verb) instead of playing them.
typedef LaunchRequest = ({List<String> paths, bool add});

/// Reads a command line such as `amped /ADD a.mp3 b.m3u`.
LaunchRequest parseLaunchArguments(List<String> arguments) {
  var add = false;
  final paths = <String>[];
  for (final argument in arguments) {
    switch (argument.toUpperCase()) {
      case "-a":
      case "--add":
      case "/ADD":
        add = true;
      case "-p":
      case "--play":
      case "/PLAY":
        add = false;
      default:
        final exists =
            FileSystemEntity.typeSync(argument) !=
            FileSystemEntityType.notFound;
        if (exists || argument.contains("://")) {
          paths.add(argument);
        }
    }
  }
  return (paths: paths, add: add);
}

/// Keeps one amped running on Windows and Linux, as the original does: a
/// second launch hands its command line to the first (over a loopback
/// socket named in a file only this user can read) and exits.
class SingleInstance {
  SingleInstance._(this._server, this._token);

  final ServerSocket _server;
  final String _token;

  /// Called with each request a later launch hands over.
  ValueChanged<LaunchRequest>? onRequest;

  static Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File("${support.path}/amped/instance");
  }

  /// Hands [request] to a running instance and returns `null` when there
  /// is one; otherwise becomes the running instance. [file] names the
  /// instance (the settings folder's by default).
  static Future<SingleInstance?> claim(
    LaunchRequest request, {
    File? file,
  }) async {
    file ??= await _file();
    try {
      final [port, token] = (await file.readAsString()).trim().split(" ");
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        int.parse(port),
        timeout: const Duration(milliseconds: 500),
      );
      socket.write(
        jsonEncode({
          "token": token,
          "paths": request.paths,
          "add": request.add,
        }),
      );
      await socket.flush();
      await socket.close();
      return null;
    } on Object {
      // No instance is running (or its file is stale).
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16),
    ].join();
    await file.parent.create(recursive: true);
    await file.writeAsString("${server.port} $token");
    if (!Platform.isWindows) {
      await Process.run("chmod", ["600", file.path]);
    }
    return SingleInstance._(server, token).._listen();
  }

  /// Stops receiving requests.
  Future<void> close() => _server.close();

  void _listen() {
    _server.listen((socket) async {
      try {
        final text = await utf8.decoder.bind(socket).join();
        final message = jsonDecode(text) as Map<String, dynamic>;
        if (message["token"] != _token) return;
        onRequest?.call((
          paths: (message["paths"] as List).cast<String>(),
          add: message["add"] == true,
        ));
      } on Object catch (error) {
        Arcane.log(
          "Bad request from another launch",
          metadata: {"error": "$error"},
          level: Level.info,
          module: "SingleInstance",
        );
      } finally {
        socket.destroy();
      }
    });
  }
}
