import "dart:async";
import "dart:ui";

import "package:flutter/foundation.dart";
import "package:flutter/painting.dart" show EdgeInsets;

import "dock_geometry.dart";
import "native_window.dart";

/// Applies a window's new rect natively.
typedef DockMoveCallback<K> = void Function(K id, Rect rect);

/// Docks and snaps a set of top-level windows the way the classic player does.
///
/// * Dragging the [primary] window carries every window attached to it
///   (directly or through a chain of attached windows) and snaps the group to
///   the screen edges and to the windows left behind (`Ui.cpp` `do_titlebar`).
/// * Dragging any other window moves it alone and snaps it to the screen and
///   to every other visible window, so dragging a docked window undocks it
///   (`Equi.cpp`/`Peui.cpp` `do_titlebar` + `SnapWindowToAllWindows`).
/// * Resizing a window keeps the windows docked to its bottom and right edges
///   pinned to them, recursively (`Set.cpp` `doMyDirtyShitholeDockingShit`).
///
/// Holding Shift inverts snapping for the duration of a drag, like the
/// original. Windows are identified by keys of type [K]; their rects live in a
/// global top-left logical coordinate space.
class DockManager<K extends Object> extends ChangeNotifier {
  DockManager({
    required this.primary,
    this.snapEnabled = true,
    this.snapLength = DockGeometry.defaultSnapLength,
    this.keepOnScreen = true,
    List<Rect> Function()? workAreas,
    this.onMove,
  }) : _workAreas = workAreas ?? NativeScreen.workAreas;

  /// The window whose drag moves the whole docked group (the classic player's main
  /// window).
  final K primary;

  /// Whether windows snap to each other and to the screen (`config_snap`).
  bool snapEnabled;

  /// The snap distance in logical pixels (`config_snaplen`).
  double snapLength;

  /// Whether windows snap to the work-area edges (`config_keeponscreen`).
  bool keepOnScreen;

  final List<Rect> Function() _workAreas;

  /// Called after a window's rect changes, in addition to moving its
  /// registered [NativeWindow].
  final DockMoveCallback<K>? onMove;

  final Map<K, _DockEntry> _entries = {};

  final Map<K, EdgeInsets> _transparentEdges = {};

  /// How much of [id]'s rect, along each edge, is see-through: the window
  /// may be pushed that far past the screen's edge so its visible part
  /// reaches it (a skin drawn below a transparent strip).
  void setTransparentEdges(K id, EdgeInsets edges) {
    if (edges == EdgeInsets.zero) {
      _transparentEdges.remove(id);
    } else {
      _transparentEdges[id] = edges;
    }
  }

  /// [rect] with [id]'s transparent edges cut off, to line up with the
  /// screen; [restore] puts them back on a rect lined up that way.
  Rect _visible(K? id, Rect rect) {
    final edges = id == null ? null : _transparentEdges[id];
    return edges == null ? rect : edges.deflateRect(rect);
  }

  Rect _withEdges(K? id, Rect visible) {
    final edges = id == null ? null : _transparentEdges[id];
    return edges == null ? visible : edges.inflateRect(visible);
  }

  /// Every registered window, in registration order.
  Iterable<K> get windows => _entries.keys;

  /// The current rect of [id], or `null` when it is not registered.
  Rect? rectOf(K id) => _entries[id]?.rect;

  /// Whether [id] is registered and visible.
  bool isVisible(K id) => _entries[id]?.visible ?? false;

  /// The native window registered for [id].
  NativeWindow? nativeWindowOf(K id) => _entries[id]?.window;

  /// A snapshot of every registered window's rect.
  Map<K, Rect> get rects => {
    for (final entry in _entries.entries) entry.key: entry.value.rect,
  };

