/// Stand-in for amped_youtube: no location is a YouTube link, so the app
/// never asks for streams or playlists.
library;

class YouTubeLink {
  const YouTubeLink._();

  static YouTubeLink? tryParse(String location) => null;

  static bool isYouTube(String location) => false;

  String? get videoId => null;
  String? get playlistId => null;
  String? get videoUrl => null;
  String? get playlistUrl => null;
}

class YouTubeVideo {
  const YouTubeVideo({required this.url, this.title, this.duration});

  final String url;
  final String? title;
  final Duration? duration;
}

class YouTubeStreams {
  const YouTubeStreams({required this.audio, this.video});

  final String audio;
  final String? video;
}

abstract class YouTubeResolver {
  Future<List<YouTubeVideo>> playlist(String url);
  Future<String?> streamUrl(String url);
  Future<YouTubeStreams?> streams(String url);
}

/// Resolves nothing.
class YtDlpResolver implements YouTubeResolver {
  YtDlpResolver({this.log});

  final void Function(String message, {Map<String, Object?>? metadata})? log;

  @override
  Future<List<YouTubeVideo>> playlist(String url) async => const [];

  @override
  Future<String?> streamUrl(String url) async => null;

  @override
  Future<YouTubeStreams?> streams(String url) async => null;
}
