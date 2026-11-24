import "dart:async";
import "dart:convert";

import "package:amped_audiobookshelf/amped_audiobookshelf.dart";
import "package:amped_jellyfin/amped_jellyfin.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_plex/amped_plex.dart";
import "package:amped_podcast/amped_podcast.dart";
import "package:amped_soundcloud/amped_soundcloud.dart";
import "package:amped_subsonic/amped_subsonic.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../features/remote_source/classes/remote_source_type.dart";
import "../player/album_art_fetch.dart";
import "../player/tag_cache.dart";
import "../remote/browser_sign_in.dart";
import "../remote/remote_credentials.dart";
import "library_sources.dart";
import "media_library.dart";
import "source_settings.dart";

/// A remote source the user added, as it is saved: everything but the
/// password, which is in the credential store.
@immutable
bool _podcastType(RemoteSourceType type) =>
    type == RemoteSourceType.podcast || type == RemoteSourceType.audiobookshelf;

class RemoteSourceConfig {
  RemoteSourceConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.server,
    required this.user,
    SourceSettings? settings,
  }) : settings =
           settings ?? SourceSettings.usualFor(podcast: _podcastType(type));

  factory RemoteSourceConfig.fromJson(Map<String, dynamic> json) {
    final type = RemoteSourceType.values.firstWhere(
      (type) => type.name == json["type"],
      orElse: () => RemoteSourceType.navidrome,
    );
    return RemoteSourceConfig(
      id: json["id"] as String,
      type: type,
      name: json["name"] as String,
      server: json["server"] as String,
      user: json["user"] as String,
      settings: SourceSettings.fromJson(
        json["settings"] as Map<String, dynamic>?,
        SourceSettings.usualFor(podcast: _podcastType(type)),
      ),
    );
  }

  final String id;
  final RemoteSourceType type;

  /// What the tree calls it.
  final String name;

  /// The server's address: `https://music.example.com`.
  final String server;
  final String user;

  /// Whether and how often it is refreshed, and when an episode of it counts
  /// as played.
  final SourceSettings settings;

  /// What the source's remote is built from.
  SourceConnection get connection =>
      SourceConnection(id: id, server: server, user: user);

  RemoteSourceConfig copyWith({
    String? name,
    String? server,
    String? user,
    SourceSettings? settings,
  }) => RemoteSourceConfig(
    id: id,
    type: type,
    name: name ?? this.name,
    server: server ?? this.server,
    user: user ?? this.user,
    settings: settings ?? this.settings,
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "type": type.name,
    "name": name,
    "server": server,
    "user": user,
    "settings": settings.toJson(),
  };
}

/// Opens the connection to a remote source.
typedef RemoteLibrarySourceFactory = RemoteLibrarySource Function(
  RemoteSourceConfig config,
  String password,
);

/// The remote that [config]'s type stands for.
RemoteLibrarySource createRemote(RemoteSourceConfig config, String password) {
  final connection = config.connection;
  return switch (config.type) {
    RemoteSourceType.navidrome => SubsonicRemote(connection, password),
    RemoteSourceType.soundcloud => SoundCloudRemote(connection, password),
    RemoteSourceType.plex => PlexRemote(connection, password),
    RemoteSourceType.jellyfin => JellyfinRemote(connection, password),
    RemoteSourceType.podcast => RssRemote(connection),
    RemoteSourceType.audiobookshelf => AudiobookshelfRemote(
      connection,
      password,
    ),
  };
}

class _Remote {
  _Remote(this.config);

  RemoteSourceConfig config;
  final MediaLibrary library = MediaLibrary();
  final MediaLibrary videos = MediaLibrary.videos();

  /// [videos] told apart: the movies, and the episodes of TV shows.
  final MediaLibrary movies = MediaLibrary.videos();
  final MediaLibrary shows = MediaLibrary.videos();

  /// The server's playlists of videos, with the paths of their items.
  Map<String, List<String>> videoPlaylists = const {};

  /// The audiobooks of a server that has them, a track per audio file.
  final MediaLibrary books = MediaLibrary();
  bool loaded = false;
  bool videosLoaded = false;
  bool booksLoaded = false;
  String? error;

  /// What is known of the track at [location], in the library or the
  /// audiobooks.
  TrackTags? tagsOf(String location) =>
      library.tagsOf(location) ?? books.tagsOf(location);

  /// Takes [tags] in place of what is known of that track.
  void update(TrackTags tags) {
    if (library.tagsOf(tags.path) != null) {
      library.update(tags);
    } else {
      books.update(tags);
    }
  }
}

/// The remote sources of the Media Library, kept in the preferences. Remote sources load their
/// tracks when they are first picked in the tree.
class LibrarySourceManager extends ChangeNotifier {
  LibrarySourceManager({
    required this.local,
    required this.credentials,
    this.remoteFactory = createRemote,
    this.localVideos,
    this.onTracks,
    this.onNewEpisodes,
    this.progressStore,
    this.artworkGet = ioArtHttpGet,
    this.browserOpener = openInSystemBrowser,
    this.pkceFor = SoundCloudClient.pkce,
    this.plexSignIn = PlexSignIn.new,
  });

