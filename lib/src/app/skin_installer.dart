import "dart:async";
import "dart:io";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../skin/input_idle_tracker.dart";
import "../skin/skin_manager.dart";
import "../skin/skin_preview_store.dart";
import "file_actions.dart";

/// Putting skins in: from the Add skins dialog, a dropped or opened archive,
/// and the file manager's previews of the folders they came from.
class SkinInstaller {
  SkinInstaller({
    required this._skins,
    required this._localizations,
    required this._files,
    required this._songTitle,
  });

  final SkinManager _skins;
  final AppLocalizations _localizations;
  final FileActions Function() _files;

  /// The main window's song title, where notices are shown.
  final ValueNotifier<String?> _songTitle;

  SkinPreviewStore? _skinPreviews;

  /// Drawing pictures waits for the person to stop using the app.
  final InputIdleTracker _idle = InputIdleTracker();

  static const String _skinFoldersKey = "amped.skin_folders";

  /// Keeps the file manager's pictures of the skin folders skins were added
  /// from up to date, a while after the app has started.
  void remakePreviewsLater() {
    Timer(const Duration(seconds: 45), () async {
      final prefs = await SharedPreferences.getInstance();
      for (final path
          in prefs.getStringList(_skinFoldersKey) ?? const <String>[]) {
        if (Directory(path).existsSync()) {
          await _makePreviews(Directory(path), remember: false);
        }
      }
    });
  }

  Future<void> _makePreviews(
    Directory folder, {
    bool remember = true,
  }) async {
    try {
      if (remember) {
        final prefs = await SharedPreferences.getInstance();
        final folders = prefs.getStringList(_skinFoldersKey) ?? [];
        if (!folders.contains(folder.path)) {
          await prefs.setStringList(_skinFoldersKey, [
            ...folders.take(19),
            folder.path,
          ]);
        }
      }
      final support = await getApplicationSupportDirectory();
      _idle.start();
      final store = _skinPreviews ??= SkinPreviewStore(
        Directory("${support.path}/amped/previews/${SkinPreviewStore.version}"),
        whenIdle: _idle.whenIdle,
      );
      await store.indexFolder(folder);
    } on Object catch (error) {
      Arcane.log(
        "Could not make skin previews",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SkinInstaller",
      );
    }
  }

  /// Copies the `.wsz` or `.wal` skin archive at [path] into the skins
  /// cache and switches to it. Re-installing a skin replaces the cached copy.
  Future<void> install(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      await _skins.importArchive(bytes, fileName: path.split("/").last);
      // The file manager's previews of the skins next to it, drawn as the
      // app draws them.
      unawaited(_makePreviews(File(path).parent));
    } on FormatException {
      _showNotice(_localizations.skinNotValid(path.split("/").last));
    } on Object catch (error) {
      Arcane.log(
        "Could not install the skin",
        metadata: {"path": path, "error": "$error"},
        level: Level.warning,
        module: "SkinInstaller",
      );
    }
  }

  /// Shows [text] in the song title for a few seconds, unless a control is
  /// showing text of its own there.
  void _showNotice(String text) {
    if (_songTitle.value != null) return;
    _songTitle.value = text;
    Timer(const Duration(seconds: 4), () {
      if (_songTitle.value == text) _songTitle.value = null;
    });
  }

  /// Lets the user pick `.wsz`/`.wal`/`.zip` (Bamp) files and installs them; the last one picked
  /// becomes active.
  Future<void> addSkins() async {
    final paths = await _files().openPanel(
      _localizations.addSkinsTitle,
      types: [_files().skinFiles],
    );
    for (final path in paths) {
      await install(path);
    }
  }
}
