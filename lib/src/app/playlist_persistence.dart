import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../library/media_library.dart";
import "../library/saved_playlists.dart";
import "../library/watch_folders.dart";
import "../player/player_state.dart";
import "../player/playlist.dart";
import "../player/tag_cache.dart";

/// The playlist and Media Library the app keeps between runs.
class PlaylistPersistence {
  PlaylistPersistence({
    required this._player,
    required this._library,
    required this._videoLibrary,
    required this._savedPlaylists,
    required this._watchFolders,
  });

  final PlayerState _player;
  final MediaLibrary _library;
  final MediaLibrary _videoLibrary;
  final SavedPlaylists _savedPlaylists;
  final WatchFolders _watchFolders;

  /// Where the playlist is kept between runs (`Amped.m3u8` in the
  /// settings folder). A list saved as `the old playlist file`, its name before the
  /// rename, moves there.
  static Future<String> _playlistPath() async {
    // TODO(any): Abstract out the directory, so that it can be mocked in tests.
    final Directory support = await getApplicationSupportDirectory();
    return "${support.path}/amped/Amped.m3u8";
  }

  /// Where tags read from files are cached (`tags.sqlite` in the settings
  /// folder).
  static Future<String> _tagCachePath() async {
    // TODO(any): Abstract out the directory, so that it can be mocked in tests.
    final Directory support = await getApplicationSupportDirectory();
    return "${support.path}/amped/tags.sqlite";
  }

  /// Loads the Media Library from the tag cache's database.
  Future<void> restoreLibrary() async {
    // TODO(any): Pass in the TagCache instance, so that it can be mocked in tests.
    final TagCache? cache = _player.playlist.tagCache;
    if (cache == null) return;

    await _library.open(cache);
    await _videoLibrary.open(cache);
    await _savedPlaylists.open(cache);
    await _watchFolders.restore();
  }

  /// Saves the current entry and, when the list changed, the playlist, as
  /// `config_write` does on exit (`config_pilp`, `plneedsave`).
  Future<void> savePlaylist(Playlist playlist) async {
    try {
      // TODO(any): Pass in the SharedPreferences instance, so that it can be mocked in tests.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt("amped.pl_position", playlist.current);

      if (!playlist.modified) return;

      // TODO(any): Save the playlist in a background isolate, so that the UI doesn't freeze.
      // TODO(any): Pass in the directory to save to, so that the playlist can be saved in a different location (e.g. for "Save Playlist As..."), or to make it easier to test.
      final String path = await _playlistPath();
      await Directory(File(path).parent.path).create(recursive: true);
      await playlist.save(path);
    } on Object catch (error) {
      // TODO(any): Show a dialog to the user, so that they know that the playlist could not be saved.
      Arcane.log(
        "Could not save the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "PlaylistPersistence",
      );
    }
  }

  /// Loads the playlist saved by the last run and makes its saved entry
  /// current, without playing it. Its titles come from the tag cache (the
  /// saved ones only show until then), and then every file is read again
  /// in the background so that tags changed since are picked up.
  Future<void> restorePlaylist() async {
    final Playlist playlist = _player.playlist;
    // TODO(any): Pass in the SqliteTagCache instance, so that it can be mocked in tests.
    playlist.tagCache ??= await SqliteTagCache.tryOpen(await _tagCachePath());
    try {
      // TODO(any): Pass in the directory to load from, so that the playlist can be loaded from a different location (e.g. for "Load Playlist..."), or to make it easier to test.
      final String path = await _playlistPath();
      if (!File(path).existsSync() ||
          !await playlist.load(path, trustListTitles: false)) {
        return;
      }
      // TODO(any): Pass in the SharedPreferences instance, so that it can be mocked in tests.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int position = prefs.getInt("amped.pl_position") ?? 0;
      playlist.setCurrent(position.clamp(0, playlist.length - 1));
      unawaited(playlist.refreshAllTags());
    } on Object catch (error) {
      Arcane.log(
        "Could not load the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "PlaylistPersistence",
      );
    }
  }
}