  static const _sourcesKey = "amped.library_sources";

  /// The local library, which the folders feed.
  final MediaLibrary local;

  /// The local video files, listed in the "Videos" section; null for no such
  /// section.
  final MediaLibrary? localVideos;

  /// The videos of every source, listed as "All videos".
  final MediaLibrary allVideos = MediaLibrary.videos();

  /// Where the passwords of remote sources are kept.
  final RemoteCredentialStore credentials;

  final RemoteLibrarySourceFactory remoteFactory;

  /// Hears the tracks of a source as they load, to keep their tags for the
  /// playlist.
  final void Function(List<TrackTags> tracks)? onTracks;

  /// Told when a refresh found episodes the source did not have before, with
  /// the source's name.
  final void Function(String source, List<TrackTags> episodes)? onNewEpisodes;

  /// Where how far the user got in an episode is kept, when there is such a
  /// place (asked each time: it may open after the manager is made).
  final ProgressStore? Function()? progressStore;

  /// Downloads a cover.
  final ArtHttpGet artworkGet;

  /// Opens the pages of browser sign-ins.
  final BrowserOpener browserOpener;

  /// The browser sign-in of a SoundCloud application.
  final PkceSignIn Function(String clientId, String secret) pkceFor;

  /// The browser sign-in at plex.tv.
  final PlexSignIn Function() plexSignIn;

  final List<_Remote> _remotes = [];
  bool _disposed = false;
  bool _watchingLocalVideos = false;

  /// The remote sources, in the order they were added.
  List<RemoteSourceConfig> get remotes => [
    for (final remote in _remotes) remote.config,
  ];

  /// Whether a podcast source (an RSS feed, Audiobookshelf) is added, so new
  /// episodes can come up.
  bool get hasPodcastSource =>
      _remotes.any((remote) => _isPodcast(remote.config.type));

  /// Keeps "All videos" in step with the videos of the sources.
  void _watchVideos(MediaLibrary videos) => videos.addListener(_mergeVideos);

  Timer? _mergeTimer;

  /// Merges at most every 300 ms while a source is still adding pages, so a
  /// big server doesn't re-sort every video after each page.
  void _mergeVideos() {
    if (_disposed) return;
    if (_remotes.any((remote) => remote.videos.scanning)) {
      _mergeTimer ??= Timer(const Duration(milliseconds: 300), () {
        _mergeTimer = null;
        _mergeVideosNow();
      });
      return;
    }
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _mergeVideosNow();
  }

  void _mergeVideosNow() {
    if (_disposed) return;
    allVideos.replaceWith([
      ...?localVideos?.tracks,
      for (final remote in _remotes) ...remote.videos.tracks,
    ]);
    for (final remote in _remotes) {
      // An episode knows its show and season; a movie has neither.
      bool episode(TrackTags t) => t.artist != null && t.album != null;
      remote.movies.replaceWith([
        for (final t in remote.videos.tracks)
          if (!episode(t)) t,
      ]);
      remote.shows.replaceWith([
        for (final t in remote.videos.tracks)
          if (episode(t)) t,
      ]);
    }
  }

  /// Whether the source with [id] is loading its tracks.
  bool isLoading(String id) => _find(id)?.library.scanning ?? false;

  /// The reason the source with [id] couldn't load, or null.
  String? errorOf(String id) => _find(id)?.error;

  _Remote? _find(String id) {
    for (final remote in _remotes) {
      if (remote.config.id == id) return remote;
    }
    return null;
  }

  _Remote _addRemote(RemoteSourceConfig config) {
    final remote = _Remote(config);
    _watchVideos(remote.videos);
    return remote;
  }

