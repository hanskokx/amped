import "dart:async";
import "dart:collection";

import "package:amped_update_checker/amped_update_checker.dart";
import "package:flutter/widgets.dart"
    show ImageConfiguration, ImageProvider, ImageStream, ImageStreamListener;
import "package:url_launcher/url_launcher.dart";

import "../player/player_state.dart";
import "../remote/remote_credentials.dart";
import "amped_dialog.dart";
import "dialog_manager.dart";

/// What the File Info, Edit Metadata and network sign-in dialogs are asked
/// to show, and how they are answered.
class DialogRequests {
  DialogRequests({required this.player, required this._dialogs});

  final PlayerState player;
  final DialogManager _dialogs;

  /// The File Info dialog's window was closed from its title bar: a Cancel.
  void fileInfoDismissed() {
    _fileInfoQueue.clear();
    fileInfoPath = null;
  }

  /// The file the File Info dialog shows.
  String? fileInfoPath;

  /// The files whose File Info dialog comes up after the one showing.
  final Queue<String> _fileInfoQueue = Queue();

  /// Opens the File Info dialog on each of [paths] in turn, the next when
  /// one is closed with OK, and none more after Cancel (the playlist's
  /// `ID_PE_ID3` loop in Pledit.cpp). URLs are skipped.
  void showFileInfo(Iterable<String> paths) {
    _fileInfoQueue
      ..clear()
      ..addAll(paths.where((path) => !path.contains("://")));
    _nextFileInfo();
  }

  /// Playlist > View file info... (Alt+3 in the playlist): the selected
  /// entries.
  void showSelectedFileInfo() {
    final playlist = player.playlist;
    final entries = playlist.entries;
    showFileInfo([
      for (final i in playlist.selected.toList()..sort())
        if (i < entries.length) entries[i].location,
    ]);
  }

  /// Alt+3 in the main window (`EDIT_ID3`): the current file.
  void showCurrentFileInfo() {
    final entry = player.playlist.currentEntry;
    if (entry != null) showFileInfo([entry.location]);
  }

  void _nextFileInfo() {
    if (_fileInfoQueue.isEmpty) {
      fileInfoPath = null;
      if (_dialogs.windows.containsKey(AmpedDialog.fileInfo)) {
        _dialogs.close(AmpedDialog.fileInfo);
      }
      return;
    }
    fileInfoPath = _fileInfoQueue.removeFirst();
    _dialogs.open(AmpedDialog.fileInfo);
  }

  /// The File Info dialog's OK (after saving) or Cancel.
  void closeFileInfo({required bool ok}) {
    if (!ok) _fileInfoQueue.clear();
    _nextFileInfo();
  }

  /// What the network share sign-in dialog asks, while it is open.
  RemoteLoginRequest? remoteLoginRequest;
  Completer<RemoteLogin?>? _remoteLoginAnswer;

  /// Asks for the name and password of a network share in a dialog; null
  /// when it is cancelled.
  Future<RemoteLogin?> promptRemoteLogin(RemoteLoginRequest request) {
    final answer = _remoteLoginAnswer;
    if (answer != null && !answer.isCompleted) answer.complete(null);
    final next = _remoteLoginAnswer = Completer<RemoteLogin?>();
    remoteLoginRequest = request;
    if (_dialogs.windows.containsKey(AmpedDialog.remoteLogin)) {
      _dialogs.close(AmpedDialog.remoteLogin);
    }
    _dialogs.open(AmpedDialog.remoteLogin);
    return next.future;
  }

  /// The sign-in dialog was answered ([login]) or cancelled (null).
  void answerRemoteLogin(RemoteLogin? login) {
    final answer = _remoteLoginAnswer;
    if (answer != null && !answer.isCompleted) answer.complete(login);
    if (_dialogs.windows.containsKey(AmpedDialog.remoteLogin)) {
      _dialogs.close(AmpedDialog.remoteLogin);
    }
  }

  /// The picture the artwork window shows and what it is titled.
  ({String title, ImageProvider image})? artwork;

