import "dart:async";
import "dart:io";
import "dart:math";

import "package:amped_classic_skin/amped_classic_skin.dart"
    show PlaylistNavigator, embedWindowInsets, videoWindowInsets;
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_update_checker/amped_update_checker.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:amped_youtube/amped_youtube.dart" show YouTubeLink;
import "package:amped_ytdlp/amped_ytdlp.dart" show YtDlp;
import "package:flutter/foundation.dart";
import "package:flutter/painting.dart" show EdgeInsets;
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_dock/window_dock.dart";

import "../features/preferences/preferences_navigation.dart";
import "../features/preferences/preferences_page.dart";
import "../library/library_source_manager.dart";
import "../library/library_view_settings.dart";
import "../library/media_library.dart";
import "../library/play_stats.dart";
import "../library/saved_playlists.dart";
import "../library/watch_folders.dart";
import "../main_window/presets_window.dart";
import "../platform/single_instance.dart";
import "../platform/system_tray_menu.dart";
import "../player/album_art.dart";
import "../player/online_art.dart";
import "../player/player_state.dart";
import "../player/playlist.dart";
import "../player/tag_cache.dart";
import "../player/video_cast.dart";
import "../remote/remote_credentials.dart";
import "../remote/remote_files.dart";
import "../remote/remote_progress_text.dart";
import "../skin/skin_manager.dart";
import "../skin/skin_previewer.dart";
import "../skin/skin_views.dart";
import "../vis/classic_vis_clicks.dart";
import "../vis/vis_host.dart";
import "amped_dialog.dart";
import "amped_menus.dart";
import "cover_art.dart";
import "dialog_manager.dart";
import "dialog_requests.dart";

import "episode_click_action.dart";
import "file_actions.dart";
import "library_actions.dart";
import "main_window_scale.dart";
import "modern_host.dart";
import "modern_video.dart";
import "notification_position.dart";
import "notifications.dart";
import "now_playing.dart";
import "playlist_persistence.dart";
import "shell_classic_host.dart";
import "shell_menu_bar.dart";
import "skin_installer.dart";
import "tag_actions.dart";
import "vis_controller.dart";
import "window_state.dart";

/// The platform channel to the native menu bar (macOS app menu).
const MethodChannel ampedChannel = MethodChannel("amped");

/// Owns every Amped window: creates them through Flutter's windowing API,
/// docks them with a [DockManager], and persists their geometry.
///
/// The skinned windows are created lazily the first time they open and are
/// hidden (not destroyed) when closed, so they reopen at their last rect.
class AmpedShell extends ChangeNotifier {
  AmpedShell._({
    required this.player,
    required this.skins,
    required this.skinPreviewer,
    required this.localizations,
    required Map<SkinWindow, Offset> savedPositions,
    required Map<SkinWindow, Size> savedSizes,
    required this._initialNotifications,
    this._launch,
    this._instance,
    this._thingerOpen,
    this._albumArtLockAspect = true,
    double? mainScale,
  }) {
    windowState = WindowState(
      dock: dock,
      skin: () => skins.current,
      isShaded: isShaded,
      ownNotifier: () => _ownNotifier,
      ownNotifierOrigin: _ownNotifierOrigin,
      changed: notifyListeners,
      savedPositions: savedPositions,
      sizes: savedSizes,
      scale: player.uiScale,
      mainScale: mainScale ?? player.uiScale,
    );
  }

  /// The windows' sizes, scales and where they were left.
  late final WindowState windowState;

