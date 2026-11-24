import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_media_source/amped_media_source.dart";
import "package:meta/meta.dart";

/// SoundCloud answered, but with an error (or something unexpected).
class SoundCloudException implements Exception {
  const SoundCloudException(this.message);

  final String message;

  @override
  String toString() => "SoundCloudException: $message";
}

/// What is kept in the secure store for a SoundCloud source, in the place of
/// a password: the application's client secret, and the tokens of the
/// browser sign-in when the user made one (which reaches their own library).
@immutable
class SoundCloudCredentials {
  const SoundCloudCredentials(this.secret, {this.tokens});

  /// Reads what [encode] made; a plain text is a client secret alone.
  factory SoundCloudCredentials.parse(String text) {
    if (text.startsWith("{")) {
      try {
        final json = jsonDecode(text) as Map<String, dynamic>;
        final tokens = json["tokens"];
        return SoundCloudCredentials(
          json["secret"] as String,
          tokens: tokens is Map<String, dynamic>
              ? OAuthTokens.fromJson(tokens)
              : null,
        );
      } on Object {
        // A secret that happens to start with a brace.
      }
    }
    return SoundCloudCredentials(text);
  }

  final String secret;
  final OAuthTokens? tokens;

  String encode() => tokens == null
      ? secret
      : jsonEncode({"secret": secret, "tokens": tokens!.toJson()});
}

/// A client for the SoundCloud API (https://developers.soundcloud.com), with
/// the application's own client id and secret.
///
/// It signs in with the client-credentials grant, which reaches the public
/// tracks and likes of a profile. Registering an application needs a
/// SoundCloud Pro (Artist Pro) subscription, which is why the user brings
/// their own key.
class SoundCloudClient {
  SoundCloudClient({
    required String profile,
    required this.clientId,
    required String clientSecret,
    this.apiBase = "https://api.soundcloud.com",
    this.authBase = "https://secure.soundcloud.com",
    this._tokens,
    this.redirectPort = PkceSignIn.defaultPort,
    HttpClient? client,
  }) : profile = normalizeProfile(profile),
       // ignore: prefer_initializing_formals
       _secret = clientSecret,
       _client = client ?? HttpClient();