  /// Shows [image] in the artwork window, opening it, or putting it in the
  /// one that is open. The Album Art window is not touched.
  void showArtwork(String title, ImageProvider image) {
    artwork = (title: title, image: image);
    _dialogs.open(AmpedDialog.artwork);
    // The window takes the picture's shape once its size is known.
    _artworkStream?.removeListener(_artworkListener!);
    final stream = _artworkStream = image.resolve(ImageConfiguration.empty);
    final listener = _artworkListener = ImageStreamListener(
      (info, _) {
        if (!identical(artwork?.image, image)) return;
        _dialogs.keepShape(
          AmpedDialog.artwork,
          info.image.width / info.image.height,
        );
      },
      onError: (error, stackTrace) {},
    );
    stream.addListener(listener);
  }

  ImageStream? _artworkStream;
  ImageStreamListener? _artworkListener;

  /// What the resume dialog asks, while it is open.
  ({String title, Duration position})? resumeRequest;
  Completer<bool>? _resumeAnswer;

  /// Asks whether to continue the episode [title] at [position]; false when
  /// it should start over, which is also what closing the window means.
  Future<bool> promptResume(String title, Duration position) {
    final answer = _resumeAnswer;
    if (answer != null && !answer.isCompleted) answer.complete(false);
    final next = _resumeAnswer = Completer<bool>();
    resumeRequest = (title: title, position: position);
    if (_dialogs.windows.containsKey(AmpedDialog.resume)) {
      _dialogs.close(AmpedDialog.resume);
    }
    _dialogs.open(AmpedDialog.resume);
    return next.future;
  }

  /// The resume dialog was answered: [resume] or start over.
  void answerResume({required bool resume}) {
    final answer = _resumeAnswer;
    if (answer != null && !answer.isCompleted) answer.complete(resume);
    if (_dialogs.windows.containsKey(AmpedDialog.resume)) {
      _dialogs.close(AmpedDialog.resume);
    }
  }

  /// The release the update dialog announces.
  UpdateInfo? update;

  /// Opens the update dialog on [release], or puts it in the open one.
  void showUpdate(UpdateInfo release) {
    update = release;
    if (_dialogs.windows.containsKey(AmpedDialog.update)) {
      _dialogs.close(AmpedDialog.update);
    }
    _dialogs.open(AmpedDialog.update);
  }

  /// The update dialog was answered: [download] opens the downloads, else
  /// it is ignored.
  void answerUpdate({required bool download}) {
    final release = update;
    if (download && release != null) {
      unawaited(launchUrl(release.downloadUrl ?? latestReleaseUrl));
    }
    if (_dialogs.windows.containsKey(AmpedDialog.update)) {
      _dialogs.close(AmpedDialog.update);
    }
  }

  /// Where the latest release can be downloaded, when the release.json
  /// has no address of its own.
  static final Uri latestReleaseUrl = Uri.parse(
    "https://github.com/hanskokx/amped/releases/latest",
  );

  /// The files the Edit Item Metadata dialog edits.
  List<String> editMetadataPaths = const [];

  /// Playlist > Edit metadata for selection... (Shift+E,
  /// `ID_PE_EDIT_SEL`): edits the selected files' tags together. URLs are
  /// left out.
  void showEditMetadata() {
    final playlist = player.playlist;
    final entries = playlist.entries;
    showEditMetadataFor([
      for (final i in playlist.selected.toList()..sort())
        if (i < entries.length && !entries[i].isUrl) entries[i].location,
    ]);
  }

  /// Opens the Edit Item Metadata dialog on the files at [paths].
  void showEditMetadataFor(List<String> paths) {
    if (paths.isEmpty) return;
    // A new selection replaces what an open dialog is editing.
    if (_dialogs.windows.containsKey(AmpedDialog.editMetadata)) {
      _dialogs.close(AmpedDialog.editMetadata);
    }
    editMetadataPaths = paths;
    _dialogs.open(AmpedDialog.editMetadata);
  }
}
