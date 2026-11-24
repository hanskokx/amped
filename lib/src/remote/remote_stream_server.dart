import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";

import "remote_file_system.dart";

/// Opens the connection a file of a share is read over.
typedef RemoteConnector = Future<RemoteFileSystem> Function();

/// Serves files of network shares on `127.0.0.1` with `Range` support, so a
/// player that only opens URLs (mpv) can read a file on a share as it plays,
/// and seek in it, without a copy on this machine.
class RemoteStreamServer {
  HttpServer? _server;

  static const int _kept = 8;

  final Map<String, _Served> _files = {};
  int _next = 0;

  /// Makes [path] (on the share [connect] reaches) available, and returns
  /// its URL. Throws when the file can't be read.
  Future<String> serve(String path, RemoteConnector connect) async {
    final system = await connect();
    final int size;
    try {
      size = await system.size(path);
    } on Object {
      await system.close();
      rethrow;
    }
    final server = _server ??= await _start();
    final token = "${_next++}";
    _files[token] = _Served(path, size, connect)..idle = system;
    // Only the latest few are kept; a player has hold of the newest.
    while (_files.length > _kept) {
      final old = _files.remove(_files.keys.first);
      unawaited(old?.idle?.close());
    }
    final name = Uri.encodeComponent(path.split("/").last);
    return "http://127.0.0.1:${server.port}/$token/$name";
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) => unawaited(_handle(request))),
    );
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final token = request.uri.pathSegments.firstOrNull;
      final file = token == null ? null : _files[token];
      if (file == null ||
          (request.method != "GET" && request.method != "HEAD")) {
        response.statusCode = file == null
            ? HttpStatus.notFound
            : HttpStatus.methodNotAllowed;
        return;
      }
      final range = parseRange(
        request.headers.value(HttpHeaders.rangeHeader),
        file.size,
      );
      response.headers.set(HttpHeaders.acceptRangesHeader, "bytes");
      response.headers.contentType = ContentType.binary;
      if (range == null &&
          request.headers.value(HttpHeaders.rangeHeader) != null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          "bytes */${file.size}",
        );
        return;
      }
      final (start, end) = range ?? (0, file.size);
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          "bytes $start-${end - 1}/${file.size}",
        );
      }
      response.contentLength = end - start;
      if (request.method == "HEAD" || end <= start) return;
      final system = file.idle ?? await file.connect();
      file.idle = null;
      var reusable = false;
      try {
        await response.addStream(system.openRead(file.path, start, end));
        reusable = true;
      } finally {
        if (reusable && file.idle == null && _files.containsValue(file)) {
          file.idle = system;
        } else {
          unawaited(system.close());
        }
      }
    } on Object catch (error) {
      // The player went away mid-file, or the share did.
      if (error is! SocketException && error is! HttpException) {
        Arcane.log(
          "Remote stream failed",
          level: Level.warning,
          module: "RemoteStreamServer",
          metadata: {"error": "$error"},
        );
      }
    } finally {
      try {
        await response.close();
      } on Object {
        // Already gone.
      }
    }
  }

  /// The first and one past the last byte [header] asks for in a file of
  /// [size] bytes, `null` for no (or an unsatisfiable) range. A header that
  /// is not a single byte range is no range.
  static (int, int)? parseRange(String? header, int size) {
    if (header == null) return null;
    final match = RegExp(r"^bytes=(\d*)-(\d*)$").firstMatch(header.trim());
    if (match == null) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty && last.isEmpty) return null;
    if (first.isEmpty) {
      // The last bytes.
      final count = int.parse(last);
      if (count == 0) return null;
      return (count >= size ? 0 : size - count, size);
    }
    final start = int.parse(first);
    if (start >= size) return null;
    final end = last.isEmpty ? size : int.parse(last) + 1;
    if (end <= start) return null;
    return (start, end > size ? size : end);
  }

  /// Stops serving and ends the connections.
  Future<void> close() async {
    final files = _files.values.toList();
    _files.clear();
    for (final file in files) {
      await file.idle?.close();
    }
    await _server?.close(force: true);
    _server = null;
  }
}

class _Served {
  _Served(this.path, this.size, this.connect);

  final String path;
  final int size;
  final RemoteConnector connect;

  /// The connection not in use, kept for the next request.
  RemoteFileSystem? idle;
}
