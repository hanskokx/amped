import "dart:math";
import "dart:ui";

/// The window docking geometry of the classic player, ported from
/// `DOCK.cpp` (`IsWindowAttached`, `SnapWindowToWindow`) and `embwnd.cpp`
/// (`SnapToScreen`).
///
/// All rects are in a global, top-left-origin logical coordinate space. The
/// functions are pure: they return new rects and never mutate their inputs.
abstract final class DockGeometry {
  /// The original `config_snaplen` default.
  static const double defaultSnapLength = 10;

  static bool _inRange(double x, double low, double high) =>
      x >= low && x <= high;

  static bool _rangesOverlap(double l1, double r1, double l2, double r2) =>
      _inRange(l1, l2, r2) ||
      _inRange(r1, l2, r2) ||
      _inRange(l2, l1, r1) ||
      _inRange(r2, l1, r1);

  /// `IsWindowAttached`: whether [a] and [b] touch edge to edge.
  ///
  /// Returns a bit set: `1` when they share a vertical seam (side by side),
  /// `2` for a horizontal seam (stacked), `0` when they do not touch. Edges
  /// must coincide exactly; the perpendicular extents must overlap (touching
  /// corners count).
  static int attachment(Rect a, Rect b) {
    var result = 0;
    if (b.right == a.left || b.left == a.right) {
      if (_rangesOverlap(a.top, a.bottom, b.top, b.bottom)) result |= 1;
    }
    if (b.bottom == a.top || b.top == a.bottom) {
      if (_rangesOverlap(a.left, a.right, b.left, b.right)) result |= 2;
    }
    return result;
  }

  /// Whether [a] and [b] touch edge to edge (see [attachment]).
  static bool isAttached(Rect a, Rect b) => attachment(a, b) != 0;

  /// `SnapWindowToWindow`: snaps [source] against [target] when its edges come
  /// within [snapLength], then aligns the parallel edges of windows that end
  /// up docked. Returns the snapped rect (same size as [source]).
  static Rect snapToWindow(
    Rect source,
    Rect target, {
    double snapLength = defaultSnapLength,
  }) {
    bool closeTo(double x, double t) =>
        _inRange(x, t - snapLength, t + snapLength);
    var left = source.left;
    var top = source.top;
    final width = source.width;
    final height = source.height;

    // Dock above/below when the horizontal extents overlap.
    if (_rangesOverlap(target.left, target.right, left, left + width)) {
      if (closeTo(top, target.bottom)) {
        top = target.bottom;
      } else if (closeTo(top + height, target.top)) {
        top = target.top - height;
      }
    }

    // Dock left/right when the vertical extents overlap.
    if (_rangesOverlap(target.top, target.bottom, top, top + height)) {
      if (closeTo(left + width, target.left)) {
        left = target.left - width;
      } else if (closeTo(left, target.right)) {
        left = target.right;
      }
    }

    // Side by side: align top or bottom edges.
    if (left + width == target.left || left == target.right) {
      if (closeTo(top, target.top)) {
        top = target.top;
      } else if (closeTo(top + height, target.bottom)) {
        top = target.bottom - height;
      }
    }

    // Stacked: align left or right edges.
    if (top + height == target.top || top == target.bottom) {
      if (closeTo(left, target.left)) {
        left = target.left;
      } else if (closeTo(left + width, target.right)) {
        left = target.right - width;
      }
    }

    return Rect.fromLTWH(left, top, width, height);
  }

