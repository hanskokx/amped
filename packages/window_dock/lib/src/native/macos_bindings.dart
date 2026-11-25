import "dart:ffi";

import "package:ffi/ffi.dart";

/// Mirrors `WDRect` in `src/window_dock_macos.m`.
final class WDRect extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;
}

@Native<Void Function(Pointer<Void>, Int32, Int32)>(symbol: "wd_configure")
external void wdConfigure(Pointer<Void> handle, int frameless, int transparent);

@Native<Void Function(Pointer<Void>, Double, Double, Double, Double)>(
  symbol: "wd_set_frame",
)
external void wdSetFrame(
  Pointer<Void> handle,
  double x,
  double y,
  double width,
  double height,
);

@Native<Void Function(Pointer<Void>, Double, Double)>(symbol: "wd_set_position")
external void wdSetPosition(Pointer<Void> handle, double x, double y);

@Native<WDRect Function(Pointer<Void>)>(symbol: "wd_get_frame")
external WDRect wdGetFrame(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "wd_set_always_on_top")
external void wdSetAlwaysOnTop(Pointer<Void> handle, int on);

@Native<Double Function(Pointer<Void>)>(symbol: "wd_safe_area_top")
external double wdSafeAreaTop(Pointer<Void> handle);

@Native<Void Function(Pointer<NativeFunction<Void Function()>>)>(
  symbol: "wd_observe_key_window",
)
external void wdObserveKeyWindow(
  Pointer<NativeFunction<Void Function()>> callback,
);

@Native<Void Function()>(symbol: "wd_reset_presentation")
external void wdResetPresentation();

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "wd_set_fullscreen")
external void wdSetFullscreen(Pointer<Void> handle, int on);

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "wd_set_visible")
external void wdSetVisible(Pointer<Void> handle, int visible);

@Native<Int32 Function(Pointer<Void>)>(symbol: "wd_is_visible")
external int wdIsVisible(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>)>(symbol: "wd_focus")
external void wdFocus(Pointer<Void> handle);

@Native<Void Function(Pointer<Void>, Double, Double)>(
  symbol: "wd_set_min_size",
)
external void wdSetMinSize(Pointer<Void> handle, double width, double height);

@Native<Void Function(Pointer<Void>, Int32)>(
  symbol: "wd_set_resizable",
)
external void wdSetResizable(Pointer<Void> handle, int resizable);

@Native<Void Function(Pointer<Void>, Int32)>(symbol: "wd_set_activatable")
external void wdSetActivatable(Pointer<Void> handle, int activatable);

@Native<Void Function(Pointer<Void>)>(symbol: "wd_minimize")
external void wdMinimize(Pointer<Void> handle);

@Native<Int32 Function(Pointer<WDRect>, Int32)>(symbol: "wd_get_work_areas")
external int wdGetWorkAreas(Pointer<WDRect> out, int max);

@Native<Void Function(Pointer<Double>, Pointer<Double>)>(
  symbol: "wd_get_cursor_position",
)
external void wdGetCursorPosition(Pointer<Double> x, Pointer<Double> y);

@Native<Int64 Function(Pointer<Utf8>, Double, Double, Double)>(
  symbol: "wd_popup_menu",
)
external int wdPopupMenu(Pointer<Utf8> json, double x, double y, double alpha);

@Native<Void Function(Pointer<Void>, Pointer<Double>, Pointer<Int32>, Int32)>(
  symbol: "wd_set_shape",
)
external void wdSetShape(
  Pointer<Void> handle,
  Pointer<Double> points,
  Pointer<Int32> counts,
  int polygonCount,
);

@Native<Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32)>(
  symbol: "wd_set_blur",
)
external void wdSetBlur(
  Pointer<Void> handle,
  Pointer<Uint8> alpha,
  int width,
  int height,
);
