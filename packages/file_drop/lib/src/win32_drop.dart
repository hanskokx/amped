import "dart:ffi";

import "package:ffi/ffi.dart";

// Explorer drops through WM_DROPFILES (DragAcceptFiles), as the original
// The classic player receives them. The window is subclassed to see the message; the
// subclass procedure runs synchronously on the platform thread, which is
// also Dart's.

final DynamicLibrary _shell32 = DynamicLibrary.open("shell32.dll");
final DynamicLibrary _comctl32 = DynamicLibrary.open("comctl32.dll");

typedef _SubclassProcNative =
    IntPtr Function(
      Pointer<Void> hwnd,
      Uint32 message,
      UintPtr wParam,
      IntPtr lParam,
      UintPtr id,
      UintPtr refData,
    );

final void Function(Pointer<Void>, int) _dragAcceptFiles = _shell32
    .lookupFunction<
      Void Function(Pointer<Void>, Int32),
      void Function(Pointer<Void>, int)
    >("DragAcceptFiles");

final int Function(Pointer<Void>, int, Pointer<Utf16>, int) _dragQueryFile =
    _shell32.lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32, Pointer<Utf16>, Uint32),
      int Function(Pointer<Void>, int, Pointer<Utf16>, int)
    >("DragQueryFileW");

final void Function(Pointer<Void>) _dragFinish = _shell32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      "DragFinish",
    );

final int Function(
  Pointer<Void>,
  Pointer<NativeFunction<_SubclassProcNative>>,
  int,
  int,
)
_setWindowSubclass = _comctl32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<NativeFunction<_SubclassProcNative>>,
        UintPtr,
        UintPtr,
      ),
      int Function(
        Pointer<Void>,
        Pointer<NativeFunction<_SubclassProcNative>>,
        int,
        int,
      )
    >("SetWindowSubclass");

final int Function(Pointer<Void>, int, int, int) _defSubclassProc = _comctl32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Uint32, UintPtr, IntPtr),
      int Function(Pointer<Void>, int, int, int)
    >("DefSubclassProc");

const int _wmDropFiles = 0x0233;
const int _subclassId = 0x46445250; // "FDRP"

/// The drop handlers by window handle address.
final Map<int, void Function(List<String>)> _handlers = {};

final NativeCallable<_SubclassProcNative> _proc =
    NativeCallable<_SubclassProcNative>.isolateLocal(
      _subclassProc,
      exceptionalReturn: 0,
    );

int _subclassProc(
  Pointer<Void> hwnd,
  int message,
  int wParam,
  int lParam,
  int id,
  int refData,
) {
  if (message != _wmDropFiles) {
    return _defSubclassProc(hwnd, message, wParam, lParam);
  }
  final drop = Pointer<Void>.fromAddress(wParam);
  final paths = <String>[];
  using((arena) {
    final count = _dragQueryFile(drop, 0xFFFFFFFF, nullptr, 0);
    for (var i = 0; i < count; i++) {
      final length = _dragQueryFile(drop, i, nullptr, 0);
      final buffer = arena<Uint16>(length + 1).cast<Utf16>();
      _dragQueryFile(drop, i, buffer, length + 1);
      paths.add(buffer.toDartString());
    }
  });
  _dragFinish(drop);
  _handlers[hwnd.address]?.call(paths);
  return 0;
}

/// Accepts files dropped on [hwnd], calling [onDrop] with their paths.
void win32EnableFileDrop(
  Pointer<Void> hwnd,
  void Function(List<String>) onDrop,
) {
  final first = !_handlers.containsKey(hwnd.address);
  _handlers[hwnd.address] = onDrop;
  if (!first) return;
  _setWindowSubclass(hwnd, _proc.nativeFunction, _subclassId, 0);
  _dragAcceptFiles(hwnd, 1);
}
