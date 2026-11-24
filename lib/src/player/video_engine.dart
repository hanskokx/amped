import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";

import "subtitle_files.dart";

/// Plays video files, picture and sound, so a large file starts at once and
/// seeking, the length and the picture's sync are the player's own. The
/// price is that a video's sound does not pass through SoLoud: the
/// equalizer, the visualizations and crossfading do not apply to it.
///
/// [extractAudio] is the other use: it decodes the sound of audio formats
/// SoLoud cannot read to a file SoLoud plays.
///
/// It notifies when a video starts or stops and when its size is known.
abstract class VideoEngine extends ChangeNotifier {
  /// Whether a video is loaded (`video_isVideoPlaying`).
  bool get active;

  /// The loaded video's size in pixels, once known.
  Size? get videoSize;

  /// The texture the picture is drawn to, once there is one.
  ValueListenable<int?> get textureId;

  /// Writes [location]'s sound to a file SoLoud can play and returns its
  /// path, or `null` when the file could not be read. A video with no sound
  /// gets silence of its own length. A later call, or [stop], abandons one
  /// still running (which then returns `null`).
  Future<String?> extractAudio(String location);

  /// Plays [location] from the start, replacing the video that was loaded,
  /// and calls [onFinished] when it ends by itself. [volume] is 0..1 and
  /// [balance] -1 (left)..1 (right). Returns the length (zero when the
  /// container does not say), or `null` when the file could not be played.
  ///
  /// With an [audioLocation], that file or address supplies the sound, for a
  /// picture that comes without it (YouTube's sharper streams).
  Future<Duration?> play(
    String location, {
    required double volume,
    required double balance,
    required VoidCallback onFinished,
    String? audioLocation,
  });

  /// The playback position; zero when no video is loaded.
  Duration get position;

  void setPaused(bool paused);

  void seek(Duration position);

  /// [volume] is 0..1.
  void setVolume(double volume);

  /// [balance] is -1 (left)..1 (right).
  void setBalance(double balance);

  /// Unloads the video.
  Future<void> stop();

  /// The subtitle tracks of the loaded video; empty when it has none (or
  /// the engine cannot show subtitles). Notifies when they become known.
  List<TrackOption> get subtitles => const [];

  /// The [TrackOption.id] shown, or `null` when subtitles are off.
  String? get subtitleId => null;

  /// Shows the subtitle track [id], or none for `null`.
  void selectSubtitle(String? id) {}

  /// Adds subtitle files from beside the video as tracks of the loaded
  /// video. The [SubtitleFile.location]s are files on this machine.
  Future<void> addSubtitleFiles(List<SubtitleFile> files) async {}

  /// The chapters of the loaded video; empty when it has none.
  List<VideoChapter> get chapters => const [];

  /// The audio tracks of the loaded video; empty when unknown.
  List<TrackOption> get audioTracks => const [];

  /// The [TrackOption.id] playing.
  String? get audioId => null;

  /// Plays the audio track [id].
  void selectAudio(String id) {}

  /// The picture on screen as a JPEG, or `null` when there is none.
  Future<Uint8List?> screenshot() async => null;
}

/// A chapter of a video.
@immutable
class VideoChapter {
  const VideoChapter({required this.time, this.title});

  /// Where the chapter starts.
  final Duration time;

  final String? title;

  /// The chapters in mpv's `chapter-list` ([json], `[{"title": "...",
  /// "time": 12.5}, ...]`), in time order; empty when it can't be read.
  static List<VideoChapter> parse(String json) {
    try {
      final list = jsonDecode(json);
      if (list is! List) return const [];
      final chapters = <VideoChapter>[
        for (final item in list)
          if (item is Map && item["time"] is num)
            VideoChapter(
              time: Duration(
                milliseconds: ((item["time"] as num) * 1000).round(),
              ),
              title:
                  item["title"] is String &&
                      (item["title"] as String).isNotEmpty
                  ? item["title"] as String
                  : null,
            ),
      ]..sort((a, b) => a.time.compareTo(b.time));
      return chapters;
    } on FormatException {
      return const [];
    }
  }
}

/// A subtitle or audio track of a video, to choose from.
@immutable
class TrackOption {
  const TrackOption({
    required this.id,
    this.title,
    this.language,
    this.supported = true,
  });

  /// What [VideoEngine.selectSubtitle] or [VideoEngine.selectAudio] takes.
  final String id;

  /// The track's own name, when the file gives one.
  final String? title;