  /// Loads the persisted window state and creates the main window.
  ///
  /// On Windows and Linux, [launch] is what the command line asks to open,
  /// and [instance] receives what later launches ask for.
  static Future<AmpedShell> load({
    required PlayerState player,
    required SkinManager skins,
    required AppLocalizations localizations,
    LaunchRequest? launch,
    SingleInstance? instance,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await WindowState.loadSaved(prefs);
    final skinRegistry = await SkinRegistry.load(
      await SkinManager.skinsDirectory(),
    );
    final shell = AmpedShell._(
      player: player,
      skins: skins,
      skinPreviewer: SkinPreviewer(skinRegistry, SkinManager.defaultFormats),
      localizations: localizations,
      savedPositions: saved.positions,
      savedSizes: saved.sizes,
      launch: launch,
      instance: instance,
      thingerOpen: prefs.getBool(_thingerOpenKey),
      albumArtLockAspect: prefs.getBool(_albumArtLockAspectKey) ?? true,
      initialNotifications: Notifications.saved(prefs),
      mainScale: saved.mainScale,
    );
    shell.skinInstaller.remakePreviewsLater();
    await shell.sources.restore(prefs);
    shell.libraryViewSettings = LibraryViewSettings.load(prefs);
    shell.dialogManager.restore(prefs);
    shell._init();
    return shell;
  }

  final PlayerState player;
  final SkinManager skins;

  /// Renders skin preview images for skin pickers.
  final SkinPreviewer skinPreviewer;

  /// The skin on show: what each window looks like.
  Skin get skin => skins.current;
  final AppLocalizations localizations;

  late final DockManager<SkinWindow> dock =
      DockManager(
          primary: SkinWindow.main,
        )
        ..addListener(_scheduleSave)
        ..addListener(_announceMoves);

  final Map<SkinWindow, Offset> _announcedAt = {};
  final Map<SkinWindow, Timer> _moveEnds = {};

  /// Tells a modern skin's layouts their window moved (`Layout.onMove`), and
  /// a moment after it stopped, that the move ended (`onEndMove`).
  void _announceMoves() {
    final scripts = _scripts;
    if (scripts == null) return;
    for (final window in dock.windows) {
      final at = dock.rectOf(window)?.topLeft;
      final last = _announcedAt[window];
      _announcedAt[window] = at ?? Offset.zero;
      if (at == null || last == null || last == at) continue;
      final layout = skin.modern?.layout(window);
      if (layout == null) continue;
      scripts.layoutMoved(layout, ended: false);
      _moveEnds[window]?.cancel();
      _moveEnds[window] = Timer(const Duration(milliseconds: 250), () {
        _moveEnds.remove(window);
        _scripts?.layoutMoved(layout, ended: true);
      });
    }
  }

  /// The command line's request, until it has been opened.
  LaunchRequest? _launch;

  /// Hands over what later launches ask to open.
  final SingleInstance? _instance;

  /// Text temporarily shown in the main window's song title while a control
  /// is held (volume, seek, EQ band, clutterbar help), like `draw_songname`
  /// with a transient string.
  final ValueNotifier<String?> songTitleOverride = ValueNotifier(null);

  /// Whether the Thinger was left open, or null to follow the skin's
  /// `default_visible`.
  bool? _thingerOpen;

  static const String _thingerOpenKey = "amped.thinger_open";

  /// What modern skins' controls act on.
  late final ShellWasabiHost wasabiHost = ShellWasabiHost(this);

  /// The active modern skin's running scripts.
  WasabiScriptRuntime? _scripts;

  WasabiScriptRuntime? get wasabiScripts => _scripts;
  WasabiSkinData? _scriptedSkin;

  /// The OS media session (Now Playing, media keys).
  late final NowPlaying nowPlaying;
  SystemTrayMenu? _systemTrayMenu;

  /// The playlist editor's keyboard navigation, while it is showing.
  PlaylistNavigator? playlistNavigator;

  /// The visualization plug-in host.
  /// The classic skin windows' view of the shell.
  late final ShellClassicHost classic = ShellClassicHost(this);

  /// The tracks added to the Media Library.
  final MediaLibrary library = MediaLibrary();

  /// The video files added to the Media Library, in its "Videos" section.
  final MediaLibrary videoLibrary = MediaLibrary.videos();

  /// The folders Preferences > Media Library keeps the library up to date
  /// with.
  late final WatchFolders watchFolders = WatchFolders(
    library: library,
    videos: videoLibrary,
  );

  /// The playlists kept in the Media Library.
  final SavedPlaylists savedPlaylists = SavedPlaylists();

  /// The visualization's window and the slots of modern skins that run it.
  late final VisController visualization = VisController(
    vis: vis,
    dialogs: dialogManager,
    dock: dock,
    scripts: () => _scripts,
    playerChanged: _onPlayerChanged,
  );

  /// Where the video is shown when a modern skin takes it from its window.
  late final ModernVideo modernVideo = ModernVideo(
    player: player,
    scripts: () => _scripts,
    changed: _onPlayerChanged,
  );

  /// Plays the video on a Chromecast.
  late final VideoCastController chromecast = VideoCastController(
    onStarted: player.castStarted,
    onEnded: player.castEnded,
    onFinished: player.castFinished,
  );

  /// Reads YouTube links for a single stream with picture and sound, which
  /// a device plays (the player's own are two).
  final YtDlp _castYtDlp = YtDlp(
    log: (message, {metadata}) => Arcane.log(
      message,
      level: Level.info,
      module: "AmpedShell",
      metadata: metadata,
    ),
  );

  /// The address a device fetches for [location]: a media server's track
  /// by its signed address, a YouTube video as one stream, anything else
  /// as it is. `null` when none could be found.
  Future<String?> _castLocation(String location) async {
    final youtube = YouTubeLink.tryParse(location)?.videoUrl;
    if (youtube != null) {
      return (await _castYtDlp.addresses(
        youtube,
        format: "b[ext=mp4]/b",
      )).firstOrNull;
    }
    if (SourceLocation.isSource(location)) {
      try {
        return await SourceLocation.resolve(location);
      } on Object {
        return null;
      }
    }
    return location;
  }

  /// The picture that goes with [location] to a device: a YouTube
  /// video's thumbnail (an address), else the cover of a track or the one
  /// beside a video, else a frame of the video playing.
  Future<(Uint8List?, String?)> _castPicture(String location) async {
    final id = YouTubeLink.tryParse(location)?.videoId;
    if (id != null) return (null, "https://i.ytimg.com/vi/$id/hqdefault.jpg");
    try {
      final cover = await covers.readCoverBytes(location);
      if (cover != null) return (cover, null);
      // A frame is only worth it from where the video plays, not from the
      // first frame of a track that follows.
      if (player.videoPlaying && !chromecast.holding) {
        return (await player.video?.screenshot(), null);
      }
    } on Object {
      // No picture, then.
    }
    return (null, null);
  }

  /// Plays what is playing on [target], from where it is.
  Future<void> castTo(CastTarget target) async {
    final entry = player.playlist.currentEntry;
    if (entry == null || !(player.playing || player.paused)) return;
    // A track the device can't play, or whose address is not found, ends
    // the cast, and plays here.
    final location = VideoCastController.canCast(entry.location)
        ? await _castLocation(entry.location)
        : null;
    // The track may have changed while its address was looked for.
    if (!identical(player.playlist.currentEntry, entry) ||
        !(player.playing || player.paused)) {
      return;
    }
    if (location == null) {
      chromecast.failed();
      if (chromecast.holding) unawaited(chromecast.stop());
      return;
    }
    final picture = await _castPicture(entry.location);
    if (!identical(player.playlist.currentEntry, entry)) return;
    // A station has no position to start from.
    final length = entry.duration ?? Duration.zero;
    await chromecast.cast(
      target,
      location,
      title: entry.playingTitle,
      picture: picture.$1,
      pictureUrl: picture.$2,
      from: length > Duration.zero
          ? Duration(seconds: player.elapsedSec)
          : Duration.zero,
      volume: player.volume / 255,
      paused: player.paused,
    );
  }

  /// The native menu bar's two-way link with the shell.
  late final ShellMenuBar menuBar = ShellMenuBar(this);

  /// What the Media Library asks of the app.
  late final LibraryActions libraryActions = LibraryActions(
    player: player,
    localizations: localizations,
    files: files,
    library: library,
    videoLibrary: videoLibrary,
    savedPlaylists: savedPlaylists,
    watchFolders: watchFolders,
  );

  /// How often things were played, for the Media Library's statistics.
  late final PlayStats playStats = PlayStats(
    () => switch (player.playlist.tagCache) {
      final PlayStatsStore store => store,
      _ => null,
    },
  );

  /// The remote sources (Navidrome...) in the Media Library's tree.
  late final LibrarySourceManager sources = LibrarySourceManager(
    local: library,
    localVideos: videoLibrary,
    credentials: RemoteFiles.shared.store ?? SecureCredentialStore(),
    // The playlist takes the titles of source tracks from the tag cache.
    onTracks: (tracks) => unawaited(_keepSourceTags(tracks)),
    onNewEpisodes: (source, episodes) =>
        unawaited(_announceEpisodes(source, episodes)),
    // Where the user left off in episodes is kept beside the tags.
    progressStore: () => switch (player.playlist.tagCache) {
      final ProgressStore store => store,
      _ => null,
    },
  );

  /// How the Media Library was left (source, picks, sorting, column order),
  /// which a window opened later starts from.
  LibraryViewSettings libraryViewSettings = const LibraryViewSettings();

  /// Remembers [settings] now and in the preferences.
  void saveLibraryViewSettings(LibraryViewSettings settings) {
    libraryViewSettings = settings;
    unawaited(
      SharedPreferences.getInstance().then(settings.save).catchError((
        Object error,
      ) {
        Arcane.log(
          "Could not save the Media Library settings",
          metadata: {"error": "$error"},
          level: Level.warning,
          module: "AmpedShell",
        );
      }),
    );
  }

  /// How many new episodes a notification lists before "and N more".
  static const _episodesListed = 3;

  /// Notifies that a refresh found new [episodes] of the podcast source
  /// [source].
  Future<void> _announceEpisodes(
    String source,
    List<TrackTags> episodes,
  ) async {
    final text = localizations;
    final lines = [
      for (final episode in episodes.take(_episodesListed))
        text.newEpisodeLine(
          episode.album ?? source,
          episode.title ?? episode.path,
        ),
      if (episodes.length > _episodesListed)
        text.newEpisodeMore(episodes.length - _episodesListed),
    ];
    // One episode brings its cover along.
    final cover = episodes.length == 1
        ? await sources.artwork(episodes.single.path)
        : null;
    await notifications.announce(
      title: text.newEpisodeTitle(episodes.length),
      body: lines.join("\n"),
      artwork: cover,
      episodes: [for (final episode in episodes) episode.path],
    );
  }

  /// Keeps the tags of source [tracks] in the tag cache and gives them to
  /// the playlist entries that were waiting for them.
  Future<void> _keepSourceTags(List<TrackTags> tracks) async {
    await player.playlist.tagCache?.store(tracks);
    await player.playlist.takeSourceTags();
  }

  late final VisHost vis = VisHost(player)
    ..addListener(() => visualization.changed());

  /// The playing item's cover, for the Album Art window and modern skins'
  /// `<AlbumArt>` objects.
  late final NowPlayingArt albumArt = NowPlayingArt(
    player,
    read: covers.readCoverBytes,
  );

  /// Saving tags and artwork for the metadata dialogs.
  late final TagActions tags = TagActions(
    player: player,
    localizations: localizations,
    files: files,
    library: library,
    fileInfoWindow: () => dialogManager.windows[AmpedDialog.fileInfo],
  );

  /// Where covers are read from and kept.
  late final CoverArt covers = CoverArt(
    player: player,
    channel: ampedChannel,
    refreshArt: () => albumArt.refresh(),
    saveTags: tags.saveFileTags,
  );

  /// The cover from iTunes, for a skin notifier's "Internet" cover.
  late final OnlineArt onlineArt = OnlineArt(player);

  /// Whether the Album Art window keeps the cover's shape
  /// (gen_classicart `wnd_lock_aspect`, on by default).
  bool get albumArtLockAspect => _albumArtLockAspect;
  bool _albumArtLockAspect;

  static const String _albumArtLockAspectKey = "amped.albumart_lock_aspect";

  void toggleAlbumArtLockAspect() {
    _albumArtLockAspect = !_albumArtLockAspect;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_albumArtLockAspectKey, _albumArtLockAspect),
      ),
    );
    notifyListeners();
  }

  final ({
    bool enabled,
    bool native,
    NotificationPosition position,
    EpisodeClickAction episodeClick,
  })
  _initialNotifications;

  /// Whether the skin-independent notification stands in for the notifier:
  /// the skin has no notifier container of its own.
  bool get _ownNotifier => skin.ownsNotifier;

  /// The popup, system notification or skin notifier for a new track.
  late final Notifications notifications = Notifications(
    player: player,
    channel: ampedChannel,
    scripts: () => _scripts,
    ownNotifier: () => _ownNotifier,
    readCover: covers.readCoverBytes,
    placeNotifier: _placeNotifier,
    playerChanged: _onPlayerChanged,
    changed: notifyListeners,
    enabled: _initialNotifications.enabled,
    native: _initialNotifications.native,
    position: _initialNotifications.position,
    episodeClick: _initialNotifications.episodeClick,
    sourceTags: (location) => sources.tagsOf(location),
  );

  /// Where the Preferences dialog is in its page tree.
  final PreferencesNavigation preferences = PreferencesNavigation();

  /// Putting skins in, and the file manager's previews of their folders.
  late final SkinInstaller skinInstaller = SkinInstaller(
    skins: skins,
    localizations: localizations,
    files: () => files,
    songTitle: songTitleOverride,
  );

  /// The playlist and Media Library kept between runs.
  late final PlaylistPersistence persistence = PlaylistPersistence(
    player: player,
    library: library,
    videoLibrary: videoLibrary,
    savedPlaylists: savedPlaylists,
    watchFolders: watchFolders,
  );

  /// Opening, adding and saving files, and the prompts and drops around it.
  late final FileActions files = FileActions(
    player: player,
    localizations: localizations,
    channel: ampedChannel,
    owner: () => windowState.controllers[SkinWindow.main],
    installSkin: (path) => skinInstaller.install(path),
  );

  /// The dialog windows.
  late final DialogManager dialogManager = DialogManager(
    player: player,
    localizations: localizations,
    files: files,
    dock: dock,
    changed: notifyListeners,
    visFullscreen: () => vis.running?.fullscreen ?? false,
    closedByUser: _onDialogClosed,
    removed: _onDialogRemoved,
  );

  /// What the information dialogs show and how they are answered.
  late final DialogRequests requests = DialogRequests(
    player: player,
    dialogs: dialogManager,
  );

  /// A dialog's window went away: what it was for ends with it.
  void _onDialogClosed(AmpedDialog dialog, {required bool current}) {
    if (dialog == AmpedDialog.visConfig) {
      unawaited(vis.saveConfig(vis.plugin));
    }
    if (!current) return;
    // Closed from its title bar: a Cancel.
    if (dialog == AmpedDialog.remoteLogin) requests.answerRemoteLogin(null);
    if (dialog == AmpedDialog.resume) requests.answerResume(resume: false);
    if (dialog == AmpedDialog.fileInfo) requests.fileInfoDismissed();
  }

  /// A dialog is out of the open ones: a fullscreen window gives the screen
  /// back.
  void _onDialogRemoved(AmpedDialog dialog) {
    if (dialog == AmpedDialog.vis) {
      NativeScreen.restoreAfterFullscreen();
      // Closed while fullscreen: back to the skinned window.
      vis.setFullscreen(false);
    } else if (dialog == AmpedDialog.video) {
      NativeScreen.restoreAfterFullscreen();
      _syncVideoWindow();
    }
  }

  /// The classic Video window shows while it is open, except under the
  /// fullscreen video, which it must not float over.
  bool _videoWindowShows() =>
      _hasOpenWindow(SkinWindow.video) &&
      !dialogManager.windows.containsKey(AmpedDialog.video);

  void _syncVideoWindow() {
    final shows = _videoWindowShows();
    if (!windowState.controllers.containsKey(SkinWindow.video)) {
      if (shows) _createWindow(SkinWindow.video);
      return;
    }
    if (dock.isVisible(SkinWindow.video) != shows) {
      dock.setVisible(SkinWindow.video, shows);
    }
  }

  /// The mode the presets dialog was last opened in.
  PresetsMode presetsMode = PresetsMode.load;

  /// Whether the presets dialog was last opened on the auto-load library.
  bool presetsAutoLoad = false;

  Timer? _saveTimer;

  /// The created skinned windows, in creation order.
  Map<SkinWindow, AppWindowController> get windows =>
      Map.unmodifiable(windowState.controllers);

  /// Before a source episode plays: where the server says it was left off,
  /// if the user wants to continue there.
  Future<Duration?> _offerResume(PlaylistEntry entry) async {
    final position = await sources.resumePosition(entry.location);
    // Seconds into an episode are not worth a question.
    if (position == null || position < const Duration(seconds: 10)) {
      return null;
    }
    final title = entry.title.isEmpty ? entry.location : entry.title;
    return await requests.promptResume(title, position) ? position : null;
  }

  /// Counts a play of [entry] in the statistics: a song, a video or a podcast
  /// episode (audiobooks are not counted).
  void _countPlay(PlaylistEntry entry) {
    final location = entry.location;
    final PlayKind? kind;
    if (SourceLocation.isSource(location)) {
      kind = sources.isPodcast(location)
          ? PlayKind.podcast
          : sources.isBook(location)
          ? null
          : sources.isVideo(location)
          ? PlayKind.video
          : PlayKind.music;
    } else {
      kind = Playlist.isVideo(location) ? PlayKind.video : PlayKind.music;
    }
    if (kind == null) return;
    unawaited(
      playStats.record(
        location,
        kind,
        title: entry.trackTitle ?? entry.title,
        artist: entry.artist,
        album: entry.album,
      ),
    );
  }

  /// Looks for a newer release at start and every hour after.
  late final UpdateChecker _updates = UpdateChecker(
    releaseUrl: Uri.parse("https://www.amped-player.com/release.json"),
    interval: const Duration(hours: 1),
  );

  void _init() {
    _updates.updates.listen(requests.showUpdate);
    _updates.start();
    skins.followShades(isShaded);
    RemoteFiles.shared.prompt = requests.promptRemoteLogin;
    SourceLocation.resolver = sources.resolve;
    sources.startRefreshing();
    SourceLocation.artworkResolver = sources.artwork;
    player.resumeOffer = _offerResume;
    player.cast = chromecast;
    player.castFollow = () {
      final target = chromecast.current;
      if (target != null) unawaited(castTo(target));
    };
    player.progressReporter = (entry, position, length, {required finished}) =>
        unawaited(
          sources.saveProgress(
            entry.location,
            position,
            length,
            finished: finished,
          ),
        );
    player.playCounter = _countPlay;
    player.buffering.addListener(_onBufferingChanged);
    // The main window always exists (it anchors the others), hidden when
    // closed.
    _createWindow(SkinWindow.main);
    if (!isOpen(SkinWindow.main)) dock.setVisible(SkinWindow.main, false);
    for (final window in SkinWindow.values.skip(1)) {
      if (_hasOpenWindow(window)) _createWindow(window);
    }
    player.addListener(_onPlayerChanged);
    player.video?.addListener(_fitVideoWindow);
    player.playlist.addListener(_onPlaylistChanged);
    watchFolders.addListener(_refreshAvailability);
    skins.addListener(_onSkinChanged);
    skins.addListener(menuBar.syncSoon);
    if (skin is ModernSkin) unawaited(_startScripts());
    ampedChannel.setMethodCallHandler(menuBar.handleCall);
    notifications.start();
    unawaited(menuBar.sync());
    unawaited(_takePendingFiles());
    unawaited(vis.load());
    nowPlaying = NowPlaying(
      player,
      ampedChannel,
      readCover: covers.readCoverBytes,
    );
  }

  void initializeSystemTrayMenu() {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) return;
    if (_systemTrayMenu != null) return;
    _systemTrayMenu = SystemTrayMenu();
    _systemTrayMenu!.initialize(AmpedMenus.dock(this));
  }

  /// Brings the tray menu up to date with the shell.
  void refreshSystemTrayMenu() =>
      _systemTrayMenu?.refresh(AmpedMenus.dock(this));

  @override
  void dispose() {
    for (final timer in _moveEnds.values) {
      timer.cancel();
    }
    _saveTimer?.cancel();
    notifications.dispose();
    _systemTrayMenu?.dispose();
    player.removeListener(_onPlayerChanged);
    player.video?.removeListener(_fitVideoWindow);
    player.buffering.removeListener(_onBufferingChanged);
    player.playlist.removeListener(_onPlaylistChanged);
    watchFolders.removeListener(_refreshAvailability);
    _sortingTimer?.cancel();
    nowPlaying.dispose();
    albumArt.dispose();
    onlineArt.dispose();
    watchFolders.dispose();
    _updates.dispose();
    sources.dispose();
    library.dispose();
    videoLibrary.dispose();
    chromecast.dispose();
    savedPlaylists.dispose();
    skins.removeListener(_onSkinChanged);
    _stopScripts();
    skins.removeListener(menuBar.syncSoon);
    dock.dispose();
    super.dispose();
  }

  // --- Window state -----------------------------------------------------------

  /// Whether the skin's scripts draw its main window over another window
  /// (the Apple-styled skin's player is a frame over its playlist editor): that window
  /// is the one on screen and the main window has none of its own.
  bool get mainIsCompanion =>
      skin is ModernSkin && (_scripts?.isCompanionContainer("main") ?? false);

  /// The component ("pl", "ml", "video", "vis") the modern skin shows inside
  /// its own main window in place of [window], or null: the player has no
  /// window of its own for it then.
  String? _embeddedComponent(SkinWindow window) {
    final data = skin.wasabi;
    if (data == null || skin.modern?.container(window) != null) return null;
    final name = switch (window) {
      SkinWindow.pl => "pl",
      SkinWindow.library => "ml",
      SkinWindow.video => "video",
      SkinWindow.vis => "vis",
      _ => null,
    };
    if (name == null || data.embeddedComponents(name).isEmpty) return null;
    return name;
  }

  /// Whether the modern skin has what [window] shows built into its own main
  /// window (its equalizer's sliders, its playlist, library, video or
  /// visualization): then the player opens no window of that kind.
  bool skinEmbeds(SkinWindow window) {
    if (window == SkinWindow.eq) {
      final data = skin.wasabi;
      return data != null &&
          skin.modern?.container(SkinWindow.eq) == null &&
          data.hasBuiltInEq;
    }
    return _embeddedComponent(window) != null;
  }

  bool isOpen(SkinWindow window) => switch (window) {
    SkinWindow.eq when skinEmbeds(window) => true,
    SkinWindow.main => player.mainOpen && !mainIsCompanion,
    _ when _embeddedComponent(window) != null =>
      _scripts?.isEmbeddedComponentShown(_embeddedComponent(window)!) ?? false,
    SkinWindow.pl when mainIsCompanion => player.mainOpen,
    SkinWindow.eq when skinShowsEq =>
      _scripts?.configAttribute(_skinEqOption) == "1",
    SkinWindow.eq => player.eqOpen,
    SkinWindow.pl => player.plOpen,
    // A skin showing the video in another window (Amped Modern's
    // drawer) has it instead of the Video window.
    SkinWindow.video => modernVideo.windowShows,
    SkinWindow.library => player.libraryOpen,
    SkinWindow.thinger => switch (skin.modern?.container(SkinWindow.thinger)) {
      final container? => _thingerOpen ?? container.defaultVisible,
      null => false,
    },
    // A skin showing it in another window (Amped Modern's drawer) has
    // it instead of its own window.
    SkinWindow.vis => visualization.windowShows,
    SkinWindow.albumArt => player.albumArtOpen,
    SkinWindow.notifier => notifications.windowShows(
      skinShown: _notifierShown,
    ),
    _ => switch (skin.modern?.container(window)) {
      final container? => skin.modern?.isExtraOpen(container) ?? false,
      null => false,
    },
  };

  /// Whether the skin's scripts have the notifier showing, and the layout
  /// of its container they chose (`Layout.show`).
  bool _notifierShown = false;

  /// The skin option Amped Modern shows its equalizer with: a tab of the
  /// main window's config drawer (`attribs.m`, `configtabs.m`). The classic player lists
  /// it in the Windows menu as "Equalizer" (`localizeSkinWindowName`).
  static const _skinEqOption = "Equalizer\tAlt+G";

  /// Whether the active modern skin shows the equalizer itself, in place of
  /// an equalizer window: it has no `eq` container, and its scripts made
  /// the [_skinEqOption] option (or are still loading).
  bool get skinShowsEq {
    if (skin is! ModernSkin || skin.modern?.container(SkinWindow.eq) != null) {
      return false;
    }
    final scripts = _scripts;
    return scripts == null || scripts.hasConfigAttribute(_skinEqOption);
  }

  /// [isOpen] for the equalizer as of the last scripts change, while the
  /// skin shows it itself.
  bool? _skinEqOpen;

  /// Whether [window] is open as a window of its own (the equalizer may be
  /// part of the skin's main window instead).
  bool _hasOpenWindow(SkinWindow window) =>
      !(window == SkinWindow.eq && skinShowsEq) &&
      !skinEmbeds(window) &&
      isOpen(window);

  bool isShaded(SkinWindow window) => switch (window) {
    SkinWindow.main => player.windowShade,
    SkinWindow.eq => player.eqShade,
    SkinWindow.pl => player.plShade,
    _ => false,
  };

  void _onSkinChanged() {
    if (!identical(skins.current.wasabi, _scriptedSkin)) {
      // The video and the visualization go where the new skin shows them:
      // in their windows for a classic skin, in the drawer for a modern
      // one. The old skin's slots giving them up (they detach after the
      // next frame) must not end them.
      final video = player.videoPlaying || modernVideo.shown;
      final visualization = vis.isRunning;
      if (video) modernVideo.skinChanging();
      if (visualization) this.visualization.skinChanging();
      unawaited(_startScripts(video: video, visualization: visualization));
    }
    _onPlayerChanged();
  }

  /// Shows the video, or the visualization when there is no video, in the
  /// way the skin that has just come up shows them. A modern skin has one
  /// place for both (its scripts open it), so the video comes first.
  void _showComponentsAfterSkinChange({
    required bool video,
    required bool visualization,
  }) {
    if (video) {
      modernVideo.skinChanged();
      if (player.videoOpen) {
        _onPlayerChanged();
      } else {
        player.setVideoOpen(true);
      }
    } else if (visualization) {
      _scripts?.cancelsComponent(wasabiVisGuid, goingVisible: true);
    }
  }

  /// Runs the active modern skin's scripts, stopping the previous skin's
  /// (which saves their settings in `onScriptUnloading`).
  Future<void> _startScripts({
    bool video = false,
    bool visualization = false,
  }) async {
    _stopScripts();
    final current = skin;
    _scriptedSkin = current.wasabi;
    if (current is! ModernSkin) {
      _showComponentsAfterSkinChange(
        video: video,
        visualization: visualization,
      );
      return;
    }
    wasabiHost.prefs ??= await SharedPreferences.getInstance();
    if (!identical(skin, current)) return;
    // The sizes the user dragged resizable layouts to.
    current.restoreSizes();
    _fitLayoutsToDisplay(current);
    _scripts = WasabiScriptRuntime(skin: current.data, host: wasabiHost)
      ..addListener(_onScriptsChanged)
      ..start();
    // The scripts decide whether the skin shows the equalizer itself.
    _followSkinEq();
    _showComponentsAfterSkinChange(video: video, visualization: visualization);
    _onPlayerChanged();
    notifyListeners();
  }

  void _stopScripts() {
    final scripts = _scripts;
    _scripts = null;
    modernVideo.scriptsStopped();
    _notifierShown = false;
    scripts
      ?..removeListener(_onScriptsChanged)
      ..dispose();
  }

  /// A drag on a modern skin's resize handle: the layout and its window take
  /// [size] (layout pixels), which is remembered for the skin.
  void resizeModern(String containerId, WasabiLayout layout, Size size) {
    final current = skin;
    if (current is! ModernSkin) return;
    final container = current.data.container(containerId);
    if (container == null) return;
    final window = current.windowForContainer(container.id);
    var snapped = window == null
        ? size
        : _snapModernSize(current, window, layout, size);
    final area = window == null
        ? null
        : wasabiAlbumArtArea(current.data, layout);
    if (area != null) {
      final root = layout.root;
      Size limit(String w, String h, double fallback) => Size(
        (root.optInt(w) ?? fallback).toDouble(),
        (root.optInt(h) ?? fallback).toDouble(),
      );
      snapped =
          _fitToAlbumArt(
            window!,
            snapped,
            Size(
              layout.size.width - area.width,
              layout.size.height - area.height,
            ),
            min: limit("minimum_w", "minimum_h", 16),
            max: limit("maximum_w", "maximum_h", 8000),
          ) ??
          snapped;
    }
    if (window == SkinWindow.video) {
      snapped = _fitToModernVideo(layout, snapped) ?? snapped;
    }
    // Never larger than the display it is on: dragging a corner past the
    // screen's edge would leave a window nobody can reach the edges of.
    if (window != null) {
      final rect = dock.rectOf(window);
      final shown = rect == null
          ? null
          : DockGeometry.workAreaFor(rect, NativeScreen.workAreas());
      if (shown != null) {
        final scale = windowState.scaleOf(window);
        snapped = Size(
          min(snapped.width, (shown.width / scale).floorToDouble()),
          min(snapped.height, (shown.height / scale).floorToDouble()),
        );
      }
    }
    if (snapped == layout.size) return;
    current.resizeLayout(container, layout, snapped);
    _onScriptsChanged();
    _scripts
      ?..layoutResized(layout)
      ..layoutUserResized(layout)
      ..changed();
    notifyListeners();
  }

  /// [size] (layout pixels), asked for by a drag on [window]'s resize
  /// handle, with its moving edges snapped to the screen and the windows
  /// next to it the way Wasabi's `resize.cpp` docks them, then kept within
  /// the layout's minimum and maximum size.
  Size _snapModernSize(
    ModernSkin current,
    SkinWindow window,
    WasabiLayout layout,
    Size size,
  ) {
    final scale = windowState.scaleOf(window);
    final snapped =
        dock.snapResize(
          window,
          size * scale,
          invertSnap: HardwareKeyboard.instance.isShiftPressed,
        ) /
        scale;
    return current.clampSize(layout, snapped);
  }

  /// The skin opened or closed its equalizer (through the menus, or the
  /// user clicking its drawer): the menus follow, and so does the equalizer
  /// window, so a classic skin shows it if the skin's equalizer was open.
  void _followSkinEq() {
    final eqOpen = _scripts != null && skinShowsEq
        ? isOpen(SkinWindow.eq)
        : null;
    if (eqOpen == _skinEqOpen) return;
    _skinEqOpen = eqOpen;
    if (eqOpen != null) player.setEqOpen(eqOpen);
    _systemTrayMenu?.refresh(AmpedMenus.dock(this));
    unawaited(menuBar.sync());
  }

  /// Flutter shows a window once its first frame is drawn, which can be
  /// after the shell hid it (the main window of a skin whose scripts draw
  /// it over another window): hide such a window again.
  void _keepClosedWindowsHidden() {
    for (final window in windowState.controllers.keys) {
      if (dock.isVisible(window)) continue;
      final native = dock.nativeWindowOf(window);
      if (native != null && native.isVisible) native.hide();
    }
  }

  /// Scripts moved or resized something: windows follow their layouts.
  bool _wasCompanion = false;

  void _onScriptsChanged() {
    _keepClosedWindowsHidden();
    _followSkinEq();
    // A script made the main window a frame over another one: that window
    // is shown instead, and the main window goes.
    if (mainIsCompanion != _wasCompanion) {
      _wasCompanion = mainIsCompanion;
      _onPlayerChanged();
      notifyListeners();
    }
    // Picking a "when to show" in the skin's own options turns
    // notifications on (or, with "Never show", off) here too.
    notifications.skinPickedMode();
    var resized = false;
    for (final window in windowState.controllers.keys) {
      if (!skin.hasModernLook(window)) continue;
      if (window == SkinWindow.notifier) continue;
      final size = windowState.scaled(window);
      if (dock.rectOf(window)!.size != size) {
        // As in `resize`: the Album Art window leaves its neighbours be.
        dock.resize(window, size, repin: window != SkinWindow.albumArt);
        resized = true;
      }
    }
    _placeNotifier();
    _applyShapes();
    // The windows' widgets are sized from their layouts: without this a
    // drawer that grew its window stayed out of reach of the pointer until
    // something else (playback) made them rebuild.
    if (resized) notifyListeners();
  }

  /// Where on the main window's screen the own notification appears: the
  /// chosen position, inside the work area.
  Offset _ownNotifierOrigin(Size size) {
    final areas = NativeScreen.workAreas();
    final mainRect = dock.rectOf(SkinWindow.main);
    final area =
        (mainRect == null ? null : DockGeometry.workAreaFor(mainRect, areas)) ??
        (areas.isEmpty ? const Rect.fromLTWH(0, 0, 1280, 800) : areas.first);
    return notifications.position.originIn(area, size);
  }

  /// Puts the notifier's window where its script put its layout
  /// (`Layout.resize`, in screen pixels).
  void _placeNotifier() {
    if (!windowState.controllers.containsKey(SkinWindow.notifier)) return;
    final layout = skin.modern?.layout(SkinWindow.notifier);
    final current = dock.rectOf(SkinWindow.notifier);
    if (current != null && _ownNotifier) {
      final size = windowState.scaled(SkinWindow.notifier);
      final rect = _ownNotifierOrigin(size) & size;
      if (rect != current) dock.setRect(SkinWindow.notifier, rect);
      return;
    }
    if (layout == null || current == null) return;
    // The skin's script says where it wants the notifier (Amped Modern:
    // the bottom-right corner, Graviton: its own position setting), and
    // slides or fades it there. Until it says, Preferences' position does.
    final size = layout.windowSize;
    final x = layout.root.optInt("x");
    final y = layout.root.optInt("y");
    final origin = x == null || y == null
        ? _ownNotifierOrigin(size)
        : _notifierArea().topLeft + Offset(x.toDouble(), y.toDouble());
    final rect = origin & size;
    if (rect != current) dock.setRect(SkinWindow.notifier, rect);
    // A notifier that slides off the screen fades as it goes: the window
    // cannot be clipped by the screen's edge (or kept above the menu bar)
    // the way the classic player's was.
    final area = _notifierArea();
    final visible = rect.intersect(area);
    final fade = rect.isEmpty
        ? 1.0
        : visible.isEmpty
        ? 0.0
        : visible.width * visible.height / (rect.width * rect.height);
    if ((fade - _notifierFade).abs() > 0.02) {
      _notifierFade = fade;
      notifyListeners();
    }
  }

  /// How much of the skin's notifier is on the screen, 1 to 0.
  double get notifierFade => _notifierFade;
  double _notifierFade = 1;

  /// The work area of the main window's screen: what a skin's notifier
  /// script reads as the viewport.
  Rect _notifierArea() {
    final areas = NativeScreen.workAreas();
    final mainRect = dock.rectOf(SkinWindow.main);
    return (mainRect == null
            ? null
            : DockGeometry.workAreaFor(mainRect, areas)) ??
        (areas.isEmpty ? const Rect.fromLTWH(0, 0, 1280, 800) : areas.first);
  }

  /// Switches the modern container of [window] to its layout [name]; false
  /// when it has none of that name (the caller falls back to windowshade).
  bool switchModernLayout(SkinWindow window, String? name) {
    final container = skin.modern?.container(window);
    final layout = name == null || container == null
        ? null
        : container.layout(name.trim());
    if (container == null || layout == null) return false;
    final before = skin.modern?.layout(window);
    if (identical(before, layout)) return true;
    skin.modern?.choose(container, layout);
    // The player's shade flag follows, for the menus that show it.
    final shadeLike = layout.id.toLowerCase().contains("shade");
    if (shadeLike != isShaded(window)) _toggleShade(window);
    _onScriptsChanged();
    _onPlayerChanged();
    _applyLayoutFlags(window);
    dock.nativeWindowOf(window)?.setAlwaysOnTop(_staysOnTop(window));
    if (before != null) {
      _scripts?.layoutSwitched(container.id, before, layout);
    }
    notifyListeners();
    return true;
  }

  /// Gives every skinned window the native shape of its skin region, so the
  /// pointer passes through its transparent parts (`SetWindowRgn` in Set.cpp).
  void _applyShapes() {
    for (final window in windowState.controllers.keys) {
      final layout = skin.modern?.layout(window);
      final modern = skin.modern;
      final region = modern == null
          ? skin.shape(window)
          : modern.shape(
              window,
              companions: [
                if (layout != null)
                  for (final companion
                      in _scripts?.companionsOf(layout) ??
                          const <(WasabiContainer, WasabiLayout)>[])
                    companion.$2,
              ],
            );
      // A shaped window may go past the screen's edge by the see-through
      // margin its shape leaves, so what shows reaches the edge.
      dock.setTransparentEdges(
        window,
        _transparentEdges(window, region, windowState.baseSize(window)),
      );
      dock
          .nativeWindowOf(window)
          ?.setShape(
            region == null
                ? null
                : [
                    for (final polygon in region)
                      [
                        for (final point in polygon)
                          point * windowState.scaleOf(window),
                      ],
                  ],
          );
    }
  }

  /// The margins of [window] (unscaled [size]) that its shape [region]
  /// leaves empty, in screen pixels.
  EdgeInsets _transparentEdges(
    SkinWindow window,
    List<List<Offset>>? region,
    Size size,
  ) {
    if (region == null || region.isEmpty || size.isEmpty) {
      return EdgeInsets.zero;
    }
    var left = size.width;
    var top = size.height;
    var right = 0.0;
    var bottom = 0.0;
    for (final polygon in region) {
      for (final point in polygon) {
        left = min(left, point.dx);
        top = min(top, point.dy);
        right = max(right, point.dx);
        bottom = max(bottom, point.dy);
      }
    }
    if (right <= left || bottom <= top) return EdgeInsets.zero;
    final scale = windowState.scaleOf(window);
    return EdgeInsets.fromLTRB(
      max(0, left) * scale,
      max(0, top) * scale,
      max(0, size.width - right) * scale,
      max(0, size.height - bottom) * scale,
    );
  }

  /// Holds the layouts' sizes (saved ones included) to what fits the
  /// display at the current scale: a size dragged out at one scale, or
  /// saved before the display changed, must not leave a window larger than
  /// the screen after double size.
  void _fitLayoutsToDisplay(ModernSkin modern) {
    final areas = NativeScreen.workAreas();
    if (areas.isEmpty) return;
    for (final window in SkinWindow.values) {
      final container = modern.container(window);
      if (container == null || window == SkinWindow.notifier) continue;
      final rect = dock.rectOf(window);
      final area =
          (rect == null ? null : DockGeometry.workAreaFor(rect, areas)) ??
          areas.first;
      final scale = windowState.scaleOf(window);
      final limit = Size(
        (area.width / scale).floorToDouble(),
        (area.height / scale).floorToDouble(),
      );
      for (final layout in container.layouts) {
        final size = layout.size;
        if (size.width <= limit.width && size.height <= limit.height) continue;
        modern.resizeLayout(
          container,
          layout,
          Size(min(size.width, limit.width), min(size.height, limit.height)),
        );
        _scripts?.layoutResized(layout);
      }
    }
  }

  /// A drag on the main window's resize grip: the main window scales so its
  /// bottom-right corner follows [corner] (relative to its top-left, in
  /// logical pixels), keeping the skin's proportions. The other windows
  /// keep their size; the ones docked to its edges move with them.
  void scaleMainTo(Offset corner) {
    final rect = dock.rectOf(SkinWindow.main);
    if (rect == null) return;
    final full =
        skin.modern?.layout(SkinWindow.main)?.size ??
        windowState.fullSize(SkinWindow.main);
    final area = DockGeometry.workAreaFor(rect, NativeScreen.workAreas());
    final limit = MainWindowScale.limitFor(full, area);
    setMainScale(
      MainWindowScale.fromCorner(
        windowState.baseSize(SkinWindow.main),
        corner,
        limit: limit,
      ),
    );
  }

  /// Gives the main window [scale], resizing it around its top-left corner.
  void setMainScale(double scale) {
    if (scale == windowState.mainScale) return;
    windowState.mainScale = scale;
    if (windowState.controllers.containsKey(SkinWindow.main)) {
      dock.resize(SkinWindow.main, windowState.scaled(SkinWindow.main));
      _applyShapes();
    }
    _scheduleSave();
    notifyListeners();
  }

  void setOpen(SkinWindow window, bool open) {
    // What the skin shows inside its own window is shown or hidden there.
    if (skinEmbeds(window)) {
      final name = _embeddedComponent(window);
      if (name != null) _scripts?.setEmbeddedComponent(name, open);
      _onPlayerChanged();
      return;
    }
    switch (window) {
      case SkinWindow.main:
        player.setMainOpen(open);
      case SkinWindow.eq when skinShowsEq:
        _scripts?.setConfigAttribute(_skinEqOption, open ? "1" : "0");
      case SkinWindow.eq:
        player.setEqOpen(open);
      case SkinWindow.pl:
        player.setPlOpen(open);
      case SkinWindow.video:
        // Closing it stops a playing video unless Shift is held or the
        // Video options say otherwise (`HideVideoWindow(1)`).
        open
            ? player.setVideoOpen(true)
            : player.closeVideoWindow(
                keepPlaying: HardwareKeyboard.instance.isShiftPressed,
              );
      case SkinWindow.library:
        player.setLibraryOpen(open);
      case SkinWindow.vis:
        // Closing the window ends the visualization.
        visualization.setRunning(open);
      case SkinWindow.albumArt:
        player.setAlbumArtOpen(open);
      case SkinWindow.notifier:
        _notifierShown = open;
        if (!open) notifications.hide();
        _onPlayerChanged();
      case SkinWindow.thinger:
        _thingerOpen = open;
        unawaited(
          SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool(_thingerOpenKey, open),
          ),
        );
        _onPlayerChanged();
      default:
        final container = skin.modern?.container(window);
        if (container == null) return;
        if (skin.modern?.setExtraOpen(container, open) ?? false) {
          _scripts?.containerVisibilityChanged(container.id, open);
        }
        _onPlayerChanged();
    }
  }

  void toggle(SkinWindow window) => setOpen(window, !isOpen(window));

  /// The classic Video window's 1x and 2x buttons (`ID_VIDEOWND_ZOOM100`,
  /// `ZOOM200`): sizes the window so the picture shows at [zoom] times its
  /// own size, at least 256×64 (`UpdateVideoSize`).
  void zoomVideo(double zoom) {
    final picture = player.video?.videoSize ?? const Size(320, 240);
    const frame = videoWindowInsets;
    resize(
      SkinWindow.video,
      Size(
        max(picture.width * zoom, 256) + frame.horizontal,
        max(picture.height * zoom, 64) + frame.vertical,
      ),
    );
  }

  /// A modern skin's 1x and 2x video buttons (`VID_1X`, `VID_2X`): sizes
  /// the window showing the video so the picture is [zoom] times its own
  /// size.
  void zoomModernVideo(double zoom) {
    final scripts = _scripts;
    final picture = player.video?.videoSize;
    if (skin is! ModernSkin || scripts == null || picture == null) return;
    for (final window in SkinWindow.values) {
      final container = skin.modern?.container(window);
      final layout = skin.modern?.layout(window);
      if (container == null || layout == null || !_hasOpenWindow(window)) {
        continue;
      }
      final area = _videoArea(scripts, layout.root);
      if (area == null) continue;
      resizeModern(
        container.id,
        layout,
        Size(
          layout.size.width + picture.width * zoom - area.width,
          layout.size.height + picture.height * zoom - area.height,
        ),
      );
      return;
    }
  }

  /// The size of the visible video component in [node], or null.
  static Size? _videoArea(WasabiScriptRuntime scripts, WasabiObject node) {
    for (final child in node.children) {
      if (!child.visible) continue;
      if (wasabiComponentName(child) == "video") {
        return scripts.rectOf(child).size;
      }
      final inside = _videoArea(scripts, child);
      if (inside != null) return inside;
    }
    return null;
  }

  /// Fills the screen with the playing video, or brings it back
  /// (`VID_FS`, a double-click on the picture).
  void toggleVideoFullscreen() {
    final controller = dialogManager.windows[AmpedDialog.video];
    if (controller != null) {
      NativeWindow.of(controller).setFullscreen(false);
      dialogManager.close(AmpedDialog.video);
      _syncVideoWindow();
      return;
    }
    if (!player.videoPlaying) return;
    dialogManager.open(AmpedDialog.video);
    final opened = dialogManager.windows[AmpedDialog.video];
    if (opened == null) return;
    NativeWindow.of(opened)
      ..configure()
      ..setFullscreen(true)
      ..focus();
    _syncVideoWindow();
  }

  /// Whether [window] floats above other windows: all do with Always on
  /// top, the Video window also on its own, and a modern skin's layout may
  /// ask for it.
  bool _staysOnTop(SkinWindow window) =>
      player.alwaysOnTop ||
      (window == SkinWindow.video && player.videoAlwaysOnTop) ||
      _layoutFlag(window, "ontop");

  void toggleShade(SkinWindow window) {
    final before = skin.modern?.layout(window);
    // The shade toggle (a menu, a double click) overrides a layout a script
    // chose.
    final container = skin.modern?.container(window);
    if (container != null) skin.modern?.unchoose(container);
    _toggleShade(window);
    // The skin's scripts hear of the layout it changed to.
    final after = skin.modern?.layout(window);
    if (before != null && after != null && !identical(before, after)) {
      _applyLayoutFlags(window);
      dock.nativeWindowOf(window)?.setAlwaysOnTop(_staysOnTop(window));
    }
    if (before != null &&
        after != null &&
        container != null &&
        !identical(before, after)) {
      _scripts?.layoutSwitched(container.id, before, after);
    }
  }

  void _toggleShade(SkinWindow window) {
    switch (window) {
      case SkinWindow.main:
        player.toggleWindowShade();
      case SkinWindow.eq:
        player.toggleEqShade();
      case SkinWindow.pl:
        player.togglePlShade();
      case SkinWindow.video ||
          SkinWindow.library ||
          SkinWindow.thinger ||
          SkinWindow.vis ||
          SkinWindow.albumArt ||
          SkinWindow.notifier:
        return;
      default:
        return;
    }
  }

  /// Gives the classic Video window the playing picture's shape, keeping
  /// its width: when the video changes, and when the window opens.
  void _fitVideoWindow() {
    if (!windowState.controllers.containsKey(SkinWindow.video) ||
        player.video?.videoSize == null) {
      return;
    }
    if (skin.hasModernLook(SkinWindow.video)) {
      final container = skin.modern?.container(SkinWindow.video);
      final layout = skin.modern?.layout(SkinWindow.video);
      if (container != null &&
          layout != null &&
          _fitToModernVideo(layout, layout.size) != layout.size) {
        resizeModern(container.id, layout, layout.size);
      }
      return;
    }
    resize(SkinWindow.video, windowState.fullSize(SkinWindow.video));
  }

  /// [size] for a modern skin's Video window layout with its video
  /// component in the playing picture's shape, taking the width of [size];
  /// null without a picture or a visible video component.
  Size? _fitToModernVideo(WasabiLayout layout, Size size) {
    final picture = player.video?.videoSize;
    final scripts = _scripts;
    if (picture == null || scripts == null) return null;
    if (picture.width <= 0 || picture.height <= 0) return null;
    final area = _videoArea(scripts, layout.root);
    if (area == null || area.isEmpty) return null;
    final frame = Size(
      layout.size.width - area.width,
      layout.size.height - area.height,
    );
    final width = size.width - frame.width;
    if (width < 1) return null;
    final root = layout.root;
    double limit(String name, double fallback) =>
        (root.optInt(name) ?? fallback).toDouble();
    return Size(
      size.width.clamp(limit("minimum_w", 16), limit("maximum_w", 8000)),
      (frame.height + width * picture.height / picture.width)
          .roundToDouble()
          .clamp(limit("minimum_h", 16), limit("maximum_h", 8000)),
    );
  }

  /// [size] for the Video window with the playing picture's shape, taking
  /// the width of [size]; null for other windows or without a picture.
  Size? _fitToVideo(SkinWindow window, Size size) {
    final picture = player.video?.videoSize;
    if (window != SkinWindow.video || picture == null) return null;
    if (picture.width <= 0 || picture.height <= 0) return null;
    const frame = videoWindowInsets;
    final width = size.width.round().toDouble().clamp(window.minWidth, 8000.0);
    final height =
        ((width - frame.horizontal) * picture.height / picture.width +
                frame.vertical)
            .round()
            .toDouble();
    return Size(
      width,
      height.clamp(SkinWindow.minResizableSize.height, 8000.0),
    );
  }

  /// Resizes a resizable window to [size] (unscaled), snapped to the skin's
  /// 25×29 grid like `do_size`; the Album Art window takes its cover's
  /// shape instead.
  void resize(SkinWindow window, Size size) {
    if (!window.resizable || skin.hasModernLook(window)) return;
    final current = windowState.sizes[window] ?? window.defaultSize;
    final snapped =
        _fitToAlbumArt(
          window,
          size,
          embedWindowInsets.collapsedSize,
        ) ??
        _fitToVideo(window, size) ??
        WindowState.snapResizable(size, window);
    if (isShaded(window)) {
      // Shaded, only the width changes (Peui.cpp do_size).
      if (snapped.width == current.width) return;
      windowState.sizes[window] = Size(snapped.width, current.height);
    } else {
      if (snapped == current) return;
      windowState.sizes[window] = snapped;
    }
    // Resizing the Album Art window must not push the windows docked to it.
    dock.resize(
      window,
      windowState.scaled(window),
      repin: window != SkinWindow.albumArt,
    );
    notifyListeners();
  }

  /// The size of the Album Art window dragged to [size] (with [frame]
  /// around its picture), keeping the cover's shape, or null for other
  /// windows, without a cover, or when the cover may stretch.
  Size? _fitToAlbumArt(
    SkinWindow window,
    Size size,
    Size frame, {
    Size min = SkinWindow.minResizableSize,
    Size max = const Size(8000, 8000),
  }) {
    final art = albumArt.image;
    if (window != SkinWindow.albumArt || art == null) return null;
    // The classic window stretches the cover when its shape isn't locked.
    if (!skin.hasModernLook(window) && !_albumArtLockAspect) return null;
    return fitWindowToArt(
      dragged: size,
      frame: frame,
      art: Size(art.width.toDouble(), art.height.toDouble()),
      min: min,
      max: max,
    );
  }

  // --- Window lifecycle -------------------------------------------------------

  void _createWindow(SkinWindow window) {
    final size = windowState.scaled(window);
    final controller = AppWindowController(
      size: size,
      title:
          skin.modern?.container(window)?.name.trim().isNotEmpty == true &&
              window.isExtra
          ? "Amped ${skin.modern?.container(window)!.name.trim()}"
          : AmpedMenus.windowTitle(window, localizations),
      delegate: _SkinnedWindowDelegate(this, window),
    );
    windowState.controllers[window] = controller;
    final native = NativeWindow.of(controller)..configure(transparent: true);
    final notifier = window == SkinWindow.notifier;
    native.setAlwaysOnTop(
      notifier || _staysOnTop(window),
    );
    if (!notifier) {
      files.acceptDrops(controller, playDropped: window == SkinWindow.main);
    }
    dock.register(
      window,
      rect: windowState.initialPosition(window, size) & size,
      window: native,
    );
    _applyLayoutFlags(window);
    _applyShapes();
    if (notifier) _placeNotifier();
    notifyListeners();
  }

  /// Whether the layout [window] shows has the flag [name] on (`ontop="1"`).
  bool _layoutFlag(SkinWindow window, String name) =>
      skin.modern?.layout(window)?.root[name]?.trim() == "1";

  /// The window flags of a modern layout: `nodock` keeps the window out of
  /// docking, `noactivation` keeps a click from giving it the focus, and
  /// `ontop` keeps it above the others. (`noparent`, `appbar`, `forcealpha`,
  /// `indesktop` and `osframe` have no meaning for these windows.)
  void _applyLayoutFlags(SkinWindow window) {
    if (window == SkinWindow.notifier) return;
    final layout = skin.modern?.layout(window);
    if (layout == null) return;
    dock.setDockable(window, !_layoutFlag(window, "nodock"));
    dock.setSnapPoints(window, [
      for (final point in layout.snapPoints)
        DockSnapPoint(point.id, point.at(layout.windowSize) * player.uiScale),
    ]);
    dock
        .nativeWindowOf(window)
        ?.setActivatable(!_layoutFlag(window, "noactivation"));
  }

  void _onWindowClosed(SkinWindow window) {
    if (window == SkinWindow.main) {
      closeMainWindow();
    } else {
      setOpen(window, false);
    }
  }

  /// Closing the main window exits, even if other windows are still open.
  void closeMainWindow() => unawaited(quit());

  /// Ctrl+Tab (`NEXT_WINDOW`): focuses the next open window.
  void focusNextWindow() {
    final open = [
      for (final window in SkinWindow.values)
        if (window != SkinWindow.notifier &&
            _hasOpenWindow(window) &&
            windowState.controllers.containsKey(window))
          window,
    ];
    if (open.length < 2) return;
    final active = open.indexWhere(
      (w) => windowState.controllers[w]!.isActivated,
    );
    final next = open[(active + 1) % open.length];
    dock.nativeWindowOf(next)?.focus();
  }

  /// Whether the player is minimized (`System.isMinimized`).
  bool get isMinimized =>
      windowState.controllers[SkinWindow.main]?.isMinimized ?? false;

  /// Brings the player back to the front, restored if it was minimized
  /// (`System.restoreApplication`, `activateApplication`).
  void activateApplication() {
    final main = windowState.controllers[SkinWindow.main];
    if (main == null) return;
    if (main.isMinimized) main.setMinimized(false);
    main.activate();
  }

  /// Whether the video or a fullscreen visualizer fills the screen
  /// (`System.isVideoFullscreen`, which the notifier's "Disable in
  /// fullscreen" waits on).
  bool get videoFullscreen =>
      dialogManager.windows.containsKey(AmpedDialog.video) ||
      (vis.isRunning && vis.fullscreen);

  /// Minimizes the main window (`ShowWindow(SW_MINIMIZE)`).
  void minimize() => dock.nativeWindowOf(SkinWindow.main)?.minimize();

  /// Saves the window layout and the playlist, and quits.
  Future<void> quit() async {
    _scripts?.quitting();
    _saveTimer?.cancel();
    await dialogManager.rememberAll();
    await windowState.save();
    await persistence.savePlaylist(player.playlist);
    // Scripts save their settings as they unload.
    _stopScripts();
    exit(0);
  }

  // --- Visualization ----------------------------------------------------------

  /// Visualization > Start/Stop plug-in.
  void toggleVisPlugin() => visualization.setRunning(!vis.isRunning);

  final _visClicks = ClassicVisClicks();

  /// A click on the classic visualization: the next mode; a double-click
  /// undoes that and starts or stops the plug-in instead (main_mouse.cpp).
  void clickClassicVis() {
    final restore = _visClicks.click(player.classicVis.mode);
    if (restore == null) {
      player.cycleClassicVis();
      return;
    }
    player.setClassicVis(player.classicVis.copyWith(mode: restore));
    toggleVisPlugin();
  }

  /// Visualization > Configure plug-in... (Alt+K): the selected module's
  /// options, saved when the dialog closes and used from its next start.
  void configureVisPlugin() => dialogManager.open(AmpedDialog.visConfig);

  /// Visualization > Select plug-in... (Ctrl+K): Preferences on the
  /// Visualization page.
  void selectVisPlugin() {
    preferences.select(PreferencesPage.visualization);
    dialogManager.close(AmpedDialog.preferences);
    dialogManager.open(AmpedDialog.preferences);
  }

  /// Preferences on Skins > Browser: the online skin browser (the Webamp
  /// skin library). The entry point for the Skins menu.
  void openOnlineSkinBrowser() {
    preferences.select(PreferencesPage.skinsOnline);
    dialogManager.close(AmpedDialog.preferences);
    dialogManager.open(AmpedDialog.preferences);
  }

  // --- Dialogs ----------------------------------------------------------------

  /// Opens the playlist search (J, "Jump to file"), or brings it forward.
  void showPlaylistSearch() => dialogManager.open(AmpedDialog.searchPlaylist);

  /// Opens the presets dialog in [mode], on the auto-load library with
  /// [autoLoad] (the "Auto-load preset..." menu items).
  void openPresets(PresetsMode mode, {bool autoLoad = false}) {
    presetsMode = mode;
    presetsAutoLoad = autoLoad;
    dialogManager.open(AmpedDialog.presets);
  }

  // --- Reacting to state ------------------------------------------------------

  /// Shows "Sorting playlist..." (with tag-reading progress) in the song
  /// title once a sort has run for [_sortingNoticeDelay], until it ends.
  /// Greys out the playlist entries on watched folders that can't be reached.
  void _refreshAvailability() =>
      player.playlist.refreshAvailability(watchFolders.isOffline);

  void _onPlaylistChanged() {
    final playlist = player.playlist;
    _refreshAvailability();
    if (playlist.sorting) {
      _sortingTimer ??= Timer(_sortingNoticeDelay, _showSortingNotice);
      if (!_sortingTimer!.isActive) _showSortingNotice();
    } else if (_sortingTimer != null) {
      _sortingTimer!.cancel();
      _sortingTimer = null;
      if (songTitleOverride.value == _sortingNotice) {
        songTitleOverride.value = null;
      }
      _sortingNotice = null;
    }
  }

  void _showSortingNotice() {
    final playlist = player.playlist;
    if (!playlist.sorting) return;
    final progress = playlist.sortTagProgress;
    final text = progress == null
        ? localizations.sortingPlaylist
        : localizations.sortingReadingTags(progress.done, progress.total);
    // Don't take the title from a control that is showing its own text.
    final current = songTitleOverride.value;
    if (current != null && current != _sortingNotice) return;
    _sortingNotice = text;
    songTitleOverride.value = text;
  }

  /// The sorting text this shell put in [songTitleOverride], if any.
  String? _sortingNotice;

  static const _sortingNoticeDelay = Duration(milliseconds: 500);
  Timer? _sortingTimer;

  /// The buffering text this shell put in [songTitleOverride], if any.
  String? _bufferingNotice;

  /// Shows how the copy of a track on a network share is coming along in
  /// the song title, until the track starts.
  void _onBufferingChanged() {
    final progress = player.buffering.value;
    if (progress == null) {
      if (songTitleOverride.value == _bufferingNotice) {
        songTitleOverride.value = null;
      }
      _bufferingNotice = null;
      return;
    }
    final percent = progress.percent;
    final remaining = progress.remainingText;
    final text = percent != null && remaining != null
        ? localizations.remoteBuffering(
            percent,
            progress.speedText,
            progress.elapsedText,
            remaining,
          )
        : localizations.remoteBufferingUnknown(
            progress.receivedText,
            progress.speedText,
            progress.elapsedText,
          );
    // Don't take the title from a control that is showing its own text.
    final current = songTitleOverride.value;
    if (current != null && current != _bufferingNotice) return;
    _bufferingNotice = text;
    songTitleOverride.value = text;
  }

  void _onPlayerChanged() {
    _keepClosedWindowsHidden();
    modernVideo.follow();
    _fitVideoWindow();
    notifications.follow();
    for (final window in SkinWindow.values) {
      final open = window == SkinWindow.video
          ? _videoWindowShows()
          : _hasOpenWindow(window);
      if (open && !windowState.controllers.containsKey(window)) {
        _createWindow(window);
      } else if (windowState.controllers.containsKey(window) &&
          dock.isVisible(window) != open) {
        dock.setVisible(window, open);
      }
      final size = windowState.scaled(window);
      if (windowState.controllers.containsKey(window) &&
          dock.rectOf(window)!.size != size) {
        if (player.uiScale == windowState.scale) dock.resize(window, size);
      }
    }
    // A new skin may change the notifier's size: keep its corner on screen.
    if (_ownNotifier) _placeNotifier();
    if (player.uiScale != windowState.scale) {
      windowState.rescale(player.uiScale);
      // What was dragged out at one scale may not fit at the next.
      final modern = skin;
      if (modern is ModernSkin) _fitLayoutsToDisplay(modern);
      // A skin that sized itself to the screen did it in the old pixels.
      if (_scripts?.sizesDependOnScale ?? false) {
        unawaited(_startScripts());
      }
    }
    for (final window in dock.windows) {
      // The notifier always floats.
      if (window == SkinWindow.notifier) continue;
      dock.nativeWindowOf(window)?.setAlwaysOnTop(_staysOnTop(window));
      _applyLayoutFlags(window);
    }
    for (final dialog in dialogManager.windows.values) {
      NativeWindow.of(dialog).setAlwaysOnTop(player.alwaysOnTop);
    }
    _applyShapes();
    _systemTrayMenu?.refresh(AmpedMenus.dock(this));
    unawaited(menuBar.sync());
  }

  /// Applies a new UI scale: every window is resized (the main window too,
  /// dropping a scale dragged to), and the windows docked to the main window
  /// keep their layout around its top-left corner.
  // --- Persistence ------------------------------------------------------------

  void _scheduleSave() {
    if (dock.isDragging) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      windowState.save,
    );
  }

  // --- Skins ------------------------------------------------------------------

  /// Opens what the app was asked to open before Dart was listening (e.g.
  /// the file that launched it).
  Future<void> _takePendingFiles() async {
    // Files opened with the app replace the restored playlist.
    await persistence.restorePlaylist();
    unawaited(playStats.load());
    unawaited(persistence.restoreLibrary());
    _instance?.onRequest = _onLaunchRequest;
    final launch = _launch;
    _launch = null;
    if (launch != null) {
      if (launch.paths.isNotEmpty) {
        await files.openPaths(launch.paths, play: !launch.add);
      }
      return;
    }
    try {
      final paths = await ampedChannel.invokeListMethod<String>(
        "takePendingFiles",
      );
      if (paths != null && paths.isNotEmpty) {
        await files.openPaths(paths, play: true);
      }
    } on Object {
      // No native file handling on this platform.
    }
  }

  /// A later launch's command line: its files, or else bringing the main
  /// window forward.
  void _onLaunchRequest(LaunchRequest request) {
    if (request.paths.isEmpty) {
      dock.nativeWindowOf(SkinWindow.main)?.focus();
      return;
    }
    unawaited(files.openPaths(request.paths, play: !request.add));
  }

  // --- Menus ------------------------------------------------------------------

  /// Shows the classic player main menu at the pointer (right-click on a window).
  void showMainMenu() => showMenu(AmpedMenus.main(this), null);

  /// Shows [items] with its top-left corner at the global [position] (the
  /// pointer when null). Deferred until the current pointer event has been
  /// dispatched, since the native menu blocks while open. The menu is as
  /// opaque as the skin's "Popup menu alpha" option says.
  void showMenu(List<NativeMenuItem> items, Offset? position) {
    Timer.run(
      () => NativeMenu.show(
        items,
        position ?? NativeScreen.cursorPosition(),
        opacity: wasabiHost.popupMenuOpacity,
      ),
    );
  }

  /// The global position of a point inside [window] given in unscaled skin
  /// pixels.
  Offset toGlobal(SkinWindow window, Offset skinPoint) =>
      dock.rectOf(window)!.topLeft + skinPoint * windowState.scaleOf(window);
}

class _SkinnedWindowDelegate with AppWindowDelegate {
  _SkinnedWindowDelegate(this.shell, this.window);

  final AmpedShell shell;
  final SkinWindow window;

  @override
  void onWindowCloseRequested(AppWindowController controller) {
    shell._onWindowClosed(window);
  }
}
