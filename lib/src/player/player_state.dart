import "dart:async";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_vis/amped_vis.dart";
import "package:amped_youtube/amped_youtube.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../remote/remote_file_system.dart";
import "../remote/remote_files.dart";
import "../remote/remote_location.dart";
import "audio_engine.dart";
import "eq_presets.dart";
import "equalizer.dart";
import "playlist.dart";
import "shared_youtube.dart";
import "subtitle_files.dart";
import "video_cast.dart";
import "video_engine.dart";

const String _kWindowShadeKey = "amped.window_shade";
const String _kAlwaysOnTopKey = "amped.always_on_top";
const String _kVideoAlwaysOnTopKey = "amped.video_always_on_top";
const String _kEqOpenKey = "amped.eq_open";
const String _kEqShadeKey = "amped.eq_shade";
const String _kPlOpenKey = "amped.pl_open";
const String _kMainOpenKey = "amped.main_open";
const String _kPlShadeKey = "amped.pl_shade";
const String _kVideoOpenKey = "amped.video_open";
const String _kVideoAutoOpenKey = "amped.video_autoopen";
const String _kVideoAutoCloseKey = "amped.video_autoclose";
const String _kVideoStopCloseKey = "amped.video_stopclose";
const String _kLibraryOpenKey = "amped.library_open";
const String _kAlbumArtOpenKey = "amped.albumart_open";
const String _kTimeRemainingKey = "amped.time_remaining";
const String _kUiScaleKey = "amped.ui_scale";
const String _kActiveSkinKey = "amped.active_skin";
const String _kEqPreampKey = "amped.eq_preamp";
const String _kEqBandsKey = "amped.eq_bands";
const String _kEqEnabledKey = "amped.eq_enabled";
const String _kEqAutoKey = "amped.eq_auto";
const String _kClassicVisKey = "amped.classic_vis";
const String _kCrossfadeKey = "amped.crossfade";

/// [d] as `m:ss`, or `h:mm:ss` from an hour up.
@visibleForTesting
String formatTrackLength(Duration d) {
  final s = d.inSeconds;
  final ss = (s % 60).toString().padLeft(2, "0");
  if (s < 3600) return "${s ~/ 60}:$ss";
  return "${s ~/ 3600}:${(s ~/ 60 % 60).toString().padLeft(2, "0")}:$ss";
}

/// The `amped.window_<name>_w/h` preference keys for a window size.
String _windowSizeKey(String window, String axis) =>
    "amped.window_${window}_$axis";

/// The `amped.window_<name>_x/y` preference keys for a window position.
String _windowPosKey(String window, String axis) =>
    "amped.window_${window}_$axis";

/// Playback and UI state for the player, mirroring the flags tracked by the
/// original main window. Playback goes through [AudioEngine]; the
/// tracks come from [playlist].
class PlayerState extends ChangeNotifier implements ClassicPlayer {
  PlayerState({
    this.windowShade = false,
    this.alwaysOnTop = false,
    this.eqOpen = false,
    this.eqShade = false,
    this.mainOpen = true,
    this.plOpen = false,
    this.plShade = false,
    this.videoOpen = false,
    this.libraryOpen = false,
    this.albumArtOpen = false,
    this.timeRemaining = false,
    double uiScale = 1.0,
    AudioEngine? engine,
    this.video,
    Playlist? playlist,
    RemoteFiles? remoteFiles,
    YouTubeResolver? youtube,
  }) : playlist = playlist ?? Playlist(youtube: youtube),
       _remoteFiles = remoteFiles ?? RemoteFiles.shared,
       _youtube = youtube ?? sharedYouTube,
       _uiScale = uiScale.clamp(1.0, 2.0),
       _engine = engine ?? AudioEngine() {
    this.playlist.addListener(notifyListeners);
    _engine.streamInfo.addListener(_streamInfoChanged);
  }

  /// Copies the tracks on network shares to this machine to play them.
  final RemoteFiles _remoteFiles;

  /// Finds the audio of YouTube links.
  final YouTubeResolver _youtube;

  /// How the copy of the track being fetched from a network share is
  /// coming along; null when nothing is being fetched.
  final ValueNotifier<RemoteProgress?> buffering = ValueNotifier(null);

  /// When [buffering] was last updated, so it changes a few times a second.
  final Stopwatch _bufferingClock = Stopwatch();

  /// The entry of the station whose song title is shown, if any.
  PlaylistEntry? _streamEntry;

  /// Shows what a playing station says about itself: its `StreamTitle` is
  /// the song title in the main window (the playlist keeps the entry's own
  /// title, the station's name), and its bitrate and sample rate light the
  /// kbps and kHz displays. The song title goes when the station stops.
  void _streamInfoChanged() {
    final info = _engine.streamInfo.value;
    final entry = playlist.currentEntry;
    final playingEntry =
        info != null && entry != null && entry.location == info.location
        ? entry
        : null;
    final previous = _streamEntry;
    if (previous != null && !identical(previous, playingEntry)) {
      playlist.clearStreamTitle(previous);
    }
    _streamEntry = playingEntry;
    if (playingEntry == null) return;
    playlist.updateStreamEntry(
      playingEntry,
      title: info!.title,
      bitrate: info.bitrate,
      sampleRate: info.sampleRate,
    );
  }

  /// The tracks to play.
  @override
  final Playlist playlist;

  final AudioEngine _engine;

  /// The audio engine (exposed so the app can start the device early).
  AudioEngine get engine => _engine;

  /// Draws video files' pictures; null when video is not available, and
  /// video files then do not play.
  final VideoEngine? video;

  /// The device the video plays on, when it is sent to one (Chromecast).
  /// While it [VideoCast.active], the video here is paused and the
  /// controls act on the device.
  VideoCast? cast;

  /// Sends the track that started to the device the last one played on.
  VoidCallback? castFollow;

  /// Whether the next track to start goes to the device the last one did.
  bool _castFollow = false;

  /// The device ended the track by itself.
  void castFinished() => _onTrackFinished(_playRequest);

  /// Whether the video plays on a device.
  bool get casting => cast?.active ?? false;

  /// Pauses the playback here, as the track went to a device.
  void castStarted() {
    _engine.setPaused(true);
    video?.setPaused(true);
    notifyListeners();
  }

