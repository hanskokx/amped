import "dart:async";
import "dart:io";
import "dart:math";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_skin/amped_skin.dart";
import "package:file_drop/file_drop.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_dock/window_dock.dart";

import "../platform/file_dialogs.dart";
import "../platform/linux_reveal.dart";
import "../player/eqf.dart";
import "../player/player_state.dart";
import "../player/playlist.dart";

/// Opening, adding, saving and revealing files for the app: the Play and
/// playlist ADD/LIST menus, the EQ file items, text prompts and drag and
/// drop. It asks the shell for nothing but the window to attach dialogs to
/// and how to install a skin.
class FileActions {
  FileActions({
    required this.player,
    required this.localizations,
    required MethodChannel channel,
    required this.owner,
    required this._installSkin,
  }) : _channel = channel,
       dialogs = FileDialogs(channel);

  final PlayerState player;
  final AppLocalizations localizations;
  final MethodChannel _channel;
  final Future<void> Function(String path) _installSkin;

  /// The window the native dialogs attach to.
  final AppWindowController? Function() owner;

  /// The native open and save dialogs.
  final FileDialogs dialogs;

  static final List<String> openableExtensions = [
    ...Playlist.audioExtensions,
    ...Playlist.decodedExtensions,
    ...Playlist.videoExtensions,
    ...Playlist.listExtensions,
  ];

  FileType get audioFiles => (
    localizations.audioFiles,
    [...Playlist.audioExtensions, ...Playlist.decodedExtensions],
  );
  FileType get videoFiles => (
    localizations.videoFiles,
    Playlist.videoExtensions.toList(),
  );
  FileType get playlistFiles => (
    localizations.playlistFiles,
    Playlist.listExtensions.toList(),
  );
  FileType get skinFiles => (
    localizations.skinFiles,
    // Bamp skins are distributed as plain zips, Audacious skins as tarballs.
    ["wsz", "wal", "zip", "tar", "tgz", "gz", "tbz2", "tbz", "bz2"],
  );

  /// Play > File... (L), the eject button: replaces the playlist with the
  /// picked files and plays them (`FILE_PLAY`).
  Future<void> openFiles() async => _play(
    await openPanel(
      localizations.openFilesTitle,
      types: [audioFiles, videoFiles, playlistFiles],
    ),
  );

  /// Play > Folder... (Shift+L), Shift-click on eject (`FILE_DIR`).
  Future<void> openFolder() async => _play(
    await openPanel(localizations.openFolderTitle, folders: true),
  );

  /// Play > URL... (Ctrl+L), Ctrl-click on eject (`FILE_LOC`).
  Future<void> openUrl() async {
    final url = await promptUrl(localizations.openUrlTitle);
    if (url != null) await _play([url]);
  }

  /// Playlist ADD > Add file(s) (`IDC_PLAYLIST_ADDMP3`).
  Future<void> addFiles() async => player.playlist.add(
    await openPanel(
      localizations.addFilesToPlaylistTitle,
      types: [audioFiles, videoFiles, playlistFiles],
    ),
  );

  /// Playlist ADD > Add folder (`IDC_PLAYLIST_ADDDIR`).
  Future<void> addFolder() async => player.playlist.add(
    await openPanel(localizations.addFolderToPlaylistTitle, folders: true),
  );

  /// Playlist ADD > Add URL (`IDC_PLAYLIST_ADDLOC`).
  Future<void> addUrl() async {
    final url = await promptUrl(localizations.addUrlToPlaylistTitle);
    if (url != null) await player.playlist.add([url]);
  }

  /// Playlist LIST > Load list (`ID_PE_OPEN`, `playlist_open`): replaces
  /// the playlist and makes its first entry (a random one with shuffle on)
  /// current, without starting or stopping playback.
  Future<void> loadList() async {
    final List<String> paths = await openPanel(
      localizations.loadPlaylistTitle,
      types: [playlistFiles],
      multiple: false,
    );
    if (paths.isEmpty) return;
    final playlist = player.playlist;
    if (!await playlist.load(paths.single)) return;
    playlist.setCurrent(
      player.shuffle ? Random().nextInt(playlist.length) : 0,
    );
  }

