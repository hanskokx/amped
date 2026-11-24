# window_dock

Classic-style docking and snapping for multi-window Flutter desktop apps built on Flutter's native windowing API.

## Use

This package is part of the Amped app repository, in `packages/window_dock`, and the
app depends on it by path:

```yaml
dependencies:
  window_dock:
    path: packages/window_dock
```

It depends on other Amped packages:

- [amped_logging](../amped_logging)

## What it provides

- `DockManager` tracks window rectangles and runs the snap, dock and attach
  logic for drags and resizes: windows snap to each other and to the screen,
  and attached windows move together.
- `WindowDragArea` is a widget that drags its window through a manager.
- `NativeWindow` and `NativeScreen`: native window control (move, frameless,
  always on top, show and hide) and screen queries the framework lacks.
- `AppWindowController`: the one adapter over Flutter's experimental
  windowing API, with its delegate and view widgets.
- `NativeMenu`: blocking native popup menus.
- `DockGeometry`: the pure snapping geometry.

Windows and Linux bind to `user32` and GTK from Dart through `dart:ffi`; macOS
uses a small Objective-C helper compiled by a native-assets hook.

```sh
flutter test
```

## License

This package is covered by the license of the Amped repository it is part of.