  /// Brings the track back here, at [at] and paused as the device had it.
  void castEnded(Duration at, bool wasPaused) {
    if (!(playing || paused)) return;
    final video = this.video;
    _engine.setVolume(volume / 255);
    video?.setVolume(volume / 255);
    // A station has no position to go back to.
    final length = playlist.currentEntry?.duration ?? Duration.zero;
    final seekTo = length > Duration.zero ? at : null;
    if (video != null && video.active) {
      if (seekTo != null) video.seek(seekTo);
      video.setPaused(wasPaused);
    } else {
      if (seekTo != null) _engine.seek(seekTo);
      _engine.setPaused(wasPaused);
    }
    if (seekTo != null) elapsedSec = at.inSeconds;
    notifyListeners();
  }

  /// Whether the Video window opens when a video starts
  /// (`config_video_autoopen`).
  bool videoAutoOpen = true;

  /// Whether the Video window closes when the video stops
  /// (`config_video_autoclose`).
  bool videoAutoClose = true;

  /// Whether closing the Video window stops a playing video
  /// (`config_video_stopclose`); the sound plays on otherwise.
  bool videoStopOnClose = true;

  void setVideoAutoOpen(bool value) {
    if (videoAutoOpen == value) return;
    videoAutoOpen = value;
    unawaited(_saveBool(_kVideoAutoOpenKey, value));
    notifyListeners();
  }

  void setVideoAutoClose(bool value) {
    if (videoAutoClose == value) return;
    videoAutoClose = value;
    unawaited(_saveBool(_kVideoAutoCloseKey, value));
    notifyListeners();
  }

  void setVideoStopOnClose(bool value) {
    if (videoStopOnClose == value) return;
    videoStopOnClose = value;
    unawaited(_saveBool(_kVideoStopCloseKey, value));
    notifyListeners();
  }

  /// Restores the saved Video options.
  Future<void> loadVideoOptions() async {
    final prefs = await SharedPreferences.getInstance();
    videoAutoOpen = prefs.getBool(_kVideoAutoOpenKey) ?? true;
    videoAutoClose = prefs.getBool(_kVideoAutoCloseKey) ?? true;
    videoStopOnClose = prefs.getBool(_kVideoStopCloseKey) ?? true;
    videoAlwaysOnTop = prefs.getBool(_kVideoAlwaysOnTopKey) ?? false;
    notifyListeners();
  }

  /// Whether the playing track is a video (`video_isVideoPlaying`).
  bool get videoPlaying => video?.active ?? false;

  /// The Video window's own close (its button, the menu, Alt+V): stops a
  /// playing video too when [videoStopOnClose] is set, unless [keepPlaying]
  /// (the original's Shift), as `HideVideoWindow(1)`.
  void closeVideoWindow({bool keepPlaying = false}) {
    final stopping = videoStopOnClose && !keepPlaying && videoPlaying;
    setVideoOpen(false);
    if (stopping) stop();
  }

  /// Unloads the playing video, closing the Video window with it when
  /// [videoAutoClose] is set (`VideoClose`).
  void _closeVideo() {
    final video = this.video;
    if (video == null) return;
    final wasPlaying = video.active;
    unawaited(video.stop());
    if (wasPlaying && videoAutoClose) setVideoOpen(false);
  }

  @override
  void startVisualization() => _engine.startVisualization();

  @override
  void stopVisualization() => _engine.stopVisualization();

  @override
  (Float32List, Float32List)? get visualizationSamples =>
      _engine.visualizationSamples;

  @override
  bool playing = false;
  @override
  bool paused = false;
  @override
  bool shuffle = false;
  @override
  bool repeat = false;

  /// Manual playlist advance (`config_pladv` off): a finished track does
  /// not move on to the next one. With [repeat] on it plays again, which
  /// is the classic player's "repeat track" (PlayQueue.cpp).
  bool manualAdvance = false;
  @override
  bool eqOpen = false;
  @override
  bool eqShade = false;

  /// Whether the main window is shown (`config_mw_open`; Alt+W).
  bool mainOpen = true;

  @override
  bool plOpen = false;
  @override
  bool plShade = false;
  @override
  bool windowShade = false;
  @override
  bool alwaysOnTop = false;
  bool videoOpen = false;
  bool libraryOpen = false;

  /// Whether the Album Art window is open (gen_classicart `wnd_open`).
  bool albumArtOpen = false;

  /// Whether the time display counts down (`config_timeleftmode`).
  @override
  bool timeRemaining = false;
  bool active = true;

  double _uiScale = 1.0;

  /// The window scaling factor (1.0, 2.0, or 3.0) from the Window menu.
  @override
  double get uiScale => _uiScale;

  /// 0..255, volume.bmp row index maps `volume * 27 / 255`.
  @override
  int volume = 200;

  /// -127..127; balance.bmp row maps `abs(balance) * 27 / 127`.
  @override
  int balance = 0;

  /// 0..256 seek position, posbar thumb maps directly.
  @override
  int position = 0;

  /// The elapsed time of the current track, in whole seconds.
  @override
  int elapsedSec = 0;

  /// The current track's length in seconds (0 when unknown).
  @override
  int get durationSec => playlist.currentEntry?.duration?.inSeconds ?? 0;

  /// The current track's bitrate (kbps) and sample rate (kHz), 0 when unknown.
  @override
  int get bitrate => playlist.currentEntry?.bitrate ?? 0;
  @override
  int get mixrate => (playlist.currentEntry?.sampleRate ?? 0) ~/ 1000;

  /// The song title shown in the main window: "N. Title (m:ss)" for the
  /// current entry, or the program name when the playlist is empty.
  @override
  String get title {
    final entry = playlist.currentEntry;
    if (entry == null) return "Amped";
    final duration = entry.duration;
    final length = duration == null ? "" : " (${formatTrackLength(duration)})";
    return "${playlist.current + 1}. ${entry.playingTitle}$length";
  }

  @override
  int playIcon = 2;

  /// The preamp slider: 0 (top, +12 dB) to 63 (bottom, -12 dB), 31 = 0 dB,
  /// as the original's `config_preamp`.
  @override
  int preamp = Equalizer.neutral;

