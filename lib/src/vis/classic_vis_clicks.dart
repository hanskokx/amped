import "package:amped_vis/amped_vis.dart";

/// Tells clicks on the classic visualization from double-clicks
/// (main_mouse.cpp). A click cycles the mode at once, so a single click has
/// no delay; the second click of a double-click undoes the first one's
/// cycle and toggles the visualization plug-in instead.
class ClassicVisClicks {
  ClassicVisClicks({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const doubleClickTime = Duration(milliseconds: 500);

  final DateTime Function() _clock;
  DateTime _last = DateTime(0);
  ClassicVisMode? _before;

  /// Records a click while the mode is [current]. Returns null for a
  /// single click (cycle the mode), or, for the second click of a
  /// double-click, the mode from before the first click to restore.
  ClassicVisMode? click(ClassicVisMode current) {
    final now = _clock();
    final before = _before;
    if (before != null && now.difference(_last) < doubleClickTime) {
      _last = DateTime(0);
      _before = null;
      return before;
    }
    _last = now;
    _before = current;
    return null;
  }
}
