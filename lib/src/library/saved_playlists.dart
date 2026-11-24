import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";

import "../player/playlist.dart";
import "../player/tag_cache.dart";

/// The playlists the user keeps in the Media Library. They live in the
/// library's SQLite database (see [open]) and can be exported to, and
/// imported from, `.m3u`, `.m3u8` and `.pls` files. Without a database they
/// are kept in memory only.
class SavedPlaylists extends ChangeNotifier {
  PlaylistStore? _store;
  List<SavedPlaylist> _playlists = const [];
  bool _disposed = false;

  /// The saved playlists, oldest first.
  List<SavedPlaylist> get playlists => _playlists;

  SavedPlaylist? byId(int id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  int _memoryId = 0;

  /// Keeps the playlists in [cache] (when it is a [PlaylistStore]) and
  /// loads what it holds.
  Future<void> open(TagCache cache) async {
    _store = cache is PlaylistStore ? cache as PlaylistStore : null;
    final store = _store;
    if (store == null) return;
    try {
      _playlists = await store.savedPlaylists();
    } on Object catch (error) {
      Arcane.log(
        "Could not load the saved playlists",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SavedPlaylists",
      );
      return;
    }
    if (!_disposed) notifyListeners();
  }

  /// Saves [items] as a new playlist called [name] and returns it.
  Future<SavedPlaylist> create(
    String name,
    List<SavedPlaylistItem> items,
  ) async {
    var id = --_memoryId;
    try {
      if (_store case final store?)
        id = await store.createPlaylist(name, items);
    } on Object catch (error) {
      Arcane.log(
        "Could not save the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SavedPlaylists",
      );
    }
    final playlist = SavedPlaylist(id, name, List.unmodifiable(items));
    _playlists = [..._playlists, playlist];
    if (!_disposed) notifyListeners();
    return playlist;
  }

  Future<void> rename(int id, String name) async {
    final playlist = byId(id);
    if (playlist == null) return;
    _playlists = [
      for (final p in _playlists) p.id == id ? p.renamed(name) : p,
    ];
    notifyListeners();
    try {
      await _store?.renamePlaylist(id, name);
    } on Object catch (error) {
      Arcane.log(
        "Could not rename the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SavedPlaylists",
      );
    }
  }

  Future<void> delete(int id) async {
    _playlists = [
      for (final p in _playlists)
        if (p.id != id) p,
    ];
    notifyListeners();
    try {
      await _store?.deletePlaylist(id);
    } on Object catch (error) {
      Arcane.log(
        "Could not delete the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SavedPlaylists",
      );
    }
  }

  /// Adds a copy of the playlist after it, called [name], and returns it
  /// (null when [id] is unknown).
  Future<SavedPlaylist?> duplicate(int id, String name) async {
    final source = byId(id);
    return source == null ? null : create(name, source.items);
  }

  /// Appends [locations] to the playlist.
  Future<void> append(int id, Iterable<String> locations) async {
    final playlist = byId(id);
    if (playlist == null) return;
    await _setItems(playlist, [
      ...playlist.items,
      for (final location in locations) SavedPlaylistItem(location),
    ]);
  }

  /// Removes the entries at [indices] from the playlist.
  Future<void> removeAt(int id, Iterable<int> indices) async {
    final playlist = byId(id);
    if (playlist == null) return;
    final gone = indices.toSet();
    await _setItems(playlist, [
      for (final (i, item) in playlist.items.indexed)
        if (!gone.contains(i)) item,
    ]);
  }

  /// Moves the entries at [indices] so that they sit together, in their
  /// order, where [to] is: an index into the playlist as it is now, so that
  /// they land before the entry that is at [to] (the end for its length).
  Future<void> move(int id, Iterable<int> indices, int to) async {
    final playlist = byId(id);
    if (playlist == null) return;
    final items = playlist.items;
    final moving = {
      for (final i in indices)
        if (i >= 0 && i < items.length) i,
    }.toList()..sort();
    if (moving.isEmpty) return;
    final target = to.clamp(0, items.length);
    final rest = [
      for (final (i, item) in items.indexed)
        if (!moving.contains(i)) item,
    ];
    final at = target - moving.where((i) => i < target).length;
    final moved = [
      ...rest.take(at),
      for (final i in moving) items[i],
      ...rest.skip(at),
    ];
    if (listEquals(moved, items)) return;
    await _setItems(playlist, moved);
  }

  /// Moves the entries at [indices] one place up ([delta] -1) or down (1).
  Future<void> nudge(int id, Iterable<int> indices, int delta) async {
    final sorted = indices.toList()..sort();
    if (sorted.isEmpty) return;
    return move(id, sorted, delta < 0 ? sorted.first - 1 : sorted.last + 2);
  }

  Future<void> _setItems(
    SavedPlaylist playlist,
    List<SavedPlaylistItem> items,
  ) async {
    _playlists = [
      for (final p in _playlists)
        p.id == playlist.id
            ? SavedPlaylist(p.id, p.name, List.unmodifiable(items))
            : p,
    ];
    if (!_disposed) notifyListeners();
    try {
      await _store?.setPlaylistItems(playlist.id, items);
    } on Object catch (error) {
      Arcane.log(
        "Could not change the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SavedPlaylists",
      );
    }
  }

  /// Reads the `.m3u`, `.m3u8` or `.pls` file at [path] into a new playlist
  /// named after the file. Null when it lists nothing.
  Future<SavedPlaylist?> import(String path) async {
    final items = [
      for (final item in await Playlist.readList(path))
        SavedPlaylistItem(
          item.location,
          title: item.title,
          duration: item.duration,
        ),
    ];
    if (items.isEmpty) return null;
    final file = path.split(RegExp(r"[\\/]")).last;
    final dot = file.lastIndexOf(".");
    return create(dot > 0 ? file.substring(0, dot) : file, items);
  }

  /// Writes [playlist] to [path] in the format its extension names (`.pls`,
  /// `.m3u8` with a byte-order mark, anything else `.m3u`).
  Future<void> export(SavedPlaylist playlist, String path) => File(path)
      .writeAsString(format(playlist, extension: Playlist.extensionOf(path)));

  /// The text of [playlist] as a file with [extension].
  static String format(SavedPlaylist playlist, {required String extension}) {
    final buffer = StringBuffer();
    final items = playlist.items;
    if (extension == "pls") {
      buffer.write("[playlist]\r\n");
      for (final (i, item) in items.indexed) {
        final n = i + 1;
        buffer.write("File$n=${item.location}\r\n");
        if (item.duration case final duration?) {
          buffer
            ..write("Title$n=${item.title ?? ""}\r\n")
            ..write("Length$n=${duration.inSeconds}\r\n");
        }
      }
      buffer
        ..write("NumberOfEntries=${items.length}\r\n")
        ..write("Version=2\r\n");
      return buffer.toString();
    }
    if (extension == "m3u8") buffer.write("﻿");
    buffer.write("#EXTM3U\n");
    for (final item in items) {
      if (item.duration case final duration?) {
        buffer.write("#EXTINF:${duration.inSeconds},${item.title ?? ""}\n");
      }
      buffer.write("${item.location}\n");
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
