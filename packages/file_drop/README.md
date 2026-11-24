# file_drop

Native file drops onto windows created with Flutter's windowing API.

## Use

This package is part of the Amped app repository, in `packages/file_drop`, and the
app depends on it by path:

```yaml
dependencies:
  file_drop:
    path: packages/file_drop
```

It depends on other Amped packages:

- [window_dock](../window_dock)

## What it provides

Drag files from the file manager onto a window and receive their paths:

```dart
import "package:file_drop/file_drop.dart";

FileDrop.enable(
  window, // an AppWindowController from window_dock
  extensions: ["mp3", "flac"], // empty: every file
  onDrop: (path) {
    // called for each dropped file
  },
);
```

`FileDrop.isSupported` says whether the platform can do it.

Implemented natively for macOS (Objective-C, built by a native-assets hook),
and over GTK on Linux and Win32 on Windows through `dart:ffi`. Windows are
identified with the handles of
[window_dock](../window_dock).

## License

This package is covered by the license of the Amped repository it is part of.
