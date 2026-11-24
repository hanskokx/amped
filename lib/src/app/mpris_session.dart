import "dart:io";
import "dart:math" as math;

import "package:amped_logging/amped_logging.dart";
import "package:dbus/dbus.dart";
import "package:flutter/foundation.dart";

import "media_session.dart";

/// Carries a command from the media session to the player: play, pause,
/// togglePlayPause, stop, next, previous, or seek to `position` seconds.
typedef MediaCommandHandler = void Function(String command, {double? position});

const _rootInterface = "org.mpris.MediaPlayer2";
const _playerInterface = "org.mpris.MediaPlayer2.Player";
const _busName = "org.mpris.MediaPlayer2.amped";
const _noTrack = "/org/mpris/MediaPlayer2/TrackList/NoTrack";

/// The Linux media session: an MPRIS player on the D-Bus session bus, which
/// desktop shells (GNOME, KDE), `playerctl` and media key daemons talk to.
class MprisSession implements MediaSession {
  /// Connects to the session bus, or to [client]'s bus.
  MprisSession(this.onCommand, {DBusClient? client})
    : _client = client ?? DBusClient.session() {
    _object = _MprisObject(this);
    _ready = _register();
  }

  final MediaCommandHandler onCommand;
  final DBusClient _client;
  late final _MprisObject _object;
  late final Future<bool> _ready;

  String _state = "stopped";
  String? _title;
  String? _artist;
  String? _album;
  int? _duration;
  int _elapsed = 0;
  DateTime _sentAt = DateTime.now();
  int _trackNumber = 0;
  File? _artFile;

  Future<bool> _register() async {
    try {
      await _client.registerObject(_object);
      final reply = await _client.requestName(
        _busName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );
      // Another instance owns the plain name; the spec's way to run several.
      if (reply != DBusRequestNameReply.primaryOwner) {
        await _client.requestName(
          "$_busName.instance$pid",
          flags: {DBusRequestNameFlag.doNotQueue},
        );
      }
      return true;
    } on Object catch (error) {
      Arcane.log(
        "MPRIS unavailable",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "MprisSession",
      );
      return false;
    }
  }

  bool get _hasTrack => _title != null;

  String get _trackId =>
      _hasTrack ? "/org/amped/track/$_trackNumber" : _noTrack;

  /// Where playback is now, in microseconds.
  int get position {
    var micros = _elapsed * Duration.microsecondsPerSecond;
    if (_state == "playing") {
      micros += DateTime.now().difference(_sentAt).inMicroseconds;
    }
    final duration = _duration;
    if (duration != null && duration > 0) {
      micros = micros.clamp(0, duration * Duration.microsecondsPerSecond);
    }
    return micros;
  }

  String get playbackStatus => switch (_state) {
    "playing" => "Playing",
    "paused" => "Paused",
    _ => "Stopped",
  };

  DBusDict get metadata => DBusDict.stringVariant({
    "mpris:trackid": DBusObjectPath(_trackId),
    if (_hasTrack) "xesam:title": DBusString(_title!),
    if (_artist != null) "xesam:artist": DBusArray.string([_artist!]),
    if (_album != null) "xesam:album": DBusString(_album!),
    if (_duration != null)
      "mpris:length": DBusInt64(_duration! * Duration.microsecondsPerSecond),
    if (_artFile != null)
      "mpris:artUrl": DBusString(Uri.file(_artFile!.path).toString()),
  });

  @override
  Future<void> setNowPlaying(Map<String, Object?> info) async {
    final title = info["title"] as String?;
    final artist = info["artist"] as String?;
    final album = info["album"] as String?;
    final duration = (info["duration"] as num?)?.toInt();
    final elapsed = (info["elapsed"] as num?)?.toInt() ?? 0;
    final state = info["state"] as String? ?? "stopped";
    final expected = position;
    final trackChanged =
        title != _title ||
        artist != _artist ||
        album != _album ||
        duration != _duration;
    final stateChanged = state != _state;
    if (trackChanged) _trackNumber++;
    _title = title;
    _artist = artist;
    _album = album;
    _duration = duration;
    _state = state;
    _elapsed = elapsed;
    _sentAt = DateTime.now();
    if (!await _ready) return;
    await _object.emitPropertiesChanged(
      _playerInterface,
      changedProperties: {
        if (trackChanged) "Metadata": metadata,
        if (stateChanged) "PlaybackStatus": DBusString(playbackStatus),
        if (trackChanged || stateChanged) ..._capabilities,
      },
    );
    // Clients extrapolate Position from the rate, so only jumps are signaled.
    final jumped =
        (position - expected).abs() > 2 * Duration.microsecondsPerSecond;
    if (!trackChanged && jumped) {
      await _object.emitSignal(_playerInterface, "Seeked", [
        DBusInt64(position),
      ]);
    }
  }

  @override
  Future<void> setArtwork(Uint8List? bytes) async {
    final previous = _artFile;
    _artFile = null;
    if (bytes != null) {
      // A new name per track, since clients cache pictures by URL.
      final file = File(
        "${Directory.systemTemp.path}/amped-art-$pid-$_trackNumber",
      );
      try {
        await file.writeAsBytes(bytes, flush: true);
        _artFile = file;
      } on FileSystemException catch (error) {
        Arcane.log(
          "Could not write cover art",
          metadata: {"error": "$error"},
          level: Level.warning,
          module: "MprisSession",
        );
      }
    }
    if (previous != null && previous.path != _artFile?.path) {
      await _delete(previous);
    }
    if (!await _ready) return;
    await _object.emitPropertiesChanged(
      _playerInterface,
      changedProperties: {"Metadata": metadata},
    );
  }

