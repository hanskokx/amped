import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter/services.dart";

import "../player/album_art_fetch.dart";
import "../player/cover_files.dart";
import "../player/player_state.dart";
import "../player/playlist.dart" show readArtwork;
import "../player/tag_cache.dart";
import "../tags/tag_io.dart";

/// Where the playing item's cover comes from and goes to: the file, the
/// database, the folder beside it, or an online lookup that is embedded.
class CoverArt {
  CoverArt({
    required this.player,
    required this._channel,
    required this._refreshArt,
    required this._saveTags,
  });

  final PlayerState player;
  final MethodChannel _channel;

  /// Reloads the cover the Album Art window and the skins show.
  final void Function() _refreshArt;

  /// Writes tags (here, a picture) into a file.
  final Future<void> Function(
    String path,
    Map<TagField, String> changes, {
    List<EmbeddedPicture>? pictures,
  })
  _saveTags;

  /// The cover of the file at [path]: the one embedded in it, else the one
  /// kept in the database for files that can't hold pictures, else a cover
  /// file beside it (`cover.jpg`, `folder.png`, ...).
  Future<Uint8List?> readCoverBytes(String path) async {
    if (SourceLocation.isSource(path)) return SourceLocation.artwork(path);
    final embedded = await readArtwork(path);
    if (embedded != null) return embedded;
    final stored = await _storedCover(path);
    return stored ?? await readCoverFile(path);
  }

  Future<Uint8List?> _storedCover(String path) async {
    final store = player.playlist.tagCache;
    if (store is! ArtworkStore) return null;
    try {
      return await (store as ArtworkStore).storedArtwork(path);
    } on Object catch (error) {
      Arcane.log(
        "Could not read the stored cover",
        metadata: {"path": path, "error": "$error"},
        level: Level.warning,
        module: "CoverArt",
      );
      return null;
    }
  }

  /// Keeps [bytes] as the cover of [path] in the database. False when
  /// there is no database to keep it in.
  Future<bool> storeCover(String path, Uint8List bytes) async {
    final store = player.playlist.tagCache;
    if (store is! ArtworkStore) return false;
    try {
      await (store as ArtworkStore).storeArtwork(path, bytes);
      return true;
    } on Object catch (error) {
      Arcane.log(
        "Could not store the cover",
        metadata: {"path": path, "error": "$error"},
        level: Level.warning,
        module: "CoverArt",
      );
      return false;
    }
  }

  /// Whether [getAlbumArt] has something to look for: a playing file with
  /// an artist and an album.
  bool get canGetAlbumArt {
    final entry = player.playlist.currentEntry;
    return entry != null &&
        !entry.isUrl &&
        (entry.artist?.isNotEmpty ?? false) &&
        (entry.album?.isNotEmpty ?? false);
  }

  /// The Album Art window's "Get album art": looks the playing item's
  /// album up online and embeds the cover found in its file.
  Future<void> getAlbumArt() async {
    final entry = player.playlist.currentEntry;
    if (!canGetAlbumArt || entry == null) return;
    final path = entry.location;
    try {
      final bytes = await fetchAlbumArt(
        artist: entry.artist!,
        album: entry.album!,
      );
      if (bytes == null) return;
      final mime = sniffImageMime(bytes);
      if (mime == null) return;
      final existing = await readFilePicturesInBackground(path);
      if (!existing.editable) {
        // The file can't hold a picture: keep it in the database.
        if (await storeCover(path, bytes) &&
            identical(player.playlist.currentEntry, entry)) {
          _refreshArt();
        }
        return;
      }
      await _saveTags(
        path,
        const {},
        pictures: [
          EmbeddedPicture(
            type: ArtworkType.frontCover,
            mimeType: mime,
            data: bytes,
          ),
          for (final picture in existing.pictures)
            if (picture.type != ArtworkType.frontCover) picture,
        ],
      );
      if (identical(player.playlist.currentEntry, entry)) _refreshArt();
    } on Object catch (error) {
      Arcane.log(
        "Could not get the album art",
        metadata: {"path": path, "error": "$error"},
        level: Level.warning,
        module: "CoverArt",
      );
    }
  }

  /// The Album Art window's "Open folder" (and double-click): shows the
  /// playing file's folder.
  void openAlbumArtFolder() {
    final entry = player.playlist.currentEntry;
    if (entry == null || entry.isUrl) return;
    final path = entry.location;
    Future<void> open() async {
      if (Platform.isMacOS) {
        await _channel.invokeMethod<void>("revealInFinder", [path]);
      } else if (Platform.isWindows) {
        await Process.start("explorer.exe", ["/select,", path]);
      } else {
        await Process.start("xdg-open", [File(path).parent.path]);
      }
    }

    unawaited(
      open().catchError((Object error) {
        Arcane.log(
          "Could not open the folder",
          metadata: {"path": path, "error": "$error"},
          level: Level.warning,
          module: "CoverArt",
        );
      }),
    );
  }
}
