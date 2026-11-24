import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:window_dock/window_dock.dart";

import "../skin/skin_views.dart";
import "amped_shell.dart";
import "amped_shortcuts.dart";
import "main_window_scale.dart";

/// The chrome shared by every skinned the classic player window.
///
/// Renders [child] at the skin's native resolution and scales it to the UI
/// scale; makes the window draggable anywhere that is not a control
/// (`config_easymove`), with the classic player docking; toggles windowshade on a
/// title-bar double click; opens the main menu on right-click; shows the
/// skin's default cursor for the window; and wires the global keyboard
/// shortcuts.
class SkinnedWindow extends StatelessWidget {
  const SkinnedWindow({
    required this.shell,
    required this.window,
    required this.cursor,
    required this.child,
    this.transparent = false,
    super.key,
  });

  final AmpedShell shell;
  final SkinWindow window;

  /// The cursor for areas not covered by a more specific cursor zone.
  final SkinCursor cursor;

  /// The window contents, laid out at the unscaled skin size.
  final Widget child;

  /// Whether the contents draw their own per-pixel transparency (modern
  /// skins): no black backing, no `region.txt` clip and no title-bar
  /// double-click (the skin's own `dblclickaction` objects do that).
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.player, shell.skins]),
      builder: (context, _) {
        final skin = shell.skins.current.classicData;
        final scale = shell.windowState.scaleOf(window);
        // The main window scales continuously from a grip in its corner.
        final grip =
            window == SkinWindow.main &&
            !transparent &&
            !shell.isShaded(window);
        final size = shell.windowState.baseSize(window);
        final key = shell.skin.regionKey(window);
        final region = key == null || transparent ? null : skin.region(key);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: AmpedShortcuts(
            shell: shell,
            window: window,
            // A skin region (region.txt) cuts the window to its shape: the
            // outside is transparent and ignores the pointer.
            child: ClipPath(
              clipper: _RegionClipper(region, scale),
              child: ColoredBox(
                color: transparent
                    ? const Color(0x00000000)
                    : const Color(0xFF000000),
                child: WindowDragArea<SkinWindow>(
                  manager: shell.dock,
                  window: window,
                  onDoubleClick: (local) {
                    if (!transparent && local.dy / scale < 14) {
                      shell.toggleShade(window);
                    }
                  },
                  // Right-click opens the main menu on release, like
                  // WM_CONTEXTMENU.
                  child: Listener(
                    onPointerDown: (event) {
                      if (event.buttons == kSecondaryButton &&
                          !SkinSecondaryClaim.take(event.pointer)) {
                        _secondary.add(event.pointer);
                      }
                    },
                    onPointerUp: (event) {
                      if (_secondary.remove(event.pointer))
                        shell.showMainMenu();
                    },
                    child: SkinButtonScope(
                      child: MouseRegion(
                        cursor: skin.cursor(cursor),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox.fromSize(
                                size: size * scale,
                                child: Transform.scale(
                                  scale: scale,
                                  alignment: Alignment.topLeft,
                                  filterQuality: FilterQuality.none,
                                  child: OverflowBox(
                                    alignment: Alignment.topLeft,
                                    minWidth: size.width,
                                    maxWidth: size.width,
                                    minHeight: size.height,
                                    maxHeight: size.height,
                                    child: ActiveWindow(child: child),
                                  ),
                                ),
                              ),
                            ),
                            if (grip)
                              Positioned(
                                left:
                                    (size.width - MainWindowScale.grip.width) *
                                    scale,
                                top:
                                    (size.height -
                                        MainWindowScale.grip.height) *
                                    scale,
                                width: MainWindowScale.grip.width * scale,
                                height: MainWindowScale.grip.height * scale,
                                child: _MainScaleGrip(
                                  shell: shell,
                                  cursor: skin.cursor(
                                    SkinCursor.plSize,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static final Set<int> _secondary = {};
}

/// The main window's resize grip: dragging it scales the window and its
/// contents continuously, keeping the skin's proportions.
class _MainScaleGrip extends StatefulWidget {
  const _MainScaleGrip({required this.shell, required this.cursor});

  final AmpedShell shell;
  final MouseCursor cursor;

  @override
  State<_MainScaleGrip> createState() => _MainScaleGripState();
}

class _MainScaleGripState extends State<_MainScaleGrip> {
  /// The window's bottom-right corner relative to the pointer at the start
  /// of the drag.
  Offset? _grab;

  /// The pointer relative to the main window's top-left, read natively
  /// because the grip moves while the window resizes.
  Offset? _pointer() {
    final rect = widget.shell.dock.rectOf(SkinWindow.main);
    if (rect == null) return null;
    return NativeScreen.cursorPosition() - rect.topLeft;
  }

  @override
  Widget build(BuildContext context) {
    return SkinDragTarget(
      cursor: widget.cursor,
      onStart: (_) {
        final rect = widget.shell.dock.rectOf(SkinWindow.main);
        final pointer = _pointer();
        if (rect == null || pointer == null) return;
        _grab = rect.size.bottomRight(Offset.zero) - pointer;
      },
      onUpdate: (_) {
        final grab = _grab;
        final pointer = _pointer();
        if (grab == null || pointer == null) return;
        widget.shell.scaleMainTo(pointer + grab);
      },
      onEnd: (_) => _grab = null,
      child: const SizedBox.expand(),
    );
  }
}

/// Clips to a skin region scaled to the UI scale; no clip without a region.
class _RegionClipper extends CustomClipper<Path> {
  _RegionClipper(this.region, this.scale);

  final Path? region;
  final double scale;

  @override
  Path getClip(Size size) {
    final region = this.region;
    if (region == null) return Path()..addRect(Offset.zero & size);
    return region.transform(Matrix4.diagonal3Values(scale, scale, 1).storage);
  }

  @override
  bool shouldReclip(_RegionClipper oldClipper) =>
      oldClipper.region != region || oldClipper.scale != scale;
}

/// Whether the enclosing window is the active one, for title bars drawn
/// active or inactive (`draw_tbar(active)`, `config_hilite`). Rebuilds its
/// dependents when that changes.
class ActiveWindow extends StatefulWidget {
  const ActiveWindow({required this.child, super.key});

  final Widget child;

  /// Whether the window around [context] is active (true outside one).
  static bool of(BuildContext context) => WindowActivity.of(context);

  @override
  State<ActiveWindow> createState() => _ActiveWindowState();
}

class _ActiveWindowState extends State<ActiveWindow> {
  AppWindowController? _controller;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    NativeScreen.activationChanges.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppWindowController.maybeOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_update);
      _controller = controller?..addListener(_update);
    }
    _active = _isActive;
  }

  @override
  void dispose() {
    NativeScreen.activationChanges.removeListener(_update);
    _controller?.removeListener(_update);
    super.dispose();
  }

  bool get _isActive => _controller?.isActivated ?? true;

  void _update() {
    if (!mounted) return;
    final active = _isActive;
    if (active != _active) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) =>
      WindowActivity(active: _active, child: widget.child);
}
