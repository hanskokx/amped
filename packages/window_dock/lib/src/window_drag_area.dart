import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "dock_manager.dart";
import "native_window.dart";

/// Makes [child] drag its window through a [DockManager], so the move snaps
/// and docks like the classic player.
///
/// A press anywhere in [child] starts a drag unless a descendant control
/// claimed the pointer first with [WindowDragArea.claimPointer] (call it from
/// the control's `Listener.onPointerDown`; descendants receive pointer events
/// before this area does). Set [hitTest] to restrict dragging to part of the
/// area (e.g. a title bar). The pointer position is read natively on every
/// move, so the window tracks the cursor exactly even though the window — and
/// with it the local coordinate space — moves under the pointer.
///
/// Holding Shift inverts snapping, as in the original.
class WindowDragArea<K extends Object> extends StatefulWidget {
  const WindowDragArea({
    required this.manager,
    required this.window,
    required this.child,
    this.hitTest,
    this.onDoubleClick,
    this.onDragStart,
    this.onDragEnd,
    super.key,
  });

  final DockManager<K> manager;

  /// The window this area drags.
  final K window;

  /// Whether a press at a local position may start a drag. Defaults to the
  /// whole area.
  final bool Function(Offset localPosition)? hitTest;

  /// Called on the second press of a double click, with its local position.
  final ValueChanged<Offset>? onDoubleClick;

  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  final Widget child;

  static final Set<int> _claimed = {};

  /// Prevents the press [event] from starting a window drag. Controls call this
  /// from `onPointerDown` so pressing them never moves the window.
  static void claimPointer(PointerDownEvent event) =>
      _claimed.add(event.pointer);

  @override
  State<WindowDragArea<K>> createState() => _WindowDragAreaState<K>();
}

class _WindowDragAreaState<K extends Object> extends State<WindowDragArea<K>> {
  int? _pointer;
  Duration? _lastDownTime;
  Offset? _lastDownPosition;

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  void _onDown(PointerDownEvent event) {
    final claimed = WindowDragArea._claimed.remove(event.pointer);
    if (event.buttons != kPrimaryButton) return;
    final isDouble =
        _lastDownTime != null &&
        event.timeStamp - _lastDownTime! < kDoubleTapTimeout &&
        (event.position - _lastDownPosition!).distance < kDoubleTapSlop;
    _lastDownTime = isDouble ? null : event.timeStamp;
    _lastDownPosition = event.position;
    if (claimed) return;
    if (widget.hitTest != null && !widget.hitTest!(event.localPosition)) return;
    if (isDouble) widget.onDoubleClick?.call(event.localPosition);
    _pointer = event.pointer;
    widget.manager.beginDrag(
      widget.window,
      NativeScreen.cursorPosition(),
      invertSnap: _shift,
    );
    widget.onDragStart?.call();
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    widget.manager.updateDrag(
      NativeScreen.cursorPosition(),
      invertSnap: _shift,
    );
  }

  void _onEnd(PointerEvent event) {
    WindowDragArea._claimed.remove(event.pointer);
    if (event.pointer != _pointer) return;
    _pointer = null;
    widget.manager.endDrag();
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: widget.child,
    );
  }
}
