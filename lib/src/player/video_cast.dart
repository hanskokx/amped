import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:dart_cast/dart_cast.dart";
import "package:flutter/foundation.dart";

/// What the player needs of a cast to a device: while [active], it follows
/// the device's position and hands pause, seek and volume to it.
abstract class VideoCast extends ChangeNotifier {
  /// Whether a video is playing on a device.
  bool get active;

  /// How far the device is into the video.
  Duration get position;

  /// Whether the device has the video paused.
  bool get paused;

  void setPaused(bool paused);

  /// Keeps the cast for the next track, which the player is starting.
  void hold();

  void seek(Duration position);

  /// [volume] is 0..1.
  void setVolume(double volume);

  /// Ends the cast, and stops the device. [position] keeps where it was.
  /// With [silent], nothing follows from it, as when the player moves on to
  /// another video.
  Future<void> stop({bool silent = false});
}

/// Serves the pictures that go with what is cast (a cover, a frame of the
/// video) to the device, which fetches them over the network.
class CastArtworkServer {
  HttpServer? _server;
  final Map<String, (Uint8List, String)> _pictures = {};
  int _next = 0;

  /// Makes [bytes] available to a device at [deviceAddress], and returns
  /// the address it fetches them from, or `null` when this machine has no
  /// address on the device's network.
  Future<String?> serve(
    Uint8List bytes, {
    required String deviceAddress,
  }) async {
    final host = await NetworkUtils.getLocalIpAddress(
      targetDeviceIp: deviceAddress,
    );
    if (host == null) return null;
    final server = _server ??= await _start();
    final token = "${_next++}";
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    _pictures[token] = (bytes, png ? "image/png" : "image/jpeg");
    // Only the latest few: a device has fetched the one it shows.
    while (_pictures.length > 4) {
      _pictures.remove(_pictures.keys.first);
    }
    return "http://$host:${server.port}/$token";
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final picture = _pictures[request.uri.pathSegments.firstOrNull];
        final response = request.response;
        if (picture == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          // A receiver app draws it from its own web page.
          response.headers
            ..set("Access-Control-Allow-Origin", "*")
            ..contentType = ContentType.parse(picture.$2);
          response.contentLength = picture.$1.length;
          if (request.method != "HEAD") response.add(picture.$1);
        }
        try {
          await response.close();
        } on Object {
          // The device went away.
        }
      }),
    );
    return server;
  }

  Future<void> close() async {
    _pictures.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// Why a video could not be sent to a device.
enum CastFailure { unsupported, failed }

/// A device that plays video from this machine.
@immutable
class CastTarget {
  const CastTarget({required this.id, required this.name});

  final String id;
  final String name;
}

/// Finds Chromecasts on the network and plays a video on one, through
/// `dart_cast`. The device fetches the video from a server `dart_cast`
/// starts on this machine's address on the local network.
class VideoCastController extends VideoCast {
  VideoCastController({
    CastService? service,
    this.onStarted,
    this.onEnded,
    this.onFinished,
  }) : _given = service {
    CastLogger.setCallback(_logCast);
  }

  final CastService? _given;

  /// Passes what `dart_cast` reports on to the log.
  static void _logCast(String level, String message) {
    Arcane.log(
      "dart_cast reported",
      level: switch (level) {
        "ERROR" => Level.error,
        "WARNING" => Level.warning,
        "INFO" => Level.info,
        _ => Level.debug,
      },
      module: "dart_cast",
      metadata: {"message": message},
    );
  }

  late final CastService _service =
      _given ??
      CastService(
        discoveryProviders: [ChromecastDiscoveryProvider()],
        sessionFactory: (device) => ChromecastSession(device: device),
      );

  final CastArtworkServer _artwork = CastArtworkServer();

  /// Called with the video's position on the device when the cast ends.
  final void Function(Duration position, bool wasPaused)? onEnded;

  /// Called when the device ends the video by itself, so the player can
  /// move on to the next.
  final VoidCallback? onFinished;

  /// Called when a video starts playing on a device, so the player can stop
  /// playing it here.
  final VoidCallback? onStarted;

  final Map<String, CastDevice> _devices = {};
  StreamSubscription<List<CastDevice>>? _discovery;
  CastSession? _session;
  final List<StreamSubscription<Object?>> _listening = [];

  List<CastTarget> _targets = const [];
  bool _discovering = false;
  bool _active = false;
  bool _paused = false;
  bool _connecting = false;
  bool _holding = false;

  /// Whether the device has played since the last load.
  bool _playedSinceLoad = false;
  Duration _position = Duration.zero;
  CastTarget? _current;
  CastFailure? _failure;

  /// The Chromecasts found so far.
  List<CastTarget> get targets => _targets;

  bool get discovering => _discovering;

  /// Whether the cast waits for the next track.
  bool get holding => _holding;

  /// Whether a device is being connected to and loaded.
  bool get connecting => _connecting;

  /// The device playing, or being connected to.
  CastTarget? get current => _current;

  /// Why the last attempt to cast failed; cleared by the next.
  CastFailure? get failure => _failure;

  @override
  bool get active => _active;

  @override
  Duration get position => _position;

  @override
  bool get paused => _paused;

  /// Formats a device can't play as they are.
  static const Set<String> _unplayable = {
    "mkv",
    "avi",
    "wmv",
    "wma",
    "flv",
    "ts",
    "m2ts",
    "mpg",
    "mpeg",
    "ape",
    "pls",
    "m3u",
    "asx",
    "xspf",
  };

  /// How [location] goes to a device, or `null` when a device can't play it
  /// as it is: an MP4, M4V, MOV, WebM, MP3, M4A, AAC, FLAC, WAV, Ogg or Opus
  /// file on this machine, or an address of one, an HLS address, or an
  /// address with no extension (a radio station, an item on a server),
  /// which is tried.
  static CastMediaType? mediaType(String location) {
    final isUrl = RegExp(
      r"^https?://",
      caseSensitive: false,
    ).hasMatch(location);
    final path = isUrl ? Uri.tryParse(location)?.path ?? "" : location;
    final dot = path.lastIndexOf(".");
    final slash = path.lastIndexOf(RegExp(r"[/\\]"));
    final extension = dot > slash ? path.substring(dot + 1).toLowerCase() : "";
    if (extension == "m3u8") return isUrl ? CastMediaType.hls : null;
    if (extension.isEmpty) return isUrl ? CastMediaType.mp4 : null;
    if (_unplayable.contains(extension)) return null;
    if (isUrl) return CastMediaType.mp4;
    return const {
          "mp4",
          "m4v",
          "mov",
          "webm",
          "mp3",
          "m4a",
          "aac",
          "flac",
          "wav",
          "ogg",
          "oga",
          "opus",
        }.contains(extension)
        ? CastMediaType.mp4
        : null;
  }

  static const Map<String, String> _audioTypes = {
    "mp3": "audio/mpeg",
    "m4a": "audio/mp4",
    "aac": "audio/aac",
    "flac": "audio/flac",
    "wav": "audio/wav",
    "ogg": "audio/ogg",
    "oga": "audio/ogg",
    "opus": "audio/ogg",
  };

  /// The MIME type to tell a device [location] has when it is sound, or
  /// `null` for anything else. Sound told to be `video/mp4` makes a Chromecast
  /// show its video layout, with no cover. An address with no extension
  /// (a station) is asked what it is.
  static Future<String?> audioType(String location) async {
    final isUrl = RegExp(
      r"^https?://",
      caseSensitive: false,
    ).hasMatch(location);
    final path = isUrl ? Uri.tryParse(location)?.path ?? "" : location;
    final dot = path.lastIndexOf(".");
    final slash = path.lastIndexOf(RegExp(r"[/\\]"));
    final extension = dot > slash ? path.substring(dot + 1).toLowerCase() : "";
    if (_audioTypes.containsKey(extension)) return _audioTypes[extension];
    if (!isUrl || extension.isNotEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.parse(location))
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      final type = response.headers.contentType?.mimeType;
      // Only the headers are wanted; a station never ends.
      unawaited(response.drain<void>().catchError((Object _) {}));
      return type != null && type.startsWith("audio/") ? type : null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether [location] may go to a device: a file or address [mediaType]
  /// takes, a track of a media server, or a YouTube video.
  static bool canCast(String location) =>
      mediaType(location) != null || SourceLocation.isSource(location);

  /// Looks for Chromecasts for a few seconds.
  void discover() {
    if (_discovering) return;
    _discovering = true;
    notifyListeners();
    _discovery?.cancel();
    _discovery = _service
        .startDiscovery(timeout: const Duration(seconds: 6))
        .listen(
          (found) {
            for (final device in found) {
              _devices[device.id] = device;
            }
            _targets = [
              for (final device in _devices.values)
                CastTarget(id: device.id, name: device.name),
            ];
            notifyListeners();
          },
          onError: (Object error) => _discoveryEnded(error),
          onDone: _discoveryEnded,
        );
  }

  void _discoveryEnded([Object? error]) {
    if (error != null) {
      Arcane.log(
        "Looking for Chromecasts failed",
        level: Level.warning,
        module: "VideoCastController",
        metadata: {"error": "$error"},
      );
    }
    _discovering = false;
    notifyListeners();
  }

  /// Shows that the address of what plays could not be found.
  void failed() {
    _failure = CastFailure.failed;
    notifyListeners();
  }

  /// Plays [location] on [target], starting [from] into it.
  Future<void> cast(
    CastTarget target,
    String location, {
    required String title,
    required Duration from,
    required double volume,
    required bool paused,
    Uint8List? picture,
    String? pictureUrl,
  }) async {
    final device = _devices[target.id];
    final type = mediaType(location);
    if (device == null || type == null) {
      _failure = CastFailure.unsupported;
      notifyListeners();
      return;
    }
    // Moving on to the next track keeps the connection to the device.
    final following = _active && _session != null && _current?.id == target.id;
    if (!following) await _end(notify: false);
    _failure = null;
    _connecting = true;
    _playedSinceLoad = false;
    _current = target;
    _position = from;
    notifyListeners();
    try {
      final session = following ? _session! : await _service.connect(device);
      if (!following) {
        _session = session;
        _listening
          ..add(
            session.positionStream.listen((at) {
              _position = at;
              notifyListeners();
            }),
          )
          ..add(session.stateStream.listen(_stateChanged));
      }
      var imageUrl = pictureUrl;
      if (picture != null) {
        imageUrl = await _artwork.serve(
          picture,
          deviceAddress: device.address.address,
        );
      }
      final contentType = await audioType(location);
      final isUrl = location.contains("://");
      await session.loadMedia(
        isUrl
            ? CastMedia(
                url: location,
                type: type,
                title: title,
                imageUrl: imageUrl,
                contentType: contentType,
                startPosition: from,
              )
            : CastMedia.file(
                filePath: location,
                type: type,
                title: title,
                imageUrl: imageUrl,
                contentType: contentType,
                startPosition: from,
              ),
      );
      await session.setVolume(volume.clamp(0.0, 1.0));
      if (paused) await session.pause();
      _active = true;
      _holding = false;
      _paused = paused;
      _connecting = false;
      onStarted?.call();
      notifyListeners();
    } on Object catch (error) {
      Arcane.log(
        "Could not cast the video",
        level: Level.warning,
        module: "VideoCastController",
        metadata: {"device": target.name, "error": "$error"},
      );
      await _end(notify: false);
      _failure = CastFailure.failed;
      notifyListeners();
      // A track that was to follow is played here instead.
      if (following) onEnded?.call(from, false);
    }
  }

  void _stateChanged(SessionState state) {
    switch (state) {
      case SessionState.playing:
        _playedSinceLoad = true;
        _paused = false;
      case SessionState.paused:
        _paused = true;
      case SessionState.disconnected:
        if (_active) unawaited(stop());
        return;
      case SessionState.idle:
        if (!_active || _connecting || _holding) return;
        final length = _session?.duration ?? Duration.zero;
        final ended =
            _playedSinceLoad &&
            (length <= Duration.zero ||
                _position >= length - const Duration(seconds: 5));
        if (ended) {
          // The video reached its end on the device: the player moves on,
          // and sends the next one here.
          onFinished?.call();
        } else {
          // The device dropped it: it never played, or it was stopped on
          // the device. It plays here.
          Arcane.log(
            "The device stopped the video",
            level: Level.warning,
            module: "VideoCastController",
            metadata: {
              "playedSinceLoad": _playedSinceLoad,
              "positionMs": _position.inMilliseconds,
              "lengthMs": length.inMilliseconds,
            },
          );
          if (!_playedSinceLoad) _failure = CastFailure.failed;
          unawaited(stop());
        }
        return;
      default:
        return;
    }
    notifyListeners();
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    final session = _session;
    if (session != null) {
      unawaited(_guard(() => paused ? session.pause() : session.play()));
    }
    notifyListeners();
  }

  @override
  void hold() {
    if (!_active) return;
    _holding = true;
    _position = Duration.zero;
    notifyListeners();
  }

  @override
  void seek(Duration position) {
    _position = position;
    final session = _session;
    if (session != null) unawaited(_guard(() => session.seek(position)));
    notifyListeners();
  }

  @override
  void setVolume(double volume) {
    final session = _session;
    if (session != null) {
      unawaited(_guard(() => session.setVolume(volume.clamp(0.0, 1.0))));
    }
  }

  Future<void> _guard(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (error) {
      Arcane.log(
        "A Chromecast did not take a command",
        level: Level.warning,
        module: "VideoCastController",
        metadata: {"error": "$error"},
      );
    }
  }

  @override
  Future<void> stop({bool silent = false}) async {
    if (!_active && _session == null) return;
    final at = _position;
    final wasPaused = _paused;
    final wasActive = _active;
    await _end(notify: true);
    if (wasActive && !silent) onEnded?.call(at, wasPaused);
  }

  Future<void> _end({required bool notify}) async {
    _active = false;
    _connecting = false;
    _holding = false;
    _current = null;
    for (final subscription in _listening) {
      unawaited(subscription.cancel());
    }
    _listening.clear();
    final session = _session;
    _session = null;
    if (session != null) {
      await _guard(session.stop);
      await _guard(session.disconnect);
      session.dispose();
    }
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_discovery?.cancel());
    unawaited(_end(notify: false));
    unawaited(_service.dispose());
    unawaited(_artwork.close());
    super.dispose();
  }
}
