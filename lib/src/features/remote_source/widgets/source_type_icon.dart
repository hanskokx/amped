import "package:material_ui/material_ui.dart";
import "package:svg_flutter/svg.dart";

import "../classes/remote_source_type.dart";

/// The square badge that stands for a kind of source: its logo, or for
/// podcasts an icon.
class SourceTypeIcon extends StatelessWidget {
  const SourceTypeIcon(this.type, {super.key});

  final RemoteSourceType type;

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: switch (type) {
        RemoteSourceType.navidrome => _logo("navidrome", 28),
        RemoteSourceType.soundcloud => _logo("soundcloud", 32),
        // Its lettering is the theme's text color.
        RemoteSourceType.plex => _logo(
          "plex",
          30,
          currentColor: theme.colorScheme.onSurface,
        ),
        RemoteSourceType.jellyfin => _logo("jellyfin", 26),
        // Podcasts are no one product, so they have no logo.
        RemoteSourceType.podcast => Icon(
          Icons.podcasts,
          size: 22,
          color: theme.colorScheme.primary,
        ),
        RemoteSourceType.audiobookshelf => _logo("audiobookshelf", 28),
      },
    );
  }

  /// [currentColor] fills what the logo leaves to the app to color.
  static Widget _logo(String name, double width, {Color? currentColor}) =>
      SvgPicture.asset(
        "assets/images/logos/$name.svg",
        width: width,
        theme: currentColor == null
            ? null
            : SvgTheme(currentColor: currentColor),
      );
}
