import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/widgets.dart";
import "package:material_ui/material_ui.dart"
    show AnimatedIcon, AnimatedIcons, Icons;

import "../player/video_engine.dart";
import "amped_dialog.dart";
import "amped_shell.dart";

/// What the jump buttons skip.
const Duration videoJump = Duration(seconds: 15);

const Color _ink = Color(0xFFFFFFFF);
const Color _dim = Color(0xB3FFFFFF);
const TextStyle _text = TextStyle(
  color: _ink,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  decoration: TextDecoration.none,
);

String formatVideoTime(Duration time) {
  final total = time.inSeconds < 0 ? 0 : time.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, "0");
  return hours > 0
      ? "$hours:${two(minutes)}:${two(seconds)}"
      : "$minutes:${two(seconds)}";
}

/// The control surface: progress bar, transport buttons, subtitle picker and
/// volume.
class VideoControls extends StatefulWidget {
  const VideoControls({
    required this.shell,
    this.picker = VideoPicker.none,
    this.onPickerChanged,
    this.onActivity,
    super.key,
  });

  final AmpedShell shell;

  /// The list open over the controls.
  final VideoPicker picker;

  /// Called when a list is opened or closed.
  final ValueChanged<VideoPicker>? onPickerChanged;

  /// Called when something is pressed, so the controls stay shown.
  final VoidCallback? onActivity;

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  /// Opens [picker], or closes it when it is the one open.
  void _togglePicker(VideoPicker picker) {
    widget.onPickerChanged?.call(
      widget.picker == picker ? VideoPicker.none : picker,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shell = widget.shell;
    final player = shell.player;
    final video = player.video;
    return ListenableBuilder(
      listenable: Listenable.merge([player, ?video]),
      builder: (context, _) {
        final subtitles = video?.subtitles ?? const <TrackOption>[];
        final audio = video?.audioTracks ?? const <TrackOption>[];
        void act(VoidCallback action) {
          action();
          widget.onActivity?.call();
        }

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xCC000000)],
            ),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A press on the bare panel closes an open list too.
            onTap: () => widget.onPickerChanged?.call(VideoPicker.none),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.picker == VideoPicker.subtitles)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TrackPicker(
                        options: subtitles,
                        selected: video?.subtitleId,
                        offLabel: l.videoSubtitlesOff,
                        unsupportedLabel: l.videoTrackUnsupported,
                        trackLabel: l.videoSubtitleTrack,
                        onSelected: (id) {
                          video?.selectSubtitle(id);
                          _togglePicker(VideoPicker.subtitles);
                          widget.onActivity?.call();
                        },
                      ),
                    ),
                  if (widget.picker == VideoPicker.audio)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TrackPicker(
                        options: audio,
                        selected: video?.audioId,
                        trackLabel: l.videoSubtitleTrack,
                        onSelected: (id) {
                          if (id != null) video?.selectAudio(id);
                          _togglePicker(VideoPicker.audio);
                          widget.onActivity?.call();
                        },
                      ),
                    ),
                  VideoSeekBar(
                    elapsed: Duration(seconds: player.elapsedSec),
                    total: Duration(seconds: player.durationSec),
                    label: l.videoPosition,
                    onSeek: (at) => act(() => player.seekTo(at)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      VideoButton(
                        icon: Icons.skip_previous,
                        label: l.previous,
                        onPressed: () => act(player.prev),
                      ),
                      VideoButton(
                        icon: Icons.replay,
                        badge: "15",
                        label: l.videoBack15,
                        onPressed: () => act(() => player.seekBy(-videoJump)),
                      ),
                      VideoButton(
                        icon: Icons.refresh,
                        badge: "15",
                        label: l.videoForward15,
                        onPressed: () => act(() => player.seekBy(videoJump)),
                      ),
                      VideoButton(
                        icon: Icons.skip_next,
                        label: l.next,
                        onPressed: () => act(player.next),
                      ),
                      VideoButton(
                        icon: Icons.stop,
                        label: l.stop,
                        onPressed: () => act(() {
                          player.stop();
                          // Stopping closes the window only when the
                          // preference says so.
                          if (shell.dialogManager.windows[AmpedDialog.video] !=
                              null) {
                            shell.toggleVideoFullscreen();
                          }
                        }),
                      ),
                      const Spacer(),
                      VideoVolume(
                        value: player.volume / 255,
                        label: l.videoVolume,
                        onMute: () => act(player.toggleMute),
                        onChanged: (v) =>
                            act(() => player.setVolume((v * 255).round())),
                      ),
                      const SizedBox(width: 12),
                      VideoButton(
                        icon: Icons.audiotrack,
                        label: l.videoAudio,
                        enabled: audio.length > 1,
                        onPressed: () => _togglePicker(VideoPicker.audio),
                      ),
                      VideoButton(
                        icon: video?.subtitleId == null
                            ? Icons.subtitles_off_outlined
                            : Icons.subtitles,
                        label: l.videoSubtitles,
                        enabled: subtitles.isNotEmpty,
                        onPressed: () => _togglePicker(VideoPicker.subtitles),
                      ),
                      VideoButton(
                        icon: Icons.fullscreen_exit,
                        label: l.videoExitFullscreen,
                        onPressed: shell.toggleVideoFullscreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Which track list is open over the controls.
enum VideoPicker { none, subtitles, audio }

/// An icon button with a semantic [label]; greyed out and inert when not
/// [enabled].
class VideoButton extends StatelessWidget {
  const VideoButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 28,
    this.badge,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double size;

  final bool enabled;

  /// A short text over the icon.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: _ink, size: size),
                  if (badge != null)
                    Text(
                      badge!,
                      style: _text.copyWith(
                        fontSize: size * 0.32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal bar a press or drag sets a fraction on.
class _Track extends StatelessWidget {
  const _Track({
    required this.fraction,
    required this.onChanged,
    this.onEnd,
    this.onHover,
    this.marks = const [],
  });

  final double fraction;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onEnd;

  /// The fraction the mouse is over, or `null` when it leaves.
  final ValueChanged<double?>? onHover;

  /// Fractions (0..1) to mark with a notch, such as where chapters start.
  final List<double> marks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double at(double dx) => width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);
        const height = 4.0;
        final f = fraction.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onChanged(at(d.localPosition.dx)),
          onTapUp: (d) => onEnd?.call(at(d.localPosition.dx)),
          onHorizontalDragStart: (d) => onChanged(at(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition.dx)),
          onHorizontalDragEnd: (_) => onEnd?.call(-1),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: onHover == null
                ? null
                : (event) => onHover!(at(event.localPosition.dx)),
            onExit: onHover == null ? null : (_) => onHover!(null),
            child: SizedBox(
              height: 20,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: const Color(0x4DFFFFFF),
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                  Container(
                    height: height,
                    width: width * f,
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                  // Where the chapters start: a gap in the bar.
                  for (final mark in marks)
                    Positioned(
                      left: width * mark - 1,
                      child: Container(
                        width: 2,
                        height: height,
                        color: const Color(0xCC000000),
                      ),
                    ),
                  Positioned(
                    left: (width * f - 6).clamp(0.0, width - 12),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: _ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The progress bar with the elapsed and total time: a press or drag seeks
/// (the video seeks when the drag ends).
class VideoSeekBar extends StatefulWidget {
  const VideoSeekBar({
    required this.elapsed,
    required this.total,
    required this.label,
    required this.onSeek,
    this.showTimes = true,
    this.chapters = const [],
    super.key,
  });

  /// Whether the elapsed and total time flank the bar.
  final bool showTimes;

  final Duration elapsed;
  final Duration total;
  final String label;
  final ValueChanged<Duration> onSeek;

  /// Where chapters start, marked on the bar and named in the preview.
  final List<VideoChapter> chapters;

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  /// The fraction being dragged to; `null` when not dragging.
  double? _drag;

  /// The fraction the mouse is over; `null` when it is not over the bar.
  double? _hover;

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.total.inMilliseconds * fraction).round(),
  );

  String? _chapterAt(Duration at) {
    String? title;
    for (final chapter in widget.chapters) {
      if (chapter.time > at) break;
      title = chapter.title;
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final playing = total > Duration.zero
        ? widget.elapsed.inMilliseconds / total.inMilliseconds
        : 0.0;
    final fraction = _drag ?? playing;
    final preview = _drag ?? _hover;
    return Semantics(
      label: widget.label,
      child: Row(
        children: [
          if (widget.showTimes)
            SizedBox(
              width: 56,
              child: Text(
                formatVideoTime(_drag == null ? widget.elapsed : _at(_drag!)),
                style: _text,
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _Track(
                      fraction: fraction,
                      marks: [
                        if (total > Duration.zero)
                          for (final chapter in widget.chapters)
                            if (chapter.time > Duration.zero &&
                                chapter.time < total)
                              chapter.time.inMilliseconds /
                                  total.inMilliseconds,
                      ],
                      onHover: (f) => setState(() => _hover = f),
                      onChanged: (f) {
                        if (total > Duration.zero) setState(() => _drag = f);
                      },
                      onEnd: (f) {
                        // A drag ends at the last fraction; a tap at its own.
                        final target = f < 0 ? _drag : f;
                        setState(() => _drag = null);
                        if (target != null && total > Duration.zero) {
                          widget.onSeek(_at(target));
                        }
                      },
                    ),
                    if (preview != null && total > Duration.zero)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomSingleChildLayout(
                            delegate: _PreviewLayout(width * preview),
                            child: SeekPreview(
                              time: formatVideoTime(_at(preview)),
                              chapter: _chapterAt(_at(preview)),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (widget.showTimes)
            SizedBox(
              width: 56,
              child: Text(
                formatVideoTime(total),
                textAlign: TextAlign.end,
                style: _text,
              ),
            ),
        ],
      ),
    );
  }
}

/// Puts the preview above the bar, centred on [x] but kept inside the bar's
/// width, whatever size the preview is.
class _PreviewLayout extends SingleChildLayoutDelegate {
  const _PreviewLayout(this.x);

  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = (size.width - childSize.width).clamp(0.0, double.infinity);
    return Offset(
      (x - childSize.width / 2).clamp(0.0, room),
      // Above the bar, with a gap.
      -childSize.height - 6,
    );
  }

  @override
  bool shouldRelayout(_PreviewLayout old) => old.x != x;
}

/// The popover over the progress bar: the chapter and the time where the
/// pointer is.
class SeekPreview extends StatelessWidget {
  const SeekPreview({required this.time, this.chapter, super.key});

  final String time;
  final String? chapter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE6101010),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chapter != null)
            Text(
              chapter!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text.copyWith(fontSize: 11, color: _dim),
            ),
          Text(time, style: _text),
        ],
      ),
    );
  }
}

/// The video's title over the top of the picture, on a gradient from black
/// so the text reads against any picture.
class VideoTitleOverlay extends StatelessWidget {
  const VideoTitleOverlay({required this.shell, this.fontSize = 18, super.key});

  final AmpedShell shell;

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final player = shell.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final title = player.playlist.currentEntry?.playingTitle ?? "";
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              fontSize + 6,
              fontSize * 0.8,
              fontSize + 6,
              fontSize * 2.4,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text.copyWith(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The volume slider.
class VideoVolume extends StatelessWidget {
  const VideoVolume({
    required this.value,
    required this.label,
    required this.onChanged,
    this.onMute,
    this.size = 22,
    this.slider = true,
    super.key,
  });

  /// The speaker's size.
  final double size;

  /// Whether the slider is shown beside the speaker.
  final bool slider;

  /// Pressing the speaker mutes, or restores the volume.
  final VoidCallback? onMute;

  /// 0..1.
  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      slider: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMute,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                value <= 0 ? Icons.volume_off : Icons.volume_up,
                color: _ink,
                size: size,
              ),
            ),
          ),
          if (slider) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: size > 20 ? 110 : 64,
              child: _Track(fraction: value, onChanged: onChanged),
            ),
          ],
        ],
      ),
    );
  }
}

