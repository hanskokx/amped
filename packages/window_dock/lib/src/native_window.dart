import "dart:async";
import "dart:ffi" hide Size;
import "dart:io";
import "dart:math";
import "dart:ui";

import "package:ffi/ffi.dart";
import "package:flutter/foundation.dart";

import "flutter_windowing.dart";
import "native/linux_bindings.dart" as gtk;
import "native/macos_bindings.dart" as mac;
import "native/win32_bindings.dart" as win32;

/// Native control over a window created through Flutter's windowing API, for
/// the operations the framework does not expose yet: moving, frameless
/// styling, always-on-top, and showing/hiding.
///
/// Rects and offsets are logical pixels in a global top-left-origin space
/// (the primary screen's top-left corner is the origin).
abstract class NativeWindow {
  /// The native window behind [controller].
  factory NativeWindow.of(AppWindowController controller) {
    return switch (controller.platformHandle) {
      MacOSWindowHandle(:final windowHandle) => _MacOSWindow(windowHandle),
      Win32WindowHandle(:final windowHandle) => _Win32Window(windowHandle),
      LinuxWindowHandle(:final windowHandle) => _LinuxWindow(windowHandle),
      null => throw UnsupportedError(
        "NativeWindow is not supported on this platform",
      ),
    };
  }

  /// Removes the title bar and border (and optionally makes the window
  /// background transparent), keeping the current content size.
  void configure({bool frameless = true, bool transparent = false});

  /// The window's current frame.
  Rect get frame;

  /// Moves and resizes the window.
  void setFrame(Rect rect);

  /// Moves the window's top-left corner to [topLeft].
  void setPosition(Offset topLeft);

  /// Keeps the window above normal windows.
  void setAlwaysOnTop(bool alwaysOnTop);

  bool get isVisible;

  void show();

  void hide();

  /// Brings the window to the front and gives it keyboard focus.
  void focus();

  /// Minimizes (iconifies) the window.
  void minimize();

  /// Whether a click gives the window the keyboard focus (a layout's
  /// `noactivation="1"` turns that off). Supported on macOS; a no-op
  /// elsewhere for now.
  void setActivatable(bool activatable);

  /// The least content size, in logical pixels, the user can drag the
  /// window down to. Supported on macOS; a no-op elsewhere for now.
  void setMinSize(Size size);

  /// Covers the whole screen the window is on, above the menu bar or
  /// taskbar (hidden meanwhile), or, with [on] false, goes back to how it
  /// was.
  void setFullscreen(bool on);

  /// How far down from the top of the window's screen content can be seen
  /// (below a camera housing), in logical pixels; 0 where nothing hides it.
  double get safeAreaTop;

  /// Restricts the window to [polygons] (in window-local logical pixels,
  /// combined with the nonzero rule), like Win32's `SetWindowRgn`: outside
  /// the shape the window ignores the mouse, so clicks reach whatever is
  /// underneath. Pass `null` to make the whole window interactive again.
  ///
  /// This only affects mouse handling; making the outside transparent is up to
  /// the window's content (and [configure] with `transparent: true`).
  /// Supported on macOS; a no-op elsewhere for now.
  void setShape(List<List<Offset>>? polygons);

  /// Blurs what is behind the window where [alpha] (a [width] by [height]
  /// image of the window, one byte a pixel, rows from the top) is opaque,
  /// for skins with translucent glass; null takes the blur away. Supported
  /// on macOS; a no-op elsewhere for now.
  void setBlurMask(Uint8List? alpha, int width, int height);
}

/// Screen-level queries in the same coordinate space as [NativeWindow].
abstract final class NativeScreen {
  /// Notifies when any window becomes or stops being the active (key)
  /// window. Flutter's window controllers report this themselves on Windows
  /// and Linux but not on macOS; listen to both.
  static Listenable get activationChanges {
    if (Platform.isMacOS && _keyWindowCallback == null) {
      _keyWindowCallback = NativeCallable<Void Function()>.listener(
        _activation.notify,
      );
      mac.wdObserveKeyWindow(_keyWindowCallback!.nativeFunction);
    }
    return _activation;
  }

  static final _ActivationNotifier _activation = _ActivationNotifier();
  static NativeCallable<Void Function()>? _keyWindowCallback;

  /// Shows the menu bar and Dock again if a fullscreen window hid them and
  /// went away without leaving fullscreen (macOS; elsewhere nothing to do).
  static void restoreAfterFullscreen() {
    if (Platform.isMacOS) mac.wdResetPresentation();
  }

