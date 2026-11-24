import "package:amped_media_source/amped_media_source.dart";
import "package:test/test.dart";

void main() {
  group("redact", () {
    test("masks a Plex token and keeps the rest of the URL", () {
      expect(
        redact(
          "http://nas:32400/library/parts/1/file.flac?X-Plex-Token=abc123",
        ),
        "http://nas:32400/library/parts/1/file.flac?X-Plex-Token=***",
      );
    });

    test("masks a token among other parameters", () {
      expect(
        redact("http://h/a?x=1&X-Plex-Token=abc&y=2"),
        "http://h/a?x=1&X-Plex-Token=***&y=2",
      );
    });

    test("masks Jellyfin's api_key and Audiobookshelf's token", () {
      expect(
        redact("http://j/Audio/1/stream?api_key=secret"),
        endsWith("=***"),
      );
      expect(
        redact("http://a/api/items/1/cover?token=eyJhbGciOi.x.y&w=1"),
        "http://a/api/items/1/cover?token=***&w=1",
      );
    });

    test("masks Subsonic's token, salt and legacy password", () {
      expect(
        redact("http://s/rest/stream?u=bob&t=0123abcd&s=salty&v=1.16&c=amped"),
        "http://s/rest/stream?u=bob&t=***&s=***&v=1.16&c=amped",
      );
      expect(redact("http://s/rest/ping?u=bob&p=enc:7365"), contains("p=***"));
    });

    test("leaves t, s and p alone on a URL that is not Subsonic's", () {
      expect(redact("http://h/a?t=1&s=2&p=3"), "http://h/a?t=1&s=2&p=3");
    });

    test("masks Authorization headers of every kind", () {
      expect(
        redact("Authorization: Bearer abc.def"),
        "Authorization: Bearer ***",
      );
      expect(
        redact("Authorization: OAuth 2-99999"),
        "Authorization: OAuth ***",
      );
      expect(
        redact("{Authorization: Basic dXNlcjpwdw==}"),
        isNot(contains("dXNl")),
      );
      expect(
        redact('Authorization: MediaBrowser Client="Amped", Token="tok123"'),
        isNot(contains("tok123")),
      );
    });

    test("masks token headers and fields", () {
      expect(redact("X-Plex-Token: abc"), "X-Plex-Token: ***");
      expect(redact('{"access_token":"abc","x":1}'), isNot(contains("abc")));
      expect(
        redact("{X-Plex-Token: abc, Accept: json}"),
        isNot(contains("abc")),
      );
    });

    test("masks credentials inside a URL's user info", () {
      expect(redact("smb://bob:hunter2@nas/share"), "smb://bob:***@nas/share");
    });

    test("masks every URL in an exception message", () {
      final error = Exception(
        "Connection closed, uri = http://h/a?X-Plex-Token=abc&b=1 "
        "then http://h/b?api_key=xyz",
      );
      final text = redactError(error);
      expect(text, isNot(contains("abc")));
      expect(text, isNot(contains("xyz")));
      expect(text, contains("b=1"));
    });

    test("leaves ordinary text and empty text alone", () {
      expect(redact(""), "");
      expect(
        redact("Could not scan /Music/Tokens"),
        "Could not scan /Music/Tokens",
      );
    });
  });
}
