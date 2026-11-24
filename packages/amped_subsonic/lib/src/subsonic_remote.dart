import "package:amped_media_source/amped_media_source.dart";

import "subsonic_client.dart";

/// The Navidrome/Subsonic server of a [RemoteLibrarySource].
class SubsonicRemote implements RemoteLibrarySource {
  SubsonicRemote(SourceConnection config, String password)
    : _client = SubsonicClient(
        server: config.server,
        user: config.user,
        password: password,
      ),
      _id = config.id;

  final SubsonicClient _client;
  final String _id;

  @override
  Future<void> check() => _client.ping();

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) => _client.songs(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (id) => SourceLocation.build(_id, id),
  );

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  @override
  String streamUrl(String id) => _client.streamUrl(id);

  @override
  String coverUrl(String id) => _client.coverArtUrl(id);

  @override
  void close() => _client.close();
}
