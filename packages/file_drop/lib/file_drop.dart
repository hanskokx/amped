/// Native file drops onto windows created with Flutter's windowing API.
library;

import "dart:ffi";
import "dart:io";

import "package:ffi/ffi.dart";
import "package:flutter/foundation.dart";
import "package:window_dock/window_dock.dart";

import "src/gtk_drop.dart";
import "src/macos_bindings.dart" as mac;
import "src/win32_drop.dart";

/// Receives files dragged onto a window (for example from Finder or
/// Explorer).
abstract final class FileDrop {
  /// Whether file drops are supported on this platform.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static final Map<int, ValueChanged<String>> _handlers = {};

  /// One native entry point for every window, keyed by token. A listener,
  /// because AppKit calls it from outside Dart's own call stack.
  static final NativeCallable<mac.FDDropCallbackNative> _callback =
      NativeCallable<mac.FDDropCallbackNative>.listener(_onDrop);

  static void _onDrop(int token, Pointer<Utf8> path) {
    final value = path.toDartString();
    malloc.free(path);
    _handlers[token]?.call(value);
  }

  /// Calls [onDrop] with the path of each file dropped on [window] whose
  /// extension (lower-case, without the dot) is in [extensions], or of every
  /// file when [extensions] is empty, and of each dropped folder when
  /// [directories] is set. Anything else is refused while dragging on macOS
  /// and ignored on drop elsewhere. Replaces an earlier handler for the same
  /// window; does nothing on unsupported platforms.
  static void enable(
    AppWindowController window, {
    required ValueChanged<String> onDrop,
    List<String> extensions = const [],
    bool directories = false,
  }) {
    void deliver(List<String> paths) {
      for (final path in paths) {
        if (_accepts(path, extensions, directories)) onDrop(path);
      }
    }

    switch (window.platformHandle) {
      case Win32WindowHandle(:final windowHandle):
        win32EnableFileDrop(windowHandle, deliver);
        return;
      case LinuxWindowHandle(:final flutterViewHandle):
        gtkEnableFileDrop(flutterViewHandle, deliver);
        return;
      case MacOSWindowHandle():
        break;
      case null:
        return;
    }
    final handle = (window.platformHandle! as MacOSWindowHandle).windowHandle;
    _handlers[handle.address] = onDrop;
    using((arena) {
      mac.fdEnableFileDrop(
        handle,
        extensions.join(",").toNativeUtf8(allocator: arena),
        directories ? 1 : 0,
        _callback.nativeFunction,
        handle.address,
      );
    });
  }

  /// Whether a dropped [path] passes the [extensions] and [directories]
  /// filters of [enable].
  static bool _accepts(
    String path,
    List<String> extensions,
    bool directories,
  ) {
    if (FileSystemEntity.isDirectorySync(path)) return directories;
    if (extensions.isEmpty) return true;
    final name = path.split(RegExp(r"[/\\]")).last;
    final dot = name.lastIndexOf(".");
    return dot >= 0 &&
        extensions.contains(name.substring(dot + 1).toLowerCase());
  }
}