  /// Registers (or re-registers) [id] at [rect]. When [window] is given,
  /// moves are applied to it directly; otherwise the `onMove` callback passed
  /// to the constructor is used.
  void register(
    K id, {
    required Rect rect,
    NativeWindow? window,
    bool visible = true,
  }) {
    _entries[id] = _DockEntry(rect: rect, window: window, visible: visible);
    _apply(id, rect, force: true);
  }

  /// Forgets [id] entirely.
  void unregister(K id) {
    _entries.remove(id);
  }

  /// Whether [id] docks to other windows and they to it (a layout's
  /// `nodock="1"` turns that off: it still snaps to the screen).
  void setDockable(K id, bool dockable) {
    _entries[id]?.dockable = dockable;
  }

  /// The places on [id]'s window that dock to the point of the same id on
  /// another window, as offsets from its top left (a skin's `<snappoint>`s).
  void setSnapPoints(K id, List<DockSnapPoint> points) {
    _entries[id]?.snapPoints = points;
  }

  /// Marks [id] shown or hidden. Hidden windows keep their rect, are never
  /// snapped against, and do not chain attachments, but still follow a
  /// primary drag when attached to it (as in the original).
  void setVisible(K id, bool visible) {
    final entry = _entries[id];
    if (entry == null || entry.visible == visible) return;
    entry.visible = visible;
    if (visible) {
      entry.window?.setPosition(entry.rect.topLeft);
      entry.window?.show();
      // Resizes while hidden were held back (see `_apply`): size it now that
      // it can draw.
      entry.window?.setFrame(entry.rect);
    } else {
      entry.window?.hide();
    }
    notifyListeners();
  }

  /// The windows attached to [id], directly or through other visible windows
  /// (not including [id] itself).
  Set<K> attachedTo(K id) => _attachedTo(id);

  /// Moves and resizes [id] to [rect] without snapping or re-pinning.
  void setRect(K id, Rect rect) {
    if (!_entries.containsKey(id)) return;
    _apply(id, rect);
    notifyListeners();
  }

  /// Moves [id] to [topLeft] without snapping (e.g. restoring a saved rect).
  void moveTo(K id, Offset topLeft) {
    final entry = _entries[id];
    if (entry == null) return;
    final rect = topLeft & entry.rect.size;
    _apply(id, rect);
    notifyListeners();
  }

  /// Resizes [id] to [size], keeping its top-left corner, and re-pins the
  /// windows docked to its bottom and right edges, unless [repin] is false
  /// (the neighbours then stay where they are).
  void resize(K id, Size size, {bool repin = true}) {
    final entry = _entries[id];
    if (entry == null || entry.rect.size == size) return;
    final grown = entry.rect.topLeft & size;
    final moves = <K, Rect>{};
    if (repin) _repin(id, grown, moves, {id});
    // A window that grows past the screen's edge, or that was already off
    // it, ends up on the screen with its edges on the screen's.
    final newRect = _onScreen(grown, id);
    _apply(id, newRect);
    for (final move in moves.entries) {
      _apply(move.key, _onScreen(move.value, move.key));
    }
    notifyListeners();
  }

  /// [rect] moved onto the screen it is on, when [keepOnScreen].
  Rect _onScreen(Rect rect, [K? id]) => keepOnScreen
      ? _withEdges(id, DockGeometry.fitInto(_visible(id, rect), _workAreas()))
      : rect;

  /// `doMyDirtyShitholeDockingShit`: windows docked to [id]'s old bottom
  /// (edge 0) or right (edge 1) edge move to the new edge, recursively.
  void _repin(K id, Rect newRect, Map<K, Rect> moves, Set<K> visited) {
    final oldRect = _entries[id]!.rect;
    for (var edge = 0; edge < 2; edge++) {
      final diff = edge == 0
          ? newRect.bottom - oldRect.bottom
          : newRect.right - oldRect.right;
      if (diff == 0) continue;
      for (final other in _entries.entries) {
        if (visited.contains(other.key)) continue;
        final otherRect = other.value.rect;
        if (!DockGeometry.isDockedToEdge(otherRect, oldRect, edge)) continue;
        final moved = edge == 0
            ? Rect.fromLTWH(
                otherRect.left,
                newRect.bottom,
                otherRect.width,
                otherRect.height,
              )
            : Rect.fromLTWH(
                newRect.right,
                otherRect.top,
                otherRect.width,
                otherRect.height,
              );
        moves[other.key] = moved;
        visited.add(other.key);
        if (other.value.snappable) {
          _repin(other.key, moved, moves, visited);
        }
      }
    }
  }

