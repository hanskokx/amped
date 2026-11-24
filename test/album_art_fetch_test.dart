import "dart:convert";
import "dart:typed_data";

import "package:amped/src/player/album_art_fetch.dart";
import "package:flutter_test/flutter_test.dart";

const _json = '''
{"resultCount":2,"results":[
 {"collectionName":"Abbey Road (Remastered)","artworkUrl100":"https://x/a/100x100bb.jpg"},
 {"collectionName":"Abbey Road","artworkUrl100":"https://x/b/100x100bb.jpg"}]}''';

void main() {
  test("picks the exact title and asks for a large cover", () {
    expect(bestArtworkUrl(_json, "Abbey Road"), "https://x/b/600x600bb.jpg");
  });

  test("falls back to a partial match, then the first result", () {
    expect(
      bestArtworkUrl(_json, "abbey road (remastered)"),
      "https://x/a/600x600bb.jpg",
    );
    expect(bestArtworkUrl(_json, "Nope"), "https://x/a/600x600bb.jpg");
  });

  test("no results or bad JSON gives null", () {
    expect(bestArtworkUrl('{"results":[]}', "x"), isNull);
    expect(bestArtworkUrl("<html>", "x"), isNull);
  });

  test("searches by artist and album, then downloads the cover", () async {
    final requested = <Uri>[];
    final bytes = await fetchAlbumArt(
      artist: "The Beatles",
      album: "Abbey Road",
      get: (uri) async {
        requested.add(uri);
        return uri.host == "itunes.apple.com"
            ? Uint8List.fromList(utf8.encode(_json))
            : Uint8List.fromList([1, 2, 3]);
      },
    );
    expect(bytes, [1, 2, 3]);
    expect(requested.first.queryParameters["term"], "The Beatles Abbey Road");
    expect(requested.last.toString(), "https://x/b/600x600bb.jpg");
  });

  test("a failed search gives null", () async {
    expect(
      await fetchAlbumArt(artist: "a", album: "b", get: (_) async => null),
      isNull,
    );
  });
}
