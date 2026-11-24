import "dart:ffi";
import "dart:ui";

import "package:ffi/ffi.dart";

// GTK 3 is already loaded by the Flutter Linux embedder, so the symbols
// resolve from the process.

final class _GdkRectangle extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;

  @Int32()
  external int width;

  @Int32()
  external int height;
}

final class _GList extends Struct {
  external Pointer<Void> data;
  external Pointer<_GList> next;
  external Pointer<_GList> prev;
}

typedef _Callback = Void Function(Pointer<Void>, Pointer<Void>);

@Native<Pointer<Void> Function()>(symbol: "gtk_menu_new")
external Pointer<Void> _gtkMenuNew();

@Native<Pointer<Void> Function()>(symbol: "gtk_menu_item_new")
external Pointer<Void> _gtkMenuItemNew();

@Native<Pointer<Void> Function()>(symbol: "gtk_check_menu_item_new")
external Pointer<Void> _gtkCheckMenuItemNew();

@Native<Pointer<Void> Function()>(symbol: "gtk_separator_menu_item_new")
external Pointer<Void> _gtkSeparatorMenuItemNew();

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_check_menu_item_set_active",
)
external void _gtkCheckMenuItemSetActive(Pointer<Void> item, int active);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_check_menu_item_set_inconsistent",
)
external void _gtkCheckMenuItemSetInconsistent(
  Pointer<Void> item,
  int inconsistent,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_menu_item_set_submenu",
)
external void _gtkMenuItemSetSubmenu(Pointer<Void> item, Pointer<Void> menu);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_menu_shell_append",
)
external void _gtkMenuShellAppend(Pointer<Void> shell, Pointer<Void> child);

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "gtk_widget_set_sensitive")
external void _gtkWidgetSetSensitive(Pointer<Void> widget, int sensitive);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_widget_show_all")
external void _gtkWidgetShowAll(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_widget_destroy")
external void _gtkWidgetDestroy(Pointer<Void> widget);

@Native<Pointer<Void> Function(Pointer<Utf8>)>(symbol: "gtk_label_new")
external Pointer<Void> _gtkLabelNew(Pointer<Utf8> text);

@Native<Void Function(Pointer<Void>, Float)>(symbol: "gtk_label_set_xalign")
external void _gtkLabelSetXAlign(Pointer<Void> label, double xalign);

@Native<Pointer<Void> Function(Int32, Int32)>(symbol: "gtk_box_new")
external Pointer<Void> _gtkBoxNew(int orientation, int spacing);

@Native<Void Function(Pointer<Void>, Pointer<Void>, Int32, Int32, Uint32)>(
  symbol: "gtk_box_pack_start",
)
external void _gtkBoxPackStart(
  Pointer<Void> box,
  Pointer<Void> child,
  int expand,
  int fill,
  int padding,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_container_add",
)
external void _gtkContainerAdd(Pointer<Void> container, Pointer<Void> child);

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gtk_widget_get_style_context",
)
external Pointer<Void> _gtkWidgetGetStyleContext(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(
  symbol: "gtk_style_context_add_class",
)
external void _gtkStyleContextAddClass(
  Pointer<Void> context,
  Pointer<Utf8> name,
);

@Native<Pointer<_GList> Function()>(symbol: "gtk_window_list_toplevels")
external Pointer<_GList> _gtkWindowListToplevels();

@Native<Void Function(Pointer<_GList>)>(symbol: "g_list_free")
external void _gListFree(Pointer<_GList> list);

@Native<Int32 Function(Pointer<Void>)>(symbol: "gtk_window_is_active")
external int _gtkWindowIsActive(Pointer<Void> window);

@Native<Int32 Function(Pointer<Void>)>(symbol: "gtk_widget_get_visible")
external int _gtkWidgetGetVisible(Pointer<Void> widget);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gtk_widget_get_window")
external Pointer<Void> _gtkWidgetGetWindow(Pointer<Void> widget);

@Native<Int32 Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>)>(
  symbol: "gdk_window_get_origin",
)
external int _gdkWindowGetOrigin(
  Pointer<Void> window,
  Pointer<Int32> x,
  Pointer<Int32> y,
);

@Native<Pointer<Uint8> Function(Int32)>(symbol: "gdk_event_new")
external Pointer<Uint8> _gdkEventNew(int type);

@Native<Void Function(Pointer<Uint8>)>(symbol: "gdk_event_free")
external void _gdkEventFree(Pointer<Uint8> event);

@Native<
  Void Function(Pointer<Void>, Pointer<Void>, Pointer<Double>, Pointer<Uint32>)