/// The list of subtitle or audio tracks, and Off when there is [offLabel].
class TrackPicker extends StatelessWidget {
  const TrackPicker({
    required this.options,
    required this.selected,
    required this.trackLabel,
    required this.onSelected,
    this.offLabel,
    this.unsupportedLabel,
    super.key,
  });

  final List<TrackOption> options;
  final String? selected;

  /// The entry that chooses none; `null` for a list that must have one.
  final String? offLabel;

  /// The badge under a track that cannot be shown.
  final String? unsupportedLabel;
  final String Function(int number) trackLabel;

  /// Called with the chosen track's id, or `null` for Off.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6101010),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offLabel != null)
            TrackChoice(
              text: offLabel!,
              selected: selected == null,
              onPressed: () => onSelected(null),
            ),
          for (var i = 0; i < options.length; i++)
            TrackChoice(
              text: options[i].label(trackLabel(i + 1)),
              selected: selected == options[i].id,
              badge: options[i].supported ? null : unsupportedLabel,
              onPressed: options[i].supported
                  ? () => onSelected(options[i].id)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// One entry of the subtitle picker.
class TrackChoice extends StatelessWidget {
  const TrackChoice({
    required this.text,
    required this.selected,
    required this.onPressed,
    this.badge,
    super.key,
  });

  final String text;
  final bool selected;

  /// `null` when the entry cannot be chosen.
  final VoidCallback? onPressed;

  /// A small note under the text.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: MouseRegion(
          cursor: onPressed == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: selected
                      ? const Icon(Icons.check, color: _ink, size: 16)
                      : null,
                ),
                Expanded(
                  child: Opacity(
                    opacity: onPressed == null ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: selected ? _text : _text.copyWith(color: _dim),
                        ),
                        if (badge != null)
                          Text(
                            badge!,
                            style: _text.copyWith(fontSize: 10, color: _dim),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slim control strip over the bottom of the windowed video: play/pause,
/// stop, 15 second jumps, a progress bar and the way into fullscreen.
class WindowedVideoControls extends StatelessWidget {
  const WindowedVideoControls({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final player = shell.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xCC000000)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final room = constraints.maxWidth >= 360;
                return Row(
                  children: [
                    VideoButton(
                      icon: Icons.stop,
                      label: l.stop,
                      size: 18,
                      onPressed: player.stop,
                    ),
                    VideoButton(
                      icon: Icons.replay,
                      badge: "15",
                      label: l.videoBack15,
                      size: 18,
                      onPressed: () => player.seekBy(-videoJump),
                    ),
                    VideoButton(
                      icon: Icons.refresh,
                      badge: "15",
                      label: l.videoForward15,
                      size: 18,
                      onPressed: () => player.seekBy(videoJump),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: VideoSeekBar(
                        elapsed: Duration(seconds: player.elapsedSec),
                        total: Duration(seconds: player.durationSec),
                        label: l.videoPosition,
                        showTimes: false,
                        onSeek: player.seekTo,
                      ),
                    ),
                    const SizedBox(width: 14),
                    VideoVolume(
                      value: player.volume / 255,
                      label: l.videoVolume,
                      size: 18,
                      // The slider goes when the window is too narrow for it.
                      slider: room,
                      onMute: player.toggleMute,
                      onChanged: (v) => player.setVolume((v * 255).round()),
                    ),
                    VideoButton(
                      icon: Icons.fullscreen,
                      label: l.fullscreen,
                      size: 18,
                      onPressed: shell.toggleVideoFullscreen,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// The large play/pause button over the middle of the video; its icon morphs
/// between the two as playback pauses and resumes.
class VideoPlayButton extends StatefulWidget {
  const VideoPlayButton({required this.shell, required this.size, super.key});

  final AmpedShell shell;

  /// The button's diameter.
  final double size;

  @override
  State<VideoPlayButton> createState() => _VideoPlayButtonState();
}

class _VideoPlayButtonState extends State<VideoPlayButton>
    with SingleTickerProviderStateMixin {
  /// 0 shows play, 1 shows pause.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.shell.player.paused ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    widget.shell.player.addListener(_follow);
  }

  @override
  void dispose() {
    widget.shell.player.removeListener(_follow);
    _morph.dispose();
    super.dispose();
  }

  void _follow() {
    final paused = widget.shell.player.paused;
    if (paused &&
        _morph.value > 0 &&
        _morph.status != AnimationStatus.reverse) {
      _morph.reverse();
    } else if (!paused &&
        _morph.value < 1 &&
        _morph.status != AnimationStatus.forward) {
      _morph.forward();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final player = widget.shell.player;
    return Semantics(
      button: true,
      label: player.paused ? l.videoPlay : l.pause,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: player.pause,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(
              color: Color(0x99000000),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: _morph,
                color: _ink,
                size: widget.size * 0.62,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