  /// The track's language code, when the file gives one.
  final String? language;

  /// Whether the player can show the track.
  final bool supported;

  /// A name to list the track by; [fallback] when the file says nothing.
  String label(String fallback) {
    final parts = [
      if (language != null && language!.isNotEmpty) language!,
      if (title != null && title!.isNotEmpty) title!,
    ];
    return parts.isEmpty ? fallback : parts.join(" - ");
  }
}

/// [VideoEngine] on media_kit (libmpv).
class MediaKitVideoEngine extends VideoEngine {
  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  bool _active = false;
  Size? _size;

  /// Bumped by every [open] and [stop], so a superseded load does not
  /// start playing.
  int _request = 0;

  /// The player decoding a file's sound, while [extractAudio] runs.
  Player? _extractor;
  Completer<void>? _extraction;

  /// The sound files written, newest last, by video location.
  final Map<String, String> _audioFiles = {};
  Directory? _audioFolder;

  /// How many sound files are kept: the playing video's and the one
  /// before it (which may still be fading out).
  static const int _keptAudioFiles = 2;

  @override
  bool get active => _active;

  @override
  Future<Uint8List?> screenshot() async {
    if (!_active) return null;
    try {
      return await _player?.screenshot();
    } on Object {
      return null;
    }
  }

  @override
  Size? get videoSize => _size;