  @override
  Future<void> dispose() async {
    final art = _artFile;
    if (art != null) await _delete(art);
    await _client.close();
  }

  Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  Map<String, DBusValue> get _capabilities => {
    "CanPlay": DBusBoolean(_hasTrack),
    "CanPause": DBusBoolean(_hasTrack),
    "CanSeek": DBusBoolean(_hasTrack && (_duration ?? 0) > 0),
    "CanGoNext": const DBusBoolean(true),
    "CanGoPrevious": const DBusBoolean(true),
  };

  Map<String, DBusValue> playerProperties() => {
    "PlaybackStatus": DBusString(playbackStatus),
    "Rate": const DBusDouble(1),
    "MinimumRate": const DBusDouble(1),
    "MaximumRate": const DBusDouble(1),
    "Metadata": metadata,
    "Volume": const DBusDouble(1),
    "Position": DBusInt64(position),
    "CanControl": const DBusBoolean(true),
    ..._capabilities,
  };

  /// Seeks to [micros], or past the end to the next track as the spec asks.
  void _seekTo(int micros) {
    final duration = _duration;
    if (duration == null || duration <= 0) return;
    if (micros > duration * Duration.microsecondsPerSecond) {
      onCommand("next");
      return;
    }
    onCommand(
      "seek",
      position: math.max(0, micros) / Duration.microsecondsPerSecond,
    );
  }
}

/// The `/org/mpris/MediaPlayer2` object.
class _MprisObject extends DBusObject {
  _MprisObject(this.session) : super(DBusObjectPath("/org/mpris/MediaPlayer2"));

  final MprisSession session;

  static final _rootProperties = {
    "CanQuit": const DBusBoolean(false),
    "CanRaise": const DBusBoolean(false),
    "HasTrackList": const DBusBoolean(false),
    "Identity": const DBusString("amped"),
    "SupportedUriSchemes": DBusArray.string(const ["file"]),
    "SupportedMimeTypes": DBusArray.string(const []),
  };

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectProperty read(String name, String type) =>
        DBusIntrospectProperty(
          name,
          DBusSignature(type),
          access: DBusPropertyAccess.read,
        );
    DBusIntrospectMethod method(String name, [Map<String, String>? args]) =>
        DBusIntrospectMethod(
          name,
          args: [
            for (final MapEntry(:key, :value) in (args ?? {}).entries)
              DBusIntrospectArgument(
                DBusSignature(value),
                DBusArgumentDirection.in_,
                name: key,
              ),
          ],
        );
    return [
      DBusIntrospectInterface(
        _rootInterface,
        methods: [method("Raise"), method("Quit")],
        properties: [
          read("CanQuit", "b"),
          read("CanRaise", "b"),
          read("HasTrackList", "b"),
          read("Identity", "s"),
          read("SupportedUriSchemes", "as"),
          read("SupportedMimeTypes", "as"),
        ],
      ),
      DBusIntrospectInterface(
        _playerInterface,
        methods: [
          method("Next"),
          method("Previous"),
          method("Pause"),
          method("PlayPause"),
          method("Stop"),
          method("Play"),
          method("Seek", {"Offset": "x"}),
          method("SetPosition", {"TrackId": "o", "Position": "x"}),
          method("OpenUri", {"Uri": "s"}),
        ],
        signals: [
          DBusIntrospectSignal(
            "Seeked",
            args: [
              DBusIntrospectArgument(
                DBusSignature("x"),
                DBusArgumentDirection.out,
                name: "Position",
              ),
            ],
          ),
        ],
        properties: [
          read("PlaybackStatus", "s"),
          read("Rate", "d"),
          read("MinimumRate", "d"),
          read("MaximumRate", "d"),
          read("Metadata", "a{sv}"),
          read("Volume", "d"),
          DBusIntrospectProperty(
            "Position",
            DBusSignature("x"),
            access: DBusPropertyAccess.read,
            annotations: [
              DBusIntrospectAnnotation(
                "org.freedesktop.DBus.Property.EmitsChangedSignal",
                "false",
              ),
            ],
          ),
          read("CanGoNext", "b"),
          read("CanGoPrevious", "b"),
          read("CanPlay", "b"),
          read("CanPause", "b"),
          read("CanSeek", "b"),
          read("CanControl", "b"),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == _rootInterface) {
      return switch (call.name) {
        "Raise" || "Quit" => DBusMethodSuccessResponse(),
        _ => DBusMethodErrorResponse.unknownMethod(),
      };
    }
    if (call.interface != _playerInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final command = switch (call.name) {
      "Next" => "next",
      "Previous" => "previous",
      "Pause" => "pause",
      "PlayPause" => "togglePlayPause",
      "Stop" => "stop",
      "Play" => "play",
      _ => null,
    };
    if (command != null) {
      session.onCommand(command);
      return DBusMethodSuccessResponse();
    }
    switch (call.name) {
      case "Seek" when call.signature == DBusSignature("x"):
        session._seekTo(session.position + call.values[0].asInt64());
      case "SetPosition" when call.signature == DBusSignature("ox"):
        final micros = call.values[1].asInt64();
        // A request for a track that is no longer current is ignored.
        if (call.values[0].asObjectPath().value == session._trackId &&
            micros >= 0) {
          session._seekTo(micros);
        }
      case "OpenUri":
        return DBusMethodErrorResponse.notSupported();
      case "Seek" || "SetPosition":
        return DBusMethodErrorResponse.invalidArgs();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  Map<String, DBusValue>? _properties(String interface) => switch (interface) {
    _rootInterface => _rootProperties,
    _playerInterface => session.playerProperties(),
    _ => null,
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = _properties(interface)?[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async => DBusMethodErrorResponse.propertyReadOnly();

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(_properties(interface) ?? {});
}
