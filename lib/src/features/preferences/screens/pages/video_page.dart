import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../../player/player_state.dart";

/// Preferences > Plug-ins > Video (`options_video.cpp`): when the Video
/// window opens and closes by itself, and whether closing it stops the video.
class VideoPage extends StatelessWidget {
  const VideoPage({required this.player, super.key});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            localizations.video,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: player.videoAutoOpen,
            title: Text(localizations.videoAutoOpen),
            onChanged: (value) => player.setVideoAutoOpen(value ?? false),
          ),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: player.videoAutoClose,
            title: Text(localizations.videoAutoClose),
            onChanged: (value) => player.setVideoAutoClose(value ?? false),
          ),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: player.videoStopOnClose,
            title: Text(localizations.videoStopOnClose),
            subtitle: Text(localizations.videoStopOnCloseHint),
            onChanged: (value) => player.setVideoStopOnClose(value ?? false),
          ),
        ],
      ),
    );
  }
}
