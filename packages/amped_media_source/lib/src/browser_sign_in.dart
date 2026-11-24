import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:crypto/crypto.dart";
import "package:meta/meta.dart";

import "auth_exception.dart";

/// Opens [url] in the user's own browser, where they sign in.
typedef BrowserOpener = Future<void> Function(Uri url);

/// The sign-in was not finished: the user closed the browser, denied the
/// request, or it took too long.
class BrowserSignInException implements Exception {
  const BrowserSignInException(this.message);

  final String message;

  @override
  String toString() => "BrowserSignInException: $message";
}

/// Waits for a sign-in that happens elsewhere (the user approves a code in
/// their browser, like Plex's PIN): calls [poll] every [interval] until it
/// returns something. Throws a [BrowserSignInException] after [timeout].
///
/// This is the shared half of the "sign in with the browser" mechanisms; the
/// other is [PkceSignIn]. A source type opens its page with the
/// [BrowserOpener], then waits with this.
Future<T> pollSignIn<T extends Object>(
  Future<T?> Function() poll, {
  Duration interval = const Duration(seconds: 2),
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final result = await poll();
    if (result != null) return result;
    await Future<void>.delayed(interval);
  }
  throw const BrowserSignInException("The sign-in took too long.");
}

/// An OAuth 2 access token with its refresh token.
@immutable
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.expires,
    this.refreshToken,
  });

  factory OAuthTokens.fromJson(Map<String, dynamic> json) => OAuthTokens(
    accessToken: json["access"] as String,
    refreshToken: json["refresh"] as String?,
    expires: DateTime.parse(json["expires"] as String),
  );

  /// Reads an answer of a token endpoint.
  factory OAuthTokens.fromResponse(
    Map<String, dynamic> json, {
    DateTime? now,
    String? previousRefreshToken,
  }) {
    final access = json["access_token"];
    if (access is! String || access.isEmpty) {
      throw const BrowserSignInException("The server sent no access token.");
    }
    final seconds = json["expires_in"];
    return OAuthTokens(
      accessToken: access,
      // Some servers keep the refresh token when they don't send a new one.
      refreshToken: json["refresh_token"] as String? ?? previousRefreshToken,
      expires: (now ?? DateTime.now()).add(
        Duration(seconds: seconds is num ? seconds.toInt() : 3600),
      ),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final DateTime expires;

  /// Whether it should be refreshed: it ends within a minute.
  bool get isExpired =>
      !expires.subtract(const Duration(minutes: 1)).isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    "access": accessToken,
    "refresh": refreshToken,
    "expires": expires.toIso8601String(),
  };
}

/// Signs in with the OAuth 2 authorization-code flow, PKCE (S256) included:
/// the browser opens the provider's page, and the provider sends it back to
/// a short-lived server on this computer ([redirectUri]), which hands the
/// code to the app.
///
/// The redirect address has to be registered with the provider as it is, so
/// [port] is fixed rather than random.
class PkceSignIn {
  PkceSignIn({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.clientSecret,
    this.port = defaultPort,
    this.scope,
    this.timeout = const Duration(minutes: 5),
  });

  /// The port of [redirectUri] when none is given.
  static const defaultPort = 53682;

  final Uri authorizeUrl;
  final Uri tokenUrl;
  final String clientId;
  final String clientSecret;
  final int port;
  final String? scope;

  /// How long the user has to finish in the browser.
  final Duration timeout;

  /// Where the provider sends the browser back to.
  Uri get redirectUri => Uri.parse("http://127.0.0.1:$port/callback");

  static String _random(int bytes) {
    final random = Random.secure();
    return base64Url
        .encode([for (var i = 0; i < bytes; i++) random.nextInt(256)])
        .replaceAll("=", "");
  }

  /// The challenge of a PKCE [verifier].
  static String challengeOf(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll("=", "");

  /// Opens the browser with [open], and returns the tokens once the user
  /// approved. Throws a [BrowserSignInException] when they didn't.
  Future<OAuthTokens> signIn(BrowserOpener open) async {
    final verifier = _random(48);
    final state = _random(16);
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw BrowserSignInException(
        "Port $port is in use, so the browser can't send the sign-in back.",
      );
    }
    try {
      final result = Completer<String>();
      server.listen((request) async {
        final query = request.uri.queryParameters;
        if (request.uri.path != "/callback") {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final String? code;
        String? failure;
        if (query["state"] != state) {
          code = null;
          failure = "The sign-in did not match the request.";
        } else if (query["error"] != null) {
          code = null;
          failure = "The sign-in was refused: ${query["error"]}";
        } else {
          code = query["code"];
          if (code == null) failure = "The sign-in sent no code.";
        }
        request.response
          ..headers.contentType = ContentType.html
          ..write(
            "<!doctype html><meta charset=utf-8><title>Amped</title> "
            '<body style="font-family:sans-serif;margin:3em">'
            "${failure == null ? "Signed in. You can close this tab and "
                      "return to Amped." : "Could not sign in. You can close this tab."}",
          );
        await request.response.close();
        if (result.isCompleted) return;
        if (code != null) {
          result.complete(code);
        } else {
          result.completeError(BrowserSignInException(failure!));
        }
      });
      // The browser may answer before it is awaited below.
      final pending = result.future.timeout(
        timeout,
        onTimeout: () =>
            throw const BrowserSignInException("The sign-in took too long."),
      )..ignore();
      await open(
        authorizeUrl.replace(
          queryParameters: {
            ...authorizeUrl.queryParameters,
            "client_id": clientId,
            "redirect_uri": redirectUri.toString(),
            "response_type": "code",
            "code_challenge": challengeOf(verifier),
            "code_challenge_method": "S256",
            "state": state,
            if (scope != null) "scope": scope!,
          },
        ),
      );
      final code = await pending;
      return await _token({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirectUri.toString(),
        "code_verifier": verifier,
      });
    } finally {
      await server.close(force: true);
    }
  }

  /// New tokens for [tokens], which have expired. Some providers' refresh
  /// tokens work once, so the returned ones replace the old ones.
  Future<OAuthTokens> refresh(OAuthTokens tokens) {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) {
      throw const RemoteAuthException("The sign-in expired. Sign in again.");
    }
    return _token({
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
    }, previousRefreshToken: refreshToken);
  }

  Future<OAuthTokens> _token(
    Map<String, String> form, {
    String? previousRefreshToken,
  }) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(tokenUrl)
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set(
          HttpHeaders.contentTypeHeader,
          "application/x-www-form-urlencoded",
        )
        ..set(HttpHeaders.acceptHeader, "application/json");
      request.write(
        Uri(
          queryParameters: {
            ...form,
            "client_id": clientId,
            "client_secret": clientSecret,
          },
        ).query,
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 400 || response.statusCode == 401) {
        throw const RemoteAuthException(
          "The server refused the sign-in (check the client id and secret).",
        );
      }
      if (response.statusCode != 200) {
        throw BrowserSignInException("HTTP ${response.statusCode}");
      }
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        throw const BrowserSignInException("Not an OAuth server.");
      }
      return OAuthTokens.fromResponse(
        json,
        previousRefreshToken: previousRefreshToken,
      );
    } on FormatException {
      throw const BrowserSignInException("Not an OAuth server.");
    } on SocketException catch (error) {
      throw BrowserSignInException(error.message);
    } on TimeoutException {
      throw const BrowserSignInException("The server did not answer.");
    } finally {
      client.close(force: true);
    }
  }
}