  /// The "Save as type" choices of Save list, in the original's order.
  List<FileType> get saveFormats => [
    (localizations.m3uPlaylistType, ["m3u"]),
    (localizations.plsPlaylistType, ["pls"]),
    (localizations.m3u8PlaylistType, ["m3u8"]),
  ];

  /// Playlist LIST > Save list (`ID_PE_SAVEAS`, `savepls`), in the format
  /// the file's extension names. The chosen type is remembered (`plsflt`,
  /// M3U8 at first).
  Future<void> saveList() async {
    // TODO(any): Pass in the SharedPreferences instance, so it can be mocked in tests.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int format = prefs.getInt("amped.pl_save_format") ?? 2;
    final (String, int)? result = await dialogs.save(
      title: localizations.savePlaylistTitle,
      formatLabel: localizations.saveAsTypeLabel,
      name: "Playlist.${saveFormats[format].$2.first}",
      types: saveFormats,
      typeIndex: format,
      owner: owner(),
    );
    if (result == null) return;
    final (String path, int chosen) = result;
    await prefs.setInt("amped.pl_save_format", chosen);
    try {
      await player.playlist.save(path);
    } on Object catch (error) {
      Arcane.log(
        "Could not save the playlist",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileActions",
      );
    }
  }

  FileType get eqFiles => (localizations.eqFiles, ["eqf", "q1"]);

  /// EQ Presets > Load > From EQF... (`ID_LOAD_EQF`): applies the "Entry1"
  /// preset of the picked EQ library.
  Future<void> loadEqf() async {
    final List<String> paths = await openPanel(
      localizations.loadEqFileTitle,
      types: [eqFiles],
      multiple: false,
    );
    if (paths.isEmpty) return;
    try {
      final preset = Eqf.read(await File(paths.single).readAsBytes());
      if (preset != null) player.applyEq(preset.preamp, preset.bands);
    } on Object catch (error) {
      Arcane.log(
        "Could not read the file",
        metadata: {"path": paths.single, "error": "$error"},
        level: Level.warning,
        module: "FileActions",
      );
    }
  }

  /// EQ Presets > Save > To EQF... (`ID_SAVE_EQF`).
  Future<void> saveEqf() async {
    final result = await dialogs.save(
      title: localizations.saveEqFileTitle,
      formatLabel: localizations.saveAsTypeLabel,
      name: "Preset.eqf",
      types: [
        (localizations.eqFiles, ["eqf"]),
      ],
      owner: owner(),
    );
    if (result == null) return;
    try {
      await File(result.$1).writeAsBytes(
        Eqf.write(preamp: player.preamp, bands: player.eqBands),
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not write the file",
        metadata: {"path": result.$1, "error": "$error"},
        level: Level.warning,
        module: "FileActions",
      );
    }
  }

  /// Context > Explore item(s) folder: reveals the selected files in Finder.
  void exploreSelection() {
    final entries = player.playlist.entries;
    revealPaths([
      for (final i in player.playlist.selected)
        if (!entries[i].isUrl) entries[i].location,
    ]);
  }

  /// Reveals the files at [paths] in the file manager.
  void revealPaths(List<String> paths) {
    if (paths.isEmpty) return;
    Future<void> reveal() async {
      if (Platform.isMacOS) {
        await _channel.invokeMethod<void>("revealInFinder", paths);
      } else if (Platform.isWindows) {
        for (final path in paths) {
          await Process.start("explorer.exe", ["/select,", path]);
        }
      } else {
        await revealInLinuxFileManager(paths);
      }
    }

    unawaited(
      reveal().catchError((Object error) {
        Arcane.log(
          "Could not reveal files",
          metadata: {"error": "$error"},
          level: Level.warning,
          module: "FileActions",
        );
      }),
    );
  }

