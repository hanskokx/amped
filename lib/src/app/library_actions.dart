import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";

import "../library/media_library.dart";
import "../library/saved_playlists.dart";
import "../library/watch_folders.dart";
import "../player/player_state.dart";
import "../player/tag_cache.dart" show SavedPlaylist, SavedPlaylistItem;
import "file_actions.dart";

/// What the Media Library asks of the app: keeping the player's playlist,
/// importing and exporting saved playlists, and adding files and folders to
/// the library.
class LibraryActions {
  LibraryActions({
    required this.player,
    required this.localizations,
    required this._files,
    required this.library,
    required this.videoLibrary,
    required this.savedPlaylists,
    required this.watchFolders,
  });

  final PlayerState player;
  final AppLocalizations localizations;
  final FileActions _files;
  final MediaLibrary library;
  final MediaLibrary videoLibrary;
  final SavedPlaylists savedPlaylists;
  final WatchFolders watchFolders;

  /// Media Library > Playlists > Save current playlist: asks for a name and
  /// keeps the player's playlist under it. The player's playlist itself is
  /// not saved between runs as a library item, only on request.
  Future<void> saveCurrentPlaylistToLibrary() async {
    final entries = player.playlist.entries;
    if (entries.isEmpty) return;
    final name = await _files.promptText(
      title: localizations.mlSavePlaylistTitle,
      message: localizations.mlPlaylistNamePrompt,
      value: localizations.mlPlaylistDefaultName,
      confirmLabel: localizations.save,
    );
    if (name == null) return;
    await savedPlaylists.create(name, [
      for (final entry in entries)
        SavedPlaylistItem(
          entry.location,
          title: entry.title,
          duration: entry.duration,
        ),
    ]);
  }

  /// Media Library > Playlists > New playlist...: asks for a name and keeps
  /// an empty playlist under it, returning it (null when cancelled).
  Future<SavedPlaylist?> newSavedPlaylist({
    List<SavedPlaylistItem> items = const [],
  }) async {
    final name = await _files.promptText(
      title: localizations.mlNewPlaylistTitle,
      message: localizations.mlPlaylistNamePrompt,
      value: localizations.mlPlaylistDefaultName,
      confirmLabel: localizations.save,
    );
    if (name == null) return null;
    return savedPlaylists.create(name, items);
  }

  /// Copies the saved playlist as "[name] copy".
  Future<void> duplicateSavedPlaylist(int id) async {
    final playlist = savedPlaylists.byId(id);
    if (playlist == null) return;
    await savedPlaylists.duplicate(
      id,
      localizations.mlPlaylistCopyName(playlist.name),
    );
  }

  /// Adds the files to the saved playlist [id], or, when it is null, to a
  /// new one that is asked for.
  Future<void> addToSavedPlaylist(int? id, List<String> paths) async {
    if (id != null) return savedPlaylists.append(id, paths);
    await newSavedPlaylist(
      items: [for (final path in paths) SavedPlaylistItem(path)],
    );
  }

  Future<void> renameSavedPlaylist(int id) async {
    final playlist = savedPlaylists.byId(id);
    if (playlist == null) return;
    final name = await _files.promptText(
      title: localizations.mlRenamePlaylistTitle,
      message: localizations.mlPlaylistNamePrompt,
      value: playlist.name,
      confirmLabel: localizations.save,
    );
    if (name != null) await savedPlaylists.rename(id, name);
  }

  Future<void> deleteSavedPlaylist(int id) => savedPlaylists.delete(id);

  /// Replaces the player's playlist with the saved one and plays it, or
  /// adds it when [play] is false.
  Future<void> openSavedPlaylist(int id, {required bool play}) async {
    final playlist = savedPlaylists.byId(id);
    if (playlist == null) return;
    await _files.openPaths([
      for (final item in playlist.items) item.location,
    ], play: play);
  }

  /// Writes the saved playlist to a file (`.m3u`, `.pls` or `.m3u8`).
  Future<void> exportSavedPlaylist(int id) async {
    final playlist = savedPlaylists.byId(id);
    if (playlist == null) return;
    final result = await _files.dialogs.save(
      title: localizations.mlExportPlaylistTitle,
      formatLabel: localizations.saveAsTypeLabel,
      name: "${playlist.name}.m3u8",
      types: _files.saveFormats,
      typeIndex: 2,
      owner: _files.owner(),
    );
    if (result == null) return;
    try {
      await savedPlaylists.export(playlist, result.$1);
    } on Object catch (error) {
      Arcane.log(
        "Could not export the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "LibraryActions",
      );
    }
  }

  /// Reads playlist files into new saved playlists.
  Future<void> importPlaylists() async {
    final paths = await _files.openPanel(
      localizations.mlImportPlaylistTitle,
      types: [_files.playlistFiles],
    );
    for (final path in paths) {
      await savedPlaylists.import(path);
    }
  }

  /// Preferences > Media Library > Add...: picks a folder to watch.
  Future<void> addWatchFolder() async {
    final folders = await _files.openPanel(
      localizations.watchFoldersAddTitle,
      folders: true,
    );
    for (final folder in folders) {
      await watchFolders.add(folder);
    }
  }

  /// Media Library > File > Add media to Library...: scans the picked
  /// folders (the library's folder picker only takes folders).
  Future<void> addToLibrary() async {
    final folders = await _files.openPanel(
      localizations.mlAddMediaTitle,
      folders: true,
    );
    if (folders.isEmpty) return;
    await library.add(folders);
    await videoLibrary.add(folders);
  }

  /// Media Library > File > Add current playlist to Library.
  Future<void> addPlaylistToLibrary() async {
    final paths = [
      for (final entry in player.playlist.entries)
        if (!entry.location.contains("://")) entry.location,
    ];
    await library.add(paths);
    await videoLibrary.add(paths);
  }
}