  /// The usable area of every monitor (excluding menu bars, docks and task
  /// bars).
  static List<Rect> workAreas() {
    if (Platform.isMacOS) return _macWorkAreas();
    if (Platform.isWindows) return win32.workAreas();
    if (Platform.isLinux) return gtk.workAreas();
    return const [];
  }

  /// The pointer's current global position. Reading it natively (rather than
  /// from pointer events, which are relative to a window that is itself
  /// moving) keeps window drags exact.
  static Offset cursorPosition() {
    if (Platform.isMacOS) {
      return using((arena) {
        final x = arena<Double>();
        final y = arena<Double>();
        mac.wdGetCursorPosition(x, y);
        return Offset(x.value, y.value);
      });
    }
    if (Platform.isWindows) return win32.cursorPosition();
    if (Platform.isLinux) return gtk.cursorPosition();
    return Offset.zero;
  }

  static List<Rect> _macWorkAreas() {
    return using((arena) {
      const max = 16;
      final out = arena<mac.WDRect>(max);
      final count = mac.wdGetWorkAreas(out, max);
      return [
        for (var i = 0; i < count; i++)
          Rect.fromLTWH(out[i].x, out[i].y, out[i].width, out[i].height),
      ];
    });
  }
}

class _MacOSWindow implements NativeWindow {
  _MacOSWindow(this._handle);

  final Pointer<Void> _handle;

  @override
  void configure({bool frameless = true, bool transparent = false}) =>
      mac.wdConfigure(_handle, frameless ? 1 : 0, transparent ? 1 : 0);

  @override
  Rect get frame {
    final r = mac.wdGetFrame(_handle);
    return Rect.fromLTWH(r.x, r.y, r.width, r.height);
  }

  /// Whether a native resize is running. AppKit runs the platform run loop
  /// until the engine has drawn at the new size, which runs Dart tasks, and
  /// one of them (a script's frame and window keeping each other the same
  /// size) resizes a window again: a resize inside a resize crashed the
  /// raster thread. Those wait for the one running, and the latest wins.
  static bool _resizing = false;
  static final Map<Pointer<Void>, Rect> _waiting = {};

  @override
  void setFrame(Rect rect) {
    if (_resizing) {
      _waiting[_handle] = rect;
      return;
    }
    _resizing = true;
    try {
      mac.wdSetFrame(_handle, rect.left, rect.top, rect.width, rect.height);
    } finally {
      _resizing = false;
    }
    if (_waiting.isNotEmpty) {
      final next = Map.of(_waiting);
      _waiting.clear();
      // Not from inside the run loop that just finished.
      Timer.run(() {
        for (final MapEntry(:key, :value) in next.entries) {
          _MacOSWindow(key).setFrame(value);
        }
      });
    }
  }

  @override
  void setPosition(Offset topLeft) =>
      mac.wdSetPosition(_handle, topLeft.dx, topLeft.dy);

  @override
  void setAlwaysOnTop(bool alwaysOnTop) =>
      mac.wdSetAlwaysOnTop(_handle, alwaysOnTop ? 1 : 0);

  @override
  bool get isVisible => mac.wdIsVisible(_handle) != 0;

  @override
  void show() => mac.wdSetVisible(_handle, 1);

  @override
  void hide() => mac.wdSetVisible(_handle, 0);

  @override
  void focus() => mac.wdFocus(_handle);

  @override
  void minimize() => mac.wdMinimize(_handle);

  @override
  void setActivatable(bool activatable) =>
      mac.wdSetActivatable(_handle, activatable ? 1 : 0);

  @override
  void setMinSize(Size size) =>
      mac.wdSetMinSize(_handle, size.width, size.height);

  @override
  void setFullscreen(bool on) => mac.wdSetFullscreen(_handle, on ? 1 : 0);

  @override
  double get safeAreaTop => mac.wdSafeAreaTop(_handle);

  @override
  void setShape(List<List<Offset>>? polygons) {
    final shape = polygons?.where((p) => p.length >= 3).toList() ?? const [];
    using((arena) {
      final pointCount = shape.fold<int>(0, (sum, p) => sum + p.length);
      final points = arena<Double>(max(pointCount * 2, 1));
      final counts = arena<Int32>(max(shape.length, 1));
      var i = 0;
      for (final (index, polygon) in shape.indexed) {
        counts[index] = polygon.length;
        for (final point in polygon) {
          points[i++] = point.dx;
          points[i++] = point.dy;
        }
      }
      mac.wdSetShape(_handle, points, counts, shape.length);
    });
  }

