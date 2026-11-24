import "dart:async";

import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "amped_dialog.dart";
import "amped_shell.dart";
import "cast_button.dart";
import "fullscreen_video_controls.dart";
import "video_view.dart";

/// The video filling the screen, with Plex-style controls that fade in when
/// the mouse moves and out when it rests. Space pauses and resumes, Escape
/// or a double-click leaves.
class FullscreenVideo extends StatefulWidget {
  const FullscreenVideo({required this.shell, super.key});

  final AmpedShell shell;

  /// How long the controls stay after the mouse last moved.
  static const Duration idleTime = Duration(seconds: 3);

  @override
  State<FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<FullscreenVideo> {
  Timer? _hide;
  bool _shown = true;
  bool _overControls = false;
  VideoPicker _picker = VideoPicker.none;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// Shows the controls and starts the wait to hide them.
  void _wake() {
    _hide?.cancel();
    _hide = Timer(FullscreenVideo.idleTime, () {
      if (_overControls || _picker != VideoPicker.none || !mounted) return;
      setState(() => _shown = false);
    });
    if (!_shown) setState(() => _shown = true);
  }

  void _pick(VideoPicker picker) {
    setState(() => _picker = picker);
    _wake();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final player = widget.shell.player;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      widget.shell.toggleVideoFullscreen();
    } else if (key == LogicalKeyboardKey.space && event is KeyDownEvent) {
      player.pause();
    } else if (key == LogicalKeyboardKey.keyX && event is KeyDownEvent) {
      // Stop, and leave the fullscreen window if stopping left it open.
      player.stop();
      if (widget.shell.dialogManager.windows[AmpedDialog.video] != null) {
        widget.shell.toggleVideoFullscreen();
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      player.seekBy(-videoJump);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      player.seekBy(videoJump);
    } else {
      return KeyEventResult.ignored;
    }
    _wake();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: MouseRegion(
        cursor: _shown ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _wake(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoView(shell: widget.shell),
            // A press outside the open list closes it.
            if (_picker != VideoPicker.none)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pick(VideoPicker.none),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: VideoTitleOverlay(shell: widget.shell, fontSize: 22),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 12,
              child: IgnorePointer(
                ignoring: !_shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: CastButton(shell: widget.shell, onActivity: _wake),
                ),
              ),
            ),
            Center(
              child: IgnorePointer(
                ignoring: !_shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: MouseRegion(
                    onEnter: (_) => _overControls = true,
                    onExit: (_) {
                      _overControls = false;
                      _wake();
                    },
                    child: VideoPlayButton(shell: widget.shell, size: 120),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: MouseRegion(
                    onEnter: (_) => _overControls = true,
                    onExit: (_) {
                      _overControls = false;
                      _wake();
                    },
                    child: VideoControls(
                      shell: widget.shell,
                      picker: _picker,
                      onPickerChanged: _pick,
                      onActivity: _wake,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
