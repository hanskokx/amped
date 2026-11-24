import "dart:ffi";

import "package:ffi/ffi.dart";

// GTK's native file chooser (which goes through the desktop portal where
// there is one). GTK 3 is already loaded by the Flutter Linux embedder, so
// the symbols resolve from the process.

final class _GSList extends Struct {
  external Pointer<Void> data;

  external Pointer<_GSList> next;
}

const int _actionOpen = 0;
const int _actionSave = 1;
const int _actionSelectFolder = 2;
const int _responseAccept = -3;

@Native<
  Pointer<Void> Function(
    Pointer<Utf8>,
    Pointer<Void>,
    Int32,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
>(symbol: "gtk_file_chooser_native_new")
external Pointer<Void> _nativeNew(
  Pointer<Utf8> title,
  Pointer<Void> parent,
  int action,
  Pointer<Utf8> acceptLabel,
  Pointer<Utf8> cancelLabel,
);

@Native<Int32 Function(Pointer<Void>)>(symbol: "gtk_native_dialog_run")
external int _run(Pointer<Void> dialog);

@Native<Void Function(Pointer<Void>)>(symbol: "g_object_unref")
external void _unref(Pointer<Void> object);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_file_chooser_set_select_multiple",
)
external void _setSelectMultiple(Pointer<Void> chooser, int multiple);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_file_chooser_set_do_overwrite_confirmation",
)
external void _setOverwriteConfirmation(Pointer<Void> chooser, int confirm);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: "gtk_file_chooser_set_current_name",
)
external void _setCurrentName(Pointer<Void> chooser, Pointer<Utf8> name);

@Native<Pointer<_GSList> Function(Pointer<Void>)>(
  symbol: "gtk_file_chooser_get_filenames",
)
external Pointer<_GSList> _getFilenames(Pointer<Void> chooser);

@Native<Pointer<Void> Function()>(symbol: "gtk_file_filter_new")
external Pointer<Void> _filterNew();

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: "gtk_file_filter_set_name",
)
external void _filterSetName(Pointer<Void> filter, Pointer<Utf8> name);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: "gtk_file_filter_add_pattern",
)
external void _filterAddPattern(Pointer<Void> filter, Pointer<Utf8> pattern);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_file_chooser_add_filter",
)
external void _addFilter(Pointer<Void> chooser, Pointer<Void> filter);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_file_chooser_set_filter",
)
external void _setFilter(Pointer<Void> chooser, Pointer<Void> filter);

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gtk_file_chooser_get_filter",
)
external Pointer<Void> _getFilter(Pointer<Void> chooser);

@Native<Void Function(Pointer<Void>)>(symbol: "g_free")
external void _gFree(Pointer<Void> memory);

@Native<Void Function(Pointer<_GSList>)>(symbol: "g_slist_free")
external void _gSlistFree(Pointer<_GSList> list);

/// Adds a filter per `(label, [extensions])` type to [chooser] and returns
/// them in order. Patterns match either case, as on Windows.
List<Pointer<Void>> _addFilters(
  Pointer<Void> chooser,
  List<(String, List<String>)> types,
  Allocator allocator,
) => [
  for (final (label, extensions) in types)
    () {
      final filter = _filterNew();
      _filterSetName(filter, label.toNativeUtf8(allocator: allocator));
      if (extensions.isEmpty) {
        _filterAddPattern(filter, "*".toNativeUtf8(allocator: allocator));
      }
      for (final extension in extensions) {
        final pattern = StringBuffer("*.");
        for (final char in extension.split("")) {
          final lower = char.toLowerCase();
          final upper = char.toUpperCase();
          pattern.write(lower == upper ? char : "[$lower$upper]");
        }
        _filterAddPattern(
          filter,
          pattern.toString().toNativeUtf8(allocator: allocator),
        );
      }
      _addFilter(chooser, filter);
      return filter;
    }(),
];

/// Runs [dialog] and returns the chosen filenames (none when cancelled).
List<String> _runForFilenames(Pointer<Void> dialog) {
  if (_run(dialog) != _responseAccept) return const [];
  final paths = <String>[];
  final list = _getFilenames(dialog);
  for (var node = list; node != nullptr; node = node.ref.next) {
    paths.add(node.ref.data.cast<Utf8>().toDartString());
    _gFree(node.ref.data);
  }
  _gSlistFree(list);
  return paths;
}

/// Picks files (several with [multiple]) or, with [folders], folders.
List<String> gtkOpen({
  required Pointer<Void> parent,
  required String title,
  required List<(String, List<String>)> types,
  required bool multiple,
  required bool folders,
}) => using((arena) {
  final dialog = _nativeNew(
    title.toNativeUtf8(allocator: arena),
    parent,
    folders ? _actionSelectFolder : _actionOpen,
    nullptr,
    nullptr,
  );
  _setSelectMultiple(dialog, multiple ? 1 : 0);
  if (!folders) _addFilters(dialog, types, arena);
  final paths = _runForFilenames(dialog);
  _unref(dialog);
  return paths;
});

/// Asks where to save, offering [types] (starting at [typeIndex]). Returns
/// the path and the chosen type's index; `null` when cancelled.
(String, int)? gtkSave({
  required Pointer<Void> parent,
  required String title,
  required String name,
  required List<(String, List<String>)> types,
  required int typeIndex,
}) => using((arena) {
  final dialog = _nativeNew(
    title.toNativeUtf8(allocator: arena),
    parent,
    _actionSave,
    nullptr,
    nullptr,
  );
  _setOverwriteConfirmation(dialog, 1);
  _setCurrentName(dialog, name.toNativeUtf8(allocator: arena));
  final filters = _addFilters(dialog, types, arena);
  if (typeIndex >= 0 && typeIndex < filters.length) {
    _setFilter(dialog, filters[typeIndex]);
  }
  final paths = _runForFilenames(dialog);
  final chosen = filters.indexOf(_getFilter(dialog));
  _unref(dialog);
  if (paths.isEmpty) return null;
  final index = chosen < 0 ? typeIndex.clamp(0, types.length - 1) : chosen;
  return (paths.first, index);
});
