import "package:amped_logging/amped_logging.dart";
import "package:flutter/services.dart";

/// One platform's media session: where [NowPlaying] publishes the current
/// track, and where media keys and transport controls come from.
///
/// `info` carries `state` ("playing", "paused" or "stopped"), `title`,
/// `artist`, `album`, `duration` and `elapsed` (whole seconds).
abstract interface class MediaSession {
  Future<void> setNowPlaying(Map<String, Object?> info);

  /// The current track's cover art (any image format), or null for none.
  Future<void> setArtwork(Uint8List? bytes);

  Future<void> dispose();
}

/// A media session implemented by the runner, over the `amped` channel (on
/// macOS: MPNowPlayingInfoCenter; on Windows: System Media Transport
/// Controls). The runner sends commands back as `remoteCommand` calls.
class ChannelMediaSession implements MediaSession {
  ChannelMediaSession(this._channel);

  final MethodChannel _channel;

  @override
  Future<void> setNowPlaying(Map<String, Object?> info) =>
      _send("setNowPlaying", info);

  @override
  Future<void> setArtwork(Uint8List? bytes) =>
      _send("setNowPlayingArtwork", bytes);

  @override
  Future<void> dispose() async {}

  Future<void> _send(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No media session on this platform.
    } on Object catch (error) {
      Arcane.log(
        "Now Playing update failed",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "MediaSession",
      );
    }
  }
}
