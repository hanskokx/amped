import "package:flutter/foundation.dart";

import "media_library.dart";
import "source_settings.dart";

/// What a [LibrarySourceSection] groups: decides the section's heading and
/// lets later source types (Navidrome, Plex, ...) add sections of their own.
enum LibrarySourceKind {
  local,
  videos,
  remote,
  playlists,
  podcasts,
  audiobooks,
  statistics,
}

/// Which play statistics list a source of the "Statistics" section shows.
enum PlayList { mostPlayed, recentlyPlayed, videos, podcasts }

/// One browsable source in the Media Library's tree, such as the local
/// library or a URL that was added.
///
/// A source type plugs in by providing [LibrarySource]s through a
/// [LibrarySourceSection]. A source with a [library] is browsed with the
/// artist, album and track panes; one without shows a message instead until
/// its type can list tracks.
class LibrarySource {
  const LibrarySource({
    required this.id,
    required this.label,
    this.library,
    this.playlistId,
    this.error,
    this.onOpen,
    this.podcast = false,
    this.completion = const PodcastCompletion(),
    this.audiobooks = false,
    this.movies = false,
    this.lists = const {},
    this.shows = false,
    this.playList,
  });

  /// Stable across runs and unique among all sources.
  final String id;

  final String label;

  /// The tracks of this source, or null when it can't be browsed yet.
  final MediaLibrary? library;

  /// The id of the saved playlist this source lists, or null.
  final int? playlistId;

  /// Why [library] couldn't be loaded, shown in place of the tracks.
  final String? error;

  /// Called when the source is picked in the tree, to load its tracks the
  /// first time.
  final VoidCallback? onOpen;

  /// Whether the tracks are podcast episodes, browsed by podcast in a
  /// sortable list of episodes instead of by artist and album.
  final bool podcast;

  /// When an episode of it counts as played.
  final PodcastCompletion completion;

  /// Whether the tracks are the audio files of audiobooks (shown as
  /// podcasts are, as books and their parts).
  final bool audiobooks;

  /// Whether these are the movies of a server: a plain list, with no show or
  /// season to browse by.
  final bool movies;

  /// The server's playlists of these movies, with the paths of their items.
  final Map<String, List<String>> lists;

  /// Whether these are the TV shows of a server, browsed by show and season.
  final bool shows;

  /// The play statistics list this source shows, or null.
  final PlayList? playList;
}

/// A row under a section's sources that does something when clicked, such
/// as importing a playlist.
class LibrarySectionAction {
  const LibrarySectionAction(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}

/// A top-level node of the source tree and the sources under it.
class LibrarySourceSection {
  const LibrarySourceSection({
    required this.id,
    required this.kind,
    required this.sources,
    this.label,
    this.actions = const [],
  });

  final String id;
  final LibrarySourceKind kind;

  /// The heading, or null for the section's default one for its [kind].
  final String? label;

  final List<LibrarySource> sources;

  /// Rows after the sources.
  final List<LibrarySectionAction> actions;
}

/// The id of the local source.
const localSourceId = "local";

/// The sections of the tree for the local library plus the other [sections]
/// that were added.
List<LibrarySourceSection> librarySections(
  MediaLibrary local, {
  String localLabel = "Local",
  List<LibrarySourceSection> others = const [],
}) => [
  LibrarySourceSection(
    id: "local",
    kind: LibrarySourceKind.local,
    sources: [
      LibrarySource(id: localSourceId, label: localLabel, library: local),
    ],
  ),
  ...others,
];

/// The id of the "Videos" section.
const videosSectionId = "videos";

/// What the id of a source of the "Videos" section starts with; the rest is
/// the id of the source whose videos it lists.
const videoSourcePrefix = "videos:";

/// The id of the "All videos" source.
const allVideosSourceId = "videos:all";

/// The id of the "Audiobooks" section.
const audiobooksSectionId = "audiobooks";

/// What the id of an audiobooks source starts with; the rest is the id of
/// the server it is of.
const bookSourcePrefix = "books:";

/// The id of the "Playlists" section.
const playlistsSectionId = "playlists";

/// What the id of a saved playlist's source starts with.
const playlistSourcePrefix = "playlist:";

/// The id of the "Statistics" section.
const statisticsSectionId = "statistics";

/// What the id of a source of the "Statistics" section starts with.
const statisticsSourcePrefix = "stats:";
