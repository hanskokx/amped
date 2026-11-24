/// classic-style window docking and snapping for multi-window Flutter desktop
/// apps built on Flutter's windowing API.
///
/// * [DockManager] — tracks window rects and runs the snap/dock/attach logic
///   for drags and resizes.
/// * [WindowDragArea] — a widget that drags its window through a manager.
/// * [NativeWindow] / [NativeScreen] — native window control (move, frameless,
///   always-on-top, show/hide) and screen queries the framework lacks.
/// * [AppWindowController] — the one adapter over Flutter's experimental
///   windowing API, with its delegate and view widgets.
/// * [NativeMenu] — blocking native popup menus.
/// * [DockGeometry] — the pure snapping geometry.
library;

export "src/dock_geometry.dart";
export "src/dock_manager.dart";
export "src/flutter_windowing.dart";
export "src/native_menu.dart";
export "src/native_window.dart";
export "src/window_drag_area.dart";
