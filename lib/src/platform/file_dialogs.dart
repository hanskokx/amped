import "dart:ffi";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:window_dock/window_dock.dart";

import "gtk_file_dialogs.dart";
import "win32_file_dialogs.dart";

/// A kind of file a dialog offers: its label and extensions (lower-case,
/// without the dot; none means every file).
typedef FileType = (String label, List<String> extensions);

/// The native open and save dialogs: the runner's panels on macOS (over
/// [channel]), the common dialogs on Windows, GTK's file chooser on Linux.
class FileDialogs {
  const FileDialogs(this.channel);

  final MethodChannel channel;

  /// Lets the user pick files of [types] (several with [multiple]) or, with
  /// [folders], folders. Returns the picked paths; none when cancelled.
  // TODO(any): Use the `result_monad` package to return a `Result` object so we can more easily test.
  Future<List<String>> open({
    required String title,
    required String allFilesLabel,
    required String allSupportedTypesLabel,
    List<FileType> types = const [],
    bool folders = false,
    bool multiple = true,
    AppWindowController? owner,
  }) async {
    try {
      if (Platform.isWindows) {
        final hwnd = _win32Handle(owner);
        if (folders) {
          final folder = win32PickFolder(owner: hwnd, title: title);
          return folder == null ? const [] : [folder];
        }
        return win32OpenFiles(
          owner: hwnd,
          title: title,
          types: _withAllFiles(
            types,
            allFilesLabel: allFilesLabel,
            allSupportedTypesLabel: allSupportedTypesLabel,
          ),
          multiple: multiple,
        );
      }
      if (Platform.isLinux) {
        return gtkOpen(
          parent: _gtkHandle(owner),
          title: title,
          types: _withAllFiles(
            types,
            allFilesLabel: allFilesLabel,
            allSupportedTypesLabel: allSupportedTypesLabel,
          ),
          multiple: multiple,
          folders: folders,
        );
      }
      final paths = await channel.invokeListMethod<String>("openPanel", {
        "title": title,
        "extensions": [for (final type in types) ...type.$2],
        "files": !folders,
        "directories": folders,
        "multiple": multiple,
      });
      return paths ?? const [];
    } on Object catch (error) {
      Arcane.log(
        "Could not show the open dialog",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileDialogs",
      );
      return const [];
    }
  }

  /// Asks where to save, suggesting [name] and offering [types] to save as,
  /// starting with the one at [typeIndex]. Returns the path and the chosen
  /// type's index, or `null` when cancelled. A path that ends in none of
  /// the types' extensions gets the chosen type's; one that names another
  /// type is kept, as the original then saves in that type.
  // TODO(any): Use the `result_monad` package to return a `Result` object so we can more easily test.
  Future<(String, int)?> save({
    required String title,
    required String formatLabel,
    required String name,
    required List<FileType> types,
    int typeIndex = 0,
    AppWindowController? owner,
  }) async {
    try {
      (String, int)? result;
      if (Platform.isWindows) {
        result = win32SaveFile(
          owner: _win32Handle(owner),
          title: title,
          name: name,
          types: types,
          typeIndex: typeIndex,
        );
      } else if (Platform.isLinux) {
        result = gtkSave(
          parent: _gtkHandle(owner),
          title: title,
          name: name,
          types: types,
          typeIndex: typeIndex,
        );
      } else {
        final reply = await channel.invokeMethod<Object?>("savePanel", {
          "title": title,
          "formatLabel": formatLabel,
          "name": name,
          "extensions": [for (final type in types) ...type.$2],
          "formats": [
            for (final (label, extensions) in types) [label, extensions.first],
          ],
          "format": typeIndex,
        });
        if (reply is Map && reply["path"] is String) {
          result = (reply["path"] as String, reply["format"] as int);
        }
      }
      if (result == null) return null;
      final (path, index) = result;
      return (withExtension(path, types[index].$2, types), index);
    } on Object catch (error) {
      Arcane.log(
        "Could not show the save dialog",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileDialogs",
      );
      return null;
    }
  }

  /// [path], given the first of [extensions] when it ends in none of them
  /// (nor in one of the other [types]).
  @visibleForTesting
  static String withExtension(
    String path,
    List<String> extensions, [
    List<FileType> types = const [],
  ]) {
    if (extensions.isEmpty) return path;
    final name = path.split(RegExp(r"[/\\]")).last;
    final dot = name.lastIndexOf(".");
    final extension = dot < 0 ? "" : name.substring(dot + 1).toLowerCase();
    final known = {...extensions, for (final type in types) ...type.$2};
    return known.contains(extension) ? path : "$path.${extensions.first}";
  }

  /// [types] as one "all supported" entry (when there are several) and an
  /// "All files" entry, as the original's open dialogs list them.
  static List<FileType> _withAllFiles(
    List<FileType> types, {
    required String allFilesLabel,
    required String allSupportedTypesLabel,
  }) {
    if (types.isEmpty) return [(allFilesLabel, [])];
    final all = [for (final type in types) ...type.$2];
    return [
      if (types.length > 1) (allSupportedTypesLabel, all),
      ...types,
      (allFilesLabel, const []),
    ];
  }

  static Pointer<Void> _win32Handle(AppWindowController? owner) =>
      switch (owner?.platformHandle) {
        Win32WindowHandle(:final windowHandle) => windowHandle,
        _ => nullptr,
      };

  static Pointer<Void> _gtkHandle(AppWindowController? owner) =>
      switch (owner?.platformHandle) {
        LinuxWindowHandle(:final windowHandle) => windowHandle,
        _ => nullptr,
      };
}
