import "dart:async";
import "dart:ui" as ui;

import "package:flutter/foundation.dart";

import "album_art.dart";
import "album_art_fetch.dart";
import "player_state.dart";
import "playlist.dart";

/// The playing item's cover from iTunes ([fetchAlbumArt]), for a skin's
/// notifier set to an "Internet" cover (the classic player's own looked it up online).
///
/// Looked up only while something listens, like [NowPlayingArt], and only
/// for items with an artist and an album to search for.
class OnlineArt extends ChangeNotifier {
  OnlineArt(this.player, {this._fetch = fetchAlbumArt}) {
    player.addListener(_onPlayerChanged);
  }

  final PlayerState player;
  final Future<Uint8List?> Function({
    required String artist,
    required String album,
  })
  _fetch;

  /// The current item's cover, or null when none was found (or yet).
  ui.Image? get image => _image;
  ui.Image? _image;

  PlaylistEntry? _entry;
  int _generation = 0;
  bool _disposed = false;

  /// Covers found, by artist and album, so a track change back is instant.
  final Map<String, ui.Image?> _found = {};

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_entry == null) scheduleMicrotask(refresh);
  }

  void _onPlayerChanged() {
    if (identical(player.playlist.currentEntry, _entry)) return;
    if (hasListeners) refresh();
  }

  void refresh() {
    if (_disposed) return;
    final entry = player.playlist.currentEntry;
    _entry = entry;
    final generation = ++_generation;
    final artist = entry?.artist ?? "";
    final album = entry?.album ?? "";
    if (artist.isEmpty || album.isEmpty) {
      _set(null);
      return;
    }
    final key = "$artist\u0000$album";
    if (_found.containsKey(key)) {
      _set(_found[key]);
      return;
    }
    _set(null);
    unawaited(_load(key, artist, album, generation));
  }

  Future<void> _load(
    String key,
    String artist,
    String album,
    int generation,
  ) async {
    ui.Image? image;
    try {
      final bytes = await _fetch(artist: artist, album: album);
      image = bytes == null ? null : await decodeArtwork(bytes);
    } on Object {
      image = null;
    }
    _found[key] = image;
    if (_disposed || generation != _generation) return;
    _set(image);
  }

  void _set(ui.Image? image) {
    if (identical(_image, image)) return;
    _image = image;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    player.removeListener(_onPlayerChanged);
    super.dispose();
  }
}
