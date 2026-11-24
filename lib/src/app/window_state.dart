import "dart:async";
import "dart:math";
import "dart:ui";

import "package:amped_skin/amped_skin.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_dock/window_dock.dart";

import "../player/player_state.dart";

import "../skin/skin_views.dart";
import "main_window_scale.dart";

/// The skinned windows' sizes, scales and positions: what size each has, how
/// much it is enlarged, where it first appears, and what is kept between
/// runs. The shell creates and moves the windows themselves.
class WindowState {
  WindowState({
    required this.dock,
    required this._skin,
    required this._isShaded,
    required this._ownNotifier,
    required this._ownNotifierOrigin,
    required this._changed,
    required this.savedPositions,
    required this.sizes,
    required this.scale,
    required this.mainScale,
  });

  final DockManager<SkinWindow> dock;
  final Skin Function() _skin;
  final bool Function(SkinWindow window) _isShaded;

  /// Whether the app's own popup stands in for the skin's notifier.
  final bool Function() _ownNotifier;

  /// Where the app's own popup goes on the screen, given its [size].
  final Offset Function(Size size) _ownNotifierOrigin;
  final void Function() _changed;

  static const String mainScaleKey = "amped.main_scale";

  /// The windows that have been created.
  final Map<SkinWindow, AppWindowController> controllers = {};

  /// Where each window was left, until it is created.
  final Map<SkinWindow, Offset> savedPositions;

  /// The unscaled sizes of the resizable windows.
  final Map<SkinWindow, Size> sizes;

  /// The UI scale of every window but the main one (double-size mode).
  double scale;

  /// The main window's scale: the UI scale, or whatever the user dragged
  /// its resize grip to.
  double mainScale;

  /// What the last run left: positions, sizes and the main window's scale.
  static Future<
    ({
      Map<SkinWindow, Offset> positions,
      Map<SkinWindow, Size> sizes,
      double? mainScale,
    })
  >
  loadSaved(SharedPreferences prefs) async {
    final positions = <SkinWindow, Offset>{};
    final sizes = <SkinWindow, Size>{};
    for (final window in SkinWindow.values) {
      final pos = await PlayerState.loadWindowPos(window.key);
      if (pos != null) positions[window] = Offset(pos.$1, pos.$2);
      if (window.resizable) {
        final size = await PlayerState.loadWindowSize("${window.key}_base");
        if (size != null) {
          final saved = Size(size.$1, size.$2);
          // The Album Art window was sized to its cover, not the grid.
          sizes[window] = window == SkinWindow.albumArt
              ? Size(
                  max(saved.width, window.minWidth),
                  max(saved.height, SkinWindow.minResizableSize.height),
                )
              : snapResizable(saved, window);
        }
      }
    }
    return (
      positions: positions,
      sizes: sizes,
      mainScale: prefs
          .getDouble(mainScaleKey)
          ?.clamp(MainWindowScale.minScale, MainWindowScale.maxScale)
          .toDouble(),
    );
  }

