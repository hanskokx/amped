import "dart:ffi";

import "package:ffi/ffi.dart";

// Drops of `text/uri-list` (from file managers) through GTK 3's drag and
// drop. GTK is already loaded by the Flutter Linux embedder, so the symbols
// resolve from the process. Signal handlers run synchronously on the main
// thread, which is also Dart's.

final class _GtkTargetEntry extends Struct {
  external Pointer<Utf8> target;

  @Uint32()
  external int flags;

  @Uint32()
  external int info;
}

typedef _DragDataReceivedNative =
    Void Function(
      Pointer<Void> widget,
      Pointer<Void> context,
      Int32 x,
      Int32 y,
      Pointer<Void> selection,
      Uint32 info,
      Uint32 time,
      Pointer<Void> userData,
    );

const int _gtkDestDefaultAll = 0x07;
const int _gdkActionCopy = 1 << 1;

@Native<
  Void Function(Pointer<Void>, Int32, Pointer<_GtkTargetEntry>, Int32, Int32)
>(
  symbol: "gtk_drag_dest_set",
)
external void _dragDestSet(
  Pointer<Void> widget,
  int flags,
  Pointer<_GtkTargetEntry> targets,
  int count,
  int actions,
);

@Native<
  UnsignedLong Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_DragDataReceivedNative>>,
    Pointer<Void>,
    Pointer<Void>,
    Int32,
  )
>(symbol: "g_signal_connect_data")
external int _signalConnect(
  Pointer<Void> instance,
  Pointer<Utf8> signal,
  Pointer<NativeFunction<_DragDataReceivedNative>> handler,
  Pointer<Void> data,
  Pointer<Void> destroyData,
  int flags,
);

@Native<Pointer<Pointer<Utf8>> Function(Pointer<Void>)>(
  symbol: "gtk_selection_data_get_uris",
)
external Pointer<Pointer<Utf8>> _getUris(Pointer<Void> selection);

@Native<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Void>, Pointer<Void>)>(
  symbol: "g_filename_from_uri",
)
external Pointer<Utf8> _filenameFromUri(
  Pointer<Utf8> uri,
  Pointer<Void> hostname,
  Pointer<Void> error,
);

@Native<Void Function(Pointer<Void>)>(symbol: "g_free")
external void _gFree(Pointer<Void> memory);

@Native<Void Function(Pointer<Pointer<Utf8>>)>(symbol: "g_strfreev")
external void _gStrfreev(Pointer<Pointer<Utf8>> strings);

/// The drop handlers by widget address.
final Map<int, void Function(List<String>)> _handlers = {};

final NativeCallable<_DragDataReceivedNative> _onReceived =
    NativeCallable<_DragDataReceivedNative>.isolateLocal(_received);

/// The target list, kept for the life of the process.
final Pointer<_GtkTargetEntry> _targets = () {
  final entry = calloc<_GtkTargetEntry>();
  entry.ref
    ..target = "text/uri-list".toNativeUtf8()
    ..flags = 0
    ..info = 0;
  return entry;
}();

void _received(
  Pointer<Void> widget,
  Pointer<Void> context,
  int x,
  int y,
  Pointer<Void> selection,
  int info,
  int time,
  Pointer<Void> userData,
) {
  final uris = _getUris(selection);
  if (uris == nullptr) return;
  final paths = <String>[];
  for (var i = 0; uris[i] != nullptr; i++) {
    final name = _filenameFromUri(uris[i], nullptr, nullptr);
    if (name == nullptr) continue;
    paths.add(name.toDartString());
    _gFree(name.cast());
  }
  _gStrfreev(uris);
  _handlers[widget.address]?.call(paths);
}

/// Accepts files dropped on [widget], calling [onDrop] with their paths.
void gtkEnableFileDrop(
  Pointer<Void> widget,
  void Function(List<String>) onDrop,
) {
  final first = !_handlers.containsKey(widget.address);
  _handlers[widget.address] = onDrop;
  if (!first) return;
  _dragDestSet(widget, _gtkDestDefaultAll, _targets, 1, _gdkActionCopy);
  using((arena) {
    _signalConnect(
      widget,
      "drag-data-received".toNativeUtf8(allocator: arena),
      _onReceived.nativeFunction,
      nullptr,
      nullptr,
      0,
    );
  });
}