  /// The 10 band sliders (70 Hz to 16 kHz), in the preamp's scale
  /// (`eq_tab`).
  @override
  final List<int> eqBands = List.filled(10, Equalizer.neutral);

  /// Whether the Equalizer is enabled (the ON button; off at first, as
  /// `config_use_eq`).
  @override
  bool eqEnabled = false;

  /// Whether the Equalizer presets auto-load per song (the AUTO button).
  @override
  bool eqAuto = false;

  Timer? _ticker;

  /// Bumped on every new playback request, so a slow track load that has been
  /// superseded does not start playing.
  int _playRequest = 0;

  /// The request whose track is being loaded, so the ticker does not judge
  /// the previous track's position against the new track's length.
  int _startingRequest = -1;

  /// Asked before a track of a remote source plays: where to start it
  /// instead of at the beginning (an episode the user left off), or null.
  /// Set by the app, which asks the user whether to continue there.
  Future<Duration?> Function(PlaylistEntry entry)? resumeOffer;

  /// Told where the user is in a track of a remote source (a podcast
  /// episode), now and then while it plays and when it stops, pauses, is
  /// skipped or ends. Set by the app, which keeps and sends it on.
  void Function(
    PlaylistEntry entry,
    Duration position,
    Duration length, {
    required bool finished,
  })?
  progressReporter;

  /// Told when the current track has been played enough to count as a play:
  /// half of it, or [playCountCap] of it, or all of it. Set by the app,
  /// which keeps the play counts. Never told twice for one start of a track.
  void Function(PlaylistEntry entry)? playCounter;

  /// The most that is played of a track before it counts as played.
  static const Duration playCountCap = Duration(minutes: 4);

  /// The play request that was already counted.
  int _countedRequest = -1;

  /// Counts the current track as played, once per start. Streams (no known
  /// length) are not counted.
  void _countPlay() {
    if (_countedRequest == _playRequest) return;
    final entry = playlist.currentEntry;
    final length = entry?.duration;
    if (entry == null || length == null || length <= Duration.zero) return;
    _countedRequest = _playRequest;
    playCounter?.call(entry);
  }

  /// Whether [elapsed] of a [total] long track is enough to count it.
  static bool playedEnough(Duration elapsed, Duration total) {
    final threshold = total ~/ 2;
    return elapsed >= (threshold < playCountCap ? threshold : playCountCap);
  }

  /// How far playback was when progress was last reported, and whether the
  /// current track already ended (nothing is reported after that).
  Duration _lastReported = Duration.zero;
  bool _ended = false;

  /// Reports the current track's progress when it is a remote one:
  /// [position] (the engine's by default), or the whole track when
  /// [finished].
  void _reportProgress({Duration? position, bool finished = false}) {
    final entry = playlist.currentEntry;
    final length = entry?.duration;
    final report = progressReporter;
    if (entry == null ||
        report == null ||
        !entry.isSource ||
        length == null ||
        length <= Duration.zero ||
        // A track is being loaded: the position is the previous one's.
        _startingRequest == _playRequest ||
        (_ended && !finished)) {
      return;
    }
    final at = finished ? length : (position ?? _engine.position);
    _lastReported = at;
    if (finished) _ended = true;
    report(entry, at, length, finished: finished);
  }

  /// How often the progress is reported while a track plays.
  static const Duration progressInterval = Duration(seconds: 15);

  /// The Play button: resumes when paused, restarts the current track when
  /// playing, otherwise starts the current (or first) track. In shuffle mode
  /// with no track picked or selected yet, it starts a random track.
  @override
  void togglePlay() {
    if (paused) {
      paused = false;
      playing = true;
      playIcon = 0;
      _engine.setPaused(casting);
      video?.setPaused(casting);
      cast?.setPaused(false);
      _startTicker();
      notifyListeners();
      return;
    }
    if (playlist.isEmpty) return;
    if (shuffle && !playlist.hasChosenCurrent && playlist.selected.isEmpty) {
      unawaited(playIndex(playlist.randomIndex()));
      return;
    }
    unawaited(playIndex(playlist.current < 0 ? 0 : playlist.current));
  }