  /// Keeps where the windows are, how big the resizable ones are and the
  /// main window's scale.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final window in dock.windows) {
      // The notifier is placed by its script each time.
      if (window == SkinWindow.notifier) continue;
      final rect = dock.rectOf(window)!;
      savedPositions[window] = rect.topLeft;
      await prefs.setDouble("amped.window_${window.key}_x", rect.left);
      await prefs.setDouble("amped.window_${window.key}_y", rect.top);
    }
    await prefs.setDouble(mainScaleKey, mainScale);
    for (final entry in sizes.entries) {
      await PlayerState.saveWindowSize(
        "${entry.key.key}_base",
        entry.value.width,
        entry.value.height,
      );
    }
  }

  /// The window's current unscaled size (taking shade mode into account).
  Size baseSize(SkinWindow window) {
    final layout = _skin().modern?.layout(window);
    if (layout != null) return layout.windowSize;
    final size = fullSize(window);
    if (_isShaded(window)) return Size(size.width, SkinWindow.shadeHeight);
    return size;
  }

  /// The unscaled size a resizable window has when not shaded. An Audacious
  /// skin may give the main window a size of its own.
  Size fullSize(SkinWindow window) {
    if (window == SkinWindow.main) {
      if (_skin().mainSize case final size?) return size;
    }
    return sizes[window] ?? window.defaultSize;
  }

  /// How much [window]'s skin pixels are enlarged on screen.
  double scaleOf(SkinWindow window) => switch (window) {
    SkinWindow.main => mainScale,
    // Placed in screen pixels by its script.
    SkinWindow.notifier => _ownNotifier() ? scale : 1,
    _ => scale,
  };

  /// [window]'s current size on screen.
  Size scaled(SkinWindow window) => window == SkinWindow.main
      ? MainWindowScale.windowSize(baseSize(window), mainScale)
      // Whole pixels: a fractional window size (a layout resized by a
      // script, a drawer's tween) crashes Impeller on macOS, as the main
      // window's does ([MainWindowScale.windowSize]).
      : MainWindowScale.windowSize(baseSize(window), scaleOf(window));

  /// The saved position when it is still on a screen, else the original's
  /// default layout: the main window centered, the others stacked below it.
  Offset initialPosition(SkinWindow window, Size size) {
    if (window == SkinWindow.notifier && _ownNotifier()) {
      return _ownNotifierOrigin(size);
    }
    if (window == SkinWindow.notifier) {
      final size = _skin().modern?.layout(window)?.windowSize;
      return size == null ? Offset.zero : _ownNotifierOrigin(size);
    }
    final areas = NativeScreen.workAreas();
    final saved = savedPositions[window];
    if (saved != null && areas.isNotEmpty) {
      // Off the screens (a monitor that is gone), or partly: moved the
      // least that shows all of it.
      return DockGeometry.fitInto(saved & size, areas).topLeft;
    }
    final mainRect = dock.rectOf(SkinWindow.main);
    if (window == SkinWindow.main || mainRect == null) {
      final area = areas.isEmpty
          ? const Rect.fromLTWH(0, 0, 1280, 800)
          : areas.first;
      return area.center - size.center(Offset.zero);
    }
    // A skin's own panels sit where it lays them out around its main window
    // (HARMONIA stacks its control and song display panels below it).
    if (window.isExtra) {
      final at = _skin().modern?.container(window)?.defaultPosition;
      final mainAt = _skin().modern
          ?.container(SkinWindow.main)
          ?.defaultPosition;
      if (at != null && mainAt != null) {
        return mainRect.topLeft + (at - mainAt) * scale;
      }
    }
    var bottom = mainRect.bottom;
    for (final other in dock.windows) {
      if (other == window || !dock.isVisible(other)) continue;
      final rect = dock.rectOf(other)!;
      if (rect.left == mainRect.left && rect.top >= bottom - 0.5) {
        if (rect.bottom > bottom) bottom = rect.bottom;
      }
    }
    // Keep the stacked window on the main window's screen.
    final area = DockGeometry.workAreaFor(mainRect, areas);
    if (area == null) return Offset(mainRect.left, bottom);
    return Offset(
      mainRect.left.clamp(area.left, max(area.left, area.right - size.width)),
      bottom.clamp(area.top, max(area.top, area.bottom - size.height)),
    );
  }

  void rescale(double newScale) {
    // Back to the old UI scale first, so the whole layout scales by one
    // factor; resizing re-pins the windows docked to the main window.
    if (mainScale != scale) {
      mainScale = scale;
      dock.resize(SkinWindow.main, scaled(SkinWindow.main));
    }
    final factor = newScale / scale;
    scale = newScale;
    mainScale = newScale;
    final mainRect = dock.rectOf(SkinWindow.main)!;
    final group = dock.attachedTo(SkinWindow.main);
    for (final window in dock.windows) {
      final rect = dock.rectOf(window)!;
      final size = scaled(window);
      final topLeft = window == SkinWindow.main || !group.contains(window)
          ? rect.topLeft
          : mainRect.topLeft + (rect.topLeft - mainRect.topLeft) * factor;
      dock.setRect(window, topLeft & size);
    }
    // Saved now, not with the positions a moment later: the UI scale is saved
    // as soon as it is chosen, and a crash in between left the main window
    // starting at the old scale beside windows at the new one.
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setDouble(mainScaleKey, mainScale),
      ),
    );
    _changed();
  }

  static Size snapResizable(Size size, SkinWindow window) {
    var width = size.width.round() + 24;
    width -= width % 25;
    var height = size.height.round() + 28;
    height -= height % 29;
    return Size(
      width.toDouble().clamp(window.minWidth, 8000),
      height.toDouble().clamp(SkinWindow.minResizableSize.height, 8000),
    );
  }
}
