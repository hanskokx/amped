import "package:amped_l10n/amped_l10n.dart";

/// The kinds of remote source that can be added. Plex, Jellyfin and SoundCloud add
/// theirs here, with a [RemoteLibrarySource] each.
enum RemoteSourceType {
  navidrome,
  soundcloud,
  plex,
  jellyfin,
  podcast,
  audiobookshelf,
}

/// What Preferences calls a [RemoteSourceType].
extension RemoteSourceTypeText on RemoteSourceType {
  String title(AppLocalizations localizations) => switch (this) {
    RemoteSourceType.navidrome => localizations.libraryTypeNavidrome,
    RemoteSourceType.podcast => localizations.libraryTypePodcast,
    // Product names, the same in every language.
    RemoteSourceType.soundcloud => "SoundCloud",
    RemoteSourceType.plex => "Plex",
    RemoteSourceType.jellyfin => "Jellyfin",
    RemoteSourceType.audiobookshelf => "Audiobookshelf",
  };

  String description(AppLocalizations localizations) => switch (this) {
    RemoteSourceType.navidrome => localizations.libraryDescribeNavidrome,
    RemoteSourceType.soundcloud => localizations.libraryDescribeSoundCloud,
    RemoteSourceType.plex => localizations.libraryDescribePlex,
    RemoteSourceType.jellyfin => localizations.libraryDescribeJellyfin,
    RemoteSourceType.podcast => localizations.libraryDescribePodcast,
    RemoteSourceType.audiobookshelf =>
      localizations.libraryDescribeAudiobookshelf,
  };
}
