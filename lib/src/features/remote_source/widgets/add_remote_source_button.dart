import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";
import "package:svg_flutter/svg.dart";

import "../classes/remote_source_type.dart";

class AddRemoteSourceButton extends StatelessWidget {
  const new({
    required this.type,
    required this.onPressed,
    super.key,
  });

  final RemoteSourceType type;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations localizations = AppLocalizations.of(context);

    final String label = switch (type) {
      RemoteSourceType.navidrome => localizations.libraryAddNavidrome,
      RemoteSourceType.audiobookshelf => localizations.libraryAddAudiobookshelf,
      RemoteSourceType.soundcloud => localizations.libraryAddSoundCloud,
      RemoteSourceType.plex => localizations.libraryAddPlex,
      RemoteSourceType.jellyfin => localizations.libraryAddJellyfin,
      RemoteSourceType.podcast => localizations.libraryAddPodcast,
    };

    if (this.type == RemoteSourceType.plex)
      return AddPlexSourceButton(
        onPressed: onPressed,
      );

    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class AddPlexSourceButton extends StatelessWidget {
  const new({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations localizations = AppLocalizations.of(context);

    final bool isDarkMode = Theme.brightnessOf(context) == Brightness.dark;

    return OutlinedButton.icon(
      icon: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SvgPicture.asset(
          height: 24,
          isDarkMode
              ? "assets/images/logos/plex_dark.svg"
              : "assets/images/logos/plex_light.svg",
        ),
      ),
      label: Text(localizations.libraryAddPlex),
      onPressed: onPressed,
    );
  }
}
