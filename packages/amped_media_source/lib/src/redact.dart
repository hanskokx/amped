/// What replaces a secret.
const String redacted = "***";

/// Query parameters that carry a credential on any URL.
const List<String> _secretParameters = [
  "x-plex-token",
  "x-emby-token",
  "x-mediabrowser-token",
  "api_key",
  "apikey",
  "token",
  "access_token",
  "refresh_token",
  "id_token",
  "auth_token",
  "authtoken",
  "client_secret",
  "password",
  "signature",
];

/// Subsonic's `t` (token), `s` (salt) and `p` (legacy password): too short to
/// be told apart from other parameters, so only masked beside its `u=` user.
const List<String> _subsonicParameters = ["t", "s", "p"];

final RegExp _secretQuery = RegExp(
  "([?&;](?:${_secretParameters.map(RegExp.escape).join("|")}))=[^&#\\s\"'<>)]*",
  caseSensitive: false,
);

final RegExp _subsonicQuery = RegExp(
  "([?&](?:${_subsonicParameters.join("|")}))=[^&#\\s\"'<>)]*",
  caseSensitive: false,
);

final RegExp _subsonicUser = RegExp(r"[?&]u=", caseSensitive: false);

/// `Authorization: Bearer abc`, `Authorization: OAuth abc`, `Basic abc`.
final RegExp _authorization = RegExp(
  r"""(authorization[\s:=]+['"]?(?:bearer|oauth|basic|token|mediabrowser|digest)?)"""
  r"""\s*[^\s,'"]+""",
  caseSensitive: false,
);

/// `Bearer abc` on its own, as an exception may quote a header's value.
final RegExp _scheme = RegExp(
  r"\b(Bearer|OAuth|Basic)\s+[A-Za-z0-9._~+/=-]{8,}",
  caseSensitive: false,
);

/// Headers and fields written as `Name: value`, `Name = value`, a Dart map's
/// `{Name: value}` or JSON's `"name": "value"`.
final RegExp _field = RegExp(
  r"""(["']?(?:x-plex-token|x-emby-token|x-mediabrowser-token|api_key|apikey|"""
  r"""access_token|refresh_token|id_token|auth_token|client_secret|"""
  r"""password|token)["']?\s*[:=]\s*["']?)[^\s,"'&}\]]+""",
  caseSensitive: false,
);

/// `Token="abc"` inside Jellyfin's `Authorization` header.
final RegExp _quotedToken = RegExp(r'(Token=")[^"]*(")', caseSensitive: false);

/// `https://user:password@host`.
final RegExp _userInfo = RegExp(r"(\w+://[^/\s:@]*:)[^/\s@]+(@)");

/// [text] with every credential in it masked: token and key query
/// parameters, Subsonic's `t`/`s`/`p`, `Authorization` headers and
/// bearer tokens, `user:password@` in a URL and token fields.
///
/// Use it on anything that may hold a URL or an error that quotes one
/// before it is logged or shown: a request URL is signed with the login.
String redact(String text) {
  if (text.isEmpty) return text;
  var result = text
      .replaceAllMapped(_secretQuery, (m) => "${m[1]}=$redacted")
      .replaceAllMapped(_quotedToken, (m) => "${m[1]}$redacted${m[2]}")
      .replaceAllMapped(_userInfo, (m) => "${m[1]}$redacted${m[2]}")
      .replaceAllMapped(_authorization, (m) => "${m[1]} $redacted")
      .replaceAllMapped(_scheme, (m) => "${m[1]} $redacted")
      .replaceAllMapped(_field, (m) => "${m[1]}$redacted");
  if (_subsonicUser.hasMatch(result)) {
    result = result.replaceAllMapped(
      _subsonicQuery,
      (m) => "${m[1]}=$redacted",
    );
  }
  return result;
}

/// [error] as text with its credentials masked.
String redactError(Object? error) => redact("$error");
