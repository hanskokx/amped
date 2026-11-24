import "dart:async";
import "dart:ui" as ui;
import "dart:ui" show Size;

import "package:flutter/foundation.dart";

import "player_state.dart";
import "playlist.dart";

/// Decodes [bytes] (a JPEG, PNG, ... cover read by [readArtwork]), or
/// null when they aren't a picture the engine can read.
Future<ui.Image?> decodeArtwork(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  }
}

/// The playing item's cover art, read when the item changes and decoded
/// for drawing: what the Album Art window and a modern skin's `<AlbumArt>`
/// show (gen_ff `AlbumArt.cpp`, gen_classicart).
///
/// The art is read only while something listens, the way the classic player reads it
/// only for a visible album art object.
class NowPlayingArt extends ChangeNotifier {
  NowPlayingArt(
    this.player, {
    this._read = readArtwork,
    this._decode = decodeArtwork,
  }) {
    player.addListener(_onPlayerChanged);
  }

  final PlayerState player;
  final Future<Uint8List?> Function(String location) _read;
  final Future<ui.Image?> Function(Uint8List bytes) _decode;

  /// The current item's cover, or null when it has none (or while it loads).
  ui.Image? get image => _image;
  ui.Image? _image;

  /// Whether the cover is being read.
  bool get loading => _loading;
  bool _loading = false;

  /// The item [image] is for, or null when nothing is loaded.
  PlaylistEntry? _entry;

  /// Whether [image] is for the current item.
  bool _current = false;

  /// The file [image] was decoded from.
  Uint8List? _bytes;

  /// Bumped by each load, so a slow one doesn't overwrite a later one.
  int _generation = 0;

  bool _disposed = false;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // Not now: widgets start listening while they build.
    if (!_current) {
      scheduleMicrotask(() {
        if (!_disposed && !_current) refresh();
      });
    }
  }

  void _onPlayerChanged() {
    if (identical(player.playlist.currentEntry, _entry)) return;
    _current = false;
    if (hasListeners) refresh();
  }

  /// Reads the current item's cover again (after its tags changed, or from
  /// the window's "Refresh album art").
  void refresh() {
    final entry = player.playlist.currentEntry;
    // The same item again (a skin asking every second): its cover stays
    // while it is read, or the picture would blink out each time.
    final same = identical(entry, _entry) && _image != null;
    _entry = entry;
    _current = true;
    final generation = ++_generation;
    if (entry == null || (entry.isUrl && !entry.isSource)) {
      _bytes = null;
      _set(null, loading: false);
      return;
    }
    // The previous track's cover goes as soon as another is asked for.
    if (!same) {
      _bytes = null;
      _set(null, loading: true);
    }
    unawaited(_load(entry.location, generation));
  }

  Future<void> _load(String location, int generation) async {
    final bytes = await _read(location);
    if (_disposed || generation != _generation) return;
    // The same picture as is shown: nothing to redraw.
    final shown = _bytes;
    if (bytes != null &&
        shown != null &&
        _image != null &&
        bytes.length == shown.length &&
        listEquals(bytes, shown)) {
      return;
    }
    final image = bytes == null ? null : await _decode(bytes);
    if (_disposed || generation != _generation) return;
    _bytes = bytes;
    _set(image, loading: false);
  }

  // Replaced images are left to the garbage collector rather than
  // disposed: a window that hasn't rebuilt yet may still paint one.
  void _set(ui.Image? image, {required bool loading}) {
    if (identical(_image, image) && _loading == loading) return;
    _image = image;
    _loading = loading;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    player.removeListener(_onPlayerChanged);
    _image = null;
    super.dispose();
  }
}

/// The size an album art window takes when dragged to [dragged], so the
/// picture area inside its [frame] has the shape of a picture of [art] size
/// and no bars beside it: the nearest such size to [dragged], so the corner
/// follows the pointer along the picture's diagonal. [frame] is how much
/// wider and taller the window is than its picture area. Kept within [min]
/// and [max], in whole pixels.
Size fitWindowToArt({
  required Size dragged,
  required Size frame,
  required Size art,
  required Size min,
  Size max = const Size(8000, 8000),
}) {
  if (art.isEmpty) return dragged;
  final aspect = art.width / art.height;
  Size fromWidth(double width) =>
      Size(width, (width - frame.width) / aspect + frame.height);
  Size fromHeight(double height) =>
      Size((height - frame.height) * aspect + frame.width, height);
  // The picture area nearest the dragged one on the line width = aspect *
  // height.
  final width = dragged.width - frame.width;
  final height = dragged.height - frame.height;
  final t = (width * aspect + height) / (aspect * aspect + 1);
  var size = fromHeight(t + frame.height);
  // Too small or large on either side: the side out of range sets it.
  if (size.width < min.width) size = fromWidth(min.width);
  if (size.height < min.height) size = fromHeight(min.height);
  if (size.width > max.width) size = fromWidth(max.width);
  if (size.height > max.height) size = fromHeight(max.height);
  return Size(size.width.roundToDouble(), size.height.roundToDouble());
}
