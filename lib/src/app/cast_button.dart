import "dart:async";

import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/widgets.dart";
import "package:material_ui/material_ui.dart" show Icons;

import "../player/video_cast.dart";
import "amped_shell.dart";
import "fullscreen_video_controls.dart";

/// The Chromecast button of the video: it opens the list of devices to play
/// the video on, and, while it plays on one, the way back.
class CastButton extends StatefulWidget {
  const CastButton({
    required this.shell,
    this.size = 28,
    this.onActivity,
    super.key,
  });

  final AmpedShell shell;
  final double size;

  /// Called when something is pressed, so the controls stay shown.
  final VoidCallback? onActivity;

  @override
  State<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends State<CastButton> {
  bool _open = false;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) widget.shell.chromecast.discover();
    widget.onActivity?.call();
  }

  void _cast(CastTarget target) {
    setState(() => _open = false);
    widget.onActivity?.call();
    unawaited(widget.shell.castTo(target));
  }

  void _stop() {
    setState(() => _open = false);
    widget.shell.chromecast.stop();
    widget.onActivity?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cast = widget.shell.chromecast;
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            VideoButton(
              icon: cast.active ? Icons.cast_connected : Icons.cast,
              label: l.videoCast,
              size: widget.size,
              onPressed: _toggle,
            ),
            if (_open)
              CastDeviceList(
                targets: cast.targets,
                searching: cast.discovering,
                casting: cast.active || cast.connecting ? cast.current : null,
                failure: cast.failure,
                onSelected: _cast,
                onStop: _stop,
                onSearch: cast.discover,
              ),
          ],
        );
      },
    );
  }
}

/// The list of Chromecasts to choose from, and the way to stop casting.
class CastDeviceList extends StatelessWidget {
  const CastDeviceList({
    required this.targets,
    required this.searching,
    required this.casting,
    required this.failure,
    required this.onSelected,
    required this.onStop,
    required this.onSearch,
    super.key,
  });

  final List<CastTarget> targets;
  final bool searching;

  /// The device the video plays on, if any.
  final CastTarget? casting;
  final CastFailure? failure;
  final ValueChanged<CastTarget> onSelected;
  final VoidCallback onStop;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6101010),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (casting != null) ...[
            TrackChoice(
              text: l.videoCastingTo(casting!.name),
              selected: true,
              onPressed: null,
            ),
            TrackChoice(
              text: l.videoCastStop,
              selected: false,
              onPressed: onStop,
            ),
          ] else ...[
            if (failure == CastFailure.unsupported)
              TrackChoice(
                text: l.videoCastUnsupported,
                selected: false,
                onPressed: null,
              ),
            if (failure == CastFailure.failed)
              TrackChoice(
                text: l.videoCastFailed,
                selected: false,
                onPressed: null,
              ),
            for (final target in targets)
              TrackChoice(
                text: target.name,
                selected: false,
                onPressed: () => onSelected(target),
              ),
            if (targets.isEmpty)
              TrackChoice(
                text: searching ? l.videoCastSearching : l.videoCastNone,
                selected: false,
                onPressed: null,
              ),
            if (!searching)
              TrackChoice(
                text: l.videoCastSearchAgain,
                selected: false,
                onPressed: onSearch,
              ),
          ],
        ],
      ),
    );
  }
}
