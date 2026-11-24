import "package:amped_media_source/amped_media_source.dart";

import "podcast_clients.dart";

/// A podcast's RSS feed: the source's [SourceConnection.server] is the feed
/// URL, and there is no password. Episodes are named by their audio URL.
class RssRemote implements RemoteLibrarySource {
  RssRemote(SourceConnection config)
    : _client = RssClient(feed: config.server),
      _id = config.id;

  final RssClient _client;
  final String _id;

  @override
  Future<void> check() => _client.podcast();

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) async {
    final podcast = await _client.podcast();
    if (isCancelled()) return;
    add(podcast.tracks((episode) => SourceLocation.build(_id, episode.id)));
  }

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  /// The picture of the episode [id] (its audio's address), else the
  /// podcast's: asked of the feed, which a playlist restored without the
  /// source having been loaded has no other way to know.
  @override
  Future<String?> coverUrl(String id) async {
    final podcast = await _client.podcast();
    for (final episode in podcast.episodes) {
      if (episode.id == id) return episode.image ?? podcast.image;
    }
    return podcast.image;
  }

  @override
  String streamUrl(String id) => id;

  @override
  void close() => _client.close();
}