  @override
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    _initialized = true;
  }

  /// The folder the sound files go in, emptied of an earlier run's.
  Future<Directory> _folder() async {
    final existing = _audioFolder;
    if (existing != null) return existing;
    final folder = Directory(
      "${Directory.systemTemp.path}${Platform.pathSeparator}amped_video",
    );
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } on FileSystemException {
      // A file still in use; the rest is gone.
    }
    await folder.create(recursive: true);
    return _audioFolder = folder;
  }

  Future<void> _abandonExtraction() async {
    final extraction = _extraction;
    _extraction = null;
    if (extraction != null && !extraction.isCompleted) extraction.complete();
  }

  @override
  Future<String?> extractAudio(String location) async {
    await _abandonExtraction();
    final cached = _audioFiles.remove(location);
    if (cached != null && File(cached).existsSync()) {
      _audioFiles[location] = cached; // The newest again.
      return cached;
    }
    _ensureInitialized();
    final folder = await _folder();
    final path =
        "${folder.path}${Platform.pathSeparator}"
        "${DateTime.now().microsecondsSinceEpoch}.wav";
    final extraction = Completer<void>();
    _extraction = extraction;
    // The picture is drawn as a bare texture, so mpv (libass) must draw the
    // subtitles into it; the default leaves them to a widget this app lacks.
    final player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _extractor = player;
    var duration = Duration.zero;
    var failed = false;
    final subscriptions = [
      player.stream.completed.listen((completed) {
        if (completed && !extraction.isCompleted) extraction.complete();
      }),
      player.stream.duration.listen((value) {
        if (value > duration) duration = value;
      }),
      // With no sound to play, the file never completes.
      player.stream.tracks.listen((tracks) {
        bool real(String id) => id != "auto" && id != "no";
        final silent =
            tracks.video.any((track) => real(track.id)) &&
            !tracks.audio.any((track) => real(track.id));
        if (silent && !extraction.isCompleted) extraction.complete();
      }),
      player.stream.error.listen((error) {
        Arcane.log(
          "Could not read the video",
          level: Level.warning,
          module: "VideoEngine",
          metadata: {"location": location, "error": "$error"},
        );
        failed = true;
        if (!extraction.isCompleted) extraction.complete();
      }),
    ];
    try {
      final native = player.platform;
      if (native is! NativePlayer) return null;
      // mpv's file output writes as fast as it decodes. Stereo 16-bit is
      // what every SoLoud build reads.
      await native.setProperty("audio-display", "no");
      await native.setProperty("ao", "pcm");
      await native.setProperty("ao-pcm-file", path);
      await native.setProperty("audio-format", "s16");
      await native.setProperty("audio-channels", "stereo");
      await player.open(Media(location));
      await extraction.future;
      // A soundless video's length may arrive a moment after its tracks.
      for (var i = 0; i < 20 && duration <= Duration.zero && !failed; i++) {
        if (!identical(_extraction, extraction)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not read the video",
        level: Level.warning,
        module: "VideoEngine",
        metadata: {"location": location, "error": "$error"},
      );
      failed = true;
    } finally {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      // Closing the output completes the file's header.
      await player.dispose();
      if (identical(_extractor, player)) _extractor = null;
    }
    final file = File(path);
    if (!identical(_extraction, extraction)) {
      // Abandoned for another track.
      _delete(file);
      return null;
    }
    _extraction = null;
    final hasSound = !failed && file.existsSync() && file.lengthSync() > 1024;
    if (!hasSound) {
      if (duration <= Duration.zero) {
        _delete(file);
        return null;
      }
      await writeSilence(file, duration);
    }
    _audioFiles[location] = path;
    while (_audioFiles.length > _keptAudioFiles) {
      _delete(File(_audioFiles.remove(_audioFiles.keys.first)!));
    }
    return path;
  }

  static void _delete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Still open (Windows); the folder is emptied on the next run.
    }
  }

  /// Writes [duration] of silence to [file] as an 8 kHz mono 16-bit WAV.
  @visibleForTesting
  static Future<void> writeSilence(File file, Duration duration) async {
    const sampleRate = 8000;
    final dataLength = duration.inMilliseconds * sampleRate ~/ 1000 * 2;
    final header = ByteData(44)
      ..setUint32(0, 0x52494646) // "RIFF"
      ..setUint32(4, 36 + dataLength, Endian.little)
      ..setUint32(8, 0x57415645) // "WAVE"
      ..setUint32(12, 0x666d7420) // "fmt "
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, 1, Endian.little) // Mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(36, 0x64617461) // "data"
      ..setUint32(40, dataLength, Endian.little);
    final output = await file.open(mode: FileMode.write);
    try {
      await output.writeFrom(header.buffer.asUint8List());
      // The rest reads as zeros.
      await output.truncate(44 + dataLength);
    } finally {
      await output.close();
    }
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    _ensureInitialized();
    // The picture is drawn as a bare texture, so mpv (libass) must draw the
    // subtitles into it; the default leaves them to a widget this app lacks.
    final player = Player(
      configuration: const PlayerConfiguration(libass: true),
    );
    final controller = VideoController(player);
    _player = player;
    _controller = controller;
    controller.id.addListener(_textureChanged);
    _textureChanged();
    _subscriptions.addAll([
      player.stream.width.listen((_) => _sizeChanged()),
      player.stream.height.listen((_) => _sizeChanged()),
      player.stream.tracks.listen((tracks) {
        _preferDecodableAudio(player, tracks);
        _audio = [
          for (final track in tracks.audio)
            if (track.id != "auto" && track.id != "no")
              TrackOption(
                id: track.id,
                title: track.title,
                language: track.language,
              ),
        ];
        bool real(String id) => id != "auto" && id != "no";
        _subtitles = [
          for (final track in tracks.subtitle)
            if (real(track.id))
              TrackOption(
                id: track.id,
                title: track.title,
                language: track.language,
                // The bundled libmpv has no decoder for Blu-ray (PGS)
                // subtitles, so such a track would show nothing.
                supported: track.codec != "hdmv_pgs_subtitle",
              ),
        ];
        notifyListeners();
      }),
      player.stream.track.listen((track) {
        final audio = track.audio.id;
        _audioId = audio == "auto" || audio == "no" ? null : audio;
        final id = track.subtitle.id;
        _subtitleId = id == "auto" || id == "no" ? null : id;
        notifyListeners();
      }),
    ]);
    return player;
  }

  void _textureChanged() => textureId.value = _controller?.id.value;

  void _sizeChanged() {
    final state = _player?.state;
    final width = state?.width ?? 0;
    final height = state?.height ?? 0;
    final size = _active && width > 0 && height > 0
        ? Size(width.toDouble(), height.toDouble())
        : null;
    if (size == _size) return;
    _size = size;
    notifyListeners();
  }

  /// How long a file may take to tell its length before it is taken as
  /// unreadable.
  static const Duration _openTimeout = Duration(seconds: 20);

  final List<StreamSubscription<Object?>> _playback = [];

  Future<void> _endPlayback() async {
    for (final subscription in _playback) {
      unawaited(subscription.cancel());
    }
    _playback.clear();
  }

  @override
  Future<Duration?> play(
    String location, {
    required double volume,
    required double balance,
    required VoidCallback onFinished,
    String? audioLocation,
  }) async {
    _fellBack = false;
    final request = ++_request;
    await _endPlayback();
    final player = _ensurePlayer();
    final length = Completer<Duration?>();
    _playback.addAll([
      player.stream.duration.listen((value) {
        if (value > Duration.zero && !length.isCompleted) {
          length.complete(value);
        }
      }),
      player.stream.error.listen((error) {
        // A sound format the build cannot decode (TrueHD) leaves the picture
        // to play; only the file itself failing is a failure to play.
        if (_audioDecoderFailure.hasMatch(error)) {
          Arcane.log(
            "Playing the video without sound",
            level: Level.info,
            module: "VideoEngine",
            metadata: {"location": location, "error": error},
          );
          return;
        }
        Arcane.log(
          "Could not play the video",
          level: Level.warning,
          module: "VideoEngine",
          metadata: {"location": location, "error": error},
        );
        if (!length.isCompleted) length.complete(null);
      }),
      player.stream.completed.listen((completed) {
        if (completed && request == _request && _active) onFinished();
      }),
    ]);
    _seekTarget = null;
    Duration? total;
    try {
      final native = player.platform;
      if (native is NativePlayer) {
        // The cover picture inside an audiobook is no video to play (and
        // its decoder may not be built in).
        await native.setProperty("audio-display", "no");
        await native.setProperty("aid", "auto");
        // The subtitle files beside the video are added by the player
        // (they may be on a share), not found by mpv for local files only.
        await native.setProperty("sub-auto", "no");
      }
      await player.setVolume(volume * 100);
      await _applyBalance(balance);
      await player.setRate(1);
      await player.open(Media(location));
      // mpv's list options split at ':', which an address has, so the
      // sound is added with the command instead; it drops with the file.
      if (audioLocation != null && native is NativePlayer) {
        await native.command(["audio-add", audioLocation, "select"]);
      }
      total = await length.future.timeout(
        _openTimeout,
        onTimeout: () => Duration.zero,
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not play the video",
        level: Level.warning,
        module: "VideoEngine",
        metadata: {"location": location, "error": "$error"},
      );
      total = null;
    }
    if (request != _request) return null;
    if (total == null) {
      await _endPlayback();
      return null;
    }
    _active = true;
    _chapters = const [];
    _sizeChanged();
    notifyListeners();
    unawaited(_loadChapters(player, request));
    return total;
  }

  Duration? _seekTarget;

  /// Since the last seek: the position reads as the target until the
  /// player has got there, so the display does not jump back.
  final Stopwatch _lastSeek = Stopwatch()..start();

  static const Duration _seekSettle = Duration(milliseconds: 500);

  @override
  Duration get position {
    final player = _player;
    if (player == null || !_active) return Duration.zero;
    final target = _seekTarget;
    if (target != null) {
      if (_lastSeek.elapsed < _seekSettle) return target;
      _seekTarget = null;
    }
    return player.state.position;
  }

  @override
  void setPaused(bool paused) {
    final player = _player;
    if (player == null || !_active) return;
    unawaited(paused ? player.pause() : player.play());
  }

  @override
  void seek(Duration position) {
    final player = _player;
    if (player == null || !_active) return;
    _seekTarget = position;
    _lastSeek.reset();
    unawaited(player.seek(position));
  }

  @override
  void setVolume(double volume) {
    final player = _player;
    if (player == null) return;
    unawaited(player.setVolume(volume * 100));
  }

  @override
  void setBalance(double balance) {
    if (_player == null) return;
    unawaited(_applyBalance(balance));
  }

  /// mpv has no balance control; a filter scales the quieter side.
  Future<void> _applyBalance(double balance) async {
    final native = _player?.platform;
    if (native is! NativePlayer) return;
    final left = balance > 0 ? 1 - balance : 1.0;
    final right = balance < 0 ? 1 + balance : 1.0;
    try {
      await native.setProperty(
        "af",
        balance == 0
            ? ""
            : "lavfi=[pan=stereo|c0=${left.toStringAsFixed(3)}*c0"
                  "|c1=${right.toStringAsFixed(3)}*c1]",
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not set the balance",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "VideoEngine",
      );
    }
  }

  /// An error saying an audio format cannot be decoded.
  static final RegExp _audioDecoderFailure = RegExp(
    r"decoder for codec '(truehd|mlp|dts|dts-hd|eac3|ac3|aac|opus|flac|vorbis|mp3|pcm\w*)'",
    caseSensitive: false,
  );

  /// Whether another audio track was chosen for the loaded file.
  bool _fellBack = false;

  /// The build cannot decode TrueHD: plays the file's other sound track
  /// (a Blu-ray rip carries a Dolby Digital one beside it).
  void _preferDecodableAudio(Player player, Tracks tracks) {
    if (_fellBack) return;
    bool lossless(AudioTrack t) =>
        const {"truehd", "mlp"}.contains(t.codec?.toLowerCase());
    final real = [
      for (final t in tracks.audio)
        if (t.id != "auto" && t.id != "no") t,
    ];
    final playing = player.state.track.audio;
    if (!real.any((t) => lossless(t) && (t.id == playing.id))) {
      // Not on TrueHD now (or not yet chosen).
      if (playing.id != "auto") return;
    }
    for (final t in real) {
      if (!lossless(t)) {
        _fellBack = true;
        unawaited(player.setAudioTrack(t));
        return;
      }
    }
  }

  @override
  Future<void> addSubtitleFiles(List<SubtitleFile> files) async {
    final native = _player?.platform;
    if (native is! NativePlayer || !_active) return;
    for (final file in files) {
      try {
        await native.command([
          "sub-add",
          file.location,
          "auto",
          file.title,
          if (file.language != null) file.language!,
        ]);
      } on Object catch (error) {
        Arcane.log(
          "Could not add the subtitle file",
          metadata: {"title": file.title, "error": "$error"},
          level: Level.warning,
          module: "VideoEngine",
        );
      }
    }
  }

  List<TrackOption> _audio = const [];
  String? _audioId;

  List<VideoChapter> _chapters = const [];

  @override
  List<VideoChapter> get chapters => _active ? _chapters : const [];

  Future<void> _loadChapters(Player player, int request) async {
    try {
      final native = player.platform;
      if (native is! NativePlayer) return;
      final json = await native.getProperty("chapter-list");
      if (request != _request) return;
      _chapters = VideoChapter.parse(json);
      notifyListeners();
    } on Object catch (error) {
      Arcane.log(
        "Could not read the chapters",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "VideoEngine",
      );
    }
  }

  @override
  List<TrackOption> get audioTracks => _active ? _audio : const [];

  @override
  String? get audioId => _active ? _audioId : null;

  @override
  void selectAudio(String id) {
    final player = _player;
    if (player == null || !_active) return;
    for (final option in _audio) {
      if (option.id != id) continue;
      // The choice stands against the fallback from TrueHD.
      _fellBack = true;
      _audioId = id;
      notifyListeners();
      unawaited(
        player.setAudioTrack(AudioTrack(id, option.title, option.language)),
      );
      return;
    }
  }

  List<TrackOption> _subtitles = const [];
  String? _subtitleId;

  @override
  List<TrackOption> get subtitles => _active ? _subtitles : const [];

  @override
  String? get subtitleId => _active ? _subtitleId : null;

  @override
  void selectSubtitle(String? id) {
    final player = _player;
    if (player == null || !_active) return;
    TrackOption? option;
    for (final candidate in _subtitles) {
      if (candidate.id == id) option = candidate;
    }
    final track = option == null
        ? SubtitleTrack.no()
        : SubtitleTrack(option.id, option.title, option.language);
    _subtitleId = option?.id;
    notifyListeners();
    unawaited(_showSubtitle(player, track));
  }

  /// Picks the track and makes sure mpv draws it: a track chosen after the
  /// file loaded stays hidden when `sub-visibility` was switched off.
  Future<void> _showSubtitle(Player player, SubtitleTrack track) async {
    try {
      await player.setSubtitleTrack(track);
      final native = player.platform;
      if (native is NativePlayer) {
        await native.setProperty("sid", track.id == "no" ? "no" : track.id);
        await native.setProperty(
          "sub-visibility",
          track.id == "no" ? "no" : "yes",
        );
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not select the subtitles",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "VideoEngine",
      );
    }
  }

  @override
  Future<void> stop() async {
    _request++;
    await _abandonExtraction();
    await _endPlayback();
    _seekTarget = null;
    _subtitles = const [];
    _subtitleId = null;
    _audio = const [];
    _audioId = null;
    _chapters = const [];
    if (!_active) return;
    _active = false;
    _size = null;
    notifyListeners();
    await _player?.stop();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _controller?.id.removeListener(_textureChanged);
    unawaited(_player?.dispose());
    unawaited(_extractor?.dispose());
    for (final path in _audioFiles.values) {
      _delete(File(path));
    }
    textureId.dispose();
    super.dispose();
  }
}