  /// Makes entry [index] current and plays it from the start. Unplayable
  /// entries are skipped, like the original moving on to the next title.
  ///
  /// With a [crossfade] length, the playing track fades out over it while
  /// this one fades in.
  @override
  Future<void> playIndex(int index, {Duration? crossfade}) async {
    if (index < 0 || index >= playlist.length) return;
    // Skipping away from a track: that is where it was left.
    if (playing || paused) _reportProgress();
    final request = ++_playRequest;
    _startingRequest = request;
    // A cast goes on with this track.
    if (casting) {
      _castFollow = true;
      cast!.hold();
    }
    playlist.setCurrent(index);
    final entry = playlist.currentEntry!;
    // A source track's tags are in the cache; the notification wants them.
    if (entry.isSource) await playlist.tagsRead(entry);
    if (request != _playRequest) return;
    final resumeAt = entry.isSource ? await resumeOffer?.call(entry) : null;
    if (request != _playRequest) return;
    // AUTO loads the track's preset before it starts.
    if (eqAuto) {
      final preset = await _autoPreset(entry);
      if (request != _playRequest) return;
      if (preset != null) applyEq(preset.preamp, preset.bands);
    }
    // A video plays, sound and picture, through the video engine.
    final video = this.video;
    final isVideo = Playlist.isVideo(entry.location);
    // Formats SoLoud cannot decode are decoded to a file by media_kit, with
    // no picture: the decoded file keeps the EQ, visualizations, volume
    // and seeking working as for any track.
    final youtubeVideo = YouTubeLink.tryParse(entry.location)?.videoUrl;
    // A source's AAC (audiobooks) is played by the video engine, from the
    // address it is streamed from, with no picture.
    final soundInVideoEngine =
        video != null && SourceLocation.playsInVideoEngine(entry.location);
    final decoded =
        youtubeVideo != null ||
        (!isVideo &&
            (!entry.isUrl || RemoteFiles.isRemote(entry.location)) &&
            Playlist.needsDecoder(entry.location));
    var location = entry.location;
    // A video on a network share is streamed from it; any other track on
    // one plays from a copy on this machine.
    var videoLocation = entry.location;
    // A YouTube video plays, picture and sound, through the video engine
    // from the two streams the resolver finds for it; without a picture it
    // plays as sound, decoded like any format SoLoud can't read.
    String? youtubeSound;
    var pictureFromYouTube = false;
    if (youtubeVideo != null) {
      final streams = await _youtube.streams(youtubeVideo);
      if (request != _playRequest) return;
      if (streams == null) {
        if (_startingRequest == request) _startingRequest = -1;
        _skipUnplayable(index);
        return;
      }
      final picture = streams.video;
      if (picture != null && video != null) {
        pictureFromYouTube = true;
        location = videoLocation = picture;
        youtubeSound = streams.audio;
      } else {
        location = videoLocation = streams.audio;
      }
    }
    if (RemoteFiles.isRemote(location) && isVideo && video != null) {
      try {
        location = videoLocation = await _remoteFiles.stream(location);
      } on Object catch (error) {
        Arcane.log(
          "Could not open the entry",
          metadata: {"location": entry.location, "error": "$error"},
          level: Level.warning,
          module: "PlayerState",
        );
        if (request == _playRequest) {
          if (_startingRequest == request) _startingRequest = -1;
          _skipUnplayable(index);
        }
        return;
      }
      if (request != _playRequest) return;
    } else if (RemoteFiles.isRemote(location)) {
      try {
        _bufferingClock.reset();
        location = videoLocation = await _remoteFiles.fetch(
          location,
          onProgress: (progress) {
            if (request != _playRequest) return;
            final first = !_bufferingClock.isRunning;
            if (!first &&
                _bufferingClock.elapsedMilliseconds < 250 &&
                progress.received != progress.total) {
              return;
            }
            _bufferingClock
              ..reset()
              ..start();
            buffering.value = progress;
          },
        );
      } on Object catch (error) {
        if (request == _playRequest) buffering.value = null;
        Arcane.log(
          "Could not open the entry",
          metadata: {"location": entry.location, "error": "$error"},
          level: Level.warning,
          module: "PlayerState",
        );
        if (request == _playRequest) {
          if (_startingRequest == request) _startingRequest = -1;
          _skipUnplayable(index);
        }
        return;
      }
      if (request != _playRequest) return;
      _bufferingClock.stop();
      buffering.value = null;
    }
    if (soundInVideoEngine) {
      try {
        videoLocation = await SourceLocation.resolve(entry.location);
      } on Object catch (error) {
        Arcane.log(
          "Could not open the entry",
          metadata: {"location": entry.location, "error": "$error"},
          level: Level.warning,
          module: "PlayerState",
        );
        if (_startingRequest == request) _startingRequest = -1;
        if (request == _playRequest) _skipUnplayable(index);
        return;
      }
      if (request != _playRequest) return;
    }
    if (isVideo || pictureFromYouTube || soundInVideoEngine) {
      if (video == null) {
        if (_startingRequest == request) _startingRequest = -1;
        _skipUnplayable(index);
        return;
      }
      // Its sound does not go through SoLoud, so there is nothing to fade.
      await _engine.stop();
      if (request != _playRequest) return;
      final length = await video.play(
        videoLocation,
        audioLocation: youtubeSound,
        volume: _castFollow ? 0 : volume / 255,
        balance: balance / 127,
        onFinished: () => _onTrackFinished(request),
      );
      if (_startingRequest == request) _startingRequest = -1;
      if (request != _playRequest) return;
      if (length == null) {
        _skipUnplayable(index);
        return;
      }
      if (videoAutoOpen && !soundInVideoEngine) setVideoOpen(true);
      if (isVideo && !pictureFromYouTube && !soundInVideoEngine) {
        unawaited(_addSubtitleFiles(entry.location, video, request));
      }
      _startedPlaying(entry, length);
      if (resumeAt != null && resumeAt < length) {
        video.seek(resumeAt);
        _resumedAt(resumeAt, length);
      }
      return;
    }
    if (decoded) {
      final sound = await video?.extractAudio(videoLocation);
      if (request != _playRequest) return;
      if (sound == null) {
        if (_startingRequest == request) _startingRequest = -1;
        _skipUnplayable(index);
        return;
      }
      location = sound;
    }
    final length = await _engine.play(
      location,
      volume: _castFollow ? 0 : volume / 255,
      pan: balance / 127,
      onFinished: () => _onTrackFinished(request),
      crossfade: crossfade,
    );
    if (_startingRequest == request) _startingRequest = -1;
    if (request != _playRequest) return;
    if (length == null) {
      _skipUnplayable(index);
      return;
    }
    _closeVideo();
    _startedPlaying(entry, length);
    if (resumeAt != null && resumeAt < length) {
      _engine.seek(resumeAt);
      _resumedAt(resumeAt, length);
    }
  }

  /// Shows the playback as already [resumeAt] into the [length] long track.
  void _resumedAt(Duration resumeAt, Duration length) {
    _lastReported = resumeAt;
    elapsedSec = resumeAt.inSeconds;
    position = (resumeAt.inMilliseconds * 256 ~/ length.inMilliseconds).clamp(
      0,
      256,
    );
    notifyListeners();
  }

  /// Shows [entry] as playing, [length] long.
  void _startedPlaying(PlaylistEntry entry, Duration length) {
    _ended = false;
    _lastReported = Duration.zero;
    playlist.updateEntry(entry, duration: length);
    // Pick up tags changed since the file was cached.
    unawaited(playlist.refreshTags(entry));
    playing = true;
    paused = false;
    playIcon = 0;
    position = 0;
    elapsedSec = 0;
    _startTicker();
    if (_castFollow) {
      // It plays on the device; here it only keeps time.
      _castFollow = false;
      _engine.setPaused(true);
      video?.setPaused(true);
      castFollow?.call();
    }
    notifyListeners();
  }

  /// Stops at entry [index], which could not be played, and moves on to
  /// the one after it.
  void _skipUnplayable(int index) {
    stop();
    final next = playlist.nextIndex(shuffle: false, repeat: false);
    if (next >= 0 && next != index) unawaited(playIndex(next));
  }

