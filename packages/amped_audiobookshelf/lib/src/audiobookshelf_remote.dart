import "package:amped_media_source/amped_media_source.dart";

import "audiobookshelf_client.dart";

/// An Audiobookshelf server's podcasts; the "password" is its API token.
class AudiobookshelfRemote
    implements RemoteLibrarySource, ResumesPlayback, ReportsProgress, HasBooks {
  AudiobookshelfRemote(SourceConnection config, String token)
    : _client = AudiobookshelfClient(server: config.server, token: token),
      _id = config.id;

  final AudiobookshelfClient _client;
  final String _id;

  @override
  Future<void> check() => _client.ping();

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) => _client.podcasts(
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
  Future<Duration?> resumePosition(String id) => _client.resumePosition(id);

  @override
  Future<void> loadBooks(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) => _client.books(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (id) => SourceLocation.build(_id, id),
  );

  @override
  Future<void> reportProgress(
    String id,
    Duration position,
    Duration duration, {
    required bool finished,
  }) => _client.reportProgress(id, position, duration, finished: finished);

  @override
  String coverUrl(String id) => _client.coverUrl(id.split("|").first);

  @override
  String streamUrl(String id) => _client.streamUrl(id);

  @override
  void close() => _client.close();
}
