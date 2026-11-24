import "dart:async";
import "dart:io";

import "package:flutter/services.dart";

import "../player/player_state.dart";
import "../player/playlist.dart";
import "media_session.dart";
import "mpris_session.dart";

/// Publishes what is playing to the operating system's media session (on
/// macOS: Now Playing in Control Center, the lock screen, and media keys; on
/// Windows: the System Media Transport Controls; on Linux: MPRIS), and
/// carries the session's commands back to the player.
///
/// Updates are sent only when something meaningful changes — another track,
/// play/pause/stop, or a seek — since the OS advances the position on its
/// own from the playback rate.
class NowPlaying {
  /// Uses [session], or else the platform's own: MPRIS on Linux, the
  /// runner over [channel] elsewhere (whose commands arrive as
  /// `remoteCommand` calls for [handleCommand]).
  NowPlaying(
    this.player,
    MethodChannel channel, {
    MediaSession? session,
    this.readCover = readArtwork,
  }) {
    _session =
        session ??
        (Platform.isLinux
            ? MprisSession(handleCommand)
            : ChannelMediaSession(channel));
    player.addListener(_update);
  }

  final PlayerState player;

  /// Reads the cover of a file.
  final Future<Uint8List?> Function(String path) readCover;
  late final MediaSession _session;

  PlaylistEntry? _entry;
  String? _title;
  String _state = "stopped";
  int? _duration;
  int _sentElapsed = 0;
  DateTime _sentAt = DateTime.now();

  void dispose() {
    player.removeListener(_update);
    unawaited(_session.dispose());
  }

  String get _currentState => player.playing
      ? "playing"
      : player.paused
      ? "paused"
      : "stopped";

  void _update() {
    final entry = player.playlist.currentEntry;
    final state = _currentState;
    final elapsed = player.elapsedSec;
    final duration = entry?.duration?.inSeconds;
    // Where the OS believes playback is, from the last update.
    final expected = _state == "playing"
        ? _sentElapsed + DateTime.now().difference(_sentAt).inSeconds
        : _sentElapsed;
    final seeked = (elapsed - expected).abs() > 2;
    final newTrack = !identical(entry, _entry);
    if (!newTrack &&
        state == _state &&
        entry?.playingTitle == _title &&
        duration == _duration &&
        !seeked) {
      return;
    }
    _entry = entry;
    _title = entry?.playingTitle;
    _state = state;
    _duration = duration;
    _sentElapsed = elapsed;
    _sentAt = DateTime.now();
    unawaited(
      _session.setNowPlaying({
        "state": entry == null ? "stopped" : state,
        "title": entry?.trackTitle ?? entry?.title,
        "artist": entry?.artist,
        "album": entry?.album,
        "duration": duration,
        "elapsed": elapsed,
      }),
    );
    if (newTrack) unawaited(_sendArtwork(entry));
  }

  Future<void> _sendArtwork(PlaylistEntry? entry) async {
    final bytes = entry == null || (entry.isUrl && !entry.isSource)
        ? null
        : await readCover(entry.location);
    // Another track may have started while the picture was being read.
    if (!identical(entry, _entry)) return;
    await _session.setArtwork(bytes);
  }

  /// Handles a command from the OS media session (media keys, Control
  /// Center, headphones).
  void handleCommand(String command, {double? position}) {
    switch (command) {
      case "play":
        if (!player.playing) player.togglePlay();
      case "pause":
        if (player.playing) player.pause();
      case "togglePlayPause":
        if (player.playing) {
          player.pause();
        } else {
          player.togglePlay();
        }
      case "stop":
        player.stop();
      case "next":
        player.next();
      case "previous":
        player.prev();
      case "seek":
        final total = player.playlist.currentEntry?.duration;
        if (position != null && total != null && total.inMilliseconds > 0) {
          player.setSeek(position * 1000 * 256 ~/ total.inMilliseconds);
        }
    }
  }
}
