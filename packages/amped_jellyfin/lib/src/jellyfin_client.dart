import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_media_source/amped_media_source.dart";

/// The server answered, but with an error (or something that isn't Jellyfin).
class JellyfinException implements Exception {
  const JellyfinException(this.message);

  final String message;

  @override
  String toString() => "JellyfinException: $message";
}

/// A client for a Jellyfin server's music and video libraries, signed in with
/// a user name and password (which it trades for an access token the first
/// time it needs one): https://api.jellyfin.org/
///
/// Items are named by their id, followed by the extension of their file
/// (`<id>.flac`) so that the player knows what it is going to play.
class JellyfinClient {
  JellyfinClient({
    required String server,
    required this.user,
    required String password,
    HttpClient? client,
  }) : server = normalizeServer(server),
       // ignore: prefer_initializing_formals
       _password = password,
       _client = client ?? HttpClient();

  /// [server] without trailing slashes, and with `http://` when it names no
  /// scheme: `http://nas:8096`.
  static String normalizeServer(String server) {
    var text = server.trim();
    while (text.endsWith("/")) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isNotEmpty && !text.contains("://")) text = "http://$text";
    return text;
  }

  /// How many items one request asks for.
  static const pageSize = 500;

  /// How many ticks (100 nanoseconds) make a millisecond.
  static const _ticksPerMillisecond = 10000;

  final String server;
  final String user;
  final String _password;
  final HttpClient _client;

  Future<({String token, String userId})>? _session;
  String? _token;

  /// The access token of the signed-in user, once [ping] or a load ran.
  Future<({String token, String userId})> _signedIn() =>
      _session ??= _authenticate().onError<Object>((error, stack) {
        _session = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<({String token, String userId})> _authenticate() async {
    final body = await _request(
      "POST",
      "/Users/AuthenticateByName",
      body: {"Username": user, "Pw": _password},
    );
    final token = body["AccessToken"];
    final id = (body["User"] is Map<String, dynamic>)
        ? (body["User"] as Map<String, dynamic>)["Id"]
        : null;
    if (token is! String || id is! String) {
      throw const JellyfinException("Not a Jellyfin server.");
    }
    _token = token;
    return (token: token, userId: id);
  }

  static const _authorization =
      'MediaBrowser Client="Amped", Device="Amped", DeviceId="amped", '
      'Version="1.0"';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String> parameters = const {},
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final base = Uri.parse("$server$path");
      final uri = base.replace(
        queryParameters: {...base.queryParameters, ...parameters},
      );
      final request = await _client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set("Accept", "application/json")
        ..set(
          "Authorization",
          token == null ? _authorization : '$_authorization, Token="$token"',
        );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        throw RemoteAuthException(
          token == null
              ? "The server refused the user name or password."
              : "The server refused the sign-in.",
        );
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw JellyfinException("HTTP ${response.statusCode}");
      }
      final text = await response.transform(utf8.decoder).join();
      final decoded = await decodeJson(text);
      if (decoded is! Map<String, dynamic>) {
        throw const JellyfinException("Not a Jellyfin server.");
      }
      return decoded;
    } on FormatException {
      throw const JellyfinException("Not a Jellyfin server.");
    } on SocketException catch (error) {
      throw JellyfinException(error.message);
    } on TimeoutException {
      throw const JellyfinException("The server did not answer.");
    } on HandshakeException catch (error) {
      throw JellyfinException(error.message);
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> parameters = const {},
  ]) async {
    final session = await _signedIn();
    return _request("GET", path, parameters: parameters, token: session.token);
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const [];

  /// Throws when the server can't be reached or the sign-in is refused.
  Future<void> ping() => _signedIn();

  /// The id of the item [id] (named `<id>.<extension>`).
  static String _idOf(String id) {
    final dot = id.indexOf(".");
    return dot < 0 ? id : id.substring(0, dot);
  }

  /// Where the file of the item [id] is streamed from, signing in first.
  Future<String> streamUrl(String id) async {
    final session = await _signedIn();
    return Uri.parse(
      "$server/Items/${_idOf(id)}/Download",
    ).replace(queryParameters: {"api_key": session.token}).toString();
  }

  /// Where the picture of the item [id] with [tag] is, or null for no tag.
  String? _image(Object? id, Object? tag) {
    if (id is! String || tag is! String || tag.isEmpty) return null;
    return Uri.parse("$server/Items/$id/Images/Primary")
        .replace(
          queryParameters: {"tag": tag, "api_key": _token ?? ""},
        )
        .toString();
  }

  /// Every item of the [types] a page at a time, handed to [onItems].
  Future<void> _items(
    String types,
    Future<bool> Function(List<Map<String, dynamic>> items) onItems, {
    String fields = "",
    bool Function()? isCancelled,
  }) async {
    final session = await _signedIn();
    for (var start = 0; ; start += pageSize) {
      if (isCancelled?.call() ?? false) return;
      final body = await _get("/Users/${session.userId}/Items", {
        "IncludeItemTypes": types,
        "Recursive": "true",
        "SortBy": "SortName",
        "Fields": fields,
        "StartIndex": "$start",
        "Limit": "$pageSize",
      });
      final items = _list(body["Items"]);
      if (!await onItems(items)) return;
      if (items.length < pageSize) break;
    }
  }

  static const _audioFields = "Genres,MediaSources,MediaStreams";
  static const _videoFields =
      "Genres,MediaSources,MediaStreams,Overview,DateCreated,PremiereDate";

  /// Every track of the server, a page at a time: [onPage] gets each page's
  /// tracks as they arrive. Their paths are [pathOf] of the track's id.
  /// Stops after the page it is on when [isCancelled] says so.
  Future<void> tracks({
    required void Function(List<TrackTags> page) onPage,
    String Function(String id)? pathOf,
    bool Function()? isCancelled,
  }) => _items(
    "Audio",
    (items) async {
      final page = [
        for (final item in items) ?_track(item, pathOf ?? (id) => id),
      ];
      if (page.isNotEmpty) onPage(page);
      return true;
    },
    fields: _audioFields,
    isCancelled: isCancelled,
  );

  /// Every movie and episode, a page at a time like [tracks]. Titles are the
  /// movie's, or the episode's, listed under its show and season.
  Future<void> videos({
    required void Function(List<TrackTags> page) onPage,
    String Function(String id)? pathOf,
    bool Function()? isCancelled,
  }) async {
    final summaries = await _showSummaries();
    await _items(
      "Movie,Episode",
      (items) async {
        final page = [
          for (final item in items)
            ?_video(item, pathOf ?? (id) => id, summaries),
        ];
        if (page.isNotEmpty) onPage(page);
        return true;
      },
      fields: _videoFields,
      isCancelled: isCancelled,
    );
  }

  /// What each show is about, by its id.
  Future<Map<String, String>> _showSummaries() async {
    final summaries = <String, String>{};
    await _items("Series", (items) async {
      for (final item in items) {
        final overview = _text(item["Overview"]);
        if (overview != null) summaries["${item["Id"]}"] = overview;
      }
      return true;
    }, fields: "Overview");
    return summaries;
  }

  /// The video playlists of the server, each with the paths of its items
  /// ([pathOf] of their ids), by name.
  Future<Map<String, List<String>>> videoPlaylists({
    String Function(String id)? pathOf,
  }) async {
    final lists = <String, List<String>>{};
    final session = await _signedIn();
    await _items("Playlist", (playlists) async {
      for (final playlist in playlists) {
        final id = playlist["Id"];
        final name = playlist["Name"];
        if (id is! String || name is! String) continue;
        if (playlist["MediaType"] != "Video") continue;
        final body = await _get("/Playlists/$id/Items", {
          "UserId": session.userId,
          "Fields": "MediaSources",
        });
        final paths = <String>[];
        for (final item in _list(body["Items"])) {
          final track = _track(item, pathOf ?? (id) => id);
          if (track != null) paths.add(track.path);
        }
        lists[name] = paths;
      }
      return true;
    });
    return lists;
  }

  TrackTags? _video(
    Map<String, dynamic> item,
    String Function(String id) pathOf,
    Map<String, String> summaries,
  ) {
    final track = _track(item, pathOf);
    if (track == null) return null;
    final show = item["SeriesName"] as String?;
    final data = item["UserData"];
    return TrackTags(
      track.path,
      artist: show,
      album: show == null ? null : item["SeasonName"] as String?,
      title: item["Name"] as String?,
      trackNumber: track.trackNumber,
      discNumber: track.discNumber,
      year: track.year,
      duration: track.duration,
      bitrate: track.bitrate,
      channels: track.channels,
      genres: track.genres,
      imageUrl:
          _image(item["Id"], (item["ImageTags"] as Map?)?["Primary"]) ??
          track.imageUrl,
      published: _date(item["PremiereDate"]),
      progress: _watched(data, track.duration),
      description: _text(item["Overview"]),
      showDescription: summaries["${item["SeriesId"]}"],
      showImageUrl: show == null
          ? null
          : _image(item["SeriesId"], item["SeriesPrimaryImageTag"]),
      seasonImageUrl: show == null
          ? null
          : _image(item["SeasonId"], item["ParentPrimaryImageTag"]),
      added: _date(item["DateCreated"]),
      lastWatched: data is Map<String, dynamic>
          ? _date(data["LastPlayedDate"])
          : null,
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// How much was watched, 0 to 1 (1 when finished); null when not started.
  static double? _watched(Object? data, Duration? length) {
    if (data is! Map<String, dynamic>) return null;
    if (data["Played"] == true) return 1.0;
    final ticks = data["PlaybackPositionTicks"];
    if (ticks is num && ticks > 0 && length != null && length > Duration.zero) {
      return (ticks / _ticksPerMillisecond / length.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return null;
  }

  /// The track of [item], or null when it has no file.
  TrackTags? _track(
    Map<String, dynamic> item,
    String Function(String id) pathOf,
  ) {
    final id = item["Id"];
    if (id is! String) return null;
    int? number(Object? value) => switch (value) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    final sources = _list(item["MediaSources"]);
    final source = sources.isEmpty ? null : sources.first;
    final streams = _list(source?["MediaStreams"] ?? item["MediaStreams"]);
    final audio = streams.where((stream) => stream["Type"] == "Audio");
    final path = source?["Path"];
    final dot = path is String ? path.lastIndexOf(".") : -1;
    final extension = path is String && dot >= 0 && !path.contains("/", dot)
        ? path.substring(dot + 1).toLowerCase()
        : null;
    final ticks = number(item["RunTimeTicks"] ?? source?["RunTimeTicks"]);
    final bitrate = number(source?["Bitrate"]);
    final artists = item["Artists"];
    return TrackTags(
      pathOf(extension == null || extension.isEmpty ? id : "$id.$extension"),
      artist:
          (item["AlbumArtist"] ??
                  (artists is List && artists.isNotEmpty
                      ? artists.first
                      : null))
              as String?,
      album: item["Album"] as String?,
      title: item["Name"] as String?,
      trackNumber: number(item["IndexNumber"]),
      discNumber: number(item["ParentIndexNumber"]),
      year: number(item["ProductionYear"]),
      duration: ticks == null
          ? null
          : Duration(milliseconds: ticks ~/ _ticksPerMillisecond),
      bitrate: bitrate == null ? null : bitrate ~/ 1000,
      channels: audio.isEmpty ? null : number(audio.first["Channels"]),
      genres: [
        for (final genre
            in item["Genres"] is List ? item["Genres"] as List : const [])
          if (genre is String) genre,
      ],
      imageUrl: _thumbUrl(item),
    );
  }

  /// Where the picture of [item] is: its own, else its album's.
  String? _thumbUrl(Map<String, dynamic> item) {
    final tags = item["ImageTags"];
    return _image(item["Id"], tags is Map ? tags["Primary"] : null) ??
        _image(item["AlbumId"], item["AlbumPrimaryImageTag"]);
  }

  void close() => _client.close(force: true);
}