  /// The preset AUTO picks for [entry] ([EqPresets.forTrack]), waiting for
  /// its tags when its genre is needed; `null` for URLs.
  Future<EqPreset?> _autoPreset(PlaylistEntry entry) async {
    if (entry.isUrl) return null;
    return EqPresets.forTrack(
      entry.location,
      genres: () async {
        await playlist.tagsRead(entry);
        return entry.genres;
      },
    );
  }

  /// Applies AUTO's preset for the current entry, when AUTO is still on
  /// and the entry still current once it is known.
  Future<void> _autoLoadCurrent() async {
    final entry = playlist.currentEntry;
    if (!eqAuto || entry == null) return;
    final preset = await _autoPreset(entry);
    if (preset == null || !eqAuto) return;
    if (!identical(playlist.currentEntry, entry)) return;
    applyEq(preset.preamp, preset.bands);
  }

  /// Whether playback stops when the current track ends (Ctrl+V,
  /// `BUTTON4_CTRL`).
  bool stopAfterCurrent = false;

  void toggleStopAfterCurrent() {
    stopAfterCurrent = !stopAfterCurrent;
    notifyListeners();
  }

  /// Whether a track fades into the next as it ends (`Enable crossfading`
  /// in the Audio options, which modern skins bind toggles to).
  bool crossfade = false;

  /// How long the end of one track and the start of the next overlap when
  /// crossfading.
  static const Duration crossfadeLength = Duration(seconds: 5);

  /// The request whose track already crossfaded, or was found not to, so
  /// the ticker decides only once per track.
  int _crossfadeChecked = -1;

  void setCrossfade(bool value) {
    if (crossfade == value) return;
    crossfade = value;
    unawaited(_saveBool(_kCrossfadeKey, value));
    notifyListeners();
  }

  /// Restores the saved crossfading setting.
  Future<void> loadCrossfade() async {
    crossfade = await _loadBool(_kCrossfadeKey);
    notifyListeners();
  }

  /// Starts the next track fading in under the end of the current one, when
  /// crossfading is on, the track is long enough, and playback goes on
  /// after it; [elapsed] and [total] are the current track's.
  bool _maybeCrossfade(Duration elapsed, Duration total) {
    final request = _playRequest;
    if (!crossfade || _crossfadeChecked == request) return false;
    if (total < crossfadeLength * 2 || elapsed < total - crossfadeLength) {
      return false;
    }
    _crossfadeChecked = request;
    if (stopAfterCurrent) return false;
    final next = _nextAfterTrack();
    if (next < 0) return false;
    // A video's sound does not pass through SoLoud, so it cannot fade.
    if (Playlist.isVideo(playlist.entries[next].location) ||
        SourceLocation.playsInVideoEngine(playlist.entries[next].location)) {
      return false;
    }
    // The new request supersedes the fading track's end report.
    final left = total - elapsed;
    unawaited(
      playIndex(
        next,
        crossfade: left > Duration.zero
            ? left
            : const Duration(milliseconds: 1),
      ),
    );
    return true;
  }

  /// How far the position may run past the track length before the track
  /// counts as finished although SoLoud has not said so.
  ///
  /// SoLoud streams MP3s from disk and only ends the voice once it has
  /// decoded as many frames as it counted when opening the file. When the
  /// decoder delivers fewer (for example LAME files whose encoder padding
  /// gets trimmed while streaming), the voice never ends: it plays silence
  /// and its position keeps counting up. Seeking resynchronises the count,
  /// which is why such tracks do end after a seek.
  static const Duration overrunGrace = Duration(milliseconds: 500);

  /// Called by the engine when request [request]'s track ends by itself, and
  /// by the ticker when the position has run past the track's length. Only
  /// the first call for the current request moves on.
  void _onTrackFinished(int request) {
    if (request != _playRequest) return;
    _countPlay();
    _reportProgress(finished: true);
    // Anything that follows (the next track, or a stop) supersedes this
    // request, so a second end report for the same track is ignored.
    _playRequest++;
    if (stopAfterCurrent) {
      stopAfterCurrent = false;
      stop();
      return;
    }
    final next = _nextAfterTrack();
    if (next < 0) {
      stop();
    } else {
      unawaited(playIndex(next));
    }
  }

  /// The entry to play once the current track ends, or -1 to stop. With
  /// manual advance it is the same track in repeat, or none (PlayQueue.cpp).
  int _nextAfterTrack() => manualAdvance
      ? (repeat ? playlist.current : -1)
      : playlist.nextIndex(shuffle: shuffle, repeat: repeat);

  /// Adds the subtitle files beside the video at [location], on this machine
  /// or on a share, as tracks to choose from.
  Future<void> _addSubtitleFiles(
    String location,
    VideoEngine video,
    int request,
  ) async {
    try {
      final List<SubtitleFile> files;
      if (RemoteFiles.isRemote(location)) {
        final remote = RemoteLocation.tryParse(location)!;
        final neighbours = await _remoteFiles.neighbours(
          location,
          subtitleFolders,
        );
        final urls = {for (final e in neighbours) e.key: e.value};
        files = [
          for (final match in matchSubtitles(
            remote.name,
            [for (final e in neighbours) e.key],
            (name) => urls[name]!,
          ))
            match.value,
        ];
      } else if (location.contains("://")) {
        return;
      } else {
        files = await localSubtitles(location);
      }
      if (files.isEmpty) return;
      final local = <SubtitleFile>[];
      for (final file in files) {
        if (request != _playRequest) return;
        final path = RemoteFiles.isRemote(file.location)
            ? await _remoteFiles.fetch(file.location)
            : file.location;
        local.add(
          SubtitleFile(
            location: path,
            title: file.title,
            language: file.language,
          ),
        );
      }
      if (request != _playRequest) return;
      await video.addSubtitleFiles(local);
    } on Object catch (error) {
      Arcane.log(
        "Could not look for subtitles",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "PlayerState",
      );
    }
  }

  /// The Pause button: toggles pause while a track is playing.
  @override
  void pause() {
    if (!playing && !paused) return;
    paused = !paused;
    playing = !paused;
    playIcon = paused ? 1 : 0;
    _engine.setPaused(paused || casting);
    video?.setPaused(paused || casting);
    cast?.setPaused(paused);
    if (paused) {
      _reportProgress();
      _stopTicker();
    } else {
      _startTicker();
    }
    notifyListeners();
  }