  @override
  void setBlurMask(Uint8List? alpha, int width, int height) {
    if (alpha == null || width <= 0 || height <= 0) {
      mac.wdSetBlur(_handle, nullptr, 0, 0);
      return;
    }
    using((arena) {
      final bytes = arena<Uint8>(alpha.length);
      bytes.asTypedList(alpha.length).setAll(0, alpha);
      mac.wdSetBlur(_handle, bytes, width, height);
    });
  }
}

class _Win32Window implements NativeWindow {
  _Win32Window(this._hwnd);

  final Pointer<Void> _hwnd;

  @override
  void configure({bool frameless = true, bool transparent = false}) {
    if (frameless) win32.makeFrameless(_hwnd);
    if (transparent) win32.makeTransparent(_hwnd);
  }

  @override
  Rect get frame => win32.windowRect(_hwnd);

  @override
  void setFrame(Rect rect) => win32.setWindowRect(_hwnd, rect);

  @override
  void setPosition(Offset topLeft) => win32.setWindowPosition(_hwnd, topLeft);

  @override
  void setAlwaysOnTop(bool alwaysOnTop) => win32.setTopmost(_hwnd, alwaysOnTop);

  @override
  bool get isVisible => win32.isVisible(_hwnd);

  @override
  void show() => win32.showWindow(_hwnd, win32.swShowNoActivate);

  @override
  void hide() => win32.showWindow(_hwnd, win32.swHide);

  @override
  void focus() => win32.focus(_hwnd);

  @override
  void minimize() => win32.showWindow(_hwnd, win32.swMinimize);

  @override
  void setActivatable(bool activatable) {}

  @override
  void setMinSize(Size size) {}

  /// The frame before going fullscreen.
  Rect? _windowed;

  @override
  double get safeAreaTop => 0;

  @override
  void setFullscreen(bool on) {
    if (on) {
      _windowed ??= frame;
      win32.setWindowRect(_hwnd, win32.monitorRect(_hwnd));
      win32.setTopmost(_hwnd, true);
    } else if (_windowed != null) {
      win32.setTopmost(_hwnd, false);
      win32.setWindowRect(_hwnd, _windowed!);
      _windowed = null;
    }
  }

  @override
  void setShape(List<List<Offset>>? polygons) =>
      win32.setShape(_hwnd, polygons);

  @override
  void setBlurMask(Uint8List? alpha, int width, int height) {}
}

class _LinuxWindow implements NativeWindow {
  _LinuxWindow(this._window);

  final Pointer<Void> _window;

  @override
  void configure({bool frameless = true, bool transparent = false}) {
    if (frameless) {
      // The compositor (KWin on Wayland) decides on a titlebar when the
      // window is mapped, so a window already on screen has to be unmapped
      // for `decorated: false` to take effect.
      final wasVisible = gtk.gtkWidgetGetVisible(_window) != 0;
      if (wasVisible) gtk.gtkWidgetHide(_window);
      gtk.gtkWindowSetDecorated(_window, 0);
      gtk.removeFrame(_window);
      if (wasVisible) gtk.gtkWidgetShow(_window);
    }
    if (transparent) gtk.makeTransparent(_window);
  }

  @override
  Rect get frame => gtk.windowRect(_window);

  @override
  void setFrame(Rect rect) {
    gtk.gtkWindowMove(_window, rect.left.round(), rect.top.round());
    gtk.gtkWindowResize(_window, rect.width.round(), rect.height.round());
  }

  @override
  void setPosition(Offset topLeft) =>
      gtk.gtkWindowMove(_window, topLeft.dx.round(), topLeft.dy.round());

  @override
  void setAlwaysOnTop(bool alwaysOnTop) =>
      gtk.gtkWindowSetKeepAbove(_window, alwaysOnTop ? 1 : 0);

  @override
  bool get isVisible => gtk.gtkWidgetGetVisible(_window) != 0;

  @override
  void show() => gtk.gtkWidgetShow(_window);

  @override
  void hide() => gtk.gtkWidgetHide(_window);

  @override
  void focus() => gtk.gtkWindowPresent(_window);

  @override
  void minimize() => gtk.gtkWindowIconify(_window);

  @override
  void setActivatable(bool activatable) =>
      gtk.setAcceptFocus(_window, activatable);

  @override
  void setMinSize(Size size) {}

  @override
  void setFullscreen(bool on) => on
      ? gtk.gtkWindowFullscreen(_window)
      : gtk.gtkWindowUnfullscreen(_window);

  @override
  double get safeAreaTop => 0;

  @override
  void setShape(List<List<Offset>>? polygons) =>
      gtk.setShape(_window, polygons);

  @override
  void setBlurMask(Uint8List? alpha, int width, int height) {}
}

class _ActivationNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
