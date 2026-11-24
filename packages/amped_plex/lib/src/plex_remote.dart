import "package:amped_media_source/amped_media_source.dart";

import "plex_client.dart";

/// A Plex Media Server. The "password" of its login is the server's
/// `X-Plex-Token`; items are named by their part key (`/library/parts/...`),
/// which is what [streamUrl] signs.
class PlexRemote implements RemoteLibrarySource, HasVideoPlaylists {
  PlexRemote(SourceConnection config, String token)
    : _client = PlexClient(server: config.server, token: token),
      _id = config.id;

  final PlexClient _client;
  final String _id;

  @override
  Future<void> check() => _client.ping();

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) => _client.tracks(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (key) => SourceLocation.build(_id, key),
  );

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) => _client.videos(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (key) => SourceLocation.build(_id, key),
  );

  @override
  Future<Map<String, List<String>>> loadVideoPlaylists() =>
      _client.videoPlaylists(pathOf: (key) => SourceLocation.build(_id, key));

  @override
  String? coverUrl(String id) => null;

  @override
  String streamUrl(String id) => _client.streamUrl(id);

  @override
  void close() => _client.close();
}