  /// Replaces the playlist with [locations] and plays the first track.
  Future<void> _play(List<String> locations) async {
    if (locations.isEmpty) return;
    player.stop();
    if (await player.playlist.replace(locations)) {
      await player.playIndex(0);
    }
  }

  /// Plays [path] from [at]: where it is playing already, it is only sought.
  Future<void> playAt(String path, Duration at) async {
    final playing = player.playlist.currentEntry?.location == path;
    if (!(playing && (player.playing || player.paused))) await _play([path]);
    player.seekTo(at);
  }

  /// Whether [path] names a skin archive that is installed rather than
  /// played. The suffixes come from [SkinFileType], the same ones the skin
  /// loaders use to discover built-in skins.
  static bool _isSkinPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return SkinFileType.values.any((type) => type.matches(name));
  }

  /// Opens [paths] handed to the app by Finder, the dock or a drop: skins are
  /// installed, everything else is played ([play]) or added to the playlist.
  Future<void> openPaths(List<String> paths, {required bool play}) async {
    final tracks = <String>[];
    for (final path in paths) {
      if (_isSkinPath(path)) {
        await _installSkin(path);
      } else {
        tracks.add(path);
      }
    }
    if (tracks.isEmpty) return;
    if (play) {
      await _play(tracks);
    } else {
      await player.playlist.add(tracks);
    }
  }

  Future<List<String>> openPanel(
    String title, {
    List<FileType> types = const [],
    bool folders = false,
    bool multiple = true,
  }) => dialogs.open(
    title: title,
    allFilesLabel: localizations.allFiles,
    allSupportedTypesLabel: localizations.allSupportedTypes,
    types: types,
    folders: folders,
    multiple: multiple,
    owner: owner(),
  );

  /// Asks for a line of text; null when cancelled or left empty.
  Future<String?> promptText({
    required String title,
    required String message,
    required String value,
    required String confirmLabel,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>("promptText", {
        "title": title,
        "message": message,
        "value": value,
        "confirmLabel": confirmLabel,
        "cancelLabel": localizations.cancel,
      });
      final trimmed = text?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on Object catch (error) {
      Arcane.log(
        "Could not prompt for text",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileActions",
      );
      return null;
    }
  }

  Future<String?> promptUrl(String title) async {
    try {
      final url = await _channel.invokeMethod<String>("promptText", {
        "title": title,
        "message": localizations.enterUrlPrompt,
        "value": "http://",
        "confirmLabel": localizations.openAction,
        "cancelLabel": localizations.cancel,
      });
      final trimmed = url?.trim();
      return trimmed == null || !trimmed.contains("://") ? null : trimmed;
    } on Object catch (error) {
      Arcane.log(
        "Could not prompt for a URL",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileActions",
      );
      return null;
    }
  }

  /// Files dropped on a window, collected for a moment so one drag of many
  /// files is handled as one batch.
  final Map<bool, List<String>> _dropped = {};
  Timer? _dropTimer;

  /// Accepts skins, tracks, playlists and folders dropped onto [window].
  /// Dropping on the main window plays them; anywhere else adds them to the
  /// playlist, as in the original.
  void acceptDrops(AppWindowController window, {required bool playDropped}) {
    FileDrop.enable(
      window,
      extensions: [
        "wsz",
        "wal",
        "zip",
        "tar",
        "tgz",
        "tbz",
        "tbz2",
        "gz",
        "bz2",
        ...openableExtensions,
      ],
      directories: true,
      onDrop: (path) {
        (_dropped[playDropped] ??= []).add(path);
        _dropTimer?.cancel();
        _dropTimer = Timer(const Duration(milliseconds: 100), () {
          final batches = Map.of(_dropped);
          _dropped.clear();
          for (final MapEntry(key: play, value: paths) in batches.entries) {
            unawaited(openPaths(paths, play: play));
          }
        });
      },
    );
  }
}
