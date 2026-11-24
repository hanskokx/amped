import "dart:convert";
import "dart:io";
import "dart:ui";

import "package:amped_logging/amped_logging.dart";
import "package:ffi/ffi.dart";
import "package:flutter/foundation.dart";

import "native/gtk_menu.dart" as gtk;
import "native/macos_bindings.dart" as mac;
import "native/win32_menu.dart" as win32;

/// An entry in a [NativeMenu].
@immutable
class NativeMenuItem {
  const NativeMenuItem({
    required this.label,
    this.onSelected,
    this.checked = false,
    this.mixed = false,
    this.checkable = false,
    this.enabled = true,
    this.shortcut,
    this.children = const [],
  }) : separator = false;

  const NativeMenuItem.separator()
    : label = "",
      onSelected = null,
      checked = false,
      mixed = false,
      checkable = false,
      enabled = false,
      shortcut = null,
      children = const [],
      separator = true;

  final String label;
  final VoidCallback? onSelected;
  final bool checked;

  /// Shown as "-" where the platform has a mixed state (macOS, GTK), for an
  /// option that holds for some of what it covers; as checked elsewhere.
  /// Ignored when [checked].
  final bool mixed;
  final bool checkable;
  final bool enabled;
  final bool separator;

  /// Accelerator text shown at the right edge (display only).
  final String? shortcut;

  /// Submenu entries; an item with children opens a submenu.
  final List<NativeMenuItem> children;
}

/// Native popup menus (NSMenu on macOS, `TrackPopupMenu` on Windows).
///
/// [show] blocks until the menu closes, like the Win32 menus the classic player
/// used, then runs the chosen item's callback.
abstract final class NativeMenu {
  /// Whether native popup menus are available on this platform.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Shows [items] with the menu's top-left corner at the global
  /// [position]. Returns whether an item was chosen. [opacity] (0 to 1) makes
  /// the menu see-through where the platform allows it (macOS).
  static bool show(
    List<NativeMenuItem> items,
    Offset position, {
    double opacity = 1,
  }) {
    final callbacks = <int, VoidCallback>{};
    _lastId = 0;
    final spec = _encode(items, callbacks);
    final int chosen;
    if (Platform.isMacOS) {
      chosen = using((arena) {
        final json = jsonEncode(spec).toNativeUtf8(allocator: arena);
        return mac.wdPopupMenu(
          json,
          position.dx,
          position.dy,
          opacity.clamp(0.0, 1.0),
        );
      });
    } else if (Platform.isWindows) {
      chosen = win32.popupMenu(spec, position);
    } else if (Platform.isLinux) {
      chosen = gtk.popupMenu(spec, position);
    } else {
      Arcane.log(
        "NativeMenu is not supported on this platform",
        level: Level.warning,
        module: "NativeMenu",
        metadata: {"platform": Platform.operatingSystem},
      );
      return false;
    }
    final callback = callbacks[chosen];
    if (callback == null) return false;
    callback();
    return true;
  }

  static int _lastId = 0;

  static List<Map<String, Object?>> _encode(
    List<NativeMenuItem> items,
    Map<int, VoidCallback> callbacks,
  ) {
    return [
      for (final item in items)
        if (item.separator)
          {"separator": true}
        else
          {
            "label": item.label,
            "checked": item.checked,
            if (item.mixed && !item.checked) "mixed": true,
            "enabled":
                item.enabled &&
                (item.onSelected != null || item.children.isNotEmpty),
            if (item.shortcut != null) "shortcut": item.shortcut,
            if (item.children.isNotEmpty)
              "items": _encode(item.children, callbacks)
            else
              "id": () {
                final id = ++_lastId;
                if (item.onSelected != null) callbacks[id] = item.onSelected!;
                return id;
              }(),
          },
    ];
  }
}
