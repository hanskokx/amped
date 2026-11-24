import "dart:convert";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

import "library_sources.dart";
import "library_view.dart";

/// What the Media Library remembers between runs: the source and the
/// artists, albums or podcasts picked in it, how the episodes are sorted,
/// the order of their columns, and the folded sections of the tree.
@immutable
class LibraryViewSettings {
  const LibraryViewSettings({
    this.sourceId = localSourceId,
    this.artists = const {},
    this.albums = const {},
    this.sortColumn = LibraryColumn.published,
    this.sortAscending = false,
    this.columns = LibraryColumn.podcast,
    this.musicColumns = LibraryColumn.music,
    this.bookColumns = LibraryColumn.book,
    this.movieColumns = LibraryColumn.movies,
    this.showColumns = LibraryColumn.shows,
    this.bookSortColumn,
    this.bookSortAscending = true,
    this.musicSortColumn,
    this.musicSortAscending = true,
    this.musicLayout = MusicLayout.browser,
    this.bookLayout = MusicLayout.split,
    this.movieLayout = MusicLayout.tracks,
    this.podcastLayout = MusicLayout.browser,
    this.videoSort = VideoSort.name,
    this.videoFilter = VideoFilter.all,
    this.coverSizes = const {},
    this.hideWatched = false,
    this.treeWidth = 0,
    this.browserWidth = 0,
    this.hideListened = false,
    this.panelSorts = const {},
    this.splitShares = const {},
    this.splitFraction = 0.4,
    this.columnWidths = const {},
    this.collapsed = const {},
    this.coverCollapsed = false,
    this.detailsExtra = 0,
  });

  final String sourceId;
  final Set<String> artists;
  final Set<String> albums;
  final LibraryColumn sortColumn;
  final bool sortAscending;

  /// The columns of podcast episodes, in the order they are shown.
  final List<LibraryColumn> columns;

  /// The columns of music, in the order they are shown, and how the music
  /// is sorted (null: as the library has it).
  final List<LibraryColumn> musicColumns;

  /// The columns of the parts of audiobooks, in order, and how they are
  /// sorted (null: by book, then part).
  final List<LibraryColumn> bookColumns;

  /// The columns of movies and of the episodes of TV shows.
  final List<LibraryColumn> movieColumns;
  final List<LibraryColumn> showColumns;
  final LibraryColumn? bookSortColumn;
  final bool bookSortAscending;
  final LibraryColumn? musicSortColumn;
  final bool musicSortAscending;

  /// How music is laid out, and how much of the height the artist and album
  /// panels have in the split layout, 0 to 1.
  final MusicLayout musicLayout;

  /// How audiobooks are laid out: split by default.
  final MusicLayout bookLayout;

  /// How movies and podcasts are laid out.
  final MusicLayout movieLayout;
  final MusicLayout podcastLayout;

  /// How movies and shows are ordered, and which are listed.
  final VideoSort videoSort;
  final VideoFilter videoFilter;

  /// How wide the covers are, by what is shown.
  final Map<String, double> coverSizes;

  /// Whether what was watched (movies, shows) or listened to (podcasts,
  /// audiobooks) is left out.
  final bool hideWatched;

  /// How wide the tree of sources and the list of artists were dragged to
  /// (0: as they start).
  final double treeWidth;
  final double browserWidth;
  final bool hideListened;

  /// How each split panel is sorted (the column of its headings, and
  /// ascending), and the share of the width each panel of a split layout
  /// has.
  final Map<String, (int, bool)> panelSorts;
  final Map<String, List<double>> splitShares;
  final double splitFraction;

  /// The widths columns were dragged to; the others have their usual one.
  final Map<LibraryColumn, double> columnWidths;
  final Set<String> collapsed;

  /// Whether the details panel is folded away, and how much taller than
  /// usual it was dragged.
  final bool coverCollapsed;
  final double detailsExtra;

