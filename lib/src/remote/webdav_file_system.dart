import "dart:convert";
import "dart:io";

import "package:xml/xml.dart";

import "remote_credentials.dart";
import "remote_file_system.dart";
import "remote_location.dart";

/// A WebDAV server (Nextcloud, a NAS, Apache's `mod_dav`...), over plain
/// HTTP requests: `PROPFIND` lists a folder and `GET` fetches a file.
///
/// Signing in uses HTTP Basic, so a name and password should only be given
/// for an encrypted (`webdavs://`) address.
class WebDavFileSystem implements RemoteFileSystem {
  WebDavFileSystem(this._location, {HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.userAgent = "amped";
    final user = _location.user;
    if (user != null) {
      final login = base64.encode(
        utf8.encode("$user:${_location.password ?? ""}"),
      );
      _authorization = "Basic $login";
    }
  }

  /// Connects, checking the login with a request for the folder.
  static Future<WebDavFileSystem> connect(RemoteLocation location) async {
    final system = WebDavFileSystem(location);
    try {
      await system._check(location.path);
    } on Object {
      await system.close();
      rethrow;
    }
    return system;
  }

  Future<void> _check(String path) async {
    final response = await _send(
      "PROPFIND",
      _uri(path, folder: true),
      headers: {"Depth": "0"},
    );
    await response.drain<void>();
    _checkStatus(response.statusCode);
  }

  static void _checkStatus(int status) {
    if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
      throw RemoteAuthException("HTTP $status");
    }
  }

  final RemoteLocation _location;
  final HttpClient _client;
  String? _authorization;

  Uri _uri(String path, {bool folder = false}) {
    final segments = [
      for (final segment in path.split("/"))
        if (segment.isNotEmpty) segment,
    ];
    return Uri(
      scheme: _location.secure ? "https" : "http",
      host: _location.host,
      port: _location.port,
      pathSegments: [...segments, if (folder) ""],
    );
  }

  Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    final authorization = _authorization;
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType("application", "xml");
      request.add(utf8.encode(body));
    }
    return request.close();
  }

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final uri = _uri(path, folder: true);
    final response = await _send(
      "PROPFIND",
      uri,
      headers: {"Depth": "1"},
      body:
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:">'
          " <d:prop><d:resourcetype/></d:prop></d:propfind>",
    );
    final text = await utf8.decodeStream(response);
    _checkStatus(response.statusCode);
    // 207 Multi-Status is the answer.
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw HttpException("HTTP ${response.statusCode}", uri: uri);
    }
    final here = Uri.decodeComponent(_normalize(uri.path));
    final entries = <RemoteEntry>[];
    for (final item in XmlDocument.parse(text).descendantElements.where(
      (element) => element.name.local == "response",
    )) {
      final href = item.childElements
          .where((element) => element.name.local == "href")
          .firstOrNull;
      if (href == null) continue;
      final hrefPath = Uri.tryParse(href.innerText.trim())?.path;
      if (hrefPath == null) continue;
      final normal = Uri.decodeComponent(_normalize(hrefPath));
      // The folder itself is listed along with what is in it.
      if (normal == here) continue;
      final name = normal.split("/").last;
      if (name.isEmpty) continue;
      final isFolder = item.descendantElements.any(
        (element) => element.name.local == "collection",
      );
      entries.add(RemoteEntry(name, isDirectory: isFolder));
    }
    return entries;
  }

  /// A path without its trailing slash.
  static String _normalize(String path) {
    var normal = path;
    while (normal.length > 1 && normal.endsWith("/")) {
      normal = normal.substring(0, normal.length - 1);
    }
    return normal;
  }

  @override
  Future<void> download(
    String path,
    File destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = _uri(path);
    final response = await _send("GET", uri);
    if (response.statusCode == HttpStatus.unauthorized) {
      await response.drain<void>();
      _checkStatus(response.statusCode);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException("HTTP ${response.statusCode}", uri: uri);
    }
    final sink = destination.openWrite();
    try {
      final total = response.contentLength < 0 ? null : response.contentLength;
      var received = 0;
      await sink.addStream(
        response.map((chunk) {
          received += chunk.length;
          onProgress?.call(received, total);
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
  }

  @override
  Future<int> size(String path) async {
    final uri = _uri(path);
    final response = await _send("HEAD", uri);
    await response.drain<void>();
    _checkStatus(response.statusCode);
    if (response.statusCode != HttpStatus.ok || response.contentLength < 0) {
      throw HttpException("HTTP ${response.statusCode}", uri: uri);
    }
    return response.contentLength;
  }

  @override
  Stream<List<int>> openRead(String path, int start, [int? end]) async* {
    final uri = _uri(path);
    final response = await _send(
      "GET",
      uri,
      headers: {
        HttpHeaders.rangeHeader: "bytes=$start-${end == null ? "" : end - 1}",
      },
    );
    _checkStatus(response.statusCode);
    final ranged = response.statusCode == HttpStatus.partialContent;
    if (!ranged && response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException("HTTP ${response.statusCode}", uri: uri);
    }
    // A server that ignores Range sends the whole file: skip to [start]
    // and stop at [end] here.
    var skip = ranged ? 0 : start;
    var left = end == null ? null : end - start;
    await for (final chunk in response) {
      var data = chunk;
      if (skip > 0) {
        if (skip >= data.length) {
          skip -= data.length;
          continue;
        }
        data = data.sublist(skip);
        skip = 0;
      }
      if (left != null) {
        if (data.length >= left) {
          yield data.sublist(0, left);
          return;
        }
        left -= data.length;
      }
      yield data;
    }
  }

  @override
  Future<void> close() async => _client.close(force: true);
}
