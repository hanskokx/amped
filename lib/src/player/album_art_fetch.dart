/// "Get album art": finds a release's cover on the iTunes Search API, which
/// is free and needs no key.
library;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

/// Gets [uri]'s body, or null when the request fails.
typedef ArtHttpGet = Future<Uint8List?> Function(Uri uri);

/// [ArtHttpGet] over `dart:io`.
Future<Uint8List?> ioArtHttpGet(Uri uri) async {
  final client = HttpClient()
    ..userAgent = "amped/0.1.0"
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) return null;
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add).timeout(const Duration(seconds: 30));
    return builder.takeBytes();
  } on Object {
    return null;
  } finally {
    client.close();
  }
}

/// The cover of [album] by [artist] (the best match the service lists), or
/// null when it has none or can't be reached.
Future<Uint8List?> fetchAlbumArt({
  required String artist,
  required String album,
  ArtHttpGet get = ioArtHttpGet,
}) async {
  final search = Uri.https("itunes.apple.com", "/search", {
    "term": "$artist $album",
    "entity": "album",
    "media": "music",
    "limit": "10",
  });
  final body = await get(search);
  if (body == null) return null;
  final url = bestArtworkUrl(utf8.decode(body, allowMalformed: true), album);
  if (url == null) return null;
  return get(Uri.parse(url));
}

/// The large-cover URL of the result in [json] that best matches [album]:
/// an exact title, else one containing it, else the first. Null when there
/// are no results.
String? bestArtworkUrl(String json, String album) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded["results"] is! List) return null;
  final results = [
    for (final r in decoded["results"] as List)
      if (r is Map && r["artworkUrl100"] is String) r,
  ];
  if (results.isEmpty) return null;
  final wanted = album.toLowerCase().trim();
  bool named(Map r, bool Function(String name) test) =>
      test((r["collectionName"] as String? ?? "").toLowerCase().trim());
  final best =
      results.where((r) => named(r, (n) => n == wanted)).firstOrNull ??
      results.where((r) => named(r, (n) => n.contains(wanted))).firstOrNull ??
      results.first;
  // The service scales the cover to the size named in its URL.
  return (best["artworkUrl100"] as String).replaceFirst(
    "100x100bb",
    "600x600bb",
  );
}