  @override
  void stop() {
    if (playing || paused) _reportProgress();
    _playRequest++;
    buffering.value = null;
    _castFollow = false;
    unawaited(cast?.stop(silent: true));
    unawaited(_engine.stop());
    _closeVideo();
    playing = false;
    paused = false;
    position = 0;
    elapsedSec = 0;
    playIcon = 2;
    _stopTicker();
    notifyListeners();
  }

  /// Shift+V (`BUTTON4_SHIFT`): fades the volume out, then stops.
  Future<void> fadeOutAndStop() async {
    if (!playing) {
      stop();
      return;
    }
    final request = _playRequest;
    const steps = 20;
    for (var i = steps - 1; i >= 0; i--) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (request != _playRequest) return;
      _engine.setVolume(volume / 255 * i / steps);
      video?.setVolume(volume / 255 * i / steps);
    }
    stop();
    _engine.setVolume(volume / 255);
    video?.setVolume(volume / 255);
  }

  /// Left/Right arrows (`FFWD5S`/`REW5S`): seek by [delta].
  void seekBy(Duration delta) {
    final total = playlist.currentEntry?.duration;
    if (!(playing || paused) || total == null || total == Duration.zero) return;
    var target = Duration(seconds: elapsedSec) + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    setSeek(target.inMilliseconds * 256 ~/ total.inMilliseconds);
  }

  /// Seeks the playing track to [at] (as far as its length allows).
  void seekTo(Duration at) {
    final total = playlist.currentEntry?.duration;
    if (total == null || total <= Duration.zero) return;
    final target = at < Duration.zero
        ? Duration.zero
        : at > total
        ? total
        : at;
    setSeek(target.inMilliseconds * 256 ~/ total.inMilliseconds);
  }

  /// Up/Down arrows (`VOLUMEUP`/`DOWN`): about 2% per press.
  void volumeBy(int delta) => setVolume(volume + delta);

  /// Ctrl+Z / Ctrl+B (`BUTTON1_CTRL` / `BUTTON5_CTRL`): the
  /// first or last track.
  void firstTrack() => _skipTo(playlist.isEmpty ? -1 : 0);

  void lastTrack() => _skipTo(playlist.length - 1);

  /// Numpad 1/3 (`JUMP10BACK`/`FWD`): ten tracks back or forward.
  void jumpTracks(int delta) {
    if (playlist.isEmpty) return;
    _skipTo((playlist.current + delta).clamp(0, playlist.length - 1));
  }

  /// Next/previous track: plays it when something was playing, otherwise
  /// just makes it current.
  @override
  void next() => _skipTo(playlist.nextIndex(shuffle: shuffle, repeat: true));

  @override
  void prev() => _skipTo(playlist.previousIndex(shuffle: shuffle));

  void _skipTo(int index) {
    if (index < 0) return;
    if (playing || paused) {
      unawaited(playIndex(index));
    } else {
      playlist.setCurrent(index);
      unawaited(_autoLoadCurrent());
    }
  }

  @override
  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  @override
  void toggleRepeat() {
    repeat = !repeat;
    notifyListeners();
  }

  /// The Playlist Editor's `Repeat` as gen_ff's core keeps it: 0 off, 1
  /// the playlist, -1 the track (repeat with manual playlist advance;
  /// Core::getRepeat).
  int get repeatValue => !repeat
      ? 0
      : manualAdvance
      ? -1
      : 1;

  /// Sets [repeatValue]: 0 turns repeat and manual advance off, a positive
  /// value repeats the playlist and a negative one the track
  /// (Core::setRepeat).
  set repeatValue(int value) {
    final repeat = value != 0;
    final manualAdvance = value < 0;
    if (repeat == this.repeat && manualAdvance == this.manualAdvance) return;
    this.repeat = repeat;
    this.manualAdvance = manualAdvance;
    notifyListeners();
  }

  @override
  void setVolume(int value) {
    volume = value.clamp(0, 255);
    _engine.setVolume(volume / 255);
    video?.setVolume(volume / 255);
    cast?.setVolume(volume / 255);
    notifyListeners();
  }

  /// The volume before muting.
  int _volumeBeforeMute = 200;

  /// Whether the volume is all the way down.
  bool get muted => volume == 0;

  /// Mutes, or brings back the volume from before.
  void toggleMute() {
    if (volume > 0) {
      _volumeBeforeMute = volume;
      setVolume(0);
    } else {
      setVolume(_volumeBeforeMute);
    }
  }

  @override
  void setBalance(int value) {
    balance = value.clamp(-127, 127);
    _engine.setPan(balance / 127);
    video?.setBalance(balance / 127);
    notifyListeners();
  }

  /// Seeks to [value] (0..256 of the track).
  @override
  void setSeek(int value) {
    position = value.clamp(0, 256);
    final total = playlist.currentEntry?.duration;
    if (total != null) {
      final target = total * (position / 256);
      _engine.seek(target);
      video?.seek(target);
      cast?.seek(target);
      elapsedSec = target.inSeconds;
    }
    notifyListeners();
  }

  @override
  void setPreamp(int value) {
    final clamped = value.clamp(0, 63);
    if (clamped == preamp) return;
    preamp = clamped;
    _eqChanged();
  }

  @override
  void setEqBand(int index, int value) {
    if (index < 0 || index >= eqBands.length) return;
    final clamped = value.clamp(0, 63);
    if (clamped == eqBands[index]) return;
    eqBands[index] = clamped;
    _eqChanged();
  }

  @override
  void setEqEnabled(bool value) {
    if (eqEnabled == value) return;
    eqEnabled = value;
    _eqChanged();
  }

  @override
  void setEqAuto(bool value) {
    if (eqAuto == value) return;
    eqAuto = value;
    _eqChanged();
    // Switching AUTO on loads the current track's preset right away.
    if (value) unawaited(_autoLoadCurrent());
  }

  /// The main window's classic visualization options.
  @override
  ClassicVisOptions classicVis = const ClassicVisOptions();

  void setClassicVis(ClassicVisOptions options) {
    classicVis = options;
    unawaited(_saveClassicVis());
    notifyListeners();
  }

  /// A click on the visualization: spectrum, oscilloscope, off, ...
  @override
  void cycleClassicVis() {
    const modes = ClassicVisMode.values;
    setClassicVis(
      classicVis.copyWith(
        mode: modes[(classicVis.mode.index + 1) % modes.length],
      ),
    );
  }

  Future<void> _saveClassicVis() async {
    final prefs = await SharedPreferences.getInstance();
    final o = classicVis;
    await prefs.setStringList(_kClassicVisKey, [
      "${o.mode.index}",
      "${o.analyzerStyle.index}",
      "${o.thinBands ? 1 : 0}",
      "${o.scopeStyle.index}",
      "${o.peaks ? 1 : 0}",
      "${o.falloff}",
      "${o.peakFalloff}",
      "${o.refresh}",
    ]);
  }

  /// Restores the saved classic visualization options.
  Future<void> loadClassicVis() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kClassicVisKey);
    if (saved == null || saved.length < 8) return;
    int at(int i, int max) => (int.tryParse(saved[i]) ?? 0).clamp(0, max);
    classicVis = ClassicVisOptions(
      mode: ClassicVisMode.values[at(0, 2)],
      analyzerStyle: AnalyzerStyle.values[at(1, 2)],
      thinBands: at(2, 1) == 1,
      scopeStyle: ScopeStyle.values[at(3, 2)],
      peaks: at(4, 1) == 1,
      falloff: at(5, 4),
      peakFalloff: at(6, 4),
      refresh: at(7, 4).clamp(1, 4),
    );
  }

  /// Sends the EQ settings to the audio engine (`eq_set`), saves them, and
  /// notifies listeners.
  void _eqChanged() {
    _engine.setEqualizer(enabled: eqEnabled, preamp: preamp, bands: eqBands);
    unawaited(_saveEqualizer());
    notifyListeners();
  }

  Future<void> _saveEqualizer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kEqPreampKey, preamp);
    await prefs.setStringList(_kEqBandsKey, [
      for (final band in eqBands) "$band",
    ]);
    await prefs.setBool(_kEqEnabledKey, eqEnabled);
    await prefs.setBool(_kEqAutoKey, eqAuto);
  }

  /// Restores the saved EQ settings and hands them to the audio engine.
  Future<void> loadEqualizer() async {
    final prefs = await SharedPreferences.getInstance();
    preamp = (prefs.getInt(_kEqPreampKey) ?? Equalizer.neutral).clamp(0, 63);
    final bands = prefs.getStringList(_kEqBandsKey) ?? const [];
    for (var i = 0; i < eqBands.length && i < bands.length; i++) {
      eqBands[i] = (int.tryParse(bands[i]) ?? Equalizer.neutral).clamp(0, 63);
    }
    eqEnabled = prefs.getBool(_kEqEnabledKey) ?? false;
    eqAuto = prefs.getBool(_kEqAutoKey) ?? false;
    _engine.setEqualizer(enabled: eqEnabled, preamp: preamp, bands: eqBands);
    notifyListeners();
  }

  void toggleEq() {
    setEqOpen(!eqOpen);
  }

  void setEqOpen(bool value) {
    if (eqOpen == value) return;
    eqOpen = value;
    unawaited(_saveEqOpen(value));
    notifyListeners();
  }

  void setMainOpen(bool value) {
    if (mainOpen == value) return;
    mainOpen = value;
    unawaited(_saveBool(_kMainOpenKey, value));
    notifyListeners();
  }

  static Future<bool> loadMainOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMainOpenKey) ?? true;
  }

  void togglePlaylist() {
    setPlOpen(!plOpen);
  }

  void setPlOpen(bool value) {
    if (plOpen == value) return;
    plOpen = value;
    unawaited(_savePlOpen(value));
    notifyListeners();
  }

  void setVideoOpen(bool value) {
    if (videoOpen == value) return;
    videoOpen = value;
    unawaited(_saveBool(_kVideoOpenKey, value));
    notifyListeners();
  }

  void setLibraryOpen(bool value) {
    if (libraryOpen == value) return;
    libraryOpen = value;
    unawaited(_saveBool(_kLibraryOpenKey, value));
    notifyListeners();
  }

  void setAlbumArtOpen(bool value) {
    if (albumArtOpen == value) return;
    albumArtOpen = value;
    unawaited(_saveBool(_kAlbumArtOpenKey, value));
    notifyListeners();
  }

  @override
  void toggleTimeRemaining() {
    timeRemaining = !timeRemaining;
    unawaited(_saveBool(_kTimeRemainingKey, timeRemaining));
    notifyListeners();
  }

  /// Applies an EQ preset (preamp plus the 10 bands).
  void applyEq(int preampValue, List<int> bands) {
    preamp = preampValue.clamp(0, 63);
    for (var i = 0; i < eqBands.length && i < bands.length; i++) {
      eqBands[i] = bands[i].clamp(0, 63);
    }
    _eqChanged();
  }

  @override
  void toggleWindowShade() {
    windowShade = !windowShade;
    unawaited(_saveWindowShade(windowShade));
    notifyListeners();
  }

  /// Whether the Video window alone stays on top (when [alwaysOnTop] is
  /// off).
  bool videoAlwaysOnTop = false;

  /// Always on top for every window; from the Video window's own state, it
  /// goes to every window (and from every window, to none).
  @override
  void toggleAlwaysOnTop() => _setOnTop(all: !alwaysOnTop, video: false);

  /// The Video window's entry: that window alone, or none (from every
  /// window too).
  void toggleVideoAlwaysOnTop() {
    final on = alwaysOnTop || videoAlwaysOnTop;
    _setOnTop(all: false, video: !on);
  }

  void _setOnTop({required bool all, required bool video}) {
    if (alwaysOnTop == all && videoAlwaysOnTop == video) return;
    alwaysOnTop = all;
    videoAlwaysOnTop = video;
    unawaited(_saveAlwaysOnTop(all));
    unawaited(_saveVideoAlwaysOnTop(video));
    notifyListeners();
  }

  Future<void> _saveVideoAlwaysOnTop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVideoAlwaysOnTopKey, value);
  }

  void setAlwaysOnTop(bool value) {
    if (alwaysOnTop == value) return;
    alwaysOnTop = value;
    unawaited(_saveAlwaysOnTop(value));
    notifyListeners();
  }

  @override
  void setUiScale(double value) {
    final clamped = value.clamp(1.0, 2.0);
    if (clamped == _uiScale) return;
    _uiScale = clamped;
    unawaited(_saveUiScale(clamped));
    notifyListeners();
  }

  void toggleUiScale() {
    setUiScale(_uiScale == 1.0 ? 2.0 : 1.0);
  }

  @override
  @override
  void toggleEqShade() {
    eqShade = !eqShade;
    unawaited(_saveEqShade(eqShade));
    notifyListeners();
  }

  @override
  void togglePlShade() {
    plShade = !plShade;
    unawaited(_savePlShade(plShade));
    notifyListeners();
  }

  /// Whether every window that can be shaded (main, EQ, playlist) is shaded.
  bool get allShadesShaded => windowShade && eqShade && plShade;

  /// Shades or unshades every window that supports it.
  void toggleAllShades() {
    final shade = !allShadesShaded;
    var changed = false;
    if (windowShade != shade) {
      windowShade = shade;
      unawaited(_saveWindowShade(shade));
      changed = true;
    }
    if (eqShade != shade) {
      eqShade = shade;
      unawaited(_saveEqShade(shade));
      changed = true;
    }
    if (plShade != shade) {
      plShade = shade;
      unawaited(_savePlShade(shade));
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> _loadBool(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<bool> loadVideoOpen() => _loadBool(_kVideoOpenKey);

  static Future<bool> loadLibraryOpen() => _loadBool(_kLibraryOpenKey);

  static Future<bool> loadAlbumArtOpen() => _loadBool(_kAlbumArtOpenKey);

  static Future<bool> loadTimeRemaining() => _loadBool(_kTimeRemainingKey);

  Future<void> _saveWindowShade(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWindowShadeKey, value);
  }

  Future<void> _saveAlwaysOnTop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlwaysOnTopKey, value);
  }

  Future<void> _saveEqOpen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEqOpenKey, value);
  }

  Future<void> _saveEqShade(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEqShadeKey, value);
  }

  Future<void> _savePlOpen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlOpenKey, value);
  }

  Future<void> _savePlShade(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPlShadeKey, value);
  }

  Future<void> _saveUiScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kUiScaleKey, value);
  }

  static Future<bool> loadWindowShade() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWindowShadeKey) ?? false;
  }

  static Future<bool> loadAlwaysOnTop() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAlwaysOnTopKey) ?? false;
  }

  static Future<bool> loadEqOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEqOpenKey) ?? false;
  }

  static Future<bool> loadEqShade() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEqShadeKey) ?? false;
  }

  static Future<bool> loadPlOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPlOpenKey) ?? false;
  }

  static Future<bool> loadPlShade() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPlShadeKey) ?? false;
  }

  static Future<double> loadUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_kUiScaleKey) ?? 1.0).clamp(1.0, 3.0);
  }

  /// The name of the active skin, or `null` when the default (Base) applies.
  static Future<String?> loadActiveSkin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveSkinKey);
  }

  /// Persists the active skin name; `null` restores the default.
  static Future<void> saveActiveSkin(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_kActiveSkinKey);
    } else {
      await prefs.setString(_kActiveSkinKey, name);
    }
  }

  /// Loads the saved top-left position of the window named [window]
  /// (`"main"`, `"eq"`, or `"pl"`), or `null` when never moved.
  static Future<(double, double)?> loadWindowPos(String window) async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_windowPosKey(window, "x"));
    final y = prefs.getDouble(_windowPosKey(window, "y"));
    if (x == null || y == null) return null;
    return (x, y);
  }

  /// Persists the top-left position of the window named [window].
  static Future<void> saveWindowPos(String window, double x, double y) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_windowPosKey(window, "x"), x);
    await prefs.setDouble(_windowPosKey(window, "y"), y);
  }

  /// Loads the saved size (width, height) of the window named [window], or
  /// `null` when never resized.
  static Future<(double, double)?> loadWindowSize(String window) async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_windowSizeKey(window, "w"));
    final h = prefs.getDouble(_windowSizeKey(window, "h"));
    if (w == null || h == null) return null;
    return (w, h);
  }

  /// Persists the size (width, height) of the window named [window].
  static Future<void> saveWindowSize(String window, double w, double h) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_windowSizeKey(window, "w"), w);
    await prefs.setDouble(_windowSizeKey(window, "h"), h);
  }

  /// Follows the playback position for the display and seek bar.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_startingRequest == _playRequest) return;
      final video = this.video;
      final onVideo = video != null && video.active;
      final elapsed = casting
          ? cast!.position
          : onVideo
          ? video.position
          : _engine.position;
      final total = playlist.currentEntry?.duration;
      if (playing &&
          total != null &&
          total > Duration.zero &&
          elapsed >= total + overrunGrace) {
        _onTrackFinished(_playRequest);
        return;
      }
      if (playing &&
          total != null &&
          total > Duration.zero &&
          !onVideo &&
          !casting &&
          _maybeCrossfade(elapsed, total)) {
        return;
      }
      if (playing &&
          total != null &&
          total > Duration.zero &&
          playedEnough(elapsed, total)) {
        _countPlay();
      }
      if (playing && (elapsed - _lastReported).abs() >= progressInterval) {
        _reportProgress(position: elapsed);
      }
      final seconds = elapsed.inSeconds;
      final pos = total == null || total.inMilliseconds == 0
          ? 0
          : (elapsed.inMilliseconds * 256 ~/ total.inMilliseconds).clamp(
              0,
              256,
            );
      if (seconds == elapsedSec && pos == position) return;
      elapsedSec = seconds;
      position = pos;
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    if (playing || paused) _reportProgress();
    _stopTicker();
    _engine.streamInfo.removeListener(_streamInfoChanged);
    unawaited(_engine.stop());
    video?.dispose();
    playlist.removeListener(notifyListeners);
    playlist.dispose();
    buffering.dispose();
    super.dispose();
  }
}
