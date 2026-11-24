import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "classic_host.dart" show SkinSecondaryClaim;

/// Lets a control keep the window from being dragged by a press that starts
/// on it. Set once by the app (e.g. to `WindowDragArea.claimPointer`).
abstract final class SkinPointerClaim {
  static void Function(PointerDownEvent event)? claim;
}

/// Keeps a press anywhere inside [child] from dragging the window.
///
/// Windows move when dragged from anywhere that is not a control
/// (`config_easymove`), and each control has to claim its presses (see
/// [SkinPointerClaim]). That is easy to forget for a list, a scrollbar or a
/// text field. Wrap an area whose presses are all its own in this instead;
/// the embedded windows' content is wrapped in it by default. It also keeps
/// a right-click from opening the window's main menu, so the content can show
/// its own.
class SkinNoWindowDrag extends StatelessWidget {
  const SkinNoWindowDrag({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      SkinPointerClaim.claim?.call(event);
      if (event.buttons == kSecondaryButton) SkinSecondaryClaim.claim(event);
    },
    child: child,
  );
}

/// Tracks the mouse "capture" for the skin buttons inside one window, the way
/// the classic player's window procedures do.
///
/// A press that starts on any [SkinButton] captures the mouse for the whole
/// group: while the button is held, whichever button is under the pointer is
/// drawn pressed, and releasing over a button activates *that* button — so
/// you can press Play, slide over to Stop and release to stop. Releasing away
/// from every button does nothing.
///
/// The scope also holds the cursor while a [SkinDragTarget] (slider,
/// scrollbar, resize grip) is dragged: like a Win32 mouse capture, the drag's
/// cursor stays until the button is released, wherever the pointer goes in
/// the window.
///
/// Place one scope at the root of each window, above every [SkinButton].
class SkinButtonScope extends StatefulWidget {
  const SkinButtonScope({required this.child, super.key});

  final Widget child;

  static SkinButtonScopeState? _of(BuildContext context) =>
      context.findAncestorStateOfType<SkinButtonScopeState>();

  @override
  State<SkinButtonScope> createState() => SkinButtonScopeState();
}

class SkinButtonScopeState extends State<SkinButtonScope> {
  /// The global pointer position while a button press is captured.
  final ValueNotifier<Offset?> pressPosition = ValueNotifier(null);

  /// The cursor held for the window while a drag control is pressed.
  final ValueNotifier<MouseCursor?> _heldCursor = ValueNotifier(null);

  final Set<_SkinButtonState> _buttons = {};
  int? _pointer;

  void _begin(PointerDownEvent event) {
    _pointer = event.pointer;
    pressPosition.value = event.position;
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer == _pointer) pressPosition.value = event.position;
  }

  void _onUp(PointerUpEvent event) {
    _heldCursor.value = null;
    if (event.pointer != _pointer) return;
    _pointer = null;
    pressPosition.value = null;
    for (final button in _buttons) {
      if (button.contains(event.position)) {
        button.fire();
        break;
      }
    }
  }

  void _onCancel(PointerCancelEvent event) {
    _heldCursor.value = null;
    if (event.pointer != _pointer) return;
    _pointer = null;
    pressPosition.value = null;
  }

  @override
  void dispose() {
    pressPosition.dispose();
    _heldCursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          // While a drag holds the cursor, a window-wide region shows it. A
          // drag's own events keep going to the control that was pressed, so
          // the region only affects which cursor is shown.
          ValueListenableBuilder<MouseCursor?>(
            valueListenable: _heldCursor,
            builder: (context, cursor, _) => cursor == null
                ? const SizedBox.shrink()
                : Positioned.fill(child: MouseRegion(cursor: cursor)),
          ),
        ],
      ),
    );
  }
}

/// A skin bitmap button with classic Win32 capture semantics (see
/// [SkinButtonScope]).
///
/// Draws [src] from [image], or [pressedSrc] while pressed. Use [builder]
/// instead for buttons whose pressed look is not a single crop.
class SkinButton extends StatefulWidget {
  const SkinButton({
    required this.onPressed,
    this.image,
    this.src,
    this.pressedSrc,
    this.builder,
    this.cursor = MouseCursor.defer,
    this.onPressedChanged,
    this.size,
    super.key,
  }) : assert(
         builder != null || (image != null && src != null),
         "Provide either a builder or an image and src",
       );

  final ui.Image? image;
  final Rect? src;
  final Rect? pressedSrc;

  /// Builds the button for the given pressed state (overrides [src]).
  final Widget Function(BuildContext context, bool pressed)? builder;

  /// Called when the press is released over this button.
  final VoidCallback? onPressed;

  /// Called whenever this button's pressed look changes (e.g. to show help
  /// text in the song title while a clutterbar button is held).
  final ValueChanged<bool>? onPressedChanged;

  final MouseCursor cursor;

  /// The hit area; defaults to the size of [src].
  final Size? size;

  @override
  State<SkinButton> createState() => _SkinButtonState();
}

class _SkinButtonState extends State<SkinButton> {
  SkinButtonScopeState? _scope;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SkinButtonScope._of(context);
    if (scope != _scope) {
      _scope?._buttons.remove(this);
      _scope?.pressPosition.removeListener(_update);
      _scope = scope;
      _scope?._buttons.add(this);
      _scope?.pressPosition.addListener(_update);
    }
  }

  @override
  void dispose() {
    _scope?._buttons.remove(this);
    _scope?.pressPosition.removeListener(_update);
    super.dispose();
  }

  bool contains(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    return (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  void fire() => widget.onPressed?.call();

  void _update() {
    final position = _scope?.pressPosition.value;
    final pressed = position != null && contains(position);
    if (pressed == _pressed) return;
    setState(() => _pressed = pressed);
    widget.onPressedChanged?.call(pressed);
  }

  void _onDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    SkinPointerClaim.claim?.call(event);
    _scope?._begin(event);
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.src;
    final size = widget.size ?? src?.size;
    final Widget content;
    if (widget.builder != null) {
      content = widget.builder!(context, _pressed);
    } else {
      content = CustomPaint(
        size: size!,
        painter: _CropPainter(
          widget.image!,
          _pressed ? (widget.pressedSrc ?? src!) : src!,
        ),
      );
    }
    return MouseRegion(
      cursor: widget.cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        child: size == null
            ? content
            : SizedBox.fromSize(size: size, child: content),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.image, this.src);

  final ui.Image image;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.src != src;
}

/// A press-and-drag control: reports the pointer's local position on press,
/// while dragging (anywhere, even outside the control), and on release. Its
/// [cursor] is held for the whole window until release (see
/// [SkinButtonScope]).
///
/// The building block for skin sliders and scrollbars, which all follow the
/// same capture pattern in the original (`do_volbar`, `do_posbar`, ...).
class SkinDragTarget extends StatelessWidget {
  const SkinDragTarget({
    required this.child,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.cursor = MouseCursor.defer,
    super.key,
  });

  final ValueChanged<Offset>? onStart;
  final ValueChanged<Offset>? onUpdate;
  final ValueChanged<Offset>? onEnd;
  final MouseCursor cursor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          SkinPointerClaim.claim?.call(event);
          if (cursor != MouseCursor.defer) {
            SkinButtonScope._of(context)?._heldCursor.value = cursor;
          }
          onStart?.call(event.localPosition);
        },
        onPointerMove: (event) => onUpdate?.call(event.localPosition),
        onPointerUp: (event) => onEnd?.call(event.localPosition),
        onPointerCancel: (event) => onEnd?.call(event.localPosition),
        child: child,
      ),
    );
  }
}
