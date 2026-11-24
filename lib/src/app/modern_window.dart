import "dart:async";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";

import "../skin/skin_views.dart";
import "../vis/vis_window.dart";
import "amped_shell.dart";
import "glass_blur.dart";
import "library_content.dart";
import "skinned_window.dart";
import "video_view.dart";

/// A window drawn by the active modern skin: its container's current layout
/// with per-pixel transparency, inside the usual window chrome (dragging,
/// docking, right-click menu, shortcuts).
class ModernWindowView extends StatelessWidget {
  const ModernWindowView({
    required this.shell,
    required this.window,
    super.key,
  });

  final AmpedShell shell;
  final SkinWindow window;

  @override
  Widget build(BuildContext context) {
    // The shell says when the skin's scripts start or stop.
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => window == SkinWindow.notifier
          ? _NotifierBody(shell: shell)
          : _ModernWindowBody(shell: shell, window: window),
    );
  }
}

class _ModernWindowBody extends StatelessWidget {
  const _ModernWindowBody({required this.shell, required this.window});

  final AmpedShell shell;
  final SkinWindow window;

  @override
  Widget build(BuildContext context) {
    final skin = shell.skin.wasabi;
    final container = shell.skin.modern?.container(window);
    final layout = shell.skin.modern?.layout(window);
    return SkinnedWindow(
      shell: shell,
      window: window,
      cursor: SkinCursor.normal,
      transparent: true,
      child: skin == null || container == null || layout == null
          ? const SizedBox.shrink()
          // The window can be smaller than the layout (its snap
          // adjustments leave out a closed drawer's room), so the layout
          // view takes its own size (following scripts that resize it) and
          // the window shows its top-left part.
          : GlassBlur(
              shell: shell,
              window: window,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: _ModernLayout(
                  key: ValueKey((skin, container.id, layout.id)),
                  shell: shell,
                  skin: skin,
                  container: container.id,
                  layout: layout,
                  window: window,
                ),
              ),
            ),
    );
  }
}

/// The notifier: the skin's layout on a transparent window, with none of
/// the usual window chrome (no dragging, no main menu, no shortcuts).
class _NotifierBody extends StatelessWidget {
  const _NotifierBody({required this.shell});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final skin = shell.skin.wasabi;
    final container = shell.skin.modern?.container(SkinWindow.notifier);
    final layout = shell.skin.modern?.layout(SkinWindow.notifier);
    if (skin == null || container == null || layout == null) {
      return const SizedBox.shrink();
    }
    // A click brings the player forward.
    return Opacity(
      opacity: shell.notifierFade.clamp(0.0, 1.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: shell.activateApplication,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: _ModernLayout(
              key: ValueKey((skin, container.id, layout.id)),
              shell: shell,
              skin: skin,
              container: container.id,
              layout: layout,
              window: SkinWindow.notifier,
            ),
          ),
        ),
      ),
    );
  }
}

/// The modern skin's layout, told whether its window has focus so objects
/// with an `inactivealpha` (the Amped titles) dim in the other windows.
class _ModernLayout extends StatelessWidget {
  const _ModernLayout({
    required this.shell,
    required this.skin,
    required this.container,
    required this.layout,
    required this.window,
    super.key,
  });

  final AmpedShell shell;
  final WasabiSkinData skin;
  final String container;
  final WasabiLayout layout;
  final SkinWindow window;

  @override
  Widget build(BuildContext context) {
    return WasabiLayoutView(
      skin: skin,
      layout: layout,
      host: shell.wasabiHost,
      container: container,
      scripts: shell.wasabiScripts,
      active: ActiveWindow.of(context),
      components: {
        // The Media Library, in the base skin's colours.
        "ml": LibraryContent(shell: shell),
        // Likewise the video: its own window, or a slot elsewhere.
        "video": window == SkinWindow.video
            ? VideoView(shell: shell, controls: true)
            : VideoSlot(shell: shell),
        // The vis container is the visualization's own window; elsewhere
        // (Amped Modern's drawer) it is a slot that runs the plug-in while
        // the skin shows it.
        "vis": window == SkinWindow.vis
            ? VisWindowContent(host: shell.vis, fullscreen: false)
            : _VisSlot(shell: shell),
      },
    );
  }
}

/// The visualization inside another skin window (`<windowholder
/// hold="guid:avs">`): while the skin shows it, the plug-in draws here
/// instead of in its own window.
class _VisSlot extends StatefulWidget {
  const _VisSlot({required this.shell});

  final AmpedShell shell;

  @override
  State<_VisSlot> createState() => _VisSlotState();
}

class _VisSlotState extends State<_VisSlot> {
  @override
  void initState() {
    super.initState();
    // Not while the tree is building: attaching starts the plug-in and
    // closes its window, which notifies the shell's listeners.
    scheduleMicrotask(widget.shell.visualization.attachSlot);
  }

  @override
  void dispose() {
    scheduleMicrotask(widget.shell.visualization.detachSlot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      VisWindowContent(host: widget.shell.vis, fullscreen: false);
}
