import "dart:ffi";
import "dart:math";
import "dart:ui";

import "package:ffi/ffi.dart";

// GTK 3 is already loaded by the Flutter Linux embedder, so the symbols
// resolve from the process. Note that Wayland compositors do not let clients
// position their own windows; moving only works under X11/XWayland.

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

final class _GdkRgba extends Struct {
  @Double()
  external double red;

  @Double()
  external double green;

  @Double()
  external double blue;

  @Double()
  external double alpha;
}

@Native<Void Function(Pointer<Void>, Int32, Int32)>(symbol: "gtk_window_move")
external void gtkWindowMove(Pointer<Void> window, int x, int y);

@Native<Void Function(Pointer<Void>, Int32, Int32)>(symbol: "gtk_window_resize")
external void gtkWindowResize(Pointer<Void> window, int width, int height);

@Native<Void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>)>(
  symbol: "gtk_window_get_position",
)
external void _gtkWindowGetPosition(
  Pointer<Void> window,
  Pointer<Int32> x,
  Pointer<Int32> y,
);

@Native<Void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>)>(
  symbol: "gtk_window_get_size",
)
external void _gtkWindowGetSize(
  Pointer<Void> window,
  Pointer<Int32> width,
  Pointer<Int32> height,
);

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "gtk_window_set_decorated")
external void gtkWindowSetDecorated(Pointer<Void> window, int decorated);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_window_set_keep_above",
)
external void gtkWindowSetKeepAbove(Pointer<Void> window, int above);

@Native<Int32 Function(Pointer<Void>)>(symbol: "gtk_widget_get_visible")
external int gtkWidgetGetVisible(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_widget_show")
external void gtkWidgetShow(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_widget_hide")
external void gtkWidgetHide(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_window_present")
external void gtkWindowPresent(Pointer<Void> window);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_window_fullscreen")
external void gtkWindowFullscreen(Pointer<Void> window);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_window_unfullscreen")
external void gtkWindowUnfullscreen(Pointer<Void> window);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_window_iconify")
external void gtkWindowIconify(Pointer<Void> window);

@Native<Pointer<Void> Function()>(symbol: "gdk_display_get_default")
external Pointer<Void> _gdkDisplayGetDefault();

@Native<Int32 Function(Pointer<Void>)>(symbol: "gdk_display_get_n_monitors")
external int _gdkDisplayGetNMonitors(Pointer<Void> display);

@Native<Pointer<Void> Function(Pointer<Void>, Int32)>(
  symbol: "gdk_display_get_monitor",
)
external Pointer<Void> _gdkDisplayGetMonitor(Pointer<Void> display, int index);

@Native<Void Function(Pointer<Void>, Pointer<_GdkRectangle>)>(
  symbol: "gdk_monitor_get_workarea",
)
external void _gdkMonitorGetWorkarea(
  Pointer<Void> monitor,
  Pointer<_GdkRectangle> rect,
);

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gdk_display_get_default_seat",
)
external Pointer<Void> _gdkDisplayGetDefaultSeat(Pointer<Void> display);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gdk_seat_get_pointer")
external Pointer<Void> _gdkSeatGetPointer(Pointer<Void> seat);

@Native<
  Void Function(
    Pointer<Void>,
    Pointer<Pointer<Void>>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: "gdk_device_get_position")
external void _gdkDeviceGetPosition(
  Pointer<Void> device,
  Pointer<Pointer<Void>> screen,
  Pointer<Int32> x,
  Pointer<Int32> y,
);

Rect windowRect(Pointer<Void> window) {
  return using((arena) {
    final x = arena<Int32>();
    final y = arena<Int32>();
    final w = arena<Int32>();
    final h = arena<Int32>();
    _gtkWindowGetPosition(window, x, y);
    _gtkWindowGetSize(window, w, h);
    return Rect.fromLTWH(
      x.value.toDouble(),
      y.value.toDouble(),
      w.value.toDouble(),
      h.value.toDouble(),
    );
  });
}

List<Rect> workAreas() {
  final display = _gdkDisplayGetDefault();
  if (display == nullptr) return const [];
  return using((arena) {
    final rect = arena<_GdkRectangle>();
    return [
      for (var i = 0; i < _gdkDisplayGetNMonitors(display); i++)
        () {
          _gdkMonitorGetWorkarea(_gdkDisplayGetMonitor(display, i), rect);
          return Rect.fromLTWH(
            rect.ref.x.toDouble(),
            rect.ref.y.toDouble(),
            rect.ref.width.toDouble(),
            rect.ref.height.toDouble(),
          );
        }(),
    ];
  });
}

Offset cursorPosition() {
  final display = _gdkDisplayGetDefault();
  if (display == nullptr) return Offset.zero;
  final pointer = _gdkSeatGetPointer(_gdkDisplayGetDefaultSeat(display));
  return using((arena) {
    final x = arena<Int32>();
    final y = arena<Int32>();
    _gdkDeviceGetPosition(pointer, nullptr, x, y);
    return Offset(x.value.toDouble(), y.value.toDouble());
  });
}

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gtk_widget_get_screen")
external Pointer<Void> _gtkWidgetGetScreen(Pointer<Void> widget);

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gdk_screen_get_rgba_visual",
)
external Pointer<Void> _gdkScreenGetRgbaVisual(Pointer<Void> screen);

@Native<Int32 Function(Pointer<Void>)>(symbol: "gtk_widget_get_realized")
external int _gtkWidgetGetRealized(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gtk_widget_set_visual",
)
external void _gtkWidgetSetVisual(Pointer<Void> widget, Pointer<Void> visual);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_widget_set_app_paintable",
)
external void _gtkWidgetSetAppPaintable(Pointer<Void> widget, int paintable);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gtk_bin_get_child")
external Pointer<Void> _gtkBinGetChild(Pointer<Void> bin);

