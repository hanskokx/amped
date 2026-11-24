// This is the only file in the repository that reaches into Flutter's
// experimental multi-window API (`RegularWindowController`-style controllers,
// `isWindowingEnabled`, the platform window classes). Flutter only exposes it
// through `package:flutter/src/widgets/_window*.dart`, with every member marked
// `@internal`, so no code change can satisfy these two lint rules while we use
// multi-window. Everything else talks to the types defined here, which keeps
// the impact small when Flutter changes or publishes the API; remove the
// ignore below then.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import "dart:ffi" hide Size;

import "package:flutter/src/foundation/_features.dart";
import "package:flutter/src/widgets/_window.dart";
import "package:flutter/src/widgets/_window_linux.dart";
import "package:flutter/src/widgets/_window_macos.dart";
import "package:flutter/src/widgets/_window_win32.dart";
import "package:flutter/widgets.dart";

/// Turns on Flutter's multi-window support. Call before the binding starts.
void enableFlutterWindowing() {
  isWindowingEnabled = true;
}

/// Receives the lifecycle of an [AppWindowController].
mixin class AppWindowDelegate {
  /// The user asked to close [controller]. The default destroys it; override
  /// to delay or prevent that.
  void onWindowCloseRequested(AppWindowController controller) {
    controller.destroy();
  }

  /// The window has been closed.
  void onWindowDestroyed() {}
}

/// The native window handles behind an [AppWindowController], by platform.
sealed class PlatformWindowHandle {
  const PlatformWindowHandle();
}

/// The `NSWindow` of a macOS window.
final class MacOSWindowHandle extends PlatformWindowHandle {
  const MacOSWindowHandle(this.windowHandle);

  final Pointer<Void> windowHandle;
}

/// The `HWND` of a Windows window.
final class Win32WindowHandle extends PlatformWindowHandle {
  const Win32WindowHandle(this.windowHandle);

  final Pointer<Void> windowHandle;
}

/// The `GtkWindow` and the Flutter view inside it, of a Linux window.
final class LinuxWindowHandle extends PlatformWindowHandle {
  const LinuxWindowHandle(this.windowHandle, this.flutterViewHandle);

  final Pointer<Void> windowHandle;
  final Pointer<Void> flutterViewHandle;
}

/// A native window created through Flutter's windowing API.
///
/// Notifies its listeners when the window changes (resized, activated, ...).
class AppWindowController implements Listenable {
  /// Creates a window with the content [size].
  factory AppWindowController({
    required Size size,
    BoxConstraints? constraints,
    String? title,
    AppWindowDelegate? delegate,
  }) {
    final bridge = _DelegateBridge(delegate ?? AppWindowDelegate());
    final controller = AppWindowController._(
      WindowController(
        size: size,
        constraints: constraints,
        title: title,
        delegate: bridge,
      ),
    );
    bridge.controller = controller;
    return controller;
  }

  AppWindowController._(this._controller) {
    _wrappers[_controller] = this;
  }

  static final Expando<AppWindowController> _wrappers = Expando();

  final BaseWindowController _controller;

  /// The controller of the window [context] is in, or `null` outside one.
  static AppWindowController? maybeOf(BuildContext context) {
    final controller = WindowScope.maybeOf(context);
    if (controller == null) return null;
    return _wrappers[controller] ?? AppWindowController._(controller);
  }

  /// Whether the window is the active one.
  bool get isActivated => switch (_controller) {
    final WindowController controller => controller.isActivated,
    final DialogWindowController controller => controller.isActivated,
    _ => true,
  };

  bool get isMinimized => switch (_controller) {
    final WindowController controller => controller.isMinimized,
    _ => false,
  };

  void setMinimized(bool minimized) {
    if (_controller case final WindowController controller) {
      controller.setMinimized(minimized);
    }
  }

  /// Brings the window to the front.
  void activate() {
    if (_controller case final WindowController controller) {
      controller.activate();
    }
  }

  /// Closes the window.
  void destroy() {
    if (_controller case final WindowController controller) {
      controller.destroy();
    }
  }

  /// The native handles of the window, or `null` on an unsupported platform.
  PlatformWindowHandle? get platformHandle {
    final controller = _controller;
    if (controller is WindowControllerMacOS) {
      return MacOSWindowHandle(controller.windowHandle);
    }
    if (controller is WindowControllerWin32) {
      return Win32WindowHandle(controller.windowHandle);
    }
    if (controller is WindowControllerLinux) {
      return LinuxWindowHandle(
        controller.windowHandle,
        controller.flutterViewHandle,
      );
    }
    return null;
  }

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);
}

class _DelegateBridge with WindowControllerDelegate {
  _DelegateBridge(this.delegate);

  final AppWindowDelegate delegate;
  late final AppWindowController controller;

  @override
  void onWindowCloseRequested(WindowController _) {
    delegate.onWindowCloseRequested(controller);
  }

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    delegate.onWindowDestroyed();
  }
}

/// Renders [child] into the native window of [controller]. Place inside an
/// [AppWindowViews].
class AppWindowView extends StatelessWidget {
  const AppWindowView({
    required this.controller,
    required this.child,
    super.key,
  });

  final AppWindowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Window(
      controller: controller._controller as WindowController,
      child: child,
    );
  }
}

/// The root of an app made of several native windows: one [AppWindowView] for
/// each.
class AppWindowViews extends StatelessWidget {
  const AppWindowViews({required this.windows, super.key});

  final List<AppWindowView> windows;

  @override
  Widget build(BuildContext context) => ViewCollection(views: windows);
}