  /// [profile] as a profile URL: `https://soundcloud.com/artist`. A bare
  /// name, or a link with a path after the name, is accepted too.
  static String normalizeProfile(String profile) {
    var text = profile.trim();
    if (text.isEmpty) return text;
    if (!text.contains("://")) {
      text = text.replaceFirst(RegExp(r"^(www\.)?soundcloud\.com/"), "");
      text = "https://soundcloud.com/$text";
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.pathSegments.isEmpty) return text;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: [uri.pathSegments.first],
    ).toString();
  }

  /// How many tracks one request asks for (the API's maximum).
  static const pageSize = 200;

  final String profile;
  final String clientId;
  final String apiBase;
  final String authBase;
  final String _secret;
  final HttpClient _client;

  /// The sign-in of the user's browser, or null for the application's own
  /// (public) access. Refreshed on the way; see [tokens].
  OAuthTokens? _tokens;

  /// The port the browser sign-in comes back to.
  final int redirectPort;

  /// Whether the user signed in with their browser, which reaches their own
  /// tracks and likes rather than a profile's public ones.
  bool get signedIn => _tokens != null;

  /// The sign-in's tokens as they are now: SoundCloud's refresh tokens work
  /// once, so a refreshed pair has to be saved.
  OAuthTokens? get tokens => _tokens;

  /// Whether [tokens] changed since the client was made.
  bool get tokensChanged => _refreshed;
  bool _refreshed = false;

  /// The browser sign-in with this application's key.
  PkceSignIn get signIn =>
      pkce(clientId, _secret, authBase: authBase, port: redirectPort);

  /// Where the sign-in comes back to; the user registers it with the
  /// application.
  static String redirectUriText([int port = PkceSignIn.defaultPort]) =>
      "http://127.0.0.1:$port/callback";

  /// The browser sign-in of an application, for [authBase].
  static PkceSignIn pkce(
    String clientId,
    String secret, {
    String authBase = "https://secure.soundcloud.com",
    int port = PkceSignIn.defaultPort,
  }) => PkceSignIn(
    authorizeUrl: Uri.parse("$authBase/authorize"),
    tokenUrl: Uri.parse("$authBase/oauth/token"),
    clientId: clientId,
    clientSecret: secret,
    port: port,
  );

  static final Map<String, _Token> _appTokens = {};

  String get _tokenKey => "$authBase|$clientId|$_secret";

  /// An access token, from the cache while it is good: the API allows few
  /// tokens per application.
  Future<String> _token() async {
    var own = _tokens;
    if (own != null) {
      if (own.isExpired) {
        own = await signIn.refresh(own);
        _tokens = own;
        _refreshed = true;
      }
      return own.accessToken;
    }
    final cached = _appTokens[_tokenKey];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.value;
    }
    final json = await _send(
      () => _client.postUrl(Uri.parse("$authBase/oauth/token")),
      headers: {
        HttpHeaders.authorizationHeader:
            "Basic ${base64.encode(utf8.encode("$clientId:$_secret"))}",
        HttpHeaders.contentTypeHeader: "application/x-www-form-urlencoded",
        HttpHeaders.acceptHeader: "application/json",
      },
      body: "grant_type=client_credentials",
      authFailure: "SoundCloud refused the client id or secret.",
    );
    final map = json is Map<String, dynamic> ? json : const {};
    final value = map["access_token"];
    if (value is! String) {
      throw const SoundCloudException("SoundCloud sent no access token.");
    }
    final expires = map["expires_in"];
    final seconds = expires is num ? expires.toInt() : 3600;
    _appTokens[_tokenKey] = _Token(
      value,
      DateTime.now().add(Duration(seconds: seconds > 120 ? seconds - 60 : 0)),
    );
    return value;
  }

  /// Sends a request and decodes its JSON answer. Redirects are followed by
  /// hand, and only within [apiBase]'s host, so the token goes nowhere else.
  Future<dynamic> _send(
    Future<HttpClientRequest> Function() open, {
    required Map<String, String> headers,
    String? body,
    String authFailure = "SoundCloud refused the sign-in.",
    Uri? redirectFrom,
    int redirects = 0,
  }) async {
    try {
      final request = await open().timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final status = response.statusCode;
      if (status >= 300 && status < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        final from = redirectFrom ?? request.uri;
        if (location == null || redirects >= 3) {
          throw const SoundCloudException("Too many redirects.");
        }
        final target = from.resolve(location);
        if (target.host != Uri.parse(apiBase).host) {
          throw const SoundCloudException("Unexpected redirect.");
        }
        return await _send(
          () => _client.getUrl(target),
          headers: headers,
          authFailure: authFailure,
          redirectFrom: target,
          redirects: redirects + 1,
        );
      }
      if (status == 401 || status == 403) {
        await response.drain<void>();
        throw RemoteAuthException(authFailure);
      }
      if (status == 404) {
        await response.drain<void>();
        throw const SoundCloudException("Not found on SoundCloud.");
      }
      if (status == 429) {
        await response.drain<void>();
        throw const SoundCloudException(
          "SoundCloud's rate limit was reached. Try again later.",
        );
      }
      if (status < 200 || status >= 300) {
        await response.drain<void>();
        throw SoundCloudException("HTTP $status");
      }
      final text = await response.transform(utf8.decoder).join();
      return jsonDecode(text);
    } on FormatException {
      throw const SoundCloudException("Not the SoundCloud API.");
    } on SocketException catch (error) {
      throw SoundCloudException(error.message);
    } on TimeoutException {
      throw const SoundCloudException("SoundCloud did not answer.");
    } on HandshakeException catch (error) {
      throw SoundCloudException(error.message);
    }
  }

  Future<dynamic> _get(Uri uri) async {
    final token = await _token();
    return _send(
      () => _client.getUrl(uri),
      headers: {
        HttpHeaders.authorizationHeader: "OAuth $token",
        HttpHeaders.acceptHeader: "application/json",
      },
    );
  }

  Uri _api(String path, [Map<String, String> query = const {}]) =>
      Uri.parse("$apiBase$path").replace(queryParameters: query);

  /// The id of the profile's user, such as `soundcloud:users:123`. Throws
  /// when the key is refused or the profile does not exist.
  Future<String> user() async {
    final json = await _get(_api("/resolve", {"url": profile}));
    final urn = json is Map ? (json["urn"] ?? json["id"]) : null;
    if (urn == null) {
      throw const SoundCloudException("That is not a SoundCloud profile.");
    }
    final text = "$urn";
    return text.contains(":") ? text : "soundcloud:users:$text";
  }

  /// Throws when the key is refused or the profile can't be found.
  Future<void> check() async {
    if (signedIn) {
      await _get(_api("/me"));
    } else {
      await user();
    }
  }

  /// The tracks the profile uploaded and liked, a page at a time: [onPage]
  /// gets each page's tracks as they arrive. Their paths are [pathOf] of
  /// the track's urn. Tracks that can't be streamed are left out.
  Future<void> tracks({
    required void Function(List<TrackTags> page) onPage,
    required String Function(String id) pathOf,
    bool Function()? isCancelled,
  }) async {
    final seen = <String>{};
    final String base;
    if (signedIn) {
      base = "/me";
    } else {
      base = "/users/${await user()}";
    }
    for (final path in ["$base/tracks", "$base/likes/tracks"]) {
      Uri? next = _api(path, {
        "limit": "$pageSize",
        "linked_partitioning": "true",
      });
      while (next != null) {
        if (isCancelled?.call() ?? false) return;
        final json = await _get(next);
        final items = json is Map
            ? json["collection"]
            : json is List
            ? json
            : null;
        final page = <TrackTags>[];
        if (items is List) {
          for (final item in items.whereType<Map<String, dynamic>>()) {
            final tags = _track(item, pathOf);
            if (tags != null && seen.add(tags.path)) page.add(tags);
          }
        }
        if (page.isNotEmpty) onPage(page);
        final href = json is Map ? json["next_href"] : null;
        next = href is String && href.isNotEmpty ? Uri.tryParse(href) : null;
        // Never hand the token to another host.
        if (next != null && next.host != Uri.parse(apiBase).host) next = null;
      }
    }
  }

  TrackTags? _track(
    Map<String, dynamic> track,
    String Function(String id) pathOf,
  ) {
    final id = track["urn"] ?? track["id"];
    if (id == null) return null;
    if (track["access"] == "blocked" || track["streamable"] == false) {
      return null;
    }
    final urn = "$id".contains(":") ? "$id" : "soundcloud:tracks:$id";
    final user = track["user"];
    final duration = track["duration"];
    final genre = track["genre"];
    return TrackTags(
      pathOf(urn),
      artist: user is Map ? user["username"] as String? : null,
      title: track["title"] as String?,
      duration: duration is num
          ? Duration(milliseconds: duration.toInt())
          : null,
      genres: [if (genre is String && genre.isNotEmpty) genre],
    );
  }

  /// The URL that plays the track [urn]: its HLS stream, which is signed.
  Future<String> streamUrl(String urn) async {
    final json = await _get(_api("/tracks/$urn/streams"));
    if (json is Map) {
      for (final key in [
        "hls_aac_160_url",
        "hls_mp3_128_url",
        "http_mp3_128_url",
        "preview_mp3_128_url",
      ]) {
        final url = json[key];
        if (url is String && url.isNotEmpty) return url;
      }
    }
    throw const SoundCloudException("That track can't be streamed.");
  }

  void close() => _client.close(force: true);
}

class _Token {
  const _Token(this.value, this.expires);

  final String value;
  final DateTime expires;
}
