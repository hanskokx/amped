import "package:amped_media_source/amped_media_source.dart";

import "soundcloud_client.dart";

/// A SoundCloud profile, reached with the user's own application key: the
/// source's [SourceConnection.server] is the profile URL and its
/// [SourceConnection.user] the client id; [password] is the client secret.
class SoundCloudRemote implements RemoteLibrarySource, RefreshesCredentials {
  SoundCloudRemote(
    SourceConnection config,
    String password, {
    String apiBase = "https://api.soundcloud.com",
    String authBase = "https://secure.soundcloud.com",
    int redirectPort = PkceSignIn.defaultPort,
  }) : _credentials = SoundCloudCredentials.parse(password),
       _id = config.id {
    _client = SoundCloudClient(
      profile: config.server,
      clientId: config.user,
      clientSecret: _credentials.secret,
      tokens: _credentials.tokens,
      apiBase: apiBase,
      authBase: authBase,
      redirectPort: redirectPort,
    );
  }

  final SoundCloudCredentials _credentials;
  late final SoundCloudClient _client;
  final String _id;

  @override
  Future<void> check() => _client.check();

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) => _client.tracks(
    onPage: add,
    isCancelled: isCancelled,
    pathOf: (urn) => SourceLocation.build(_id, urn),
  );

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  @override
  String? coverUrl(String id) => null;

  @override
  Future<String> streamUrl(String id) => _client.streamUrl(id);

  @override
  String? get refreshedPassword => _client.tokensChanged
      ? SoundCloudCredentials(
          _credentials.secret,
          tokens: _client.tokens,
        ).encode()
      : null;

  @override
  void close() => _client.close();
}
