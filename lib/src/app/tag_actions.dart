import "dart:io";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:window_dock/window_dock.dart";

import "../library/media_library.dart";
import "../platform/file_dialogs.dart";
import "../player/player_state.dart";
import "../tags/tag_io.dart";
import "file_actions.dart";

/// Saving tags and artwork for the File Info and Edit Metadata dialogs.
class TagActions {
  TagActions({
    required this.player,
    required this.localizations,
    required this._files,
    required this._library,
    required this._fileInfoWindow,
  });

  final PlayerState player;
  final AppLocalizations localizations;
  final FileActions _files;
  final MediaLibrary _library;

  /// The File Info dialog's window, which its pickers attach to.
  final AppWindowController? Function() _fileInfoWindow;

  /// Writes the File Info dialog's [changes] to the file at [path], then
  /// re-reads its tags for the playlist (titles) and the tag cache.
  Future<void> saveFileTags(
    String path,
    Map<TagField, String> changes, {
    List<EmbeddedPicture>? pictures,
    Id3Edit? id3,
  }) async {
    await writeFileTagsInBackground(
      path,
      changes,
      pictures: pictures,
      id3: id3,
    );
    await player.playlist.fileTagsChanged(path);
    await _library.refresh([path]);
  }

  /// The image types the Artwork tab loads and saves, by extension.
  List<FileType> get _imageTypes => [
    (localizations.jpegFiles, ["jpg", "jpeg"]),
    (localizations.pngFiles, ["png"]),
    (localizations.gifFiles, ["gif"]),
    (localizations.bmpFiles, ["bmp"]),
    (localizations.webpFiles, ["webp"]),
  ];

  /// File Info > Artwork > Load Artwork... / Change...: the picked image
  /// file's bytes.
  Future<Uint8List?> openArtworkImage() async {
    final paths = await _files.dialogs.open(
      title: localizations.loadArtworkTitle,
      allFilesLabel: localizations.allFiles,
      allSupportedTypesLabel: localizations.imageFiles,
      types: _imageTypes,
      multiple: false,
      owner: _fileInfoWindow(),
    );
    if (paths.isEmpty) return null;
    try {
      return await File(paths.single).readAsBytes();
    } on Object catch (error) {
      Arcane.log(
        "Could not read the file",
        metadata: {"path": paths.single, "error": "$error"},
        level: Level.warning,
        module: "TagActions",
      );
      return null;
    }
  }

  /// File Info > Artwork > Save As...: writes the picture's data as it is
  /// stored, so in its own format.
  Future<void> saveArtworkAs(EmbeddedPicture picture) async {
    final format = picture.formatName.toLowerCase();
    final type = _imageTypes.firstWhere(
      (type) => type.$2.contains(format),
      orElse: () => (localizations.allFiles, const <String>[]),
    );
    final extension = type.$2.firstOrNull;
    final result = await _files.dialogs.save(
      title: localizations.saveArtworkTitle,
      formatLabel: localizations.saveAsTypeLabel,
      name: extension == null ? "cover" : "cover.$extension",
      types: [type],
      owner: _fileInfoWindow(),
    );
    if (result == null) return;
    try {
      await File(result.$1).writeAsBytes(picture.data);
    } on Object catch (error) {
      Arcane.log(
        "Could not write the file",
        metadata: {"path": result.$1, "error": "$error"},
        level: Level.warning,
        module: "TagActions",
      );
    }
  }
}