@Native<Void Function(Pointer<Void>, Pointer<_GdkRgba>)>(
  symbol: "fl_view_set_background_color",
)
external void _flViewSetBackgroundColor(
  Pointer<Void> view,
  Pointer<_GdkRgba> color,
);

@Native<Pointer<Void> Function(Pointer<Void>)>(symbol: "gtk_widget_get_window")
external Pointer<Void> _gtkWidgetGetWindow(Pointer<Void> widget);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: "gdk_window_set_opaque_region",
)
external void _gdkWindowSetOpaqueRegion(
  Pointer<Void> window,
  Pointer<Void> region,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>, Int32, Int32)>(
  symbol: "gdk_window_shape_combine_region",
)
external void _gdkWindowShapeCombineRegion(
  Pointer<Void> window,
  Pointer<Void> region,
  int offsetX,
  int offsetY,
);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_window_set_accept_focus",
)
external void _gtkWindowSetAcceptFocus(Pointer<Void> window, int accept);

@Native<Pointer<Void> Function(Pointer<_GdkRectangle>, Int32)>(
  symbol: "cairo_region_create_rectangles",
)
external Pointer<Void> _cairoRegionCreateRectangles(
  Pointer<_GdkRectangle> rects,
  int count,
);

@Native<Void Function(Pointer<Void>)>(symbol: "cairo_region_destroy")
external void _cairoRegionDestroy(Pointer<Void> region);

@Native<Pointer<Void> Function(Pointer<Void>)>(
  symbol: "gtk_window_get_titlebar",
)
external Pointer<Void> _gtkWindowGetTitlebar(Pointer<Void> window);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "gtk_widget_set_no_show_all",
)
external void _gtkWidgetSetNoShowAll(Pointer<Void> widget, int noShowAll);

@Native<Void Function(Pointer<Void>)>(symbol: "gtk_widget_hide")
external void _gtkWidgetHide(Pointer<Void> widget);

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

@Native<Pointer<Void> Function()>(symbol: "gtk_css_provider_new")
external Pointer<Void> _gtkCssProviderNew();

@Native<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int64, Pointer<Void>)>(
  symbol: "gtk_css_provider_load_from_data",
)
external int _gtkCssProviderLoadFromData(
  Pointer<Void> provider,
  Pointer<Utf8> data,
  int length,
  Pointer<Void> error,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>, Uint32)>(
  symbol: "gtk_style_context_add_provider_for_screen",
)
external void _gtkStyleContextAddProviderForScreen(
  Pointer<Void> screen,
  Pointer<Void> provider,
  int priority,
);

bool _frameCssAdded = false;

/// Removes the header bar Flutter puts on every window (turning off
/// `decorated` doesn't hide a custom titlebar) and the frame GTK draws around
/// client-side decorated windows, which would otherwise show a border and keep
/// the window opaque.
void removeFrame(Pointer<Void> window) {
  final titlebar = _gtkWindowGetTitlebar(window);
  if (titlebar != nullptr) {
    _gtkWidgetSetNoShowAll(titlebar, 1);
    _gtkWidgetHide(titlebar);
  }
  using((arena) {
    if (!_frameCssAdded) {
      _frameCssAdded = true;
      final provider = _gtkCssProviderNew();
      final css =
          """
window.amped-frameless, window.amped-frameless.background,
window.amped-frameless decoration {
  background: transparent;
  background-color: transparent;
  box-shadow: none;
  border: none;
  border-radius: 0;
  margin: 0;
}
"""
              .toNativeUtf8(allocator: arena);
      _gtkCssProviderLoadFromData(provider, css, -1, nullptr);
      // GTK_STYLE_PROVIDER_PRIORITY_APPLICATION
      _gtkStyleContextAddProviderForScreen(
        _gtkWidgetGetScreen(window),
        provider,
        600,
      );
    }
    _gtkStyleContextAddClass(
      _gtkWidgetGetStyleContext(window),
      "amped-frameless".toNativeUtf8(allocator: arena),
    );
  });
}