  // --- Dragging --------------------------------------------------------------

  _DragSession<K>? _drag;

  /// Whether a drag is in progress.
  /// The size [id] should take when a resize asks for [size] (keeping its
  /// top-left corner): the edges that move snap to the screen and to the
  /// other visible windows ([DockGeometry.snapResize]). An edge moves when
  /// [size] differs from the current size along it. [invertSnap] (Shift)
  /// flips [snapEnabled].
  Size snapResize(K id, Size size, {bool invertSnap = false}) {
    final entry = _entries[id];
    if (entry == null || snapEnabled == invertSnap) return size;
    final rect = entry.rect.topLeft & size;
    final area = keepOnScreen
        ? DockGeometry.workAreaFor(rect, _workAreas())
        : null;
    final snapped = DockGeometry.snapResize(
      rect,
      others: [
        for (final other in _entries.entries)
          if (other.key != id && other.value.snappable && entry.dockable)
            other.value.rect,
      ],
      workArea: area,
      right: size.width != entry.rect.width,
      bottom: size.height != entry.rect.height,
      snapLength: snapLength,
    );
    return snapped.size;
  }

  bool get isDragging => _drag != null;

  /// Starts dragging [id] with the pointer at [cursor] (global coordinates).
  ///
  /// When [id] is the [primary] window, the set of windows attached to it is
  /// frozen now, as the original does on mouse-down. [invertSnap] (Shift)
  /// flips [snapEnabled] for this decision.
  void beginDrag(K id, Offset cursor, {bool invertSnap = false}) {
    final entry = _entries[id];
    if (entry == null) return;
    final attached = <K>{};
    if (id == primary && (snapEnabled != invertSnap)) {
      attached.addAll(_attachedTo(id));
    }
    _drag = _DragSession(id, cursor - entry.rect.topLeft, attached);
  }

  /// Moves the dragged window so the pointer keeps its grab offset.
  void updateDrag(Offset cursor, {bool invertSnap = false}) {
    final drag = _drag;
    if (drag == null) return;
    final snap = snapEnabled != invertSnap;
    if (drag.id == primary) {
      _dragPrimary(drag, cursor, snap);
    } else {
      _dragSingle(drag, cursor, snap);
    }
  }

  /// Ends the current drag.
  void endDrag() {
    if (_drag == null) return;
    _drag = null;
    notifyListeners();
  }

