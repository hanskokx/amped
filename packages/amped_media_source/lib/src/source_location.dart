import "dart:typed_data";

/// How a track of a remote source (Navidrome, later Plex...) is named in the
/// playlist and the library: `amped-source://<source id>/<item id>`.
///
/// The name holds no password or token, so it can be saved in playlists.
/// The real, signed URL is made when the track is about to play
/// ([resolve]), from the credentials kept in the secure store.
class SourceLocation {
  const SourceLocation._();

  static const scheme = "amped-source";

  /// Makes the location of [itemId] on the source [sourceId].
  static String build(String sourceId, String itemId) => Uri(
    scheme: scheme,
    host: sourceId,
    pathSegments: [itemId],
  ).toString();

  static bool isSource(String location) =>
      location.toLowerCase().startsWith("$scheme://");

  /// The source id and item id of [location], or null when it isn't one.
  static ({String sourceId, String itemId})? parse(String location) {
    if (!isSource(location)) return null;
    final uri = Uri.tryParse(location);
    if (uri == null || uri.host.isEmpty || uri.pathSegments.length != 1) {
      return null;
    }
    return (sourceId: uri.host, itemId: uri.pathSegments.single);
  }

  /// The extensions of the audio SoLoud cannot decode (AAC in an MP4
  /// container: the usual audiobook), which the video engine plays instead.
  static const Set<String> videoEngineExtensions = {
    "m4a",
    "m4b",
    "mp4",
    "aac",
    "wma",
  };

  /// The extension of the item [itemId] ends with (`"m4b"`), or "".
  static String extensionOfItem(String itemId) {
    final dot = itemId.lastIndexOf(".");
    return dot < 0 ? "" : itemId.substring(dot + 1).toLowerCase();
  }

  /// Whether [location] is a track of a source in a format that only the
  /// video engine plays: the source marks it with the extension its item id
  /// ends with.
  static bool playsInVideoEngine(String location) {
    final parsed = parse(location);
    return parsed != null &&
        videoEngineExtensions.contains(extensionOfItem(parsed.itemId));
  }

  /// Turns a source location into the URL to play; set by the app.
  static Future<String> Function(String location)? resolver;

  /// Fetches the cover of a source location; set by the app.
  static Future<Uint8List?> Function(String location)? artworkResolver;

  /// The cover of the source track [location], or null when it has none.
  static Future<Uint8List?> artwork(String location) async =>
      isSource(location) ? await artworkResolver?.call(location) : null;

  /// [location] as something the audio engine can open: a source location
  /// becomes its signed URL (throwing when the source is gone), anything
  /// else stays as it is.
  static Future<String> resolve(String location) async {
    final resolver = SourceLocation.resolver;
    if (resolver == null || !isSource(location)) return location;
    return resolver(location);
  }
}