>(
  symbol: "gdk_device_get_state",
)
external void _gdkDeviceGetState(
  Pointer<Void> device,
  Pointer<Void> window,
  Pointer<Double> axes,
  Pointer<Uint32> mask,
);

@Native<Int64 Function()>(symbol: "g_get_monotonic_time")
external int _gGetMonotonicTime();

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "g_object_ref")
external Pointer<Void> _gObjectRef(Pointer<Void> object);

@Native<Pointer<Void> Function()>(symbol: "gdk_display_get_default")
external Pointer<Void> _gdkDisplayGetDefault();

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gdk_display_get_default_seat",
)
external Pointer<Void> _gdkDisplayGetDefaultSeat(Pointer<Void> display);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gdk_seat_get_pointer")
external Pointer<Void> _gdkSeatGetPointer(Pointer<Void> seat);

@Native<Pointer<Void> Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>)>(
  symbol: "gdk_device_get_window_at_position",
)
external Pointer<Void> _gdkDeviceGetWindowAtPosition(
  Pointer<Void> device,
  Pointer<Int32> winX,
  Pointer<Int32> winY,
);

/// A button press for GTK to anchor the popup to: Wayland only places popups
/// against an input event. Fields follow the 64-bit GdkEventButton layout.
Pointer<Uint8> _triggerEvent(Pointer<Void> gdkWindow) {
  final event = _gdkEventNew(4); // GDK_BUTTON_PRESS
  final seat = _gdkDisplayGetDefaultSeat(_gdkDisplayGetDefault());
  final at = event.cast<Uint64>();
  at[1] = _gObjectRef(gdkWindow).address; // window
  (event + 16).cast<Int8>().value = 1; // send_event
  // GTK ignores a button release this soon after the popup's trigger time, so
  // the click that opened the menu doesn't close it again. Input events are
  // stamped in milliseconds on the monotonic clock.
  (event + 20).cast<Uint32>().value = _gGetMonotonicTime() ~/ 1000; // time
  final pointer = _gdkSeatGetPointer(seat);
  // The button that's down, so GTK matches its release to this press: a
  // menu-bar click is the left button, a context menu the right one.
  final mask = calloc<Uint32>();
  _gdkDeviceGetState(pointer, gdkWindow, nullptr, mask);
  final button = switch (mask.value) {
    final m when m & (1 << 10) != 0 => 3,
    final m when m & (1 << 9) != 0 => 2,
    _ => 1,
  };
  calloc.free(mask);
  (event + 48).cast<Uint32>().value = 0; // state
  (event + 52).cast<Uint32>().value = button;
  at[7] = pointer.address; // device
  return event;
}

@Native<
  Void Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<_GdkRectangle>,
    Int32,
    Int32,
    Pointer<Void>,
  )
>(symbol: "gtk_menu_popup_at_rect")
external void _gtkMenuPopupAtRect(
  Pointer<Void> menu,
  Pointer<Void> rectWindow,
  Pointer<_GdkRectangle> rect,
  int rectAnchor,
  int menuAnchor,
  Pointer<Void> triggerEvent,
);

@Native<
  Uint64 Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_Callback>>,
    Pointer<Void>,
    Pointer<Void>,
    Int32,
  )
>(symbol: "g_signal_connect_data")
external int _gSignalConnectData(
  Pointer<Void> instance,
  Pointer<Utf8> signal,
  Pointer<NativeFunction<_Callback>> handler,
  Pointer<Void> data,
  Pointer<Void> destroyData,
  int flags,
);

@Native<Int32 Function(Pointer<Void>, Int32)>(
  symbol: "g_main_context_iteration",
)
external int _gMainContextIteration(Pointer<Void> context, int mayBlock);

const int _gdkGravityNorthWest = 1;
const int _gtkOrientationHorizontal = 0;

/// The window the menu is positioned against: the active one, else any
/// visible one.
Pointer<Void> _anchorWindow() {
  final list = _gtkWindowListToplevels();
  Pointer<Void> active = nullptr;
  Pointer<Void> visible = nullptr;
  for (var node = list; node != nullptr; node = node.ref.next) {
    final window = node.ref.data;
    if (_gtkWidgetGetVisible(window) == 0) continue;
    if (visible == nullptr) visible = window;
    if (_gtkWindowIsActive(window) != 0) {
      active = window;
      break;
    }
  }
  _gListFree(list);
  return active != nullptr ? active : visible;
}

Pointer<Void> _label(String text, Arena arena, {bool dim = false}) {
  final label = _gtkLabelNew(text.toNativeUtf8(allocator: arena));
  _gtkLabelSetXAlign(label, 0);
  if (dim) {
    _gtkStyleContextAddClass(
      _gtkWidgetGetStyleContext(label),
      "dim-label".toNativeUtf8(allocator: arena),
    );
  }
  return label;
}