  /// These settings with another [sourceId].
  LibraryViewSettings copyWith({String? sourceId}) => LibraryViewSettings(
    sourceId: sourceId ?? this.sourceId,
    artists: artists,
    albums: albums,
    sortColumn: sortColumn,
    sortAscending: sortAscending,
    columns: columns,
    musicColumns: musicColumns,
    bookColumns: bookColumns,
    movieColumns: movieColumns,
    showColumns: showColumns,
    bookSortColumn: bookSortColumn,
    bookSortAscending: bookSortAscending,
    musicSortColumn: musicSortColumn,
    musicSortAscending: musicSortAscending,
    musicLayout: musicLayout,
    bookLayout: bookLayout,
    movieLayout: movieLayout,
    podcastLayout: podcastLayout,
    videoSort: videoSort,
    videoFilter: videoFilter,
    coverSizes: coverSizes,
    hideWatched: hideWatched,
    treeWidth: treeWidth,
    browserWidth: browserWidth,
    hideListened: hideListened,
    panelSorts: panelSorts,
    splitShares: splitShares,
    splitFraction: splitFraction,
    columnWidths: columnWidths,
    collapsed: collapsed,
    coverCollapsed: coverCollapsed,
    detailsExtra: detailsExtra,
  );

  static const _key = "amped.library_view";

