import "dart:convert";
import "dart:io";

import "package:amped/src/remote/browser_sign_in.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:crypto/crypto.dart";
import "package:flutter_test/flutter_test.dart";

/// An OAuth provider with a token endpoint that checks PKCE.
class _FakeProvider {
  late final HttpServer http;
  String? challenge;
  final List<Map<String, String>> forms = [];
  int issued = 0;

  Uri get tokenUrl => Uri.parse("http://127.0.0.1:${http.port}/oauth/token");

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      final form = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      forms.add(form);
      var status = 200;
      Object reply = {};
      if (form["client_secret"] != "secret") {
        status = 401;
      } else if (form["grant_type"] == "authorization_code") {
        final verifier = form["code_verifier"]!;
        final expected = base64Url
            .encode(sha256.convert(ascii.encode(verifier)).bytes)
            .replaceAll("=", "");
        if (form["code"] != "the-code" || expected != challenge) {
          status = 400;
        } else {
          reply = {
            "access_token": "a${++issued}",
            "refresh_token": "r$issued",
            "expires_in": 3600,
          };
        }
      } else if (form["grant_type"] == "refresh_token") {
        reply = {
          "access_token": "a${++issued}",
          "refresh_token": "r$issued",
          "expires_in": 3600,
        };
      }
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply));
      await request.response.close();
    });
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late _FakeProvider provider;

  setUp(() async {
    provider = _FakeProvider();
    await provider.start();
  });

  tearDown(() => provider.http.close(force: true));

  Future<PkceSignIn> signIn({Duration? timeout}) async => PkceSignIn(
    authorizeUrl: Uri.parse("http://127.0.0.1:1/authorize"),
    tokenUrl: provider.tokenUrl,
    clientId: "id",
    clientSecret: "secret",
    port: await _freePort(),
    timeout: timeout ?? const Duration(seconds: 5),
  );

  /// A "browser" that approves, sending back [code] (and [state]).
  BrowserOpener approving({String code = "the-code", String? state}) =>
      (url) async {
        provider.challenge = url.queryParameters["code_challenge"];
        expect(url.queryParameters["code_challenge_method"], "S256");
        expect(url.queryParameters["response_type"], "code");
        final redirect = Uri.parse(url.queryParameters["redirect_uri"]!);
        final client = HttpClient();
        final request = await client.getUrl(
          redirect.replace(
            queryParameters: {
              "code": code,
              "state": state ?? url.queryParameters["state"]!,
            },
          ),
        );
        final response = await request.close();
        await response.drain<void>();
        client.close();
      };

  test("signs in through the browser with PKCE", () async {
    final tokens = await (await signIn()).signIn(approving());
    expect(tokens.accessToken, "a1");
    expect(tokens.refreshToken, "r1");
    expect(tokens.isExpired, isFalse);
    final form = provider.forms.single;
    expect(form["client_id"], "id");
    expect(form["redirect_uri"], startsWith("http://127.0.0.1:"));
  });

  test("a redirect with the wrong state is refused", () async {
    await expectLater(
      (await signIn()).signIn(approving(state: "forged")),
      throwsA(isA<BrowserSignInException>()),
    );
    expect(provider.forms, isEmpty);
  });

  test("a provider that refuses the code is an auth error", () async {
    await expectLater(
      (await signIn()).signIn(approving(code: "bad")),
      throwsA(isA<RemoteAuthException>()),
    );
  });

  test("gives up when the browser never comes back", () async {
    await expectLater(
      (await signIn(timeout: const Duration(milliseconds: 100))).signIn(
        (url) async {},
      ),
      throwsA(isA<BrowserSignInException>()),
    );
  });

  test("refreshes tokens, replacing the single-use refresh token", () async {
    final flow = await signIn();
    final first = await flow.signIn(approving());
    final second = await flow.refresh(first);
    expect(second.accessToken, "a2");
    expect(second.refreshToken, "r2");
    expect(provider.forms.last["refresh_token"], "r1");
  });

  test("tokens survive a round trip and expire", () {
    final tokens = OAuthTokens(
      accessToken: "a",
      refreshToken: "r",
      expires: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    final back = OAuthTokens.fromJson(
      jsonDecode(jsonEncode(tokens.toJson())) as Map<String, dynamic>,
    );
    expect(back.accessToken, "a");
    expect(back.refreshToken, "r");
    expect(back.isExpired, isTrue);
  });

  test("pollSignIn waits for the answer, or times out", () async {
    var calls = 0;
    final result = await pollSignIn<String>(
      () async => ++calls < 3 ? null : "token",
      interval: const Duration(milliseconds: 5),
    );
    expect(result, "token");
    await expectLater(
      pollSignIn<String>(
        () async => null,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<BrowserSignInException>()),
    );
  });
}