Pointer<Void> _build(
  List<Map<String, Object?>> items,
  Arena arena,
  Pointer<NativeFunction<_Callback>> handler,
) {
  final menu = _gtkMenuNew();
  for (final item in items) {
    if (item["separator"] == true) {
      _gtkMenuShellAppend(menu, _gtkSeparatorMenuItemNew());
      continue;
    }
    final children = item["items"] as List<Map<String, Object?>>?;
    final checked = item["checked"] == true;
    final mixed = !checked && item["mixed"] == true;
    final widget = (checked || mixed) && children == null
        ? _gtkCheckMenuItemNew()
        : _gtkMenuItemNew();
    if (checked && children == null) _gtkCheckMenuItemSetActive(widget, 1);
    if (mixed && children == null) {
      _gtkCheckMenuItemSetActive(widget, 1);
      _gtkCheckMenuItemSetInconsistent(widget, 1);
    }

    final box = _gtkBoxNew(_gtkOrientationHorizontal, 24);
    _gtkBoxPackStart(
      box,
      _label(item["label"]! as String, arena),
      1,
      1,
      0,
    );
    final shortcut = item["shortcut"] as String?;
    if (shortcut != null) {
      _gtkBoxPackStart(box, _label(shortcut, arena, dim: true), 0, 0, 0);
    }
    _gtkContainerAdd(widget, box);

    _gtkWidgetSetSensitive(widget, item["enabled"] == false ? 0 : 1);
    if (children != null) {
      _gtkMenuItemSetSubmenu(widget, _build(children, arena, handler));
    } else {
      _gSignalConnectData(
        widget,
        "activate".toNativeUtf8(allocator: arena),
        handler,
        Pointer<Void>.fromAddress(item["id"]! as int),
        nullptr,
        0,
      );
    }
    _gtkMenuShellAppend(menu, widget);
  }
  return menu;
}

/// Shows the menu described by [items] with its top-left corner at the global
/// [position], running GTK's event loop until it closes; returns the chosen
/// id or 0.
int popupMenu(List<Map<String, Object?>> items, Offset position) {
  var chosen = 0;
  var closed = false;
  // Items pass their id as the data pointer; the "deactivate" signal passes 0.
  final callable = NativeCallable<_Callback>.isolateLocal((
    Pointer<Void> instance,
    Pointer<Void> data,
  ) {
    if (data.address == 0) {
      closed = true;
    } else {
      chosen = data.address;
    }
  });
  try {
    return using((arena) {
      final anchor = _anchorWindow();
      if (anchor == nullptr) return 0;
      var gdkWindow = _gtkWidgetGetWindow(anchor);
      if (gdkWindow == nullptr) return 0;

      // Menus open from a click, so anchor to the window under the pointer, at
      // the position it reports in that window. The global [position] is
      // unusable on Wayland, where an app can't know where its windows are.
      final localX = arena<Int32>();
      final localY = arena<Int32>();
      var local = false;
      {
        final seat = _gdkDisplayGetDefaultSeat(_gdkDisplayGetDefault());
        final under = _gdkDeviceGetWindowAtPosition(
          _gdkSeatGetPointer(seat),
          localX,
          localY,
        );
        if (under != nullptr) {
          gdkWindow = under;
          local = true;
        }
      }

      final menu = _build(items, arena, callable.nativeFunction);
      _gSignalConnectData(
        menu,
        "deactivate".toNativeUtf8(allocator: arena),
        callable.nativeFunction,
        nullptr,
        nullptr,
        0,
      );

      _gtkWidgetShowAll(menu);
      final event = _triggerEvent(gdkWindow);
      final rect = arena<_GdkRectangle>();
      if (local) {
        rect.ref
          ..x = localX.value
          ..y = localY.value;
      } else {
        // The anchor rect is in the window's own coordinates.
        final originX = arena<Int32>();
        final originY = arena<Int32>();
        _gdkWindowGetOrigin(gdkWindow, originX, originY);
        rect.ref
          ..x = position.dx.round() - originX.value
          ..y = position.dy.round() - originY.value;
      }
      rect.ref
        ..width = 1
        ..height = 1;
      _gtkMenuPopupAtRect(
        menu,
        gdkWindow,
        rect,
        _gdkGravityNorthWest,
        _gdkGravityNorthWest,
        event.cast(),
      );
      _gdkEventFree(event);
      while (!closed) {
        _gMainContextIteration(nullptr, 1);
      }
      // The chosen item's "activate" can arrive after "deactivate".
      while (_gMainContextIteration(nullptr, 0) != 0) {}
      _gtkWidgetDestroy(menu);
      return chosen;
    });
  } finally {
    callable.close();
  }
}