  /// The transitive closure of windows touching [id] (Ui.cpp mouse-down).
  /// Hidden windows can be attached but never extend the chain.
  Set<K> _attachedTo(K id) {
    final attached = <K>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final source in _entries.entries) {
        if (!attached.contains(source.key) || !source.value.snappable) continue;
        for (final target in _entries.entries) {
          if (attached.contains(target.key) || !target.value.dockable) continue;
          if (DockGeometry.isAttached(source.value.rect, target.value.rect) ||
              _pointsCoincide(source.value, target.value)) {
            attached.add(target.key);
            changed = true;
          }
        }
      }
    }
    return attached..remove(id);
  }

  /// Whether a snap point of [a] lies exactly on the one of the same id on
  /// [b]: the windows are docked through them (`SnapPoint::match`).
  bool _pointsCoincide(_DockEntry a, _DockEntry b) {
    for (final p in a.snapPoints) {
      for (final q in b.snapPoints) {
        if (p.id.toLowerCase() != q.id.toLowerCase()) continue;
        if ((a.rect.topLeft + p.offset - (b.rect.topLeft + q.offset))
                .distanceSquared <
            1) {
          return true;
        }
      }
    }
    return false;
  }

  /// Moves [rect] (of window [id]) so a snap point of its lies on the point
  /// of the same id of a visible window that is not [except], when within 10
  /// pixels, each axis on its own.
  Rect _snapPoints(K id, Rect rect, Set<K> except) {
    final mine = _entries[id]?.snapPoints ?? const <DockSnapPoint>[];
    if (mine.isEmpty) return rect;
    double? dx;
    double? dy;
    for (final other in _entries.entries) {
      if (other.key == id ||
          except.contains(other.key) ||
          !other.value.snappable) {
        continue;
      }
      for (final p in mine) {
        for (final q in other.value.snapPoints) {
          if (p.id.toLowerCase() != q.id.toLowerCase()) continue;
          final here = rect.topLeft + p.offset;
          final there = other.value.rect.topLeft + q.offset;
          if (dx == null && (here.dx - there.dx).abs() < 10) {
            dx = there.dx - here.dx;
          }
          if (dy == null && (here.dy - there.dy).abs() < 10) {
            dy = there.dy - here.dy;
          }
        }
      }
    }
    return rect.shift(Offset(dx ?? 0, dy ?? 0));
  }

  Rect _snapToScreen(Rect rect, [K? id]) {
    if (!keepOnScreen) return rect;
    final visible = _visible(id, rect);
    final area = DockGeometry.workAreaFor(visible, _workAreas());
    if (area == null) return rect;
    return _withEdges(
      id,
      DockGeometry.snapToScreen(visible, area, snapLength: snapLength),
    );
  }

  void _dragSingle(_DragSession<K> drag, Offset cursor, bool snap) {
    final entry = _entries[drag.id]!;
    var rect = (cursor - drag.grab) & entry.rect.size;
    if (snap) {
      // SnapWindowToAllWindows.
      rect = _snapToScreen(rect, drag.id);
      for (final other in _entries.entries) {
        if (other.key == drag.id || !other.value.snappable || !entry.dockable) {
          continue;
        }
        rect = DockGeometry.snapToWindow(
          rect,
          other.value.rect,
          snapLength: snapLength,
        );
      }
      rect = _snapPoints(drag.id, rect, const {});
    }
    _apply(drag.id, rect);
  }

  void _dragPrimary(_DragSession<K> drag, Offset cursor, bool snap) {
    final attached = drag.attached;
    final rects = {
      for (final entry in _entries.entries) entry.key: entry.value.rect,
    };
    void shiftGroup(Offset delta, {K? except}) {
      rects[primary] = rects[primary]!.shift(delta);
      for (final id in attached) {
        if (id != except) rects[id] = rects[id]!.shift(delta);
      }
    }

    final before = rects[primary]!;
    var main = (cursor - drag.grab) & before.size;

    // Snap the main window to the screen and to the non-attached windows.
    if (snap) {
      main = _snapToScreen(main, primary);
      for (final other in _entries.entries) {
        if (other.key == primary || attached.contains(other.key)) continue;
        if (!other.value.snappable) continue;
        main = DockGeometry.snapToWindow(
          main,
          other.value.rect,
          snapLength: snapLength,
        );
      }
      main = _snapPoints(primary, main, attached);
    }
    rects[primary] = before;
    shiftGroup(main.topLeft - before.topLeft);

    if (snap) {
      if (keepOnScreen) {
        // Dock the attached windows to the screen edges, carrying the group.
        for (final id in attached) {
          if (!_entries[id]!.visible) continue;
          final old = rects[id]!;
          final delta = _snapToScreen(old, id).topLeft - old.topLeft;
          if (delta == Offset.zero) continue;
          rects[id] = old.shift(delta);
          shiftGroup(delta, except: id);
        }
        final old = rects[primary]!;
        shiftGroup(_snapToScreen(old, primary).topLeft - old.topLeft);
      }

      // Dock the attached windows to the windows left behind.
      for (final target in _entries.entries) {
        if (target.key == primary || attached.contains(target.key)) continue;
        if (!target.value.snappable) continue;
        for (final id in attached) {
          final old = rects[id]!;
          final snapped = DockGeometry.snapToWindow(
            old,
            target.value.rect,
            snapLength: snapLength,
          );
          final delta = snapped.topLeft - old.topLeft;
          if (delta != Offset.zero) shiftGroup(delta);
        }
      }
    }

    _apply(primary, rects[primary]!);
    for (final id in attached) {
      _apply(id, rects[id]!);
    }
  }

  bool _flushScheduled = false;
  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  /// The least time between native resizes. Each one waits for the engine to
  /// draw at the new size (and gives up after a second), so resizes issued
  /// back to back while the pointer moves piled up and stalled; spaced out,
  /// each finds the engine idle, and the latest size wins.
  static const Duration _flushGap = Duration(milliseconds: 40);

  void _scheduleFrameFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    final wait = _flushGap - DateTime.now().difference(_lastFlush);
    Timer(wait.isNegative ? Duration.zero : wait, () {
      _flushScheduled = false;
      // One window at a time: each native resize runs the platform loop until
      // its view has drawn, and resizing every window of the app back to back
      // (the double-size toggle) crashed the raster thread. The rest follow
      // one gap apart.
      for (final entry in _entries.values) {
        if (!entry.framePending) continue;
        entry.framePending = false;
        _lastFlush = DateTime.now();
        if (entry.visible) entry.window?.setFrame(entry.rect);
        _lastFlush = DateTime.now();
        break;
      }
      if (_entries.values.any((e) => e.framePending)) _scheduleFrameFlush();
    });
  }

  void _apply(K id, Rect rect, {bool force = false}) {
    final entry = _entries[id];
    if (entry == null) return;
    final old = entry.rect;
    entry.rect = rect;
    if (!force && old == rect) return;
    final window = entry.window;
    // A hidden window has no drawable surface, and resizing its Flutter view
    // races with the raster thread (an intermittent Impeller crash when a
    // skin change resized every window): it is sized when shown instead.
    if (window != null && entry.visible) {
      if (force) {
        entry.framePending = false;
        window.setFrame(rect);
      } else if (old.size != rect.size) {
        // Resizing a Flutter view runs the platform run loop until the
        // engine has drawn a frame at the new size. Doing that from inside a
        // pointer handler (a resize drag) re-enters the engine and crashed
        // the raster thread, so the native resize waits for the handler to
        // return; several resizes in a row coalesce into one.
        entry.framePending = true;
        _scheduleFrameFlush();
      } else if (entry.framePending) {
        // Keep the order: the pending frame carries the new position.
      } else {
        window.setPosition(rect.topLeft);
      }
    }
    onMove?.call(id, rect);
  }
}

/// A place on a window that docks to the same-named place on another
/// (Wasabi's `SnapPoint`).
class DockSnapPoint {
  const DockSnapPoint(this.id, this.offset);

  final String id;

  /// From the window's top left.
  final Offset offset;
}

class _DockEntry {
  _DockEntry({required this.rect, required this.visible, this.window});

  /// Whether other windows may snap to this one (`nodock` turns it off).
  bool dockable = true;

  /// The skin's snap points on this window.
  List<DockSnapPoint> snapPoints = const [];

  /// Whether it takes part in docking: shown, and not `nodock`.
  bool get snappable => visible && dockable;

  /// A native resize is waiting to be applied (see `_scheduleFrameFlush`).
  bool framePending = false;
  Rect rect;
  bool visible;
  final NativeWindow? window;
}

class _DragSession<K> {
  _DragSession(this.id, this.grab, this.attached);

  final K id;
  final Offset grab;
  final Set<K> attached;
}
