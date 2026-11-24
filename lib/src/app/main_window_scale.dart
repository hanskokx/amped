import "dart:math";
import "dart:ui";

/// The arithmetic of drag-resizing the main window: its contents scale
/// continuously, with the aspect ratio locked to the skin's shape.
abstract final class MainWindowScale {
  /// The smallest scale: below the skin's native size it is unreadable.
  static const double minScale = 1;

  /// The largest scale on a screen too small to limit it.
  static const double maxScale = 8;

  /// Scales within this distance of a whole number snap to it, so the
  /// pixel-art skin is easy to get back to a crisp 1x, 2x, ...
  static const double snap = 0.03;

  /// The size of the resize grip in the bottom-right corner, in unscaled
  /// skin pixels. It stays clear of the classic player logo button (253, 91, 13×15).
  static const Size grip = Size(9, 10);

  /// The scale that puts the window's bottom-right corner nearest to
  /// [corner] (relative to its top-left, in logical pixels) while keeping
  /// the proportions of [base], the unscaled skin size.
  ///
  /// The result is snapped to whole numbers when close ([snap]), rounded so
  /// the window is a whole number of pixels wide, and clamped to
  /// [minScale]..[limit].
  static double fromCorner(
    Size base,
    Offset corner, {
    double limit = maxScale,
  }) {
    // The projection of the corner onto the diagonal of the base size.
    final diagonal = base.width * base.width + base.height * base.height;
    var scale = (corner.dx * base.width + corner.dy * base.height) / diagonal;
    final whole = scale.roundToDouble();
    if ((scale - whole).abs() <= snap) {
      scale = whole;
    } else {
      scale = (scale * base.width).roundToDouble() / base.width;
    }
    return scale.clamp(minScale, max(minScale, limit)).toDouble();
  }

  /// The main window's size on screen at [scale]: [base] scaled, rounded to
  /// whole logical pixels in both directions.
  ///
  /// Only whole scales make both sides of a skin whole on their own (275×116
  /// has no common factor). A fractional window size gives the window a
  /// backing surface the renderer sizes differently from its textures,
  /// which crashes Impeller on macOS while resizing ("The texture and its
  /// descriptor disagree about its size"). The contents still scale by
  /// exactly [scale]; the window is at most half a pixel off.
  static Size windowSize(Size base, double scale) => Size(
    _side(base.width * scale),
    _side(base.height * scale),
  );

  /// The most a window side may be, and the least: a window with no area or
  /// one past what the GPU can make a texture of leaves Impeller without a
  /// render target, which it dereferences (a crash in
  /// `Canvas::SetupRenderPass` after a skin left a window enormous).
  static const double maxSide = 8192;

  static double _side(double value) =>
      value.isNaN ? 1 : value.roundToDouble().clamp(1, maxSide);

  /// The largest scale at which a window of unscaled size [base] still fits
  /// in [workArea] (or [maxScale] when the screen is unknown).
  static double limitFor(Size base, Rect? workArea) {
    if (workArea == null || base.isEmpty) return maxScale;
    final fit = min(
      workArea.width / base.width,
      workArea.height / base.height,
    );
    return fit.clamp(minScale, maxScale).toDouble();
  }
}