  /// The saved settings, or the defaults when there are none or they can't
  /// be read.
  // ignore: prefer_constructors_over_static_methods
  static LibraryViewSettings load(SharedPreferences prefs) {
    final text = prefs.getString(_key);
    if (text == null) return const LibraryViewSettings();
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      LibraryColumn? column(Object? name) =>
          LibraryColumn.values.where((c) => c.name == name).firstOrNull;
      Set<String> strings(Object? list) => {
        for (final item in (list as List<dynamic>? ?? const []))
          if (item is String) item,
      };
      // The saved order of [usual]'s columns; columns added since stay
      // shown, after the saved ones.
      List<LibraryColumn> ordered(Object? names, List<LibraryColumn> usual) => [
        ...{
          for (final name in (names as List<dynamic>? ?? const []))
            if (column(name) case final c? when usual.contains(c)) c,
          ...usual,
        },
      ];
      return LibraryViewSettings(
        sourceId: json["source"] as String? ?? localSourceId,
        artists: strings(json["artists"]),
        albums: strings(json["albums"]),
        sortColumn: column(json["sortColumn"]) ?? LibraryColumn.published,
        sortAscending: json["sortAscending"] as bool? ?? false,
        columns: ordered(json["columns"], LibraryColumn.podcast),
        musicColumns: ordered(json["musicColumns"], LibraryColumn.music),
        bookColumns: ordered(json["bookColumns"], LibraryColumn.book),
        movieColumns: ordered(json["movieColumns"], LibraryColumn.movies),
        showColumns: ordered(json["showColumns"], LibraryColumn.shows),
        bookSortColumn: column(json["bookSortColumn"]),
        bookSortAscending: json["bookSortAscending"] as bool? ?? true,
        musicSortColumn: column(json["musicSortColumn"]),
        musicSortAscending: json["musicSortAscending"] as bool? ?? true,
        musicLayout: MusicLayout.values.firstWhere(
          (layout) => layout.name == json["musicLayout"],
          orElse: () => MusicLayout.browser,
        ),
        bookLayout: MusicLayout.values.firstWhere(
          (layout) => layout.name == json["bookLayout"],
          orElse: () => MusicLayout.split,
        ),
        movieLayout: MusicLayout.values.firstWhere(
          (layout) => layout.name == json["movieLayout"],
          orElse: () => MusicLayout.tracks,
        ),
        podcastLayout: MusicLayout.values.firstWhere(
          (layout) => layout.name == json["podcastLayout"],
          orElse: () => MusicLayout.browser,
        ),
        videoSort: VideoSort.values.firstWhere(
          (sort) => sort.name == json["videoSort"],
          orElse: () => VideoSort.name,
        ),
        videoFilter: VideoFilter.values.firstWhere(
          (filter) => filter.name == json["videoFilter"],
          orElse: () => VideoFilter.all,
        ),
        hideWatched: json["hideWatched"] as bool? ?? false,
        treeWidth: switch (json["treeWidth"]) {
          final num width when width > 0 && width < 5000 => width.toDouble(),
          _ => 0,
        },
        browserWidth: switch (json["browserWidth"]) {
          final num width when width > 0 && width < 5000 => width.toDouble(),
          _ => 0,
        },
        hideListened: json["hideListened"] as bool? ?? false,
        coverSizes: {
          for (final entry
              in (json["coverSizes"] as Map<String, dynamic>? ?? const {})
                  .entries)
            if (entry.value case final num size when size > 0 && size < 1000)
              entry.key: size.toDouble(),
        },
        panelSorts: {
          for (final entry
              in (json["panelSorts"] as Map<String, dynamic>? ?? const {})
                  .entries)
            if (entry.value case [final int column, final bool ascending])
              if (column >= 0 && column < 4) entry.key: (column, ascending),
        },
        splitShares: {
          for (final entry
              in (json["splitShares"] as Map<String, dynamic>? ?? const {})
                  .entries)
            if (entry.value case final List<dynamic> list)
              if (list.every((share) => share is num && share > 0))
                entry.key: [
                  for (final share in list) (share as num).toDouble(),
                ],
        },
        splitFraction: switch (json["splitFraction"]) {
          final num fraction when fraction >= 0.1 && fraction <= 0.9 =>
            fraction.toDouble(),
          _ => 0.4,
        },
        columnWidths: {
          for (final entry
              in (json["columnWidths"] as Map<String, dynamic>? ?? const {})
                  .entries)
            if (column(entry.key) case final c?)
              if (entry.value case final num width when width > 0)
                c: width.toDouble(),
        },
        collapsed: strings(json["collapsed"]),
        coverCollapsed: json["coverCollapsed"] as bool? ?? false,
        detailsExtra: switch (json["detailsExtra"]) {
          final num extra when extra >= 0 && extra < 5000 => extra.toDouble(),
          _ => 0,
        },
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not read the Media Library settings",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "LibraryViewSettings",
      );
      return const LibraryViewSettings();
    }
  }

  Future<void> save(SharedPreferences prefs) => prefs.setString(
    _key,
    jsonEncode({
      "source": sourceId,
      "artists": artists.toList(),
      "albums": albums.toList(),
      "sortColumn": sortColumn.name,
      "sortAscending": sortAscending,
      "columns": [for (final column in columns) column.name],
      "musicColumns": [for (final column in musicColumns) column.name],
      "bookColumns": [for (final column in bookColumns) column.name],
      "movieColumns": [for (final column in movieColumns) column.name],
      "showColumns": [for (final column in showColumns) column.name],
      "bookSortColumn": bookSortColumn?.name,
      "bookSortAscending": bookSortAscending,
      "musicSortColumn": musicSortColumn?.name,
      "musicSortAscending": musicSortAscending,
      "musicLayout": musicLayout.name,
      "bookLayout": bookLayout.name,
      "movieLayout": movieLayout.name,
      "podcastLayout": podcastLayout.name,
      "videoSort": videoSort.name,
      "videoFilter": videoFilter.name,
      "coverSizes": coverSizes,
      "hideWatched": hideWatched,
      "treeWidth": treeWidth,
      "browserWidth": browserWidth,
      "hideListened": hideListened,
      "panelSorts": {
        for (final entry in panelSorts.entries)
          entry.key: [entry.value.$1, entry.value.$2],
      },
      "splitShares": splitShares,
      "splitFraction": splitFraction,
      "columnWidths": {
        for (final entry in columnWidths.entries) entry.key.name: entry.value,
      },
      "collapsed": collapsed.toList(),
      "coverCollapsed": coverCollapsed,
      "detailsExtra": detailsExtra,
    }),
  );
}
