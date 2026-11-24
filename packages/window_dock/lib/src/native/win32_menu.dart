import "dart:ffi";
import "dart:ui";

import "package:ffi/ffi.dart";

final DynamicLibrary _user32 = DynamicLibrary.open("user32.dll");

final _createPopupMenu = _user32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      "CreatePopupMenu",
    );
final _appendMenu = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, IntPtr, Pointer<Utf16>),
      int Function(Pointer<Void>, int, int, Pointer<Utf16>)
    >("AppendMenuW");
final _destroyMenu = _user32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      "DestroyMenu",
    );
final _trackPopupMenu = _user32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Uint32,
        Int32,
        Int32,
        Int32,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        int,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )
    >("TrackPopupMenu");
final _getForegroundWindow = _user32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      "GetForegroundWindow",
    );
final _getDpiForSystem = _user32
    .lookupFunction<Uint32 Function(), int Function()>(
      "GetDpiForSystem",
    );

const int _mfString = 0x0000;
const int _mfGrayed = 0x0001;
const int _mfChecked = 0x0008;
const int _mfPopup = 0x0010;
const int _mfSeparator = 0x0800;
const int _tpmReturnCmd = 0x0100;

Pointer<Void> _build(List<Map<String, Object?>> items, Arena arena) {
  final menu = _createPopupMenu();
  for (final item in items) {
    if (item["separator"] == true) {
      _appendMenu(menu, _mfSeparator, 0, nullptr);
      continue;
    }
    var label = item["label"]! as String;
    final shortcut = item["shortcut"] as String?;
    if (shortcut != null) label = "$label\t$shortcut";
    var flags = _mfString;
    if (item["enabled"] == false) flags |= _mfGrayed;
    if (item["checked"] == true || item["mixed"] == true) flags |= _mfChecked;
    final children = item["items"] as List<Map<String, Object?>>?;
    if (children != null) {
      final submenu = _build(children, arena);
      _appendMenu(
        menu,
        flags | _mfPopup,
        submenu.address,
        label.toNativeUtf16(allocator: arena),
      );
    } else {
      _appendMenu(
        menu,
        flags,
        item["id"]! as int,
        label.toNativeUtf16(allocator: arena),
      );
    }
  }
  return menu;
}

/// Shows the menu described by [items] at the global logical [position];
/// returns the chosen id or 0.
int popupMenu(List<Map<String, Object?>> items, Offset position) {
  return using((arena) {
    final menu = _build(items, arena);
    final scale = _getDpiForSystem() / 96.0;
    final chosen = _trackPopupMenu(
      menu,
      _tpmReturnCmd,
      (position.dx * scale).round(),
      (position.dy * scale).round(),
      0,
      _getForegroundWindow(),
      nullptr,
    );
    _destroyMenu(menu);
    return chosen;
  });
}
