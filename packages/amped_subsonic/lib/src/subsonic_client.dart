import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:amped_media_source/amped_media_source.dart";

import "package:crypto/crypto.dart";

/// The server answered, but with an error (or something that isn't the
/// Subsonic API).
class SubsonicException implements Exception {
  const SubsonicException(this.message);

  final String message;

  @override
  String toString() => "SubsonicException: $message";
}

/// A client for the Subsonic API (1.16.1) that Navidrome and other servers
/// speak: https://www.navidrome.org/docs/developers/subsonic-api/
///
/// Requests are signed with the token scheme: `t=md5(password + salt)` and
/// `s=salt`, so the password itself is never sent. The salt is fixed per
/// client, which keeps the stream URLs of tracks stable between runs.
class SubsonicClient {
  SubsonicClient({
    required String server,
    required this.user,
    required String password,
    String? salt,
    HttpClient? client,
  }) : server = normalizeServer(server),
       salt = salt ?? newSalt(),
       // ignore: prefer_initializing_formals
       _password = password,
       _client = client ?? HttpClient();

  /// A random salt for [SubsonicClient.salt].
  static String newSalt() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 12; i++) random.nextInt(16).toRadixString(16),
    ].join();
  }

  /// [server] without trailing slashes, and with `http://` when it names no
  /// scheme: `https://music.example.com/navidrome`.
  static String normalizeServer(String server) {
    var text = server.trim();
    while (text.endsWith("/")) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isNotEmpty && !text.contains("://")) text = "http://$text";
    return text;
  }

  /// The API version this client says it speaks.
  static const apiVersion = "1.16.1";

  /// How many songs one request asks for.
  static const pageSize = 500;

  final String server;
  final String user;
  final String salt;
  final String _password;
  final HttpClient _client;

  /// The query that signs a request.
  Map<String, String> get _auth => {
    "u": user,
    "t": md5.convert(utf8.encode("$_password$salt")).toString(),
    "s": salt,
    "v": apiVersion,
    "c": "amped",
    "f": "json",
  };

  Uri _uri(String method, [Map<String, String> parameters = const {}]) {
    final base = Uri.parse("$server/rest/$method");
    return base.replace(queryParameters: {..._auth, ...parameters});
  }

  Future<Map<String, dynamic>> _get(
    String method, [
    Map<String, String> parameters = const {},
  ]) async {
    final Map<String, dynamic> body;
    try {
      final request = await _client
          .getUrl(_uri(method, parameters))
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        throw const RemoteAuthException("The server refused the sign-in.");
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw SubsonicException("HTTP ${response.statusCode}");
      }
      final text = await response.transform(utf8.decoder).join();
      final decoded = await decodeJson(text);
      if (decoded is! Map<String, dynamic> ||
          decoded["subsonic-response"] is! Map<String, dynamic>) {
        throw const SubsonicException("Not a Subsonic server.");
      }
      body = decoded["subsonic-response"] as Map<String, dynamic>;
    } on FormatException {
      throw const SubsonicException("Not a Subsonic server.");
    } on SocketException catch (error) {
      throw SubsonicException(error.message);
    } on TimeoutException {
      throw const SubsonicException("The server did not answer.");
    } on HandshakeException catch (error) {
      throw SubsonicException(error.message);
    }
    if (body["status"] != "ok") {
      final error = body["error"];
      final code = error is Map ? error["code"] : null;
      final message = error is Map
          ? "${error["message"] ?? "Error $code"}"
          : "The server reported an error.";
      // 40: wrong name or password; 41: token auth not supported.
      if (code == 40 || code == 41 || code == 44) {
        throw RemoteAuthException(message);
      }
      throw SubsonicException(message);
    }
    return body;
  }

  /// Throws when the server can't be reached or the sign-in is refused.
  Future<void> ping() => _get("ping");

  /// Where [id]'s audio is streamed from, as it came (no transcoding).
  String streamUrl(String id) => _uri("stream", {
    "id": id,
    "format": "raw",
  }).toString();

  /// Where the cover of the song [id] is, scaled to [size] pixels.
  String coverArtUrl(String id, {int size = 600}) => _uri("getCoverArt", {
    "id": id,
    "size": "$size",
  }).toString();

  /// Every song on the server, a page at a time: [onPage] gets each page's
  /// tracks as they arrive. Their paths are [pathOf] of the song's id (the
  /// stream URL when null). Stops after the page it is on when [isCancelled]
  /// says so.
  Future<void> songs({
    required void Function(List<TrackTags> page) onPage,
    String Function(String id)? pathOf,
    bool Function()? isCancelled,
  }) async {
    for (var offset = 0; ; offset += pageSize) {
      if (isCancelled?.call() ?? false) return;
      // An empty query matches everything (Navidrome and OpenSubsonic).
      final body = await _get("search3", {
        "query": "",
        "artistCount": "0",
        "albumCount": "0",
        "songCount": "$pageSize",
        "songOffset": "$offset",
      });
      final result = body["searchResult3"];
      final songs = result is Map && result["song"] is List
          ? (result["song"] as List).whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      if (songs.isNotEmpty)
        onPage([for (final song in songs) _track(song, pathOf ?? streamUrl)]);
      if (songs.length < pageSize) return;
    }
  }

  TrackTags _track(
    Map<String, dynamic> song,
    String Function(String id) pathOf,
  ) {
    int? number(String key) => switch (song[key]) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    final id = "${song["id"]}";
    final seconds = number("duration");
    final genre = song["genre"];
    return TrackTags(
      pathOf(id),
      artist: song["artist"] as String?,
      album: song["album"] as String?,
      title: song["title"] as String?,
      trackNumber: number("track"),
      discNumber: number("discNumber"),
      year: number("year"),
      duration: seconds == null ? null : Duration(seconds: seconds),
      bitrate: number("bitRate"),
      sampleRate: number("samplingRate"),
      channels: number("channelCount"),
      genres: [if (genre is String && genre.isNotEmpty) genre],
    );
  }

  void close() => _client.close(force: true);
}