  /// `SnapToScreen`: magnetizes [rect] to the edges of [workArea] when within
  /// [snapLength] (exclusive, like the original).
  static Rect snapToScreen(
    Rect rect,
    Rect workArea, {
    double snapLength = defaultSnapLength,
  }) {
    var left = rect.left;
    var top = rect.top;
    final width = rect.width;
    final height = rect.height;
    if (left < workArea.left + snapLength &&
        left > workArea.left - snapLength) {
      left = workArea.left;
    }
    if (top < workArea.top + snapLength && top > workArea.top - snapLength) {
      top = workArea.top;
    }
    if (left + width > workArea.right - snapLength &&
        left + width < workArea.right + snapLength) {
      left = workArea.right - width;
    }
    if (top + height > workArea.bottom - snapLength &&
        top + height < workArea.bottom + snapLength) {
      top = workArea.bottom - height;
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  /// `WindowTracker::autoDock` for a resize (Wasabi's `resize.cpp`): the
  /// moving edges of [rect] ([left], [top], [right], [bottom]) snap to the
  /// edges of [workArea] and of [others] within [snapLength] (exclusive),
  /// while the other edges stay put. An edge snaps to a window's facing edge
  /// (side by side) or to its matching edge (flush), but a snap that leaves
  /// [rect] not touching that window or work area is undone, so only
  /// neighbours pull. Later windows in [others] win over earlier ones.
  static Rect snapResize(
    Rect rect, {
    Iterable<Rect> others = const [],
    Rect? workArea,
    bool left = false,
    bool top = false,
    bool right = false,
    bool bottom = false,
    double snapLength = defaultSnapLength,
  }) {
    bool closeTo(double x, double t) =>
        x > t - snapLength && x < t + snapLength;
    var l = rect.left;
    var t = rect.top;
    var r = rect.right;
    var b = rect.bottom;
    void snapTo(Rect target, {required bool screen}) {
      final (ol, ot, or, ob) = (l, t, r, b);
      var doneX = false;
      var doneY = false;
      if (left && closeTo(l, target.left)) {
        l = target.left;
        doneX = true;
      }
      if (!screen && right && !doneX && closeTo(r, target.left)) {
        r = target.left;
        doneX = true;
      }
      if (top && closeTo(t, target.top)) {
        t = target.top;
        doneY = true;
      }
      if (!screen && bottom && !doneY && closeTo(b, target.top)) {
        b = target.top;
        doneY = true;
      }
      if (right && !doneX && closeTo(r, target.right)) {
        r = target.right;
        doneX = true;
      }
      if (!screen && left && !doneX && closeTo(l, target.right)) {
        l = target.right;
        doneX = true;
      }
      if (bottom && !doneY && closeTo(b, target.bottom)) {
        b = target.bottom;
        doneY = true;
      }
      if (!screen && top && !doneY && closeTo(t, target.bottom)) {
        t = target.bottom;
        doneY = true;
      }
      if (!_touches(Rect.fromLTRB(l, t, r, b), target)) {
        (l, t, r, b) = (ol, ot, or, ob);
      }
    }

    if (workArea != null) snapTo(workArea, screen: true);
    for (final other in others) {
      snapTo(other, screen: false);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// `WindowTracker::touches`: whether an edge of [a] lies on the line of a
  /// parallel edge of [b] where their extents overlap.
  static bool _touches(Rect a, Rect b) {
    if (a.left == b.right ||
        a.right == b.left ||
        a.right == b.right ||
        a.left == b.left) {
      if (a.bottom >= b.top && a.top <= b.bottom) return true;
    }
    if (a.top == b.bottom ||
        a.bottom == b.top ||
        a.bottom == b.bottom ||
        a.top == b.top) {
      if (a.right >= b.left && a.left <= b.right) return true;
    }
    return false;
  }

  /// `getViewport`: the work area of the monitor showing [rect] — the one it
  /// overlaps most, else the nearest one. Returns `null` when [workAreas] is
  /// empty.
  static Rect? workAreaFor(Rect rect, List<Rect> workAreas) {
    Rect? best;
    var bestArea = 0.0;
    for (final area in workAreas) {
      final overlap = area.intersect(rect);
      if (overlap.width <= 0 || overlap.height <= 0) continue;
      final size = overlap.width * overlap.height;
      if (size > bestArea) {
        bestArea = size;
        best = area;
      }
    }
    if (best != null) return best;
    var bestDistance = double.infinity;
    for (final area in workAreas) {
      final distance = (area.center - rect.center).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = area;
      }
    }
    return best;
  }

  /// [rect] moved the least that puts all of it inside the work area of the
  /// monitor it is on (or nearest to): a window past the bottom-left corner
  /// ends with its bottom and left edges on the monitor's. A window bigger
  /// than the work area has its top-left corner at the work area's, so the
  /// title bar stays reachable. [workAreas] empty leaves [rect] as it is.
  static Rect fitInto(Rect rect, List<Rect> workAreas) {
    final area = workAreaFor(rect, workAreas);
    if (area == null) return rect;
    final left = rect.left.clamp(
      area.left,
      max(area.left, area.right - rect.width),
    );
    final top = rect.top.clamp(
      area.top,
      max(area.top, area.bottom - rect.height),
    );
    return Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      rect.width,
      rect.height,
    );
  }

  /// Whether [moved]'s edge was docked to [anchor]'s bottom (`edge == 0`) or
  /// right (`edge == 1`) edge, as tested by `doMyDirtyShitholeDockingShit`
  /// (Set.cpp). Uses half-open overlap, unlike [attachment].
  static bool isDockedToEdge(Rect moved, Rect anchor, int edge) {
    bool overlap(double l1, double r1, double l2, double r2) =>
        (l1 >= l2 && l1 < r2) ||
        (r1 > l2 && r1 <= r2) ||
        (l2 >= l1 && l2 < r1) ||
        (r2 > l1 && r2 <= r1);
    if (edge == 0) {
      return moved.top == anchor.bottom &&
          overlap(moved.left, moved.right, anchor.left, anchor.right);
    }
    return moved.left == anchor.right &&
        overlap(moved.top, moved.bottom, anchor.top, anchor.bottom);
  }
}