  /// Reads the folders and sources saved last time.
  Future<void> restore(SharedPreferences prefs) async {
    for (final remote in _remotes) {
      remote.videos.removeListener(_mergeVideos);
    }
    _remotes.clear();
    if (!_watchingLocalVideos) {
      _watchingLocalVideos = true;
      localVideos?.addListener(_mergeVideos);
    }
    final saved = prefs.getString(_sourcesKey);
    if (saved != null) {
      try {
        for (final json in jsonDecode(saved) as List<dynamic>) {
          _remotes.add(
            _addRemote(
              RemoteSourceConfig.fromJson(json as Map<String, dynamic>),
            ),
          );
        }
      } on Object catch (error) {
        Arcane.log(
          "Could not read the library sources",
          metadata: {"error": "$error"},
          level: Level.warning,
          module: "LibrarySourceManager",
        );
      }
    }
    _mergeVideos();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sourcesKey,
      jsonEncode([for (final remote in _remotes) remote.config.toJson()]),
    );
  }

  static String _credentialKey(String id) => "source:$id";

  // --- Remote sources -------------------------------------------------------

  /// Adds a Navidrome/Subsonic server. Throws what [check] throws when the
  /// server can't be used, and then adds nothing.
  Future<RemoteSourceConfig> addNavidrome({
    required String name,
    required String server,
    required String user,
    required String password,
    SourceSettings? settings,
  }) async {
    final config = RemoteSourceConfig(
      id: "navidrome-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.navidrome,
      name: name.trim().isEmpty ? SubsonicClient.normalizeServer(server) : name,
      server: SubsonicClient.normalizeServer(server),
      user: user,
      settings: settings,
    );
    await check(config, password);
    await credentials.write(
      _credentialKey(config.id),
      RemoteLogin(user, password),
    );
    _remotes.add(_track(_addRemote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  /// Adds a Plex Media Server, signed in with its `X-Plex-Token`. Throws
  /// what [check] throws when the server can't be used, and then adds
  /// nothing.
  Future<RemoteSourceConfig> addPlex({
    required String name,
    required String server,
    required String token,
    SourceSettings? settings,
  }) async {
    final config = RemoteSourceConfig(
      id: "plex-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.plex,
      name: name.trim().isEmpty ? PlexClient.normalizeServer(server) : name,
      server: PlexClient.normalizeServer(server),
      user: plexUser,
      settings: settings,
    );
    await check(config, token);
    await credentials.write(
      _credentialKey(config.id),
      RemoteLogin(plexUser, token),
    );
    _remotes.add(_track(_addRemote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  /// Adds a Jellyfin server, signed in with a user name and password. Throws
  /// what [check] throws when the server can't be used, and then adds
  /// nothing.
  Future<RemoteSourceConfig> addJellyfin({
    required String name,
    required String server,
    required String user,
    required String password,
    SourceSettings? settings,
  }) async {
    final config = RemoteSourceConfig(
      id: "jellyfin-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.jellyfin,
      name: name.trim().isEmpty ? JellyfinClient.normalizeServer(server) : name,
      server: JellyfinClient.normalizeServer(server),
      user: user,
      settings: settings,
    );
    await check(config, password);
    await credentials.write(
      _credentialKey(config.id),
      RemoteLogin(user, password),
    );
    _remotes.add(_track(_addRemote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  /// Subscribes to the podcast at the RSS feed [feed]. Throws when the feed
  /// can't be read, and then adds nothing. The name defaults to the
  /// podcast's title.
  Future<RemoteSourceConfig> addPodcast({
    required String name,
    required String feed,
    SourceSettings? settings,
  }) async {
    final normalized = RssClient.normalizeFeed(feed);
    var title = name.trim();
    final client = RssClient(feed: normalized);
    try {
      final podcast = await client.podcast();
      if (title.isEmpty) title = podcast.title;
    } finally {
      client.close();
    }
    final config = RemoteSourceConfig(
      id: "podcast-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.podcast,
      name: title,
      server: normalized,
      user: podcastUser,
      settings: settings,
    );
    await credentials.write(
      _credentialKey(config.id),
      const RemoteLogin(podcastUser, ""),
    );
    _remotes.add(_track(_Remote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  /// The "user" of a podcast feed, which has no sign-in.
  static const podcastUser = "feed";

  /// Adds the podcasts of an Audiobookshelf server, signed in with an API
  /// token. Throws what [check] throws, and then adds nothing.
  Future<RemoteSourceConfig> addAudiobookshelf({
    required String name,
    required String server,
    required String token,
    SourceSettings? settings,
  }) async {
    final normalized = AudiobookshelfClient.normalizeServer(server);
    final config = RemoteSourceConfig(
      id: "audiobookshelf-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.audiobookshelf,
      name: name.trim().isEmpty ? normalized : name,
      server: normalized,
      user: plexUser,
      settings: settings,
    );
    await check(config, token);
    await credentials.write(
      _credentialKey(config.id),
      RemoteLogin(plexUser, token),
    );
    _remotes.add(_track(_Remote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  /// The "user" of a Plex source, which signs in with a token alone.
  static const plexUser = "token";

  /// Signs in at plex.tv in the user's browser: the token, the address of
  /// the first server of their account (or null), and the users of their
  /// Plex Home to choose from.
  Future<({String token, String? server, List<PlexUser> users})>
  signInToPlex() async {
    final signIn = plexSignIn();
    try {
      final token = await signIn.signIn(browserOpener);
      final servers = await signIn.servers(token);
      final users = await signIn.homeUsers(token);
      return (
        token: token,
        server: servers.isEmpty ? null : servers.first,
        users: users,
      );
    } finally {
      signIn.close();
    }
  }

  /// The token that presents as [user] of the Plex Home [token] belongs to,
  /// given their [pin] when they have one.
  Future<String> switchPlexUser(
    String token,
    PlexUser user, {
    String? pin,
  }) async {
    final signIn = plexSignIn();
    try {
      return await signIn.switchUser(token, user, pin: pin);
    } finally {
      signIn.close();
    }
  }

  /// Adds a SoundCloud profile with the user's own application key: [profile]
  /// is its URL, [clientId] and [clientSecret] the key of an application they
  /// registered (which needs a SoundCloud Pro subscription). Throws what
  /// [check] throws, and then adds nothing.
  Future<RemoteSourceConfig> addSoundCloud({
    required String name,
    required String profile,
    required String clientId,
    required String clientSecret,
    bool browserSignIn = false,
    SourceSettings? settings,
  }) async {
    final normalized = browserSignIn
        ? "https://soundcloud.com/you"
        : SoundCloudClient.normalizeProfile(profile);
    final config = RemoteSourceConfig(
      id: "soundcloud-${DateTime.now().microsecondsSinceEpoch}",
      type: RemoteSourceType.soundcloud,
      name: name.trim().isEmpty ? normalized : name,
      server: normalized,
      user: clientId.trim(),
      settings: settings,
    );
    var password = clientSecret.trim();
    if (browserSignIn) {
      final tokens = await pkceFor(config.user, password).signIn(browserOpener);
      password = SoundCloudCredentials(password, tokens: tokens).encode();
    }
    password = await _checked(config, password);
    await credentials.write(
      _credentialKey(config.id),
      RemoteLogin(config.user, password),
    );
    _remotes.add(_track(_addRemote(config)));
    notifyListeners();
    await _save();
    return config;
  }

  static String _normalizeServer(RemoteSourceType type, String server) =>
      switch (type) {
        RemoteSourceType.navidrome => SubsonicClient.normalizeServer(server),
        RemoteSourceType.soundcloud => SoundCloudClient.normalizeProfile(
          server,
        ),
        RemoteSourceType.plex => PlexClient.normalizeServer(server),
        RemoteSourceType.jellyfin => JellyfinClient.normalizeServer(server),
        RemoteSourceType.podcast => RssClient.normalizeFeed(server),
        RemoteSourceType.audiobookshelf => AudiobookshelfClient.normalizeServer(
          server,
        ),
      };

  /// Changes a source. [password] null keeps the saved one. Throws when the
  /// changed source can't be used, and then changes nothing.
  Future<void> edit(
    String id, {
    String? name,
    String? server,
    String? user,
    String? password,
    SourceSettings? settings,
  }) async {
    final remote = _find(id);
    if (remote == null) return;
    final changed = remote.config.copyWith(
      settings: settings,
      name: name,
      server: server == null
          ? null
          : _normalizeServer(remote.config.type, server),
      user: user,
    );
    final saved = await credentials.read(_credentialKey(id));
    final newPassword = password ?? saved?.password ?? "";
    final reconnect =
        changed.server != remote.config.server ||
        changed.user != remote.config.user ||
        password != null;
    if (reconnect) await check(changed, newPassword);
    await credentials.write(
      _credentialKey(id),
      RemoteLogin(changed.user, newPassword),
    );
    final settingsChanged = changed.settings != remote.config.settings;
    remote.config = changed;
    if (_refreshStarted && (settingsChanged || reconnect)) {
      // The next look is one interval from now.
      _scheduleRefresh(remote, firstAfter: changed.settings.refreshEvery);
    }
    if (reconnect) {
      // Its tracks may be another server's now.
      remote.loaded = false;
      remote.videosLoaded = false;
      remote.error = null;
      remote.library.cancel();
      unawaited(remote.library.clear());
      remote.videos.cancel();
      unawaited(remote.videos.clear());
      remote.booksLoaded = false;
      remote.books.cancel();
      unawaited(remote.books.clear());
    }
    notifyListeners();
    await _save();
  }

  /// Takes the source away; the password is forgotten too.
  Future<void> remove(String id) async {
    final remote = _find(id);
    if (remote == null) return;
    _remotes.remove(remote);
    _refreshTimers.remove(id)?.cancel();
    remote.videos.removeListener(_mergeVideos);
    remote.library.dispose();
    remote.videos.dispose();
    remote.movies.dispose();
    remote.shows.dispose();
    remote.books.dispose();
    _mergeVideos();
    notifyListeners();
    await _save();
    await credentials.delete(_credentialKey(id));
  }

  /// [check], and the password to save: refreshed when the check refreshed
  /// the sign-in.
  Future<String> _checked(RemoteSourceConfig config, String password) async {
    final remote = remoteFactory(config, password);
    try {
      await remote.check();
      return (remote is RefreshesCredentials
              ? (remote as RefreshesCredentials).refreshedPassword
              : null) ??
          password;
    } finally {
      remote.close();
    }
  }

  /// Saves the sign-in that [remote] refreshed while it was used.
  Future<void> _keepRefreshed(String id, RemoteLibrarySource remote) async {
    final refreshed = remote is RefreshesCredentials
        ? (remote as RefreshesCredentials).refreshedPassword
        : null;
    final remoteSource = _find(id);
    if (refreshed == null || remoteSource == null) return;
    final login = await credentials.read(_credentialKey(id));
    await credentials.write(
      _credentialKey(id),
      RemoteLogin(login?.user ?? remoteSource.config.user, refreshed),
    );
  }

  /// Throws when [config] can't be connected to with [password].
  Future<void> check(RemoteSourceConfig config, String password) async {
    final remote = remoteFactory(config, password);
    try {
      await remote.check();
    } finally {
      remote.close();
    }
  }

  /// Loads the tracks of the source with [id], unless that was done
  /// already. A failure is kept for [errorOf] and shown in the tree's pane.
  Future<void> open(String id) async {
    final remote = _find(id);
    if (remote == null || remote.loaded || remote.library.scanning) return;
    remote.error = null;
    final login = await credentials.read(_credentialKey(id));
    if (login == null) {
      remote.error = "No saved password for ${remote.config.name}.";
      notifyListeners();
      return;
    }
    final connection = remoteFactory(remote.config, login.password);
    final saved = await _savedProgress(id);
    try {
      await remote.library.fill(
        (add, isCancelled) => connection.load((tracks) {
          final shown = saved.isEmpty
              ? tracks
              : [
                  for (final track in tracks)
                    track.progress == null && saved[track.path] != null
                        ? track.withProgress(saved[track.path]!.fraction)
                        : track,
                ];
          add(shown);
          onTracks?.call(shown);
        }, isCancelled),
      );
      remote.loaded = true;
    } on Object catch (error) {
      remote.error = error is RemoteAuthException
          ? error.message
          : error is SubsonicException
          ? error.message
          : error is SoundCloudException
          ? error.message
          : error is PlexException
          ? error.message
          : error is JellyfinException
          ? error.message
          : error is PodcastException
          ? error.message
          : "$error";
    } finally {
      await _keepRefreshed(id, connection);
      connection.close();
      if (!_disposed) notifyListeners();
    }
  }

  /// Loads the videos (movies, episodes) of the source with [id], unless that
  /// was done already. Kept apart from [open] so that browsing a server's
  /// music never waits for its movies. A failure is only logged: the music
  /// of the source is not affected.
  Future<void> openVideos(String id) async {
    final remote = _find(id);
    if (remote == null ||
        remote.videosLoaded ||
        remote.videos.scanning ||
        _isPodcast(remote.config.type)) {
      return;
    }
    final login = await credentials.read(_credentialKey(id));
    if (login == null) return;
    final connection = remoteFactory(remote.config, login.password);
    try {
      await remote.videos.fill(
        (add, isCancelled) => connection.loadVideos((videos) {
          add(videos);
          onTracks?.call(videos);
        }, isCancelled),
      );
      remote.videosLoaded = true;
      try {
        if (connection is HasVideoPlaylists) {
          remote.videoPlaylists = await (connection as HasVideoPlaylists)
              .loadVideoPlaylists();
        }
      } on Object catch (error) {
        Arcane.log(
          "Could not load the playlists",
          metadata: {"source": remote.config.name, "error": "$error"},
          level: Level.warning,
          module: "LibrarySourceManager",
        );
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not load the videos",
        metadata: {"source": remote.config.name, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
    } finally {
      await _keepRefreshed(id, connection);
      connection.close();
      if (!_disposed) notifyListeners();
    }
  }

  /// Loads the audiobooks of the source with [id] (a server that has them),
  /// unless that was done already. A failure is only logged: the podcasts of
  /// the source are not affected.
  Future<void> openBooks(String id) async {
    final remote = _find(id);
    if (remote == null || remote.booksLoaded || remote.books.scanning) return;
    final login = await credentials.read(_credentialKey(id));
    if (login == null) return;
    final connection = remoteFactory(remote.config, login.password);
    if (connection is! HasBooks) {
      connection.close();
      return;
    }
    final saved = await _savedProgress(id);
    try {
      await remote.books.fill(
        (add, isCancelled) => (connection as HasBooks).loadBooks((tracks) {
          final shown = _withSaved(tracks, saved);
          add(shown);
          onTracks?.call(shown);
        }, isCancelled),
      );
      remote.booksLoaded = true;
    } on Object catch (error) {
      Arcane.log(
        "Could not load the books",
        metadata: {"source": remote.config.name, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
    } finally {
      await _keepRefreshed(id, connection);
      connection.close();
      if (!_disposed) notifyListeners();
    }
  }

  /// [tracks] with the progress that was saved here for those the server
  /// gave none for.
  static List<TrackTags> _withSaved(
    List<TrackTags> tracks,
    Map<String, PlaybackProgress> saved,
  ) => saved.isEmpty
      ? tracks
      : [
          for (final track in tracks)
            track.progress == null && saved[track.path] != null
                ? track.withProgress(saved[track.path]!.fraction)
                : track,
        ];

  /// The URL to play for the source location [location]: signed with the
  /// saved login, fresh every time. Throws when the source was removed or
  /// has no saved login.
  Future<String> resolve(String location) async {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    if (parsed == null || remote == null) {
      throw SubsonicException("The source of $location was removed.");
    }
    final login = await credentials.read(_credentialKey(parsed.sourceId));
    if (login == null) {
      throw RemoteAuthException("No saved password for ${remote.config.name}.");
    }
    final connection = remoteFactory(remote.config, login.password);
    try {
      return await connection.streamUrl(parsed.itemId);
    } finally {
      await _keepRefreshed(parsed.sourceId, connection);
      connection.close();
    }
  }

  /// What was saved of how far the user got in the tracks of the source
  /// [sourceId], by location.
  Future<Map<String, PlaybackProgress>> _savedProgress(String sourceId) async {
    try {
      return await progressStore?.call()?.progressWithPrefix(
            SourceLocation.build(sourceId, ""),
          ) ??
          const {};
    } on Object catch (error) {
      Arcane.log(
        "Could not read the saved progress",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
      return const {};
    }
  }

  /// Notes that the user got to [position] of the [duration] long source
  /// track [location], or finished it: kept here, shown in the library and,
  /// for a server that wants to know, sent to it. Never throws.
  Future<void> saveProgress(
    String location,
    Duration position,
    Duration duration, {
    bool finished = false,
  }) async {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    if (parsed == null || remote == null || duration <= Duration.zero) return;
    // The last seconds of an episode are its credits: it counts as heard.
    final done = finished || duration - position <= const Duration(seconds: 10);
    final progress = PlaybackProgress(position, duration, finished: done);
    try {
      await progressStore?.call()?.saveProgress(location, progress);
    } on Object catch (error) {
      Arcane.log(
        "Could not save the progress",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
    }
    if (_disposed) return;
    if (remote.tagsOf(location) case final tags?) {
      remote.update(tags.withProgress(progress.fraction));
    }
    try {
      final login = await credentials.read(_credentialKey(parsed.sourceId));
      if (login == null) return;
      final connection = remoteFactory(remote.config, login.password);
      try {
        if (connection is ReportsProgress) {
          await (connection as ReportsProgress).reportProgress(
            parsed.itemId,
            position,
            duration,
            finished: done,
          );
        }
      } finally {
        await _keepRefreshed(parsed.sourceId, connection);
        connection.close();
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not report the progress",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
    }
  }

  /// What the loaded source knows of its track at [location], or null (the
  /// source was not loaded, or has no such track).
  TrackTags? tagsOf(String location) {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    return remote?.tagsOf(location);
  }

  /// Whether [location] is an episode of a podcast source.
  bool isPodcast(String location) {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    return remote != null && _isPodcast(remote.config.type);
  }

  /// Whether [location] is a video of a server.
  bool isVideo(String location) {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    return remote?.videos.tagsOf(location) != null;
  }

  /// Whether [location] is an audiobook of a server (not a podcast episode).
  bool isBook(String location) {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    return remote?.books.tagsOf(location) != null;
  }

  /// Marks the episodes at [locations] as played (all of it heard) or as
  /// not played (not started), here and on the server that keeps progress.
  Future<void> markPlayed(
    Iterable<String> locations, {
    required bool played,
  }) async {
    for (final location in locations) {
      final parsed = SourceLocation.parse(location);
      final remote = parsed == null ? null : _find(parsed.sourceId);
      if (remote == null) continue;
      // Without a known length, any will do to say "all of it".
      final length =
          remote.tagsOf(location)?.duration ?? const Duration(seconds: 1);
      await saveProgress(
        location,
        played ? length : Duration.zero,
        length,
        finished: played,
      );
    }
  }

  /// The ids of the sources the tracks at [locations] belong to.
  static Set<String> sourcesOf(Iterable<String> locations) => {
    for (final location in locations)
      if (SourceLocation.parse(location) case final parsed?) parsed.sourceId,
  };

  /// Where the user stopped playing the source track [location]: what its
  /// server says, or for a source whose server keeps none, what was saved
  /// here. Null when the track was not started, is finished or counts as
  /// played (as the source's settings say), or the server can't be reached.
  Future<Duration?> resumePosition(String location) async {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    if (parsed == null || remote == null) return null;
    try {
      final login = await credentials.read(_credentialKey(parsed.sourceId));
      if (login == null) return null;
      final connection = remoteFactory(remote.config, login.password);
      Duration? position;
      Duration? duration = remote.tagsOf(location)?.duration;
      try {
        if (connection is ResumesPlayback) {
          position = await (connection as ResumesPlayback).resumePosition(
            parsed.itemId,
          );
        } else {
          final saved = (await progressStore?.call()?.progressWithPrefix(
            location,
          ))?[location];
          if (saved != null && !saved.finished) position = saved.position;
          duration ??= saved?.duration;
        }
      } finally {
        await _keepRefreshed(parsed.sourceId, connection);
        connection.close();
      }
      // Played as far as this source counts as played: nothing to resume.
      if (position != null &&
          duration != null &&
          remote.config.settings.completion.isCompleted(
            position: position,
            duration: duration,
          )) {
        return null;
      }
      return position;
    } on Object catch (error) {
      Arcane.log(
        "Could not get the progress",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
      return null;
    }
  }

  /// The cover of the source track [location], downloaded from its server,
  /// or null when it has none or the server can't be reached. The picture
  /// the library holds for the track is used when it has one; otherwise the
  /// server is asked for it by id.
  Future<Uint8List?> artwork(String location) async {
    final parsed = SourceLocation.parse(location);
    final remote = parsed == null ? null : _find(parsed.sourceId);
    if (parsed == null || remote == null) return null;
    final cached = _artwork[location];
    if (cached != null) return cached;
    try {
      var url =
          (remote.tagsOf(location) ?? remote.videos.tagsOf(location))?.imageUrl;
      if (url == null) {
        final login = await credentials.read(_credentialKey(parsed.sourceId));
        if (login == null) return null;
        final connection = remoteFactory(remote.config, login.password);
        try {
          url = await connection.coverUrl(parsed.itemId);
        } finally {
          await _keepRefreshed(parsed.sourceId, connection);
          connection.close();
        }
      }
      if (url == null) return null;
      final bytes = await artworkGet(Uri.parse(url));
      if (bytes == null) return null;
      if (_artwork.length >= _artworkKept) _artwork.remove(_artwork.keys.first);
      return _artwork[location] = bytes;
    } on Object catch (error) {
      Arcane.log(
        "Could not get the cover",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "LibrarySourceManager",
      );
      return null;
    }
  }

  /// The covers fetched last, by location, so a track's cover isn't
  /// downloaded again for each window and notification that shows it.
  final Map<String, Uint8List> _artwork = {};
  static const _artworkKept = 20;

  final Map<String, Timer> _refreshTimers = {};
  final Set<String> _refreshingIds = {};
  bool _refreshStarted = false;

  /// Starts refreshing the sources in the background as each one's settings
  /// say: the first time after its first delay, then at its interval, until
  /// [dispose] or the next call. [firstAfter] and [every] stand in for the
  /// settings of every source when given.
  void startRefreshing({Duration? firstAfter, Duration? every}) {
    _refreshStarted = true;
    for (final remote in _remotes) {
      _scheduleRefresh(remote, firstAfter: firstAfter, every: every);
      // Videos are listed once there are some, so they are looked for now.
      unawaited(openVideos(remote.config.id));
    }
  }

  /// A source that was added or restored: refreshed from now on, if the
  /// refreshing was started.
  _Remote _track(_Remote remote) {
    if (_refreshStarted) {
      _scheduleRefresh(remote);
      unawaited(openVideos(remote.config.id));
    }
    return remote;
  }

  /// Schedules, or cancels, the background refresh of [remote] as its
  /// settings say.
  void _scheduleRefresh(
    _Remote remote, {
    Duration? firstAfter,
    Duration? every,
  }) {
    final id = remote.config.id;
    _refreshTimers.remove(id)?.cancel();
    if (_disposed) return;
    final settings = remote.config.settings;
    if (every == null && !settings.refresh) return;
    final interval = every ?? settings.refreshEvery;
    _refreshTimers[id] = Timer(firstAfter ?? settings.refreshFirst, () {
      unawaited(_refresh(remote));
      _refreshTimers[id] = Timer.periodic(
        interval,
        (_) => unawaited(_refresh(remote)),
      );
    });
  }

  /// Looks at each podcast source again now, quietly (see [_refresh]).
  Future<void> refreshPodcasts() async {
    for (final remote in [..._remotes]) {
      if (_disposed) return;
      if (_isPodcast(remote.config.type)) await _refresh(remote);
    }
  }

  /// Looks at [remote] again, quietly: the list on screen changes only when
  /// the server's has, nothing flashes or goes empty, and [onNewEpisodes]
  /// hears of the episodes of a podcast that were not there before. A source
  /// that was never loaded is loaded now, without saying that everything in
  /// it is new. A failure is only logged, and the source is left as it was.
  Future<void> _refresh(_Remote remote) async {
    final id = remote.config.id;
    // Someone is loading it on screen; that is as good as a refresh.
    if (_disposed || remote.library.scanning || !_refreshingIds.add(id)) return;
    try {
      final login = await credentials.read(_credentialKey(id));
      if (login == null || _disposed || !_remotes.contains(remote)) return;
      final connection = remoteFactory(remote.config, login.password);
      try {
        final saved = await _savedProgress(id);
        final fresh = <TrackTags>[];
        await connection.load(
          (tracks) => fresh.addAll([
            for (final track in tracks)
              track.progress == null && saved[track.path] != null
                  ? track.withProgress(saved[track.path]!.fraction)
                  : track,
          ]),
          () => _disposed,
        );
        if (_disposed || !_remotes.contains(remote)) return;
        // Looked at again meanwhile by the user: theirs is the newer.
        if (remote.library.scanning) return;
        final first = !remote.loaded;
        final added = first
            ? const <TrackTags>[]
            : [
                for (final track in fresh)
                  if (remote.library.tagsOf(track.path) == null) track,
              ];
        final changed =
            first ||
            added.isNotEmpty ||
            fresh.length != remote.library.tracks.length ||
            fresh.any((track) => remote.library.tagsOf(track.path) != track);
        if (changed) {
          remote.library.replaceWith(fresh);
          onTracks?.call(fresh);
        }
        remote.loaded = true;
        remote.error = null;
        if (changed) notifyListeners();
        if (added.isNotEmpty && _isPodcast(remote.config.type)) {
          onNewEpisodes?.call(remote.config.name, added);
        }
        // The audiobooks, if they were looked at, are kept up to date too.
        if (remote.booksLoaded &&
            !remote.books.scanning &&
            connection is HasBooks) {
          final books = <TrackTags>[];
          await (connection as HasBooks).loadBooks(
            (tracks) => books.addAll(_withSaved(tracks, saved)),
            () => _disposed,
          );
          if (!_disposed && remote.books.tracks.length != books.length ||
              books.any((track) => remote.books.tagsOf(track.path) != track)) {
            remote.books.replaceWith(books);
            onTracks?.call(books);
            if (!_disposed) notifyListeners();
          }
        }
      } on Object catch (error) {
        Arcane.log(
          "Could not refresh the source",
          metadata: {"source": remote.config.name, "error": "$error"},
          level: Level.warning,
          module: "LibrarySourceManager",
        );
      } finally {
        await _keepRefreshed(id, connection);
        connection.close();
      }
    } finally {
      _refreshingIds.remove(id);
    }
  }

  /// Loads the source again, from the server.
  Future<void> reload(String id) async {
    final remote = _find(id);
    if (remote == null) return;
    remote.loaded = false;
    await open(id);
    if (remote.booksLoaded) {
      remote.booksLoaded = false;
      await openBooks(id);
    }
  }

  static bool _isPodcast(RemoteSourceType type) =>
      type == RemoteSourceType.podcast ||
      type == RemoteSourceType.audiobookshelf;

  static String _moviesOf(String name) => "$name - Movies";
  static String _showsOf(String name) => "$name - TV shows";

  /// The tree: the local library, then the remote sources.
  List<LibrarySourceSection> sections({
    required String localLabel,
    String allVideosLabel = "All videos",
    String Function(String name) moviesLabel = _moviesOf,
    String Function(String name) showsLabel = _showsOf,
  }) {
    final base = librarySections(local, localLabel: localLabel);
    final video = localVideos;
    // A source with no videos is left out until it has some.
    final videoSources = <LibrarySource>[
      if (!allVideos.isEmpty)
        LibrarySource(
          id: allVideosSourceId,
          label: allVideosLabel,
          library: allVideos,
          onOpen: () {
            _mergeVideos();
            for (final remote in _remotes) {
              unawaited(openVideos(remote.config.id));
            }
          },
        ),
      if (video != null && !video.isEmpty)
        LibrarySource(
          id: "$videoSourcePrefix$localSourceId",
          label: localLabel,
          library: video,
        ),
      for (final remote in _remotes)
        if (!_isPodcast(remote.config.type)) ...[
          if (remote.error != null || !remote.movies.isEmpty)
            LibrarySource(
              id: "$videoSourcePrefix${remote.config.id}:movies",
              label: moviesLabel(remote.config.name),
              library: remote.error == null ? remote.movies : null,
              error: remote.error,
              movies: true,
              lists: remote.videoPlaylists,
              onOpen: () => unawaited(openVideos(remote.config.id)),
            ),
          if (remote.error != null || !remote.shows.isEmpty)
            LibrarySource(
              id: "$videoSourcePrefix${remote.config.id}:shows",
              label: showsLabel(remote.config.name),
              library: remote.error == null ? remote.shows : null,
              error: remote.error,
              shows: true,
              onOpen: () => unawaited(openVideos(remote.config.id)),
            ),
        ],
    ];
    final videoSection = video == null || videoSources.isEmpty
        ? null
        : LibrarySourceSection(
            id: videosSectionId,
            kind: LibrarySourceKind.videos,
            sources: videoSources,
          );
    if (videoSection != null) base.insert(1, videoSection);
    LibrarySourceSection? section(
      String id,
      LibrarySourceKind kind,
      bool Function(RemoteSourceType type) wanted,
    ) {
      final remotes = [
        for (final remote in _remotes)
          if (wanted(remote.config.type)) remote,
      ];
      if (remotes.isEmpty) return null;
      return LibrarySourceSection(
        id: id,
        kind: kind,
        sources: [
          for (final remote in remotes)
            LibrarySource(
              id: remote.config.id,
              label: remote.config.name,
              library: remote.error == null ? remote.library : null,
              error: remote.error,
              onOpen: () => unawaited(open(remote.config.id)),
              podcast: kind == LibrarySourceKind.podcasts,
              completion: remote.config.settings.completion,
            ),
        ],
      );
    }

    // The servers that have audiobooks, each as a source of its own.
    final books = [
      for (final remote in _remotes)
        if (remote.config.type == RemoteSourceType.audiobookshelf) remote,
    ];
    return [
      ...base,
      ?section("remote", LibrarySourceKind.remote, (type) => !_isPodcast(type)),
      ?section("podcasts", LibrarySourceKind.podcasts, _isPodcast),
      if (books.isNotEmpty)
        LibrarySourceSection(
          id: audiobooksSectionId,
          kind: LibrarySourceKind.audiobooks,
          sources: [
            for (final remote in books)
              LibrarySource(
                id: "$bookSourcePrefix${remote.config.id}",
                label: remote.config.name,
                library: remote.error == null ? remote.books : null,
                error: remote.error,
                podcast: true,
                audiobooks: true,
                completion: remote.config.settings.completion,
                onOpen: () => unawaited(openBooks(remote.config.id)),
              ),
          ],
        ),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _mergeTimer?.cancel();
    localVideos?.removeListener(_mergeVideos);
    for (final remote in _remotes) {
      remote.library.dispose();
      remote.videos.dispose();
      remote.books.dispose();
    }
    allVideos.dispose();
    super.dispose();
  }
}
