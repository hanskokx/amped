import "dart:async";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart" show SkinWindow;
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "../player/video_engine.dart";
import "amped_menus.dart";
import "amped_shell.dart";
import "cast_button.dart";
import "fullscreen_video_controls.dart";

/// The playing video's picture, scaled to fit (keeping its shape) on black;
/// plain black while no video plays. Inside the classic Video window and a
/// modern skin's video component.
class VideoView extends StatefulWidget {
  const VideoView({required this.shell, this.controls = false, super.key});

  final AmpedShell shell;

  /// Whether play controls fade in while the mouse is over the picture
  /// (the windowed video; fullscreen has its own).
  final bool controls;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  bool _hovering = false;
  int? _menuPointer;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kSecondaryButton) return;
    // The window would open the main menu on release otherwise.
    SkinSecondaryClaim.claim(event);
    _menuPointer = event.pointer;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _menuPointer) return;
    _menuPointer = null;
    widget.shell.showMenu(AmpedMenus.video(widget.shell), null);
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final video = shell.player.video;
    return _DoubleClick(
      // A double-click fills the screen with the video, and brings it
      // back.
      onDoubleClick: shell.toggleVideoFullscreen,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (video != null) _VideoPicture(video: video),
                // Controls only while a video plays.
                if (widget.controls && video != null)
                  ListenableBuilder(
                    listenable: video,
                    builder: (context, _) {
                      if (!video.active) return const SizedBox.shrink();
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _hovering ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: VideoTitleOverlay(
                                  shell: shell,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: IgnorePointer(
                              ignoring: !_hovering,
                              child: AnimatedOpacity(
                                opacity: _hovering ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      SkinNoWindowDrag(
                                        child: VideoPlayButton(
                                          shell: shell,
                                          // Large, but never filling a small
                                          // window.
                                          size:
                                              (constraints
                                                          .biggest
                                                          .shortestSide *
                                                      0.3)
                                                  .clamp(32.0, 96.0),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: IgnorePointer(
                              ignoring: !_hovering,
                              child: AnimatedOpacity(
                                opacity: _hovering ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: SkinNoWindowDrag(
                                  child: CastButton(shell: shell, size: 18),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              ignoring: !_hovering,
                              child: AnimatedOpacity(
                                opacity: _hovering ? 1 : 0,
                                duration: const Duration(milliseconds: 200),
                                // Pressing and dragging the sliders must
                                // not move the window.
                                child: SkinNoWindowDrag(
                                  child: WindowedVideoControls(shell: shell),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Calls [onDoubleClick] for two left presses in quick succession, without
/// keeping the presses from anything else.
class _DoubleClick extends StatefulWidget {
  const _DoubleClick({required this.onDoubleClick, required this.child});

  final VoidCallback onDoubleClick;
  final Widget child;

  @override
  State<_DoubleClick> createState() => _DoubleClickState();
}

class _DoubleClickState extends State<_DoubleClick> {
  Duration? _last;
  Offset _at = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        final last = _last;
        if (last != null &&
            event.timeStamp - last <= kDoubleTapTimeout &&
            (event.position - _at).distance <= kDoubleTapSlop) {
          _last = null;
          widget.onDoubleClick();
          return;
        }
        _last = event.timeStamp;
        _at = event.position;
      },
      child: widget.child,
    );
  }
}

/// The video inside a modern skin window other than the Video window
/// (Amped Modern's drawer): while the skin shows it there, the Video
/// window stays closed.
class VideoSlot extends StatefulWidget {
  const VideoSlot({required this.shell, super.key});

  final AmpedShell shell;

  @override
  State<VideoSlot> createState() => _VideoSlotState();
}

class _VideoSlotState extends State<VideoSlot> {
  @override
  void initState() {
    super.initState();
    // Not while the tree is building: attaching closes the Video window,
    // which notifies the shell's listeners.
    scheduleMicrotask(widget.shell.modernVideo.attachSlot);
  }

  @override
  void dispose() {
    scheduleMicrotask(widget.shell.modernVideo.detachSlot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      VideoView(shell: widget.shell, controls: true);
}

class _VideoPicture extends StatelessWidget {
  const _VideoPicture({required this.video});

  final VideoEngine video;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([video, video.textureId]),
      builder: (context, _) {
        final id = video.textureId.value;
        final size = video.videoSize;
        if (!video.active || id == null || size == null) {
          return const SizedBox.shrink();
        }
        return FittedBox(
          child: SizedBox.fromSize(
            size: size,
            child: Texture(textureId: id, filterQuality: FilterQuality.medium),
          ),
        );
      },
    );
  }
}

/// The picture's class by its size, shown as a badge.
enum VideoSizeClass {
  sd("SD"),
  hd("HD"),
  fhd("FHD"),
  qhd("QHD"),
  uhd4k("4K"),
  uhd8k("8K");

  const VideoSizeClass(this.label);

  final String label;

  /// The class of a picture of [size]: the larger of its width and height
  /// decides (a widescreen film is less tall than its width suggests).
  static VideoSizeClass of(Size size) {
    final wide = size.width;
    final high = size.height;
    if (wide >= 7680 || high >= 4320) return uhd8k;
    if (wide >= 3840 || high >= 2160) return uhd4k;
    if (wide >= 2560 || high >= 1440) return qhd;
    if (wide >= 1920 || high >= 1080) return fhd;
    if (wide >= 1280 || high >= 720) return hd;
    return sd;
  }
}

/// The classic Video window around [VideoView], with the picture's size as
/// its status text.
class ClassicVideoWindow extends StatelessWidget {
  const ClassicVideoWindow({required this.shell, super.key});

  final AmpedShell shell;

  /// "elapsed / total" with both as wide as the total, so the text keeps
  /// its width as it counts: `0:05:09 / 1:41:50`, `05:09 / 42:10`.
  @visibleForTesting
  static String playbackTime(Duration elapsed, Duration total) {
    String two(int n) => n.toString().padLeft(2, "0");
    final hours = total.inHours > 0;
    String format(Duration time) {
      final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
      final mm = two(seconds ~/ 60 % 60);
      final ss = two(seconds % 60);
      return hours ? "${seconds ~/ 3600}:$mm:$ss" : "${two(seconds ~/ 60)}:$ss";
    }

    final capped = total > Duration.zero && elapsed > total ? total : elapsed;
    return "${format(capped)} / ${format(total)}";
  }

  @override
  Widget build(BuildContext context) {
    final player = shell.player;
    final video = player.video;
    return ListenableBuilder(
      listenable: Listenable.merge([?video, player]),
      builder: (context, _) {
        final size = video?.videoSize;
        final entry = player.playlist.currentEntry;
        // Nothing to say while no video plays.
        final shown = size != null;
        final playing = video?.active ?? false;
        final total = Duration(seconds: player.durationSec);
        return VideoWindow(
          host: shell.classic,
          title: shown ? entry?.playingTitle ?? "" : "",
          time: shown
              ? playbackTime(Duration(seconds: player.elapsedSec), total)
              : "",
          badge: size == null ? "" : VideoSizeClass.of(size).label,
          // Nothing to zoom, fill the screen with or choose tracks of while
          // no video plays; the TV button opens the Media Library anyway, and the misc menu its Always on top.
          onZoom: playing ? shell.zoomVideo : null,
          onFullscreen: playing ? shell.toggleVideoFullscreen : null,
          onTv: () => shell.setOpen(SkinWindow.library, true),
          // The menu opens stopped too, for Always on top.
          onMisc: () => shell.showMenu(AmpedMenus.video(shell), null),
          content: VideoView(shell: shell, controls: true),
        );
      },
    );
  }
}
