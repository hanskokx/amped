import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/playlist.dart";

/// An HTTP connection to a playlist entry's URL, opened to find out whether
/// it is a live stream (a Shoutcast or Icecast station) that has to play as
/// it arrives, or a file that can be downloaded first.
///
/// The classic player's `in_mp3` asks for `Icy-MetaData: 1`, so a station interleaves
/// its song titles with the audio every `icy-metaint` bytes, and plays the
/// response as it comes in.
class NetworkStream {
  NetworkStream._(this._client, this._response);

  final HttpClient _client;
  final HttpClientResponse _response;

  /// Whether [location] is fetched over HTTP: a station or a file on a web
  /// server.
  static bool isHttp(String location) {
    final lower = location.toLowerCase();
    return lower.startsWith("http://") || lower.startsWith("https://");
  }

  /// Whether [url] names a playlist file (`.pls`, `.m3u`, `.m3u8`), such as
  /// the station links on directory.shoutcast.com, rather than audio.
  static bool isPlaylistUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? "";
    final dot = path.lastIndexOf(".");
    if (dot < 0) return false;
    return Playlist.listExtensions.contains(
      path.substring(dot + 1).toLowerCase(),
    );
  }

  /// The stream a playlist file at [url] points to: its first entry, or
  /// [url] itself when it isn't a playlist file or can't be read. The classic player
  /// does the same when it is asked to play a `.pls` link.
  static Future<String> resolvePlaylist(
    String url, {
    HttpClient? client,
  }) async {
    if (!isHttp(url) || !isPlaylistUrl(url)) return url;
    final http = client ?? HttpClient();
    http.userAgent = "amped";
    try {
      final request = await http
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        unawaited(response.drain<void>().catchError((_) {}));
        return url;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 1 << 20) return url;
      }
      final items = Playlist.parseListText(
        utf8.decode(bytes, allowMalformed: true),
        isPls: Uri.parse(url).path.toLowerCase().endsWith(".pls"),
      );
      for (final item in items) {
        if (isHttp(item.location)) return item.location;
      }
      return url;
    } on Object {
      return url;
    } finally {
      http.close(force: true);
    }
  }

  /// Connects to [url]; throws when the server can't be reached or doesn't
  /// answer 200.
  static Future<NetworkStream> open(String url, {HttpClient? client}) async {
    final http = client ?? HttpClient();
    http.userAgent = "amped";
    try {
      final request = await http.getUrl(Uri.parse(url));
      request.headers.set("Icy-MetaData", "1");
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        unawaited(response.drain<void>().catchError((_) {}));
        throw HttpException("HTTP ${response.statusCode}", uri: Uri.parse(url));
      }
      return NetworkStream._(http, response);
    } on Object {
      http.close(force: true);
      rethrow;
    }
  }

  /// How many audio bytes come between two metadata blocks (`icy-metaint`),
  /// or 0 when the server sends none.
  int get icyMetaInt =>
      int.tryParse(_response.headers.value("icy-metaint")?.trim() ?? "") ?? 0;

  /// The station's name (`icy-name`), when it gives one.
  String? get stationName {
    final name = _response.headers.value("icy-name")?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// The bitrate in kbps the station announces (`icy-br`), or null.
  int? get bitrate => _headerInt("icy-br");

  /// The sample rate in Hz the station announces (`icy-sr`), or null.
  int? get sampleRate => _headerInt("icy-sr");

  int? _headerInt(String name) {
    // Some stations list several values ("128,128"); the first is the one.
    final value = _response.headers.value(name)?.split(",").first.trim();
    final number = int.tryParse(value ?? "");
    return number == null || number <= 0 ? null : number;
  }

  /// Whether this is a live stream: a station (it sends `icy-*` headers) or
  /// a response with no length. Such a stream never ends by itself, so it
  /// can't be downloaded before it plays.
  bool get isLive =>
      _response.contentLength < 0 ||
      _response.headers.value("icy-metaint") != null ||
      _response.headers.value("icy-name") != null;

  /// The audio as it arrives, with the station's metadata blocks taken out
  /// and handed to [onMetadata] instead.
  Stream<Uint8List> audio({void Function(IcyMetadata)? onMetadata}) {
    final demuxer = IcyDemuxer(icyMetaInt, onMetadata: onMetadata);
    return _response.expand(
      (chunk) => demuxer.add(
        chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
      ),
    );
  }

  /// Drops the connection.
  void close() => _client.close(force: true);
}

/// A metadata block of a Shoutcast/Icecast stream, as the classic player's `in_mp3`
/// reads it: `StreamTitle='Artist - Title';StreamUrl='...';`.
class IcyMetadata {
  const IcyMetadata({this.title, this.url});

  /// Parses a metadata block's text; the fields are `key='value';` pairs
  /// whose values may themselves contain quotes.
  factory IcyMetadata.parse(String text) {
    final fields = <String, String>{};
    for (final match in RegExp(
      r"(\w+)='(.*?)';(?=\w+='|\s*$)",
      dotAll: true,
    ).allMatches(text.replaceAll("\u0000", "").trim())) {
      fields[match.group(1)!.toLowerCase()] = match.group(2)!;
    }
    String? field(String name) {
      final value = fields[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return IcyMetadata(title: field("streamtitle"), url: field("streamurl"));
  }

  /// What is playing now (`StreamTitle`), usually "Artist - Title".
  final String? title;

  /// A link the station sends along (`StreamUrl`).
  final String? url;
}

/// Splits a stream sent with `icy-metaint` into its audio and its metadata
/// blocks: after every [metaInt] audio bytes comes one length byte (the
/// block's size in 16-byte units) and then the block, padded with zeros.
class IcyDemuxer {
  IcyDemuxer(this.metaInt, {this.onMetadata});

  /// The audio bytes between two metadata blocks; 0 for a stream without
  /// metadata, which passes through untouched.
  final int metaInt;

  /// Called with each non-empty metadata block.
  final void Function(IcyMetadata)? onMetadata;

  /// Audio bytes left before the next length byte.
  late int _audioLeft = metaInt;

  /// The metadata block being collected, once its length byte was read.
  BytesBuilder? _block;
  int _blockLeft = 0;

  /// Takes the next [chunk] of the response and returns its audio.
  List<Uint8List> add(Uint8List chunk) {
    if (metaInt <= 0) return [chunk];
    final audio = <Uint8List>[];
    var i = 0;
    while (i < chunk.length) {
      if (_audioLeft > 0) {
        final end = i + _audioLeft < chunk.length
            ? i + _audioLeft
            : chunk.length;
        audio.add(Uint8List.sublistView(chunk, i, end));
        _audioLeft -= end - i;
        i = end;
      } else if (_block == null) {
        _blockLeft = chunk[i++] * 16;
        if (_blockLeft == 0) {
          _audioLeft = metaInt;
        } else {
          _block = BytesBuilder(copy: false);
        }
      } else {
        final end = i + _blockLeft < chunk.length
            ? i + _blockLeft
            : chunk.length;
        _block!.add(Uint8List.sublistView(chunk, i, end));
        _blockLeft -= end - i;
        i = end;
        if (_blockLeft == 0) {
          final bytes = _block!.takeBytes();
          _block = null;
          _audioLeft = metaInt;
          onMetadata?.call(IcyMetadata.parse(_decode(bytes)));
        }
      }
    }
    return audio;
  }

  /// Stations send UTF-8 or, older ones, Latin-1.
  static String _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