void setAcceptFocus(Pointer<Void> window, bool accept) =>
    _gtkWindowSetAcceptFocus(window, accept ? 1 : 0);

/// Lets what the window's content leaves transparent show what is behind it:
/// an RGBA visual for the window (before it is realized; GTK cannot change it
/// afterwards) and a transparent background for the Flutter view inside it.
/// Does nothing without a compositing window manager.
void makeTransparent(Pointer<Void> window) {
  try {
    if (_gtkWidgetGetRealized(window) == 0) {
      final visual = _gdkScreenGetRgbaVisual(_gtkWidgetGetScreen(window));
      if (visual != nullptr) {
        _gtkWidgetSetVisual(window, visual);
        _gtkWidgetSetAppPaintable(window, 1);
      }
    }
    // Without this a Wayland compositor treats the surface as opaque and
    // draws black where the content is transparent.
    final gdkWindow = _gtkWidgetGetWindow(window);
    if (gdkWindow != nullptr) _gdkWindowSetOpaqueRegion(gdkWindow, nullptr);
    final view = _gtkBinGetChild(window);
    if (view == nullptr) return;
    using((arena) {
      final color = arena<_GdkRgba>()
        ..ref.red = 0
        ..ref.green = 0
        ..ref.blue = 0
        ..ref.alpha = 0;
      _flViewSetBackgroundColor(view, color);
    });
  } on Object {
    // A GTK or embedder without these symbols keeps its opaque window.
  }
}

/// Cuts the window to [polygons] (logical pixels from its top-left corner,
/// combined with the nonzero rule), or back to its full rectangle for
/// `null`: the outside shows what is behind and passes the pointer through.
void setShape(Pointer<Void> window, List<List<Offset>>? polygons) {
  final gdkWindow = _gtkWidgetGetWindow(window);
  if (gdkWindow == nullptr) return;
  final spans = polygons == null ? const <Rect>[] : _scanlines(polygons);
  if (spans.isEmpty) {
    _gdkWindowShapeCombineRegion(gdkWindow, nullptr, 0, 0);
    return;
  }
  using((arena) {
    final rects = arena<_GdkRectangle>(spans.length);
    for (final (i, span) in spans.indexed) {
      rects[i]
        ..x = span.left.round()
        ..y = span.top.round()
        ..width = span.width.round()
        ..height = span.height.round();
    }
    final region = _cairoRegionCreateRectangles(rects, spans.length);
    _gdkWindowShapeCombineRegion(gdkWindow, region, 0, 0);
    _cairoRegionDestroy(region);
  });
}

/// The pixel rows covered by [polygons] (nonzero rule) as rectangles, rows
/// with the same spans merged.
List<Rect> _scanlines(List<List<Offset>> polygons) {
  final shapes = [
    for (final polygon in polygons)
      if (polygon.length >= 3) polygon,
  ];
  if (shapes.isEmpty) return const [];
  var top = double.infinity, bottom = -double.infinity;
  for (final polygon in shapes) {
    for (final point in polygon) {
      top = min(top, point.dy);
      bottom = max(bottom, point.dy);
    }
  }
  final result = <Rect>[];
  // Rectangles still growing downwards, by "left,right".
  var open = <String, Rect>{};
  final first = max(0, top.floor()), last = bottom.ceil();
  for (var y = first; y <= last; y++) {
    final center = y + 0.5;
    final crossings = <(double, int)>[];
    for (final polygon in shapes) {
      for (var i = 0; i < polygon.length; i++) {
        final a = polygon[i], b = polygon[(i + 1) % polygon.length];
        if ((a.dy <= center) == (b.dy <= center)) continue;
        final x = a.dx + (center - a.dy) * (b.dx - a.dx) / (b.dy - a.dy);
        crossings.add((x, b.dy > a.dy ? 1 : -1));
      }
    }
    crossings.sort((p, q) => p.$1.compareTo(q.$1));
    final next = <String, Rect>{};
    var winding = 0;
    double? start;
    for (final (x, direction) in crossings) {
      final before = winding;
      winding += direction;
      if (before == 0 && winding != 0) {
        start = x;
      } else if (before != 0 && winding == 0 && start != null) {
        final left = start.round().toDouble();
        final right = x.round().toDouble();
        if (right > left) {
          final key = "$left,$right";
          final grown = open.remove(key);
          next[key] = grown == null
              ? Rect.fromLTRB(left, y.toDouble(), right, y + 1.0)
              : Rect.fromLTRB(left, grown.top, right, y + 1.0);
        }
        start = null;
      }
    }
    result.addAll(open.values);
    open = next;
  }
  result.addAll(open.values);
  return result;
}
