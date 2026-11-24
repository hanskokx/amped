import "dart:async";
import "dart:io";

import "package:smb_connect/smb_connect.dart";

import "remote_credentials.dart";
import "remote_file_system.dart";
import "remote_location.dart";

/// A Samba (SMB 1 / 2) share, through the pure-Dart `smb_connect`.
class SmbFileSystem implements RemoteFileSystem {
  SmbFileSystem._(this._connection);

  final SmbConnect _connection;

  static Future<SmbFileSystem> connect(RemoteLocation location) async {
    final user = location.userName;
    try {
      final connection = await SmbConnect.connectAuth(
        host: location.host,
        domain: location.domain,
        username: user ?? "guest",
        password: location.password ?? "",
      );
      return SmbFileSystem._(connection);
    } on Object catch (error) {
      // Not reaching the server is not a login problem; the rest (a
      // refused logon, no guest access) is.
      if (error is SocketException ||
          error is TimeoutException ||
          error.toString().startsWith("Can't connect")) {
        rethrow;
      }
      throw RemoteAuthException("$error");
    }
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    // The root of a server holds its shares.
    final files = path == "/"
        ? await _connection.listShares()
        : await _connection.listFiles(await _connection.file(_folder(path)));
    return [
      for (final file in files)
        if (_name(file.name) case final name
            when name.isNotEmpty && name != "." && name != "..")
          RemoteEntry(name, isDirectory: path == "/" || file.isDirectory()),
    ];
  }

  @override
  Future<void> download(
    String path,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final file = await _connection.file(path);
    if (!file.isExists) throw RemoteFileException("$path not found");
    final sink = destination.openWrite();
    var received = 0;
    try {
      await sink.addStream(
        (await _connection.openRead(file)).map((chunk) {
          received += chunk.length;
          onProgress?.call(received, file.size);
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
  }

  @override
  Future<int> size(String path) async {
    final file = await _connection.file(path);
    if (!file.isExists) throw RemoteFileException("$path not found");
    return file.size;
  }

  @override
  Stream<List<int>> openRead(String path, int start, [int? end]) async* {
    final file = await _connection.file(path);
    if (!file.isExists) throw RemoteFileException("$path not found");
    yield* await _connection.openRead(file, start, end);
  }

  @override
  Future<void> close() => _connection.close();

  static String _folder(String path) => path.endsWith("/") ? path : "$path/";

  static String _name(String name) =>
      name.endsWith("/") ? name.substring(0, name.length - 1) : name;
}
