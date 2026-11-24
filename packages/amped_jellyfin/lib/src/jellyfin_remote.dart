import "package:amped_media_source/amped_media_source.dart";

import "jellyfin_client.dart";

/// A Jellyfin server. Its login is the user name and password; items are
/// named by their id and file extension, which [streamUrl] signs.
class JellyfinRemote implements RemoteLibrarySource, HasVideoPlaylists {
  JellyfinRemote(SourceConnection config, String password)
    : _client = JellyfinClient(
        server: config.server,
        user: config.user,
        password: password,
      ),
      _id = config.id;

  final JellyfinClient _client;
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
    pathOf: (id) => SourceLocation.build(_id, id),
  );

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) => _client.videos(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (id) => SourceLocation.build(_id, id),
  );

  @override
  Future<Map<String, List<String>>> loadVideoPlaylists() =>
      _client.videoPlaylists(pathOf: (id) => SourceLocation.build(_id, id));

  @override
  String? coverUrl(String id) => null;

  @override
  Future<String> streamUrl(String id) => _client.streamUrl(id);

  @override
  void close() => _client.close();
}
