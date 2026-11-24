import "dart:async";
import "dart:math";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_wasabi/amped_wasabi.dart" show WasabiComponentOptions;
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "../player/tag_cache.dart";
import "cover_grid.dart";
import "description_text.dart";
import "library_sources.dart";
import "library_view_settings.dart";
import "media_library.dart";
import "play_stats.dart";
import "saved_playlists.dart";
import "source_settings.dart";
import "watch_folders.dart";

ImageProvider _networkImage(String url) => NetworkImage(url);

/// What the Media Library window shows: a search box, the artists and
/// albums on the left, the matching tracks on the right. Double-clicking a
/// track plays it; the buttons play or enqueue the selected track (or all
/// that are listed, when none is selected).
class LibraryView extends StatefulWidget {
  /// A search to put in the library's search box, from outside it (a
  /// notification's link to its artist): the view takes it and clears it.
  static final ValueNotifier<String?> searchRequest = ValueNotifier(null);

  const LibraryView({
    required this.library,
    required this.colors,
    required this.localizations,
    required this.onPlay,
    required this.onEnqueue,
    required this.onAddMedia,
    required this.onContextMenu,
    this.buttonBuilder,
    this.sections,
    this.skin,
    this.playlists,
    this.playStats,
    this.onSavePlaylist,
    this.onNewPlaylist,
    this.onRemoveFromPlaylist,
    this.onMoveInPlaylist,
    this.onDropOnPlaylist,
    this.onImportPlaylists,
    this.onPlaylistMenu,
    this.settings = const LibraryViewSettings(),
    this.onSettingsChanged,
    this.coverProvider = _networkImage,
    this.coverLoader,
    this.onOpenArtwork,
    this.onPlayAt,
    super.key,
  });

  /// Opens a picture (the cover of the details) in a window of its own, with
  /// the title it has there.
  final void Function(String title, ImageProvider image)? onOpenArtwork;

  /// Plays the track at a path from a time (a time in a description that
  /// was clicked).
  final void Function(String path, Duration at)? onPlayAt;

  /// Reads the picture of the track at a path (embedded, beside it or from
  /// its source), for the cover of music; null for none.
  final Future<Uint8List?> Function(String path)? coverLoader;

  /// Loads the picture at a URL, for the cover of a podcast or episode.
  final ImageProvider Function(String url) coverProvider;

  /// What was remembered of how the library was left; it starts that way.
  final LibraryViewSettings settings;

  /// Told whenever the source, the picks, the sorting, the column order or
  /// the folded sections change, to be kept.
  final ValueChanged<LibraryViewSettings>? onSettingsChanged;

  /// The playlists kept in the library, listed in the tree's "Playlists"
  /// section; null for no such section.
  final SavedPlaylists? playlists;

  /// How often things were played, listed in the tree's "Statistics"
  /// section; null for no such section.
  final PlayStats? playStats;

  /// Saves the player's playlist as a saved playlist.
  final VoidCallback? onSavePlaylist;

  /// Asks for a name and creates an empty saved playlist.
  final VoidCallback? onNewPlaylist;

  /// Removes the entries at these indices from the saved playlist with this
  /// id (Delete, in its track list).
  final void Function(int id, List<int> indices)? onRemoveFromPlaylist;

  /// Moves the entries at these indices of the saved playlist with this id
  /// so that they land before the entry at the last index (the end for the
  /// playlist's length): reordering, by Alt+Up/Down or by dragging.
  final void Function(int id, List<int> indices, int to)? onMoveInPlaylist;

  /// Adds the files dragged from a track list to the saved playlist with
  /// this id.
  final void Function(int id, List<String> paths)? onDropOnPlaylist;

  /// Asks for playlist files to import.
  final VoidCallback? onImportPlaylists;

  /// Shows the context menu of the saved playlist with this id.
  final void Function(int id)? onPlaylistMenu;

  /// The local library: what the "Local" source browses.
  final MediaLibrary library;

  /// The tree of sources on the left, or null for just the local library.
  /// Other source types (URLs and, later, Navidrome, Plex, ...) add sections
  /// here; a source without a library of its own can't be browsed yet.
  final List<LibrarySourceSection>? sections;

  /// The colours of the lists, from the skin's playlist editor.
  final PlEditConfig colors;

  /// The classic skin whose scrollbar the lists use; without one they get a
  /// scrollbar in [colors].
  final ClassicSkinData? skin;
  final AppLocalizations localizations;

  /// Replaces the playlist with the files and plays them.
  final void Function(List<String> paths) onPlay;

  /// Adds the files to the playlist.
  final void Function(List<String> paths) onEnqueue;

  /// Asks for folders to add to the library.
  final VoidCallback onAddMedia;

  /// Shows the context menu of the selected tracks (the one that was
  /// right-clicked, unless it is part of a larger selection), at the pointer.
  final void Function(List<String> paths) onContextMenu;

  /// Draws the library's push buttons (Add media, Enqueue, Play), for a
  /// skin that has buttons of its own; null for the plain strip buttons.
  final Widget Function(String label, bool enabled, VoidCallback onPressed)?
  buttonBuilder;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  /// The artists and albums picked on the left; none of either shows
  /// everything.
  Set<String> _artists = {};
  Set<String> _albums = {};

  /// The categories (genres) and playlists picked among the movies.
  Set<String> _categories = {};
  Set<String> _lists = {};

  /// The tracks selected on the right.
  Set<String> _selected = {};

  /// The source picked in the tree, and the sections folded away.
  String _sourceId = localSourceId;
  final Set<String> _collapsed = {};

  /// The source tree's width, dragged with the divider.
  double _treeWidth = _minTreeWidth;

  static const double _minTreeWidth = 80;

  /// Where a shift-click on the artists and albums starts its range.
  String? _artistAnchor;
  String? _albumAnchor;

  /// Where a shift-click on the tracks starts its range.
  String? _trackAnchor;

  /// The track the arrow keys moved to last, and the paths of the tracks
  /// listed, in order, which they move through.
  String? _cursor;
  List<String> _navPaths = const [];

  /// The panel the arrow keys act on (by its name: `tracks`, `artists`,
  /// `albums`, `authors`, `series`, `books`, `browser` or `list`), the
  /// panels there are now left to right, what each lists to move through,
  /// and how each scrolls.
  String _focusPane = "tracks";
  List<String> _panes = const ["tracks"];
  Map<String, List<_PaneRow>> _paneRows = {};
  final Map<String, ScrollController> _paneScrolls = {};

  ScrollController _scrollOf(String pane) =>
      _paneScrolls.putIfAbsent(pane, ScrollController.new);

  /// Keeps a panel and its scroll where it is when the tree around it is
  /// rebuilt differently (the details panel appearing under it): a scroll
  /// controller must not be on two lists at once.
  final Map<String, GlobalKey> _paneKeys = {};
  Key _keyOf(String pane) => _paneKeys.putIfAbsent(pane, GlobalKey.new);

  void _focusOn(String pane) {
    if (_focusPane == pane) return;
    setState(() => _focusPane = pane);
  }

  /// The tables of tracks, which the arrow keys scroll to keep the track they
  /// reach in view, and the list of a saved playlist.
  final GlobalKey<_TrackTableState> _musicTable = GlobalKey();
  final GlobalKey<_TrackTableState> _podcastTable = GlobalKey();
  final ScrollController _playlistScroll = ScrollController();

  /// Scrolls the track list of the compact layout.
  final ScrollController _compactScroll = ScrollController();

  /// Narrower than this, the library shows only a track list, a search field
  /// and a menu: the rest has no room.
  static const double _compactBelow = 300;

  /// The column the episodes of a podcast are sorted by, and the direction;
  /// newest first until a heading is clicked.
  LibraryColumn _sortColumn = LibraryColumn.published;
  bool _sortAscending = false;

  /// The episode columns, in the order they are shown.
  List<LibraryColumn> _columns = LibraryColumn.values;

  /// How each split panel is sorted, by the panel's name, and how the width is
  /// shared among the panels of each split layout ("music", "books").
  Map<String, _PanelSort> _panelSorts = {};
  Map<String, List<double>> _splitShares = {};

  /// The columns of the parts of audiobooks, in order, and how they are sorted
  /// (null: by book, then part).
  List<LibraryColumn> _bookColumns = LibraryColumn.book;
  LibraryColumn? _bookSortColumn;
  bool _bookSortAscending = true;

  /// The series picked among the audiobooks, and how they are laid out
  /// (split by default: authors, series and books above the parts).
  Set<String> _series = {};
  MusicLayout _bookLayout = MusicLayout.split;
  MusicLayout _movieLayout = MusicLayout.tracks;
  VideoSort _videoSort = VideoSort.name;

  /// Whether what was watched (movies, shows) or listened to (podcasts,
  /// audiobooks) is left out.
  bool _hideWatched = false;
  bool _hideListened = false;

  /// How wide the covers are, by what is shown ("music", "books",
  /// "podcasts", "movies", "shows").
  Map<String, double> _coverSizes = {};
  VideoFilter _videoFilter = VideoFilter.all;
  MusicLayout _podcastLayout = MusicLayout.browser;

  /// How music is laid out, and how much of the height the artist and album
  /// panels have in the split layout.
  MusicLayout _musicLayout = MusicLayout.browser;
  double _splitFraction = 0.4;

  /// The columns of music, in order, and how music is sorted (null: as the
  /// library has it).
  List<LibraryColumn> _musicColumns = LibraryColumn.music;
  List<LibraryColumn> _movieColumns = LibraryColumn.movies;
  List<LibraryColumn> _showColumns = LibraryColumn.shows;
  LibraryColumn? _musicSortColumn;
  bool _musicSortAscending = true;

  /// The widths columns were dragged to; the others have their usual one.
  Map<LibraryColumn, double> _columnWidths = {};

  /// Whether the cover under the podcasts is folded away.
  bool _coverCollapsed = false;

  /// How much taller than its usual height the details panel was dragged.
  double _detailsExtra = 0;

  /// The least width of either pane: how wide the artists pane starts.
  static const double _minPaneWidth = 120;

  /// The artists pane's width, dragged with the divider.
  double _browserWidth = _minPaneWidth;

  /// Set for [_cancelWindow] after the first Escape of a scan.
  Timer? _cancelPrompt;

  /// How long "Press Esc again" waits for the second press.
  static const _cancelWindow = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    final saved = widget.settings;
    _sourceId = saved.sourceId;
    _artists = {...saved.artists};
    _albums = {...saved.albums};
    _sortColumn = saved.sortColumn;
    _sortAscending = saved.sortAscending;
    _columns = saved.columns;
    _musicColumns = saved.musicColumns;
    _movieColumns = saved.movieColumns;
    _showColumns = saved.showColumns;
    _musicLayout = saved.musicLayout;
    _bookLayout = saved.bookLayout;
    _movieLayout = saved.movieLayout;
    _videoSort = saved.videoSort;
    _treeWidth = max(_minTreeWidth, saved.treeWidth);
    _browserWidth = max(_minPaneWidth, saved.browserWidth);
    _hideWatched = saved.hideWatched;
    _hideListened = saved.hideListened;
    _coverSizes = {...saved.coverSizes};
    _videoFilter = saved.videoFilter;
    _podcastLayout = saved.podcastLayout;
    _bookColumns = saved.bookColumns;
    _bookSortColumn = saved.bookSortColumn;
    _bookSortAscending = saved.bookSortAscending;
    _panelSorts = {
      for (final entry in saved.panelSorts.entries)
        entry.key: _PanelSort(entry.value.$1, ascending: entry.value.$2),
    };
    _splitShares = {...saved.splitShares};
    _splitFraction = saved.splitFraction;
    _musicSortColumn = saved.musicSortColumn;
    _musicSortAscending = saved.musicSortAscending;
    _columnWidths = {...saved.columnWidths};
    _coverCollapsed = saved.coverCollapsed;
    _detailsExtra = saved.detailsExtra;
    _collapsed.addAll(saved.collapsed);
    _query.addListener(_changed);
    LibraryView.searchRequest.addListener(_takeSearchRequest);
    _takeSearchRequest();
    // A remote source that was left open loads its tracks again.
    if (_sourceId != localSourceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _source?.onOpen?.call();
      });
    }
  }

  /// Hands what is worth remembering to the app.
  void _remember() => widget.onSettingsChanged?.call(
    LibraryViewSettings(
      sourceId: _sourceId,
      artists: {..._artists},
      albums: {..._albums},
      sortColumn: _sortColumn,
      sortAscending: _sortAscending,
      columns: _columns,
      musicColumns: _musicColumns,
      movieColumns: _movieColumns,
      showColumns: _showColumns,
      musicLayout: _musicLayout,
      bookLayout: _bookLayout,
      movieLayout: _movieLayout,
      videoSort: _videoSort,
      treeWidth: _treeWidth,
      browserWidth: _browserWidth,
      hideWatched: _hideWatched,
      hideListened: _hideListened,
      coverSizes: _coverSizes,
      videoFilter: _videoFilter,
      podcastLayout: _podcastLayout,
      bookColumns: _bookColumns,
      bookSortColumn: _bookSortColumn,
      bookSortAscending: _bookSortAscending,
      panelSorts: {
        for (final entry in _panelSorts.entries)
          entry.key: (entry.value.column, entry.value.ascending),
      },
      splitShares: {..._splitShares},
      splitFraction: _splitFraction,
      musicSortColumn: _musicSortColumn,
      musicSortAscending: _musicSortAscending,
      columnWidths: {..._columnWidths},
      collapsed: {..._collapsed},
      coverCollapsed: _coverCollapsed,
      detailsExtra: _detailsExtra,
    ),
  );

  void _resizeColumn(LibraryColumn column, double width) => setState(() {
    _columnWidths = {
      ..._columnWidths,
      column: width.clamp(_columnMinWidth, 800.0),
    };
    _remember();
  });

  void _resetColumn(LibraryColumn column) => setState(() {
    _columnWidths = {..._columnWidths}..remove(column);
    _remember();
  });

  /// Makes the details panel [more] taller (less, when negative), never
  /// shorter than it usually is and never more than [most] taller.
  void _growDetails(double more, double most) => setState(() {
    _detailsExtra = (_detailsExtra + more).clamp(0, max(0, most));
    _remember();
  });

  void _toggleCover() => setState(() {
    _coverCollapsed = !_coverCollapsed;
    _remember();
  });

  void _takeSearchRequest() {
    final request = LibraryView.searchRequest.value;
    if (request == null) return;
    LibraryView.searchRequest.value = null;
    _query.text = request;
  }

  @override
  void dispose() {
    LibraryView.searchRequest.removeListener(_takeSearchRequest);
    _cancelPrompt?.cancel();
    _query
      ..removeListener(_changed)
      ..dispose();
    _queryFocus.dispose();
    _playlistScroll.dispose();
    _compactScroll.dispose();
    for (final controller in _paneScrolls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Moves the track the arrow keys are on: [target] is given where it is
  /// now (-1 for none), how many are listed and how many make a page, and
  /// says where to go. With [extend] the tracks between where the selection
  /// started and the new one are all selected.
  void _moveTrack(
    int Function(int at, int count, int page) target, {
    bool extend = false,
  }) {
    final paths = _navPaths;
    if (paths.isEmpty) return;
    final at = _cursor == null ? -1 : paths.indexOf(_cursor!);
    final scroll =
        (_compactScroll.hasClients ? _compactScroll : null) ??
        _musicTable.currentState?.scroll ??
        _podcastTable.currentState?.scroll ??
        _playlistScroll;
    final positions = scroll.positions;
    final viewport = positions.isEmpty ? 0.0 : positions.last.viewportDimension;
    final page = max(1, (viewport / _SkinList.rowHeight).floor() - 1);
    final to = target(at, paths.length, page).clamp(0, paths.length - 1);
    setState(() {
      final anchor = _trackAnchor == null ? -1 : paths.indexOf(_trackAnchor!);
      if (extend && anchor >= 0) {
        // The tracks from the anchor to the new one, the new one last.
        final range = paths.sublist(min(anchor, to), max(anchor, to) + 1);
        _selected = {...range.where((p) => p != paths[to]), paths[to]};
      } else {
        _selected = {paths[to]};
        _trackAnchor = paths[to];
      }
      _cursor = paths[to];
    });
    // Scrolled the least that shows it.
    if (positions.isNotEmpty) {
      final position = positions.last;
      final top = to * _SkinList.rowHeight;
      final bottom = top + _SkinList.rowHeight;
      if (top < position.pixels) {
        scroll.jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        scroll.jumpTo(
          (bottom - position.viewportDimension).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
      }
    }
  }

  /// Moves through the rows of the panel [pane] as [_moveTrack] does through
  /// the tracks: picks the row [target] says (given where the picked one
  /// is, how many rows there are and how many make a page), and keeps it in
  /// view.
  void _movePane(
    String pane,
    int Function(int at, int count, int page) target,
  ) {
    final rows = _paneRows[pane] ?? const <_PaneRow>[];
    if (rows.isEmpty) return;
    final at = rows.lastIndexWhere((row) => row.selected);
    final positions = _scrollOf(pane).positions;
    final viewport = positions.isEmpty ? 0.0 : positions.last.viewportDimension;
    final page = max(1, (viewport / _SkinList.rowHeight).floor() - 1);
    final to = target(at, rows.length, page).clamp(0, rows.length - 1);
    if (to != at) rows[to].pick();
    if (positions.isNotEmpty) {
      final position = positions.last;
      final top = to * _SkinList.rowHeight;
      final bottom = top + _SkinList.rowHeight;
      if (top < position.pixels) {
        _scrollOf(pane).jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scrollOf(pane).jumpTo(
          (bottom - position.viewportDimension).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
      }
    }
  }

  /// The arrow keys, Home, End and the page keys move through the rows of
  /// the panel that has the focus (the tracks, or the list of artists...),
  /// Left and Right move the focus between panels, and Enter plays (rather
  /// than seeking, changing the volume or doing nothing, as elsewhere).
  /// Whether [event] was one of those.
  bool _navigationKey(KeyEvent event) {
    if (event is KeyUpEvent || _queryFocus.hasFocus) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return false;
    }
    final extend = keys.isShiftPressed;
    final key = event.logicalKey;
    final onTracks =
        _focusPane == "tracks" || !_paneRows.containsKey(_focusPane);
    void move(int Function(int at, int count, int page) target) => onTracks
        ? _moveTrack(target, extend: extend)
        : _movePane(_focusPane, target);
    if (key == LogicalKeyboardKey.arrowDown) {
      move((at, count, page) => at + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      move((at, count, page) => at < 0 ? count - 1 : at - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      move((at, count, page) => at + page);
    } else if (key == LogicalKeyboardKey.pageUp) {
      move((at, count, page) => at < 0 ? count - 1 : at - page);
    } else if (key == LogicalKeyboardKey.home) {
      move((at, count, page) => 0);
    } else if (key == LogicalKeyboardKey.end) {
      move((at, count, page) => count - 1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // To the panel beside this one, if there is one.
      final to =
          _panes.indexOf(_focusPane) +
          (key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      if (to >= 0 && to < _panes.length && _panes[to] != _focusPane) {
        setState(() => _focusPane = _panes[to]);
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is! KeyDownEvent) return true;
      // On the tracks: what is selected. On a list of artists or books:
      // all the tracks it has narrowed the tracks to.
      final paths = [
        for (final path in _navPaths)
          if (!onTracks || _selected.contains(path)) path,
      ];
      if (paths.isNotEmpty) {
        (extend ? widget.onEnqueue : widget.onPlay)(paths);
      }
    } else {
      return false;
    }
    return true;
  }

  /// Escape while files are being added: the first press asks to confirm,
  /// a second one within three seconds cancels the scan.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final playlistId = _source?.playlistId;
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) &&
        !_queryFocus.hasFocus &&
        _selected.isNotEmpty &&
        playlistId != null) {
      final items = widget.playlists?.byId(playlistId)?.items ?? const [];
      widget.onRemoveFromPlaylist?.call(playlistId, [
        for (final (i, item) in items.indexed)
          if (_selected.contains(item.location)) i,
      ]);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isAltPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) &&
        !_queryFocus.hasFocus &&
        _selected.isNotEmpty &&
        playlistId != null) {
      final items = widget.playlists?.byId(playlistId)?.items ?? const [];
      final indices = [
        for (final (i, item) in items.indexed)
          if (_selected.contains(item.location)) i,
      ];
      if (indices.isNotEmpty) {
        final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
        widget.onMoveInPlaylist?.call(
          playlistId,
          indices,
          up ? max(0, indices.first - 1) : min(items.length, indices.last + 2),
        );
      }
      return KeyEventResult.handled;
    }
    if (_navigationKey(event)) return KeyEventResult.handled;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !widget.library.scanning) {
      return KeyEventResult.ignored;
    }
    if (_cancelPrompt != null) {
      _cancelPrompt!.cancel();
      setState(() => _cancelPrompt = null);
      widget.library.cancel();
    } else {
      setState(() {
        _cancelPrompt = Timer(_cancelWindow, () {
          if (mounted) setState(() => _cancelPrompt = null);
        });
      });
    }
    return KeyEventResult.handled;
  }

  static bool get _additive =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  static bool get _ranged => HardwareKeyboard.instance.isShiftPressed;

  /// The picks of [anchor] to [name] in [names] when shift is held, the
  /// picks of [current] with [name] toggled with ctrl/cmd, else just [name].
  Set<String> _pick(
    List<String> names,
    String name,
    String? anchor,
    Set<String> current,
  ) {
    final from = anchor == null ? -1 : names.indexOf(anchor);
    final to = names.indexOf(name);
    if (_ranged && from >= 0 && to >= 0) {
      final range = names.sublist(min(from, to), max(from, to) + 1);
      return {if (_additive) ...current, ...range};
    }
    if (_additive) {
      return current.contains(name)
          ? ({...current}..remove(name))
          : {...current, name};
    }
    return {name};
  }

  List<LibrarySourceSection> get _sections {
    final saved = widget.playlists;
    final texts = widget.localizations;
    return [
      ...(widget.sections ??
          librarySections(
            widget.library,
            localLabel: widget.localizations.mlSourceLocal,
          )),
      if (saved != null)
        LibrarySourceSection(
          id: playlistsSectionId,
          kind: LibrarySourceKind.playlists,
          sources: [
            for (final playlist in saved.playlists)
              LibrarySource(
                id: "$playlistSourcePrefix${playlist.id}",
                label: playlist.name,
                playlistId: playlist.id,
              ),
          ],
          actions: [
            if (widget.onNewPlaylist case final create?)
              LibrarySectionAction(
                widget.localizations.mlNewPlaylistRow,
                create,
              ),
            if (widget.onSavePlaylist case final save?)
              LibrarySectionAction(
                widget.localizations.mlSavePlaylistRow,
                save,
              ),
            if (widget.onImportPlaylists case final import?)
              LibrarySectionAction(
                widget.localizations.mlImportPlaylistRow,
                import,
              ),
          ],
        ),
      if (widget.playStats != null)
        LibrarySourceSection(
          id: statisticsSectionId,
          kind: LibrarySourceKind.statistics,
          sources: [
            for (final (list, label) in [
              (PlayList.mostPlayed, texts.mlStatsMostPlayed),
              (PlayList.recentlyPlayed, texts.mlStatsRecentlyPlayed),
              (PlayList.videos, texts.mlStatsMostPlayedVideos),
              (PlayList.podcasts, texts.mlStatsMostPlayedPodcasts),
            ])
              LibrarySource(
                id: "$statisticsSourcePrefix${list.name}",
                label: label,
                playList: list,
              ),
          ],
        ),
    ];
  }

  /// The rows of the play statistics list [list].
  List<PlayRow> _statRows(PlayList list) {
    final stats = widget.playStats;
    if (stats == null) return const [];
    return switch (list) {
      PlayList.mostPlayed => stats.mostPlayed(PlayKind.music),
      PlayList.recentlyPlayed => stats.recentlyPlayed(PlayKind.music),
      PlayList.videos => stats.mostPlayed(PlayKind.video),
      PlayList.podcasts => stats.mostPlayed(PlayKind.podcast),
    };
  }

  LibrarySource? get _source {
    for (final section in _sections) {
      for (final source in section.sources) {
        if (source.id == _sourceId) return source;
      }
    }
    return null;
  }

  void _pickSource(String id) {
    if (id == _sourceId) return;
    setState(() {
      _sourceId = id;
      _artists = {};
      _albums = {};
      _categories = {};
      _lists = {};
      _series = {};
      _selected = {};
      _artistAnchor = _albumAnchor = _trackAnchor = null;
      _query.clear();
    });
    _remember();
    // After the state change: opening may load tracks, which notifies the
    // listeners.
    _source?.onOpen?.call();
  }

  /// Sorts by [column]; again on the same column reverses the order.
  void _sortBy(LibraryColumn column) => setState(() {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      // Dates and numbers start with the newest, text with A.
      _sortAscending =
          column == LibraryColumn.title ||
          column == LibraryColumn.album ||
          column == LibraryColumn.length;
      if (column == LibraryColumn.progress) _sortAscending = false;
    }
    _remember();
  });

  void _setHideWatched(bool hide) => setState(() {
    _hideWatched = hide;
    _selected = {};
    _remember();
  });

  void _setVideoSort(VideoSort sort) => setState(() {
    _videoSort = sort;
    _remember();
  });

  void _setVideoFilter(VideoFilter filter) => setState(() {
    _videoFilter = filter;
    _selected = {};
    _remember();
  });

  /// Sorts the music by [column]; again on the same column reverses it.
  void _sortMusicBy(LibraryColumn column) => setState(() {
    if (_musicSortColumn == column) {
      _musicSortAscending = !_musicSortAscending;
    } else {
      _musicSortColumn = column;
      _musicSortAscending = true;
    }
    _remember();
  });

  /// Sorts the parts of audiobooks by [column]; again on the same column
  /// reverses it.
  void _sortBooksBy(LibraryColumn column) => setState(() {
    if (_bookSortColumn == column) {
      _bookSortAscending = !_bookSortAscending;
    } else {
      _bookSortColumn = column;
      _bookSortAscending = true;
    }
    _remember();
  });

  /// Moves the column [moved] to where [target] is, among the columns of
  /// music, of audiobooks or of episodes.
  void _moveColumn(
    LibraryColumn moved,
    LibraryColumn target, {
    bool music = false,
    bool books = false,
    bool movies = false,
    bool shows = false,
  }) {
    if (moved == target) return;
    setState(() {
      final was = movies
          ? _movieColumns
          : shows
          ? _showColumns
          : music
          ? _musicColumns
          : books
          ? _bookColumns
          : _columns;
      final order = [...was]..remove(moved);
      order.insert(
        order.indexOf(target) +
            (was.indexOf(moved) < was.indexOf(target) ? 1 : 0),
        moved,
      );
      if (movies) {
        _movieColumns = order;
      } else if (shows) {
        _showColumns = order;
      } else if (music) {
        _musicColumns = order;
      } else if (books) {
        _bookColumns = order;
      } else {
        _columns = order;
      }
      _remember();
    });
  }

  void _toggleSection(String id) => setState(() {
    if (!_collapsed.remove(id)) _collapsed.add(id);
    _remember();
  });

  /// Picks the album [title] among the [titles] listed, leaving the artists
  /// picked as they are (the albums panel is beside the artists, not under
  /// them).
  void _pickAlbumOnly(String title, List<String> titles) => setState(() {
    _albums = _pick(titles, title, _albumAnchor, _albums);
    if (!_ranged) _albumAnchor = title;
    _selected = {};
    _remember();
  });

  /// The tracks the row [name] of the split panel [panel] stands for (all the
  /// panel lists, when [name] is empty), among [all]: those of the artist or
  /// author, series or book, within what the panels before it have picked.
  List<String> _groupPaths(String panel, String name, List<TrackTags> all) {
    bool byAuthor(TrackTags t) =>
        _artists.isEmpty || _artists.contains(t.artist);
    bool bySeries(TrackTags t) => _series.isEmpty || _series.contains(t.series);
    bool named(String? value) => name.isEmpty || value == name;
    final matches = switch (panel) {
      "artists" ||
      "authors" => (TrackTags t) => t.artist != null && named(t.artist),
      "albums" => (
        TrackTags t,
      ) => t.album != null && named(t.album) && byAuthor(t),
      "series" => (
        TrackTags t,
      ) => t.series != null && named(t.series) && byAuthor(t),
      "books" => (
        TrackTags t,
      ) => t.album != null && named(t.album) && byAuthor(t) && bySeries(t),
      _ => (TrackTags t) => false,
    };
    return [
      for (final track in all)
        if (matches(track)) track.path,
    ];
  }

  /// The tiles of the cover grid for [all]: an album of music, a book, a
  /// podcast or a show, or a movie by itself. [paths] are the tracks as
  /// listed, which the arrow keys move through.
  List<CoverItem> _coverItems(
    List<TrackTags> all,
    List<String> paths, {
    required bool books,
    required bool podcasts,
    required bool movies,
    required bool shows,
  }) {
    final l = widget.localizations;
    if (movies) {
      return [
        for (final track in all)
          CoverItem(
            key: track.path,
            title: track.title ?? _TrackItem.label(track),
            subtitle: "${track.year ?? ""}",
            badge: (track.progress ?? 0) >= 1 ? "✓" : null,
            coverPath: track.path,
            picked: _selected.contains(track.path),
            onTap: () => _selectTrack(track.path, paths),
            onPlay: () => widget.onPlay([track.path]),
            onMenu: () => _trackMenu(track.path, paths),
          ),
      ];
    }
    // Groups, in the order the tracks list them.
    final groups = <String, List<TrackTags>>{};
    String name(TrackTags t) => shows
        ? (t.artist ?? "")
        : (t.album ?? (books || podcasts ? "" : t.artist ?? ""));
    for (final track in all) {
      final key = podcasts || books || shows
          ? name(track)
          : "${track.artist}\u0000${track.album}";
      (groups[key] ??= []).add(track);
    }
    final titles = [
      for (final group in groups.values) name(group.first),
    ];
    final counts = podcasts && !books
        ? _episodeCounts(all, _source?.completion ?? const PodcastCompletion())
        : const <String, ({int total, int unplayed})>{};
    return [
      for (final entry in groups.entries)
        () {
          final group = entry.value;
          final first = group.first;
          final title = name(first);
          final groupPaths = [for (final t in group) t.path];
          final bool picked;
          final VoidCallback tap;
          final String subtitle;
          if (shows) {
            picked = _artists.contains(first.artist);
            tap = () => _pickArtist(title, titles);
            subtitle = l.mlSeasonCount(
              {
                for (final t in group) t.album,
              }.length,
            );
          } else if (books) {
            picked = _albums.contains(first.album);
            tap = () => _pickAlbumOnly(title, titles);
            subtitle = first.artist ?? "";
          } else if (podcasts) {
            picked = _albums.contains(first.album);
            tap = () => _pickAlbum(null, title, titles);
            final count = counts[title];
            subtitle = count == null
                ? ""
                : "${count.unplayed} (${count.total})";
          } else {
            picked =
                _albums.contains(first.album) &&
                (_artists.isEmpty || _artists.contains(first.artist));
            tap = () => _pickAlbum(first.artist, first.album ?? "", titles);
            subtitle = first.artist ?? "";
          }
          return CoverItem(
            key: entry.key,
            title: title,
            subtitle: subtitle,
            coverPath: first.path,
            picked: picked,
            onTap: tap,
            onPlay: () => widget.onPlay(groupPaths),
            onMenu: () {
              if (!picked) tap();
              widget.onContextMenu(groupPaths);
            },
          );
        }(),
    ];
  }

  /// The groups of [all] by what [key] says (those without it left out), in
  /// the order they first come.
  Map<String, List<TrackTags>> _groupsBy(
    List<TrackTags> all,
    String? Function(TrackTags track) key,
  ) {
    final groups = <String, List<TrackTags>>{};
    for (final track in all) {
      final name = key(track);
      if (name != null) (groups[name] ??= []).add(track);
    }
    return groups;
  }

  /// The tiles of the shows, or of the artists, of [all]: the picture of a
  /// show or an artist, which the first of their tracks knows.
  List<CoverItem> _artistTiles(List<TrackTags> all, {required bool shows}) {
    final l = widget.localizations;
    final groups = _groupsBy(all, (t) => t.artist);
    final names = groups.keys.toList();
    final dates = shows ? _showDates(all, _videoSort) : null;
    if (dates != null && _videoSort != VideoSort.name) {
      names.sort((a, b) {
        final x = dates[a];
        final y = dates[b];
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });
    }
    return [
      for (final name in names)
        () {
          final group = groups[name]!;
          final first = group.first;
          final count = {for (final t in group) t.album}.length;
          final watched = shows && group.every((t) => (t.progress ?? 0) >= 1);
          void tap() => _pickArtist(name, names);
          final picked = _artists.contains(name);
          return CoverItem(
            key: "artist:$name",
            title: name,
            subtitle: shows ? l.mlSeasonCount(count) : l.mlAlbumCount(count),
            badge: watched ? "✓" : null,
            coverPath: first.path,
            imageUrl: shows ? first.showImageUrl : first.artistImageUrl,
            picked: picked,
            onTap: tap,
            onPlay: () => widget.onPlay([for (final t in group) t.path]),
            onMenu: () {
              if (!picked) tap();
              widget.onContextMenu([for (final t in group) t.path]);
            },
          );
        }(),
    ];
  }

  /// The tiles of the seasons, or of the albums, of [all] that belong to
  /// the shows or artists picked.
  List<CoverItem> _albumTiles(List<TrackTags> all, {required bool shows}) {
    final l = widget.localizations;
    final here = [
      for (final t in all)
        if (_artists.isEmpty || _artists.contains(t.artist)) t,
    ];
    final groups = <String, List<TrackTags>>{};
    for (final t in here) {
      if (t.album == null) continue;
      (groups["${t.artist}\u0000${t.album}"] ??= []).add(t);
    }
    final titles = {for (final g in groups.values) g.first.album!}.toList();
    return [
      for (final entry in groups.entries)
        () {
          final group = entry.value;
          final first = group.first;
          final title = first.album!;
          final watched = shows && group.every((t) => (t.progress ?? 0) >= 1);
          void tap() => _pickAlbumOnly(title, titles);
          final picked = _albums.contains(title);
          return CoverItem(
            key: "album:${entry.key}",
            title: title,
            subtitle: shows
                ? "${l.mlColumnEpisodes}: ${group.length}"
                : first.artist ?? "",
            badge: watched ? "✓" : null,
            coverPath: first.path,
            imageUrl: shows ? first.seasonImageUrl : null,
            picked: picked,
            onTap: tap,
            onPlay: () => widget.onPlay([for (final t in group) t.path]),
            onMenu: () {
              if (!picked) tap();
              widget.onContextMenu([for (final t in group) t.path]);
            },
          );
        }(),
    ];
  }

  /// The tiles of the episodes in [tracks], each with its own picture.
  List<CoverItem> _episodeTiles(List<TrackTags> tracks, List<String> paths) => [
    for (final track in tracks)
      CoverItem(
        key: "episode:${track.path}",
        title: track.title ?? _TrackItem.label(track),
        subtitle: "S${track.discNumber ?? "?"}E${track.trackNumber ?? "?"}",
        badge: (track.progress ?? 0) >= 1 ? "✓" : null,
        coverPath: track.path,
        imageUrl: track.imageUrl,
        picked: _selected.contains(track.path),
        onTap: () => _selectTrack(track.path, paths),
        onPlay: () => widget.onPlay([track.path]),
        onMenu: () => _trackMenu(track.path, paths),
      ),
  ];

  /// Panels side by side with a bar between them, sharing the width as
  /// [flex] says.
  Widget _coverColumns(
    List<Widget> panes,
    PlEditConfig colors, {
    List<int>? flex,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, pane) in panes.indexed) ...[
        if (i > 0)
          SizedBox(
            width: _PaneDivider.width,
            child: Center(
              child: SizedBox(
                width: _dividerLine,
                child: ColoredBox(color: colors.normal.withAlpha(215)),
              ),
            ),
          ),
        Expanded(flex: flex?[i] ?? 1, child: pane),
      ],
    ],
  );

  /// The grid of covers for [items], with the scroll and keys of its panel.
  Widget _coverGrid(
    List<CoverItem> items,
    PlEditConfig colors, {
    String id = "covers",
    double tileWidth = CoverGrid.defaultTileWidth,
  }) {
    _paneRows[id] = [
      for (final item in items) (selected: item.picked, pick: item.onTap),
    ];
    return _PaneFocus(
      key: _keyOf(id),
      id: id,
      focus: _focusPane,
      onFocus: _focusOn,
      colors: colors,
      child: CoverGrid(
        items: items,
        colors: colors,
        controller: _scrollOf(id),
        loader: widget.coverLoader,
        provider: widget.coverProvider,
        tileWidth: tileWidth,
        scrollbar: (controller) => _ListScrollbar(
          skin: widget.skin,
          colors: colors,
          controller: controller,
        ),
      ),
    );
  }

  /// Opens the context menu for the tracks of a row of a panel.
  void _panelMenu(String panel, String name, List<TrackTags> all) {
    final paths = _groupPaths(panel, name, all);
    if (paths.isNotEmpty) widget.onContextMenu(paths);
  }

  /// A heading of the split panel [panel] was clicked.
  void _sortPanel(String panel, int column) => setState(() {
    _panelSorts = {
      ..._panelSorts,
      panel: (_panelSorts[panel] ?? _PanelSort.byName).click(column),
    };
    _remember();
  });

  /// The bar after panel [divider] of the [count] panels of the layout [key]
  /// was dragged by [moved] pixels of the [width] they share: that panel
  /// gets more, the next less, neither under its least width.
  void _resizePanels(
    String key,
    int count,
    int divider,
    double moved,
    double width,
    List<double> leasts,
  ) {
    if (width <= 0) return;
    final shares = [..._SplitPanels.sharesOf(_splitShares[key], count)];
    final pair = shares[divider] + shares[divider + 1];
    // Neither keeps less than its least (if both cannot, the split stays).
    final leastLeft = leasts[divider] / width;
    final leastRight = leasts[divider + 1] / width;
    if (leastLeft + leastRight > pair) return;
    final left = (shares[divider] + moved / width).clamp(
      leastLeft,
      pair - leastRight,
    );
    shares[divider] = left;
    shares[divider + 1] = pair - left;
    setState(() {
      _splitShares = {..._splitShares, key: shares};
      _remember();
    });
  }

  /// The bar of the split layout moved by [moved] of the height.
  void _moveSplit(double moved) => setState(() {
    _splitFraction = (_splitFraction + moved).clamp(0.1, 0.9);
    _remember();
  });

  /// Picks the series [name] among those [listed]: its books are listed.
  void _pickSeries(String name, List<String> listed) => setState(() {
    _series = _pick(listed, name, null, _series);
    _albums = {};
    _selected = {};
    _remember();
  });

  void _pickNoSeries() => setState(() {
    _series = {};
    _albums = {};
    _selected = {};
    _remember();
  });

  void _setBookLayout(MusicLayout layout) => setState(() {
    if (_source?.audiobooks ?? false) {
      _bookLayout = layout;
    } else {
      _podcastLayout = layout;
    }
    _carryPicks(books: true);
    _remember();
  });

  /// Makes the picks of the panels agree with the one item picked, so that a
  /// layout with other panels shows it: the artist (or author), series and
  /// album (book) of the one track selected, or of the one album picked.
  void _carryPicks({required bool books}) {
    final library = _source?.library;
    if (library == null) return;
    TrackTags? one;
    if (_selected.length == 1) {
      one = library.tagsOf(_selected.single);
    } else if (_albums.length == 1) {
      final album = _albums.single;
      one = library.tracks.where((t) => t.album == album).firstOrNull;
    } else if (_albums.isEmpty && _artists.length == 1) {
      return;
    }
    if (one == null) return;
    _artists = {?one.artist};
    _albums = {?one.album};
    if (books) _series = {?one.series};
    // The panels are built with this, then scrolled to what is picked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealPicks());
  }

  /// Scrolls each panel to its first picked row, when that is out of view.
  void _revealPicks() {
    if (!mounted) return;
    for (final entry in _paneRows.entries) {
      final index = entry.value.indexWhere((row) => row.selected);
      final controller = _paneScrolls[entry.key];
      if (index < 0 || controller == null || !controller.hasClients) continue;
      final position = controller.position;
      final top = index * _SkinList.rowHeight;
      final bottom = top + _SkinList.rowHeight;
      if (top >= position.pixels &&
          bottom <= position.pixels + position.viewportDimension) {
        continue;
      }
      controller.jumpTo(
        (top - position.viewportDimension / 2 + _SkinList.rowHeight / 2).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _pickNoAlbums() => setState(() {
    _albums = {};
    _selected = {};
    _remember();
  });

  void _pickCategory(String name, List<String> names) => setState(() {
    _categories = _pick(names, name, _artistAnchor, _categories);
    if (!_ranged) _artistAnchor = name;
    _selected = {};
  });

  void _pickList(String name, List<String> names) => setState(() {
    _lists = _pick(names, name, _albumAnchor, _lists);
    if (!_ranged) _albumAnchor = name;
    _selected = {};
  });

  void _pickNoCategories() => setState(() {
    _categories = {};
    _selected = {};
  });

  void _pickNoLists() => setState(() {
    _lists = {};
    _selected = {};
  });

  /// How wide the covers of [kind] are: as set, else [fallback].
  double _coverSize(String kind, double fallback) =>
      (_coverSizes[kind] ?? fallback).clamp(
        CoverGrid.minTileWidth,
        CoverGrid.maxTileWidth,
      );

  void _setCoverSize(String kind, double size) => setState(() {
    _coverSizes = {..._coverSizes, kind: size};
    _remember();
  });

  void _setLayout(MusicLayout layout) => setState(() {
    if (_source?.movies ?? false) {
      _movieLayout = layout;
    } else {
      _musicLayout = layout;
    }
    _carryPicks(books: false);
    _remember();
  });

  void _pickAll() => setState(() {
    _artists = {};
    _albums = {};
    _categories = {};
    _lists = {};
    _series = {};
    _selected = {};
    _remember();
  });

  void _pickArtist(String name, List<String> names) => setState(() {
    _artists = _pick(names, name, _artistAnchor, _artists);
    if (!_ranged) _artistAnchor = name;
    _albums = {};
    _series = {};
    _selected = {};
    _remember();
  });

  void _pickAlbum(String? artist, String title, List<String> titles) =>
      setState(() {
        _albums = _pick(titles, title, _albumAnchor, _albums);
        if (!_ranged) _albumAnchor = title;
        if (!_additive && !_ranged) _artists = <String>{?artist};
        _selected = {};
        _remember();
      });

  void _selectTrack(String path, List<String> paths) => setState(() {
    _selected = _pick(paths, path, _trackAnchor, _selected);
    if (!_ranged) _trackAnchor = path;
    _cursor = path;
  });

  void _trackMenu(String path, List<String> paths) {
    if (!_selected.contains(path)) {
      setState(() {
        _selected = {path};
        _trackAnchor = path;
        _cursor = path;
      });
    }
    widget.onContextMenu([
      for (final p in paths)
        if (_selected.contains(p)) p,
    ]);
  }

  /// The genre and quality of [track], or null when none is known.
  static String? _facts(TrackTags track) {
    final facts = [
      if (track.genres.isNotEmpty) track.genres.join(", "),
      if (track.bitrate != null) "${track.bitrate} kbps",
      if (track.sampleRate != null)
        "${(track.sampleRate! / 1000).toStringAsFixed(1)} kHz",
    ];
    return facts.isEmpty ? null : facts.join("  ·  ");
  }

  /// What the details panel says under the music: the track selected, else
  /// the one album or artist picked; null when there is nothing to say.
  _Details? _musicDetails(List<TrackTags> tracks) {
    final loader = widget.coverLoader;
    _Cover? coverOf(TrackTags track) => loader == null
        ? null
        : _Cover(track.path, () async {
            final bytes = await loader(track.path);
            return bytes == null ? null : MemoryImage(bytes);
          });
    final selected = _selected.isEmpty
        ? null
        : tracks.where((t) => t.path == _selected.last).firstOrNull;
    if (selected != null) {
      return _Details(
        title: selected.title ?? _TrackItem.label(selected),
        meta: [
          ?selected.artist,
          ?selected.album,
          if (selected.duration != null) _TrackItem.time(selected.duration),
        ].join("  ·  "),
        text: selected.description ?? _facts(selected),
        cover: coverOf(selected),
      );
    }
    final String? name = _albums.length == 1
        ? _albums.single
        : (_artists.length == 1 ? _artists.single : null);
    if (name == null || tracks.isEmpty) return null;
    final first = tracks.first;
    // The picture of what is picked: a season's or show's poster, an
    // artist's picture; else the first track's cover.
    final url = _albums.length == 1
        ? first.seasonImageUrl
        : first.showImageUrl ?? first.artistImageUrl;
    return _Details(
      title: name,
      meta: [
        if (_albums.length == 1) ?first.artist,
        widget.localizations.mlTrackCount(tracks.length),
      ].join("  ·  "),
      text: _albums.isEmpty ? first.showDescription : null,
      cover: url == null
          ? coverOf(first)
          : _Cover(url, () async => widget.coverProvider(url)),
    );
  }

  /// "1 artist, 3 albums, 16 tracks": what is selected, or the number of
  /// tracks listed when nothing is.
  String _status(List<TrackTags> tracks) {
    final l = widget.localizations;
    if (_artists.isEmpty && _albums.isEmpty && _selected.isEmpty) {
      return l.mlTrackCount(tracks.length);
    }
    return [
      if (_artists.isNotEmpty) l.mlArtistCount(_artists.length),
      if (_albums.isNotEmpty) l.mlAlbumCount(_albums.length),
      l.mlSelectedTrackCount(
        _selected.isEmpty ? tracks.length : _selected.length,
      ),
    ].join(", ");
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final style = TextStyle(
      color: colors.normal,
      fontSize: 11,
      fontFamily: colors.fontName.isEmpty ? "Arial" : colors.fontName,
      height: 1.2,
    );
    return _WithOverlay(
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: ColoredBox(
          color: colors.normalBg,
          child: DefaultTextStyle(
            style: style,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                ?widget.playlists,
                ?widget.playStats,
              ]),
              builder: (context, _) => LayoutBuilder(
                builder: (context, outer) {
                  // A deleted playlist was the one shown: back to the local library.
                  if (_source == null) _sourceId = localSourceId;
                  final source = _source;
                  final browsed = source?.library;
                  final playlist = switch (source?.playlistId) {
                    final id? => widget.playlists?.byId(id),
                    null => null,
                  };
                  final double treeWidth = _treeWidth.clamp(
                    _minTreeWidth,
                    max(_minTreeWidth, outer.maxWidth / 3).toDouble(),
                  );
                  final compact = outer.maxWidth < _compactBelow;
                  // Too narrow for the sources: the library one is shown.
                  final Widget tree = compact
                      ? const SizedBox.shrink()
                      : SizedBox(
                          width: treeWidth,
                          child: _SourceTree(
                            skin: widget.skin,
                            colors: colors,
                            localizations: widget.localizations,
                            sections: _sections,
                            collapsed: _collapsed,
                            selectedId: _sourceId,
                            onSection: _toggleSection,
                            onSource: _pickSource,
                            onDrop: (source, drag) =>
                                widget.onDropOnPlaylist?.call(
                                  source.playlistId!,
                                  drag.paths,
                                ),
                            onSourceMenu: (source) {
                              _pickSource(source.id);
                              widget.onPlaylistMenu?.call(source.playlistId!);
                            },
                          ),
                        );
                  final Widget treeDivider = compact
                      ? const SizedBox.shrink()
                      : _PaneDivider(
                          color: colors.normal.withAlpha(90),
                          onDrag: (dx) => setState(() {
                            _treeWidth = (treeWidth + dx).clamp(
                              _minTreeWidth,
                              max(_minTreeWidth, outer.maxWidth / 3).toDouble(),
                            );
                            _remember();
                          }),
                        );
                  if (playlist != null) {
                    final tracks = [
                      for (final item in playlist.items)
                        widget.library.tagsOf(item.location) ??
                            TrackTags(
                              item.location,
                              title: item.title,
                              duration: item.duration,
                            ),
                    ];
                    final paths = [
                      for (final item in playlist.items) item.location,
                    ];
                    _navPaths = paths;
                    _panes = const ["tracks"];
                    _focusPane = "tracks";
                    final shown = paths.toSet();
                    if (!shown.containsAll(_selected)) {
                      _selected = _selected.intersection(shown);
                    }
                    final target = _selected.isEmpty
                        ? paths
                        : [
                            for (final path in paths)
                              if (_selected.contains(path)) path,
                          ];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tree,
                        treeDivider,
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: _TrackList(
                                  controller: _playlistScroll,
                                  skin: widget.skin,
                                  tracks: tracks,
                                  colors: colors,
                                  selected: _selected,
                                  onSelect: (path) => _selectTrack(path, paths),
                                  onPlay: (path) => widget.onPlay([path]),
                                  onContextMenu: (path) =>
                                      widget.onPlaylistMenu?.call(playlist.id),
                                  playlistId: playlist.id,
                                  onMove: (indices, to) => widget
                                      .onMoveInPlaylist
                                      ?.call(playlist.id, indices, to),
                                ),
                              ),
                              _StatusRow(
                                buttonBuilder: widget.buttonBuilder,
                                colors: colors,
                                status: Text(
                                  _selected.isEmpty
                                      ? widget.localizations.mlTrackCount(
                                          tracks.length,
                                        )
                                      : widget.localizations
                                            .mlSelectedTrackCount(
                                              _selected.length,
                                            ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                playLabel: widget.localizations.play,
                                addLabel:
                                    widget.localizations.mlSavePlaylistButton,
                                onAdd: widget.onSavePlaylist ?? () {},
                                enqueueLabel: widget.localizations.mlEnqueue,
                                enabled: target.isNotEmpty,
                                onPlay: () => widget.onPlay(target),
                                onEnqueue: () => widget.onEnqueue(target),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  if (source?.playList case final list?) {
                    final rows = _statRows(list);
                    final paths = [
                      for (final row in rows)
                        if (row.location != null) row.location!,
                    ];
                    _navPaths = paths;
                    _panes = const ["tracks"];
                    _focusPane = "tracks";
                    final shown = paths.toSet();
                    if (!shown.containsAll(_selected)) {
                      _selected = _selected.intersection(shown);
                    }
                    final target = _selected.isEmpty
                        ? paths
                        : [
                            for (final path in paths)
                              if (_selected.contains(path)) path,
                          ];
                    final texts = widget.localizations;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tree,
                        treeDivider,
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: rows.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Text(texts.mlStatsNothingPlayed),
                                      )
                                    : _SkinList(
                                        skin: widget.skin,
                                        colors: colors,
                                        itemCount: rows.length,
                                        itemBuilder: (context, i) {
                                          final row = rows[i];
                                          final location = row.location;
                                          return _BrowserItem(
                                            colors: colors,
                                            row: _BrowserRow(
                                              "${i + 1}. ${row.label}",
                                              0,
                                              location != null &&
                                                  _selected.contains(location),
                                              () => setState(
                                                () =>
                                                    _selected = location == null
                                                    ? {}
                                                    : {location},
                                              ),
                                              trailing: (
                                                strong: "",
                                                rest: texts.mlStatsPlays(
                                                  row.plays,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              _StatusRow(
                                buttonBuilder: widget.buttonBuilder,
                                colors: colors,
                                status: Text(
                                  texts.mlTrackCount(rows.length),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                playLabel: texts.play,
                                addLabel: texts.mlAddMediaButton,
                                onAdd: widget.onAddMedia,
                                enqueueLabel: texts.mlEnqueue,
                                enabled: target.isNotEmpty,
                                onPlay: () => widget.onPlay(target),
                                onEnqueue: () => widget.onEnqueue(target),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  if (browsed == null) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tree,
                        treeDivider,
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              source?.error ??
                                  widget.localizations.mlSourceUnavailable,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  if (source?.podcast ?? false) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tree,
                        treeDivider,
                        Expanded(
                          child: ListenableBuilder(
                            listenable: browsed,
                            builder: (context, _) {
                              final books = source?.audiobooks ?? false;
                              final completion =
                                  source?.completion ??
                                  const PodcastCompletion();
                              final everything = [
                                for (final t in browsed.search(
                                  query: _query.text,
                                ))
                                  if (!_hideListened ||
                                      !completion.isCompletedAt(
                                        t.progress ?? 0,
                                        t.duration,
                                      ))
                                    t,
                              ];
                              // Audiobooks are also narrowed by author and
                              // series.
                              bool inBooks(TrackTags track) =>
                                  !books ||
                                  ((_artists.isEmpty ||
                                          _artists.contains(track.artist)) &&
                                      (_series.isEmpty ||
                                          _series.contains(track.series)));
                              final titles = books
                                  ? {
                                      for (final track in everything)
                                        if (inBooks(track) &&
                                            track.album != null)
                                          track.album!,
                                    }.toList()
                                  : browsed.albums();
                              final known = titles.toSet();
                              if (!known.containsAll(_albums)) {
                                _albums = _albums.intersection(known);
                                _selected = {};
                              }
                              final listed = [
                                for (final track in everything)
                                  if (inBooks(track) &&
                                      (_albums.isEmpty ||
                                          _albums.contains(track.album)))
                                    track,
                              ];
                              // Several books: the Book column first and the
                              // parts grouped by it, unless sorted otherwise.
                              final severalBooks =
                                  titles.length > 1 && _albums.length != 1;
                              final bookSort = _bookSortColumn;
                              final tracks = !books
                                  ? LibraryColumn.sorted(
                                      listed,
                                      _sortColumn,
                                      _sortAscending,
                                    )
                                  : bookSort == null
                                  ? LibraryColumn.sortedByBook(listed)
                                  : LibraryColumn.sorted(
                                      listed,
                                      bookSort,
                                      _bookSortAscending,
                                    );
                              final bookPanels =
                                  books && _bookLayout == MusicLayout.split
                                  ? _bookPanels(
                                      widget.localizations,
                                      _BookStats.of(
                                        everything,
                                        _artists,
                                        _series,
                                      ),
                                      onMenu: (panel, name) =>
                                          _panelMenu(panel, name, everything),
                                      sorts: _panelSorts,
                                      onSort: _sortPanel,
                                      authors: _artists,
                                      series: _series,
                                      books: _albums,
                                      onAll: _pickAll,
                                      onAuthor: _pickArtist,
                                      onAllSeries: _pickNoSeries,
                                      onSeries: _pickSeries,
                                      onAllBooks: _pickNoAlbums,
                                      onBook: _pickAlbumOnly,
                                    )
                                  : null;
                              // The panels the arrow keys move between, and
                              // what each lists.
                              _panes = bookPanels != null
                                  ? const [
                                      "authors",
                                      "series",
                                      "books",
                                      "tracks",
                                    ]
                                  : titles.length > 1
                                  ? const ["list", "tracks"]
                                  : const ["tracks"];
                              _paneRows = {
                                for (final panel
                                    in bookPanels ?? const <_PanelSpec>[])
                                  panel.id: [
                                    for (final row in panel.rows)
                                      (selected: row.selected, pick: row.onTap),
                                  ],
                              };
                              if (!_panes.contains(_focusPane)) {
                                _focusPane = "tracks";
                              }
                              final paths = [for (final t in tracks) t.path];
                              _navPaths = paths;
                              final shown = paths.toSet();
                              if (!shown.containsAll(_selected)) {
                                _selected = _selected.intersection(shown);
                              }
                              final target = _selected.isEmpty
                                  ? paths
                                  : [
                                      for (final path in paths)
                                        if (_selected.contains(path)) path,
                                    ];
                              return Column(
                                children: [
                                  _SearchRow(
                                    controller: _query,
                                    focusNode: _queryFocus,
                                    colors: colors,
                                    label: widget.localizations.mlSearch,
                                    trailing: _VideoControls(
                                      colors: colors,
                                      localizations: widget.localizations,
                                      sort: _videoSort,
                                      filter: _videoFilter,
                                      shows: false,
                                      onSort: (_) {},
                                      onFilter: (_) {},
                                      onlyHide: true,
                                      hide: _hideListened,
                                      hideLabel:
                                          widget.localizations.mlHideListened,
                                      hideTip: widget
                                          .localizations
                                          .mlHideListenedTip,
                                      onHide: (hide) => setState(() {
                                        _hideListened = hide;
                                        _selected = {};
                                        _remember();
                                      }),
                                    ),
                                    leading: _LayoutButtons(
                                      colors: colors,
                                      localizations: widget.localizations,
                                      layout: books
                                          ? _bookLayout
                                          : _podcastLayout,
                                      layouts: books
                                          ? const [
                                              MusicLayout.browser,
                                              MusicLayout.split,
                                              MusicLayout.covers,
                                            ]
                                          : const [
                                              MusicLayout.browser,
                                              MusicLayout.covers,
                                            ],
                                      kind: books
                                          ? _LayoutKind.books
                                          : _LayoutKind.podcasts,
                                      coverSize: _coverSize(
                                        books ? "books" : "podcasts",
                                        CoverGrid.defaultTileWidth,
                                      ),
                                      onCoverSize: (size) => _setCoverSize(
                                        books ? "books" : "podcasts",
                                        size,
                                      ),
                                      onLayout: _setBookLayout,
                                    ),
                                  ),
                                  Expanded(
                                    child: _PodcastBrowser(
                                      panels: bookPanels,
                                      cover:
                                          (books
                                                  ? _bookLayout
                                                  : _podcastLayout) ==
                                              MusicLayout.covers
                                          ? _coverGrid(
                                              _coverItems(
                                                [
                                                  for (final t in everything)
                                                    if (inBooks(t)) t,
                                                ],
                                                paths,
                                                books: books,
                                                podcasts: true,
                                                movies: false,
                                                shows: false,
                                              ),
                                              colors,
                                              tileWidth: _coverSize(
                                                books ? "books" : "podcasts",
                                                CoverGrid.defaultTileWidth,
                                              ),
                                            )
                                          : null,
                                      focus: _focusPane,
                                      onFocus: _focusOn,
                                      scrollOf: _scrollOf,
                                      keyOf: _keyOf,
                                      onListRows: (rows) =>
                                          _paneRows["list"] = [
                                            for (final row in rows)
                                              (
                                                selected: row.selected,
                                                pick: row.onTap,
                                              ),
                                          ],
                                      onGroupMenu: (podcast) =>
                                          widget.onContextMenu([
                                            for (final t in everything)
                                              if (inBooks(t) &&
                                                  (podcast == null ||
                                                      t.album == podcast))
                                                t.path,
                                          ]),
                                      splitFraction: _splitFraction,
                                      onSplitMoved: _moveSplit,
                                      splitWeights: _splitShares["books"],
                                      onSplitWeights:
                                          (divider, moved, width, leasts) =>
                                              _resizePanels(
                                                "books",
                                                3,
                                                divider,
                                                moved,
                                                width,
                                                leasts,
                                              ),
                                      skin: widget.skin,
                                      colors: colors,
                                      localizations: widget.localizations,
                                      audiobooks: source?.audiobooks ?? false,
                                      podcasts: titles,
                                      counts: _episodeCounts(
                                        browsed.tracks,
                                        source?.completion ??
                                            const PodcastCompletion(),
                                      ),
                                      picked: _albums,
                                      onAll: _pickAll,
                                      onPodcast: (title) =>
                                          _pickAlbum(null, title, titles),
                                      tracks: tracks,
                                      selected: _selected,
                                      onSelect: (path) =>
                                          _selectTrack(path, paths),
                                      onPlay: (path) => widget.onPlay([path]),
                                      onContextMenu: (path) =>
                                          _trackMenu(path, paths),
                                      sortColumn: !books
                                          ? _sortColumn
                                          : _bookSortColumn ??
                                                (severalBooks
                                                    ? LibraryColumn.album
                                                    : null),
                                      sortAscending: books
                                          ? _bookSortAscending
                                          : _sortAscending,
                                      onSort: books ? _sortBooksBy : _sortBy,
                                      columns: books ? _bookColumns : _columns,
                                      onMoveColumn: (moved, target) =>
                                          _moveColumn(
                                            moved,
                                            target,
                                            books: books,
                                          ),
                                      widths: _columnWidths,
                                      onResizeColumn: _resizeColumn,
                                      onResetColumn: _resetColumn,
                                      coverCollapsed: _coverCollapsed,
                                      onToggleCover: _toggleCover,
                                      detailsExtra: _detailsExtra,
                                      onGrowDetails: _growDetails,
                                      tableKey: _podcastTable,
                                      onOpenArtwork: widget.onOpenArtwork,
                                      onPlayAt: widget.onPlayAt,
                                      coverProvider: widget.coverProvider,
                                      scanning: browsed.scanning,
                                      empty: browsed.isEmpty,
                                    ),
                                  ),
                                  _StatusRow(
                                    buttonBuilder: widget.buttonBuilder,
                                    colors: colors,
                                    status: browsed.scanning
                                        ? ScanningText(
                                            localizations: widget.localizations,
                                            count: browsed.scanned,
                                          )
                                        : Text(
                                            _selected.isEmpty
                                                ? widget.localizations
                                                      .mlTrackCount(
                                                        tracks.length,
                                                      )
                                                : widget.localizations
                                                      .mlSelectedTrackCount(
                                                        _selected.length,
                                                      ),
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    playLabel: widget.localizations.play,
                                    addLabel:
                                        widget.localizations.mlAddMediaButton,
                                    onAdd: widget.onAddMedia,
                                    enqueueLabel:
                                        widget.localizations.mlEnqueue,
                                    enabled: target.isNotEmpty,
                                    onPlay: () => widget.onPlay(target),
                                    onEnqueue: () => widget.onEnqueue(target),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      tree,
                      treeDivider,
                      Expanded(
                        child: ListenableBuilder(
                          listenable: browsed,
                          builder: (context, _) {
                            final library = browsed;
                            // Movies are a plain list; the rest, as chosen.
                            final layout = (source?.movies ?? false)
                                ? _movieLayout
                                : _musicLayout;
                            final video = source?.shows ?? false;
                            final isMovies = source?.movies ?? false;
                            // Tags edited since may have renamed what is picked away: back
                            // to everything, rather than an empty list.
                            final known = library.artists.toSet();
                            if (!known.containsAll(_artists)) {
                              _artists = _artists.intersection(known);
                              _selected = {};
                            }
                            final albumsHere = <String>{
                              for (final artist
                                  in _artists.isEmpty
                                      ? <String?>[null]
                                      : _artists.toList())
                                ...library.albums(artist: artist),
                            };
                            if (!albumsHere.containsAll(_albums)) {
                              _albums = _albums.intersection(albumsHere);
                              _selected = {};
                            }
                            final everything = isMovies || video
                                ? _filterVideos(
                                    [
                                      for (final t in library.search(
                                        query: _query.text,
                                      ))
                                        if (!_hideWatched ||
                                            (t.progress ?? 0) < 1)
                                          t,
                                    ],
                                    _videoFilter,
                                    shows: video,
                                  )
                                : library.search(query: _query.text);
                            final inLists = {
                              for (final name in _lists)
                                ...?source?.lists[name],
                            };
                            final unsorted = [
                              for (final track in everything)
                                if ((_artists.isEmpty ||
                                        _artists.contains(track.artist)) &&
                                    (_albums.isEmpty ||
                                        _albums.contains(track.album)) &&
                                    (!isMovies ||
                                        ((_categories.isEmpty ||
                                                track.genres.any(
                                                  _categories.contains,
                                                )) &&
                                            (_lists.isEmpty ||
                                                inLists.contains(track.path)))))
                                  track,
                            ];
                            // Sorted as the headings say, else as the library has them.
                            final sortedBy = _musicSortColumn;
                            final byDate =
                                (isMovies || video) &&
                                _videoSort != VideoSort.name;
                            final sortedTracks = sortedBy == null
                                ? unsorted
                                : LibraryColumn.sorted(
                                    unsorted,
                                    sortedBy,
                                    _musicSortAscending,
                                  );
                            // Movies the most recent first when asked; a
                            // show's episodes stay in their order, the shows
                            // follow the date of their latest episode.
                            final dates = video
                                ? _showDates(unsorted, _videoSort)
                                : const <String, DateTime?>{};
                            DateTime? dateOf(TrackTags t) => video
                                ? dates[t.artist]
                                : _videoDate(t, _videoSort);
                            final tracks = !byDate
                                ? sortedTracks
                                : ([...sortedTracks]..sort((a, b) {
                                    final x = dateOf(a);
                                    final y = dateOf(b);
                                    if (x == null && y == null) return 0;
                                    if (x == null) return 1;
                                    if (y == null) return -1;
                                    return y.compareTo(x);
                                  }));
                            // While scanning: the progress, or the question after Escape.
                            final Widget scanStatus = _cancelPrompt != null
                                ? Text(
                                    widget.localizations.mlCancelPrompt,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : ScanningText(
                                    localizations: widget.localizations,
                                    count: library.scanned,
                                  );
                            final paths = [for (final t in tracks) t.path];
                            _navPaths = paths;
                            // Selected tracks that a new search hid are not selected.
                            final shown = paths.toSet();
                            if (!shown.containsAll(_selected)) {
                              _selected = _selected.intersection(shown);
                            }
                            final target = _selected.isEmpty
                                ? paths
                                : [
                                    for (final path in paths)
                                      if (_selected.contains(path)) path,
                                  ];
                            if (compact) {
                              final l = widget.localizations;
                              String? musicLabel(LibraryColumn c) =>
                                  switch (c) {
                                    LibraryColumn.artist => l.mlColumnArtist,
                                    LibraryColumn.album => l.mlColumnAlbum,
                                    LibraryColumn.number => l.mlColumnNumber,
                                    LibraryColumn.title => l.mlColumnTitle,
                                    LibraryColumn.length => l.mlColumnLength,
                                    LibraryColumn.genre => l.mlColumnGenre,
                                    _ => null,
                                  };
                              _panes = const ["tracks"];
                              _paneRows = {};
                              _focusPane = "tracks";
                              final entries = isMovies || video
                                  ? <_MenuEntry>[
                                      for (final sort in VideoSort.values)
                                        _MenuEntry(
                                          label: switch (sort) {
                                            VideoSort.name => l.mlVideoSortName,
                                            VideoSort.watched =>
                                              l.mlVideoSortWatched,
                                            VideoSort.aired =>
                                              l.mlVideoSortAired,
                                            VideoSort.added =>
                                              l.mlVideoSortAdded,
                                          },
                                          active: _videoSort == sort,
                                          onTap: () => _setVideoSort(sort),
                                        ),
                                      const _MenuEntry(
                                        label: "",
                                        active: false,
                                      ),
                                      for (final filter in VideoFilter.values)
                                        _MenuEntry(
                                          label: switch (filter) {
                                            VideoFilter.all =>
                                              l.mlVideoFilterAll,
                                            VideoFilter.watching =>
                                              video
                                                  ? l.mlVideoFilterWatching
                                                  : l.mlVideoFilterInProgress,
                                            VideoFilter.unwatched =>
                                              l.mlVideoFilterUnwatched,
                                          },
                                          active: _videoFilter == filter,
                                          onTap: () => _setVideoFilter(filter),
                                        ),
                                      const _MenuEntry(
                                        label: "",
                                        active: false,
                                      ),
                                      _MenuEntry(
                                        label: l.mlHideWatched,
                                        active: _hideWatched,
                                        onTap: () =>
                                            _setHideWatched(!_hideWatched),
                                      ),
                                    ]
                                  : <_MenuEntry>[
                                      for (final column in LibraryColumn.music)
                                        if (musicLabel(column) case final name?)
                                          _MenuEntry(
                                            label: name,
                                            active: _musicSortColumn == column,
                                            // The arrow says which way the
                                            // column is sorted; choosing it
                                            // again reverses it.
                                            arrow: _musicSortAscending
                                                ? "▲"
                                                : "▼",
                                            onTap: () => _sortMusicBy(column),
                                          ),
                                    ];
                              return Column(
                                children: [
                                  _CompactBar(
                                    controller: _query,
                                    focusNode: _queryFocus,
                                    colors: colors,
                                    entries: entries,
                                  ),
                                  Expanded(
                                    child: library.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Text(
                                              library.scanning
                                                  ? l.mlTrackCount(0)
                                                  : l.mlEmpty,
                                            ),
                                          )
                                        : _TrackList(
                                            controller: _compactScroll,
                                            skin: widget.skin,
                                            tracks: tracks,
                                            colors: colors,
                                            selected: _selected,
                                            onSelect: (path) =>
                                                _selectTrack(path, paths),
                                            onPlay: (path) =>
                                                widget.onPlay([path]),
                                            onContextMenu: (path) =>
                                                _trackMenu(path, paths),
                                          ),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _SearchRow(
                                  controller: _query,
                                  focusNode: _queryFocus,
                                  colors: colors,
                                  label: widget.localizations.mlSearch,
                                  trailing: isMovies || video
                                      ? _VideoControls(
                                          colors: colors,
                                          localizations: widget.localizations,
                                          sort: _videoSort,
                                          filter: _videoFilter,
                                          shows: video,
                                          hide: _hideWatched,
                                          hideLabel: widget
                                              .localizations
                                              .mlHideWatched,
                                          hideTip: widget
                                              .localizations
                                              .mlHideWatchedTip,
                                          onHide: _setHideWatched,
                                          onSort: _setVideoSort,
                                          onFilter: _setVideoFilter,
                                        )
                                      : null,
                                  leading: _LayoutButtons(
                                    colors: colors,
                                    localizations: widget.localizations,
                                    layout: layout,
                                    layouts: isMovies
                                        ? const [
                                            MusicLayout.tracks,
                                            MusicLayout.split,
                                            MusicLayout.covers,
                                          ]
                                        : MusicLayout.values,
                                    kind: isMovies
                                        ? _LayoutKind.movies
                                        : video
                                        ? _LayoutKind.shows
                                        : _LayoutKind.music,
                                    coverSize: _coverSize(
                                      isMovies
                                          ? "movies"
                                          : video
                                          ? "shows"
                                          : "music",
                                      isMovies
                                          ? CoverGrid.defaultTileWidth
                                          : 92,
                                    ),
                                    onCoverSize: (size) => _setCoverSize(
                                      isMovies
                                          ? "movies"
                                          : video
                                          ? "shows"
                                          : "music",
                                      size,
                                    ),
                                    onLayout: _setLayout,
                                  ),
                                ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      // Neither side gets narrower than the artists
                                      // pane starts out.
                                      final widest = max(
                                        _minPaneWidth,
                                        constraints.maxWidth -
                                            _PaneDivider.width -
                                            _minPaneWidth,
                                      );
                                      final browserWidth = _browserWidth.clamp(
                                        _minPaneWidth,
                                        widest,
                                      );
                                      final Widget plainContent =
                                          library.isEmpty
                                          ? Padding(
                                              padding: const EdgeInsets.all(6),
                                              // The progress is in the status row.
                                              child: Text(
                                                library.scanning
                                                    ? widget.localizations
                                                          .mlTrackCount(0)
                                                    : widget
                                                          .localizations
                                                          .mlEmpty,
                                              ),
                                            )
                                          : _TrackTable(
                                              key: _musicTable,
                                              music: true,
                                              skin: widget.skin,
                                              colors: colors,
                                              localizations:
                                                  widget.localizations,
                                              tracks: tracks,
                                              selected: _selected,
                                              onSelect: (path) =>
                                                  _selectTrack(path, paths),
                                              onPlay: (path) =>
                                                  widget.onPlay([path]),
                                              onContextMenu: (path) =>
                                                  _trackMenu(path, paths),
                                              sortColumn: _musicSortColumn,
                                              sortAscending:
                                                  _musicSortAscending,
                                              onSort: _sortMusicBy,
                                              columns: isMovies
                                                  ? _movieColumns
                                                  : video
                                                  ? [
                                                      // One show or season
                                                      // needs no column
                                                      // to say which.
                                                      for (final c
                                                          in _showColumns)
                                                        if (!(c ==
                                                                    LibraryColumn
                                                                        .showName &&
                                                                _artists.length ==
                                                                    1) &&
                                                            !(c ==
                                                                    LibraryColumn
                                                                        .season &&
                                                                _albums.length ==
                                                                    1))
                                                          c,
                                                    ]
                                                  : _musicColumns,
                                              widths: _columnWidths,
                                              onMoveColumn: (moved, target) =>
                                                  _moveColumn(
                                                    moved,
                                                    target,
                                                    music: true,
                                                    movies: isMovies,
                                                    shows: video,
                                                  ),
                                              onResizeColumn: _resizeColumn,
                                              onResetColumn: _resetColumn,
                                            );
                                      final Widget content = _PaneFocus(
                                        id: "tracks",
                                        focus: _focusPane,
                                        onFocus: _focusOn,
                                        colors: colors,
                                        child: plainContent,
                                      );
                                      final splitPanels =
                                          (layout == MusicLayout.split ||
                                                  layout ==
                                                      MusicLayout.covers) &&
                                              isMovies
                                          ? _moviePanels(
                                              widget.localizations,
                                              everything,
                                              source?.lists ?? const {},
                                              sorts: _panelSorts,
                                              onSort: _sortPanel,
                                              categories: _categories,
                                              lists: _lists,
                                              onCategory: _pickCategory,
                                              onAllCategories:
                                                  _pickNoCategories,
                                              onList: _pickList,
                                              onAllLists: _pickNoLists,
                                              onMenu: widget.onContextMenu,
                                            )
                                          : layout == MusicLayout.split
                                          ? _musicPanels(
                                              widget.localizations,
                                              _MusicStats.of(
                                                everything,
                                                _artists,
                                              ),
                                              onMenu: (panel, name) =>
                                                  _panelMenu(
                                                    panel,
                                                    name,
                                                    everything,
                                                  ),
                                              sorts: _panelSorts,
                                              onSort: _sortPanel,
                                              artists: _artists,
                                              albums: _albums,
                                              onAll: _pickAll,
                                              onArtist: _pickArtist,
                                              onAlbum: _pickAlbumOnly,
                                              onAllAlbums: _pickNoAlbums,
                                              shows: video,
                                              unwatchedShows: video
                                                  ? _unwatched(
                                                      everything,
                                                      (t) => t.artist,
                                                    )
                                                  : null,
                                              unwatchedSeasons: video
                                                  ? _unwatched(
                                                      everything,
                                                      (t) => t.album,
                                                      only: (t) =>
                                                          _artists.isEmpty ||
                                                          _artists.contains(
                                                            t.artist,
                                                          ),
                                                    )
                                                  : null,
                                              showDates:
                                                  video &&
                                                      _videoSort !=
                                                          VideoSort.name
                                                  ? dates
                                                  : null,
                                            )
                                          : null;
                                      // The panels the arrow keys move between.
                                      _panes = switch (layout) {
                                        MusicLayout.tracks => const ["tracks"],
                                        MusicLayout.browser => const [
                                          "browser",
                                          "tracks",
                                        ],
                                        MusicLayout.split =>
                                          isMovies
                                              ? const [
                                                  "categories",
                                                  "lists",
                                                  "tracks",
                                                ]
                                              : const [
                                                  "artists",
                                                  "albums",
                                                  "tracks",
                                                ],
                                        MusicLayout.covers =>
                                          isMovies
                                              ? const [
                                                  "categories",
                                                  "lists",
                                                  "covers",
                                                ]
                                              : video
                                              ? const [
                                                  "showCovers",
                                                  "seasonCovers",
                                                  "episodeCovers",
                                                ]
                                              : const [
                                                  "artistCovers",
                                                  "albumCovers",
                                                  "tracks",
                                                ],
                                      };
                                      _paneRows = {
                                        for (final panel
                                            in splitPanels ??
                                                const <_PanelSpec>[])
                                          panel.id: [
                                            for (final row in panel.rows)
                                              (
                                                selected: row.selected,
                                                pick: row.onTap,
                                              ),
                                          ],
                                      };
                                      if (!_panes.contains(_focusPane)) {
                                        _focusPane = _panes.contains("tracks")
                                            ? "tracks"
                                            : _panes.last;
                                      }
                                      final Widget row = switch (layout) {
                                        MusicLayout.tracks => content,
                                        MusicLayout.covers when isMovies =>
                                          _SplitPanels(
                                            skin: widget.skin,
                                            colors: colors,
                                            panels: splitPanels!,
                                            weights: _splitShares["movies"],
                                            onWeights:
                                                (
                                                  divider,
                                                  moved,
                                                  width,
                                                  leasts,
                                                ) => _resizePanels(
                                                  "movies",
                                                  2,
                                                  divider,
                                                  moved,
                                                  width,
                                                  leasts,
                                                ),
                                            fraction: _splitFraction,
                                            onMoved: _moveSplit,
                                            focus: _focusPane,
                                            onFocus: _focusOn,
                                            scrollOf: _scrollOf,
                                            keyOf: _keyOf,
                                            bottom: _coverGrid(
                                              _coverItems(
                                                tracks,
                                                paths,
                                                books: false,
                                                podcasts: false,
                                                movies: true,
                                                shows: false,
                                              ),
                                              colors,
                                              tileWidth: _coverSize(
                                                "movies",
                                                CoverGrid.defaultTileWidth,
                                              ),
                                            ),
                                          ),
                                        MusicLayout.covers when video =>
                                          _coverColumns([
                                            _coverGrid(
                                              _artistTiles(
                                                everything,
                                                shows: true,
                                              ),
                                              colors,
                                              id: "showCovers",
                                              tileWidth: _coverSize(
                                                "shows",
                                                92,
                                              ),
                                            ),
                                            _coverGrid(
                                              _albumTiles(
                                                everything,
                                                shows: true,
                                              ),
                                              colors,
                                              id: "seasonCovers",
                                              tileWidth: _coverSize(
                                                "shows",
                                                92,
                                              ),
                                            ),
                                            _coverGrid(
                                              _episodeTiles(tracks, paths),
                                              colors,
                                              id: "episodeCovers",
                                              tileWidth: _coverSize(
                                                "shows",
                                                92,
                                              ),
                                            ),
                                          ], colors),
                                        MusicLayout.covers => _coverColumns(
                                          [
                                            _coverGrid(
                                              _artistTiles(
                                                everything,
                                                shows: false,
                                              ),
                                              colors,
                                              id: "artistCovers",
                                              tileWidth: _coverSize(
                                                "music",
                                                92,
                                              ),
                                            ),
                                            _coverGrid(
                                              _albumTiles(
                                                everything,
                                                shows: false,
                                              ),
                                              colors,
                                              id: "albumCovers",
                                              tileWidth: _coverSize(
                                                "music",
                                                92,
                                              ),
                                            ),
                                            content,
                                          ],
                                          colors,
                                          flex: const [2, 2, 3],
                                        ),
                                        MusicLayout.browser => Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              width: browserWidth,
                                              child: _PaneFocus(
                                                key: _keyOf("browser"),
                                                id: "browser",
                                                focus: _focusPane,
                                                onFocus: _focusOn,
                                                colors: colors,
                                                child: _BrowserList(
                                                  controller: _scrollOf(
                                                    "browser",
                                                  ),
                                                  onRows: (rows) =>
                                                      _paneRows["browser"] = [
                                                        for (final row in rows)
                                                          (
                                                            selected:
                                                                row.selected,
                                                            pick: row.onTap,
                                                          ),
                                                      ],
                                                  skin: widget.skin,
                                                  colors: colors,
                                                  allArtists: widget
                                                      .localizations
                                                      .mlAllArtists,
                                                  allAlbums: widget
                                                      .localizations
                                                      .mlAllAlbums,
                                                  library: library,
                                                  query: _query.text,
                                                  artists: _artists,
                                                  albums: _albums,
                                                  onAll: _pickAll,
                                                  onArtist: _pickArtist,
                                                  onAlbum: _pickAlbum,
                                                  onArtistMenu: (artist) =>
                                                      widget.onContextMenu([
                                                        for (final t
                                                            in everything)
                                                          if (t.artist ==
                                                              artist)
                                                            t.path,
                                                      ]),
                                                  onAlbumMenu:
                                                      (
                                                        artist,
                                                        album,
                                                      ) => widget.onContextMenu(
                                                        [
                                                          for (final t
                                                              in everything)
                                                            if (t.album ==
                                                                    album &&
                                                                (artist ==
                                                                        null ||
                                                                    t.artist ==
                                                                        artist))
                                                              t.path,
                                                        ],
                                                      ),
                                                ),
                                              ),
                                            ),
                                            _PaneDivider(
                                              color: colors.normal.withAlpha(
                                                90,
                                              ),
                                              onDrag: (dx) => setState(() {
                                                // From the width as it is now: several moves
                                                // can arrive before the next build.
                                                _browserWidth =
                                                    (_browserWidth.clamp(
                                                              _minPaneWidth,
                                                              widest,
                                                            ) +
                                                            dx)
                                                        .clamp(
                                                          _minPaneWidth,
                                                          widest,
                                                        );
                                                _remember();
                                              }),
                                            ),
                                            Expanded(child: content),
                                          ],
                                        ),
                                        MusicLayout.split => _SplitPanels(
                                          skin: widget.skin,
                                          colors: colors,
                                          panels: splitPanels!,
                                          weights:
                                              _splitShares[isMovies
                                                  ? "movies"
                                                  : "music"],
                                          onWeights:
                                              (divider, moved, width, leasts) =>
                                                  _resizePanels(
                                                    isMovies
                                                        ? "movies"
                                                        : "music",
                                                    2,
                                                    divider,
                                                    moved,
                                                    width,
                                                    leasts,
                                                  ),
                                          fraction: _splitFraction,
                                          onMoved: _moveSplit,
                                          focus: _focusPane,
                                          onFocus: _focusOn,
                                          scrollOf: _scrollOf,
                                          keyOf: _keyOf,
                                          bottom: content,
                                        ),
                                      };
                                      final details = library.isEmpty
                                          ? null
                                          : _musicDetails(tracks);
                                      if (details == null) return row;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(child: row),
                                          _DetailsPanel(
                                            key: ValueKey(details.cover?.key),
                                            details: details,
                                            onSeek: null,
                                            colors: colors,
                                            label:
                                                widget.localizations.mlDetails,
                                            maxHeight:
                                                constraints.maxHeight / 2,
                                            totalMax: max(
                                              0,
                                              constraints.maxHeight * 0.6 - 21,
                                            ),
                                            collapsed: _coverCollapsed,
                                            extra: _detailsExtra,
                                            onGrow: _growDetails,
                                            onOpenArtwork:
                                                widget.onOpenArtwork == null
                                                ? null
                                                : (image) =>
                                                      widget.onOpenArtwork!(
                                                        details.title,
                                                        image,
                                                      ),
                                            onToggle: _toggleCover,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                _StatusRow(
                                  buttonBuilder: widget.buttonBuilder,
                                  colors: colors,
                                  status: library.scanning
                                      ? scanStatus
                                      : Text(
                                          _status(tracks),
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  playLabel: widget.localizations.play,
                                  addLabel:
                                      widget.localizations.mlAddMediaButton,
                                  onAdd: widget.onAddMedia,
                                  enqueueLabel: widget.localizations.mlEnqueue,
                                  enabled: target.isNotEmpty,
                                  onPlay: () => widget.onPlay(target),
                                  onEnqueue: () => widget.onEnqueue(target),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of a panel the arrow keys move through: whether it is picked, and
/// picking it.
typedef _PaneRow = ({bool selected, VoidCallback pick});

/// Outlines [child] when the arrow keys act on it, and makes it the one they
/// act on when it is pressed.
class _PaneFocus extends StatelessWidget {
  const _PaneFocus({
    required this.id,
    required this.focus,
    required this.onFocus,
    required this.colors,
    required this.child,
    super.key,
  });

  final String id;

  /// The panel that has the focus.
  final String focus;
  final ValueChanged<String> onFocus;
  final PlEditConfig colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => onFocus(id),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        // The highlight color, two pixels thick, so that it shows on any
        // skin.
        border: focus == id
            ? Border.all(color: colors.selectedBg, width: 2)
            : null,
      ),
      child: child,
    ),
  );
}

/// How a split panel is sorted: by [column] (0 the names, then each count),
/// ascending or not.
@immutable
class _PanelSort {
  const _PanelSort(this.column, {this.ascending = true});

  final int column;
  final bool ascending;

  /// What it is when it was not chosen: by name.
  static const byName = _PanelSort(0);

  /// The sort after the heading of [column] was clicked: the first click
  /// sorts by it (names from A, counts from the most), the next reverses.
  _PanelSort click(int clicked) => clicked == column
      ? _PanelSort(column, ascending: !ascending)
      : _PanelSort(clicked, ascending: clicked == 0);

  @override
  bool operator ==(Object other) =>
      other is _PanelSort &&
      other.column == column &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);
}

/// [items] ordered as [sort] says: by [name], or by one of the [numbers]
/// (counts, a year) with the missing ones last either way, ties by name.
List<T> _sortedItems<T>(
  List<T> items,
  _PanelSort? sort,
  String Function(T item) name,
  List<int?> Function(T item) numbers,
) {
  final by = sort ?? _PanelSort.byName;
  int byName(T a, T b) =>
      name(a).toLowerCase().compareTo(name(b).toLowerCase());
  int compare(T a, T b) {
    if (by.column == 0) return byName(a, b) * (by.ascending ? 1 : -1);
    final x = numbers(a)[by.column - 1];
    final y = numbers(b)[by.column - 1];
    if (x == null && y == null) return byName(a, b);
    if (x == null) return 1;
    if (y == null) return -1;
    final order = x.compareTo(y) * (by.ascending ? 1 : -1);
    return order != 0 ? order : byName(a, b);
  }

  return [...items]..sort(compare);
}

/// What the split layout lists: the artists with their counts, and the
/// albums of those picked with theirs.
class _MusicStats {
  const _MusicStats({
    required this.artists,
    required this.albums,
    required this.trackCount,
  });

  /// Each artist with how many albums and tracks it has.
  final List<({String name, int albums, int tracks})> artists;

  /// Each album of the artists picked with its track count and year.
  final List<({String name, int tracks, int? year})> albums;

  /// How many tracks all of this is of.
  final int trackCount;

  /// The stats of [tracks], the albums being those of [picked] artists.
  factory _MusicStats.of(List<TrackTags> tracks, Set<String> picked) {
    final albumsOf = <String, Set<String>>{};
    final tracksOf = <String, int>{};
    final albumTracks = <String, int>{};
    final albumYear = <String, int>{};
    for (final track in tracks) {
      final artist = track.artist;
      if (artist != null) {
        tracksOf[artist] = (tracksOf[artist] ?? 0) + 1;
        if (track.album != null) {
          (albumsOf[artist] ??= {}).add(track.album!);
        }
      }
      final album = track.album;
      if (album != null && (picked.isEmpty || picked.contains(artist))) {
        albumTracks[album] = (albumTracks[album] ?? 0) + 1;
        if (track.year case final year?) {
          // The earliest the album's tracks say.
          albumYear[album] = min(albumYear[album] ?? year, year);
        }
      }
    }
    return _MusicStats(
      artists: [
        for (final name in tracksOf.keys)
          (
            name: name,
            albums: albumsOf[name]?.length ?? 0,
            tracks: tracksOf[name]!,
          ),
      ],
      albums: [
        for (final name in albumTracks.keys)
          (name: name, tracks: albumTracks[name]!, year: albumYear[name]),
      ],
      trackCount: tracks.length,
    );
  }
}

/// Shows [message] in a small box under [child] when the pointer rests on it
/// (the library window has no tooltips of its own).
class _HoverTip extends StatefulWidget {
  const _HoverTip({
    required this.message,
    required this.colors,
    required this.child,
  });

  final String message;
  final PlEditConfig colors;
  final Widget child;

  /// How long the pointer rests before the tip shows.
  static const delay = Duration(milliseconds: 400);

  @override
  State<_HoverTip> createState() => _HoverTipState();
}

class _HoverTipState extends State<_HoverTip> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    _timer?.cancel();
    _timer = Timer(_HoverTip.delay, () {
      if (mounted) _portal.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: MouseRegion(
      onEnter: (_) => _show(),
      onExit: (_) => _hide(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 3),
          child: Align(
            alignment: Alignment.topLeft,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.colors.normalBg.withAlpha(255),
                  border: Border.all(color: _legible(widget.colors)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    widget.message,
                    softWrap: false,
                    style: TextStyle(
                      color: _legible(widget.colors),
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: widget.child,
      ),
    ),
  );
}

/// The colour of text on the list's background: the skin's own when it
/// stands out from it, else black or white, whichever does.
Color _legible(PlEditConfig colors) {
  double contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return (max(x, y) + 0.05) / (min(x, y) + 0.05);
  }

  final background = colors.normalBg;
  for (final candidate in [colors.normal, colors.current]) {
    if (contrast(candidate, background) >= 4.5) return candidate;
  }
  return background.computeLuminance() > 0.4
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

/// The colour of links in text on the list's background.
Color _linkColor(PlEditConfig colors) {
  double contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return (max(x, y) + 0.05) / (min(x, y) + 0.05);
  }

  for (final candidate in [colors.current, colors.selectedBg]) {
    if (contrast(candidate, colors.normalBg) >= 3) return candidate;
  }
  return _legible(colors);
}

/// The covers button with a little arrow on its right that opens a slider
/// for how big the covers are.
class _CoverSplitButton extends StatefulWidget {
  const _CoverSplitButton({
    required this.colors,
    required this.label,
    required this.sizeLabel,
    required this.on,
    required this.size,
    required this.onSelect,
    required this.onSize,
  });

  final PlEditConfig colors;
  final String label;
  final String sizeLabel;
  final bool on;
  final double size;
  final VoidCallback onSelect;
  final ValueChanged<double> onSize;

  @override
  State<_CoverSplitButton> createState() => _CoverSplitButtonState();
}

class _CoverSplitButtonState extends State<_CoverSplitButton> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final on = widget.on;
    Widget part(Widget child, VoidCallback onTap, String tip, double width) =>
        _HoverTip(
          message: tip,
          colors: colors,
          child: _Tap(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: 14,
              child: Center(child: child),
            ),
          ),
        );
    TextStyle style() => TextStyle(
      color: on ? colors.current : colors.normal,
      fontSize: 10,
      height: 1,
    );
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: this,
        onTapOutside: (_) => _portal.hide(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 3),
            child: Align(
              alignment: Alignment.topLeft,
              child: TapRegion(
                groupId: this,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.normalBg.withAlpha(255),
                    border: Border.all(color: _legible(colors)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: SizedBox(
                      width: 140,
                      height: 14,
                      child: _SizeSlider(
                        colors: colors,
                        value: widget.size,
                        min: CoverGrid.minTileWidth,
                        max: CoverGrid.maxTileWidth,
                        onChanged: widget.onSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: on ? colors.selectedBg : colors.normalBg,
              border: Border.all(color: colors.normal.withAlpha(on ? 200 : 90)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                part(
                  Text("▦", style: style()),
                  widget.onSelect,
                  widget.label,
                  18,
                ),
                SizedBox(
                  height: 14,
                  child: ColoredBox(
                    color: colors.normal.withAlpha(90),
                    child: const SizedBox(width: 1),
                  ),
                ),
                part(Text("▾", style: style()), _toggle, widget.sizeLabel, 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal slider in the list's colors: drag the knob, or press on the
/// line, to a value between [min] and [max].
class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    required this.colors,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final PlEditConfig colors;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const knob = 8.0;
      final room = box.maxWidth - knob < 1 ? 1.0 : box.maxWidth - knob;
      final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
      void set(double x) => onChanged(
        (min + ((x - knob / 2) / room).clamp(0.0, 1.0) * (max - min))
            .roundToDouble(),
      );
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => set(event.localPosition.dx),
          onPointerMove: (event) => set(event.localPosition.dx),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              SizedBox(
                height: 2,
                width: double.infinity,
                child: ColoredBox(color: colors.normal.withAlpha(120)),
              ),
              Positioned(
                left: fraction * room,
                child: SizedBox(
                  width: knob,
                  height: 12,
                  child: ColoredBox(color: colors.current),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// What the layout buttons are for.
enum _LayoutKind { music, books, podcasts, movies, shows }

/// The buttons that choose how music is laid out.
class _LayoutButtons extends StatelessWidget {
  const _LayoutButtons({
    required this.colors,
    required this.localizations,
    required this.layout,
    required this.onLayout,
    this.layouts = MusicLayout.values,
    this.kind = _LayoutKind.music,
    this.coverSize,
    this.onCoverSize,
  });

  final PlEditConfig colors;
  final AppLocalizations localizations;
  final MusicLayout layout;

  /// The layouts there is a button for.
  final List<MusicLayout> layouts;

  /// What is laid out, which words the tooltips.
  final _LayoutKind kind;

  /// How wide the covers are, and called with a new width from the slider
  /// beside the covers button (none without).
  final double? coverSize;
  final ValueChanged<double>? onCoverSize;
  final ValueChanged<MusicLayout> onLayout;

  @override
  Widget build(BuildContext context) {
    Widget button(MusicLayout own, String glyph, String label) {
      final on = layout == own;
      return Semantics(
        button: true,
        label: label,
        child: _HoverTip(
          message: label,
          colors: colors,
          child: _Tap(
            behavior: HitTestBehavior.opaque,
            onTap: () => onLayout(own),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: on ? colors.selectedBg : colors.normalBg,
                border: Border.all(
                  color: colors.normal.withAlpha(on ? 200 : 90),
                ),
              ),
              child: SizedBox(
                width: 18,
                height: 14,
                child: Center(
                  child: Text(
                    glyph,
                    style: TextStyle(
                      color: on ? colors.current : colors.normal,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, own) in [
          for (final candidate in [
            MusicLayout.tracks,
            MusicLayout.browser,
            MusicLayout.split,
            MusicLayout.covers,
          ])
            if (layouts.contains(candidate)) candidate,
        ].indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          switch (own) {
            MusicLayout.tracks => button(
              own,
              "≡",
              switch (kind) {
                _LayoutKind.movies => localizations.mlLayoutMovies,
                _LayoutKind.shows => localizations.mlLayoutEpisodes,
                _ => localizations.mlLayoutTracks,
              },
            ),
            MusicLayout.browser => button(
              own,
              "◧",
              switch (kind) {
                _LayoutKind.books => localizations.mlLayoutBooksList,
                _LayoutKind.podcasts => localizations.mlLayoutPodcastsList,
                _LayoutKind.shows => localizations.mlLayoutShowsList,
                _ => localizations.mlLayoutBrowser,
              },
            ),
            MusicLayout.split => button(
              own,
              "▤",
              switch (kind) {
                _LayoutKind.books => localizations.mlLayoutBooksSplit,
                _LayoutKind.shows => localizations.mlLayoutShowsSplit,
                _LayoutKind.movies => localizations.mlLayoutMovieCategories,
                _ => localizations.mlLayoutSplit,
              },
            ),
            MusicLayout.covers when onCoverSize != null => _CoverSplitButton(
              colors: colors,
              label: switch (kind) {
                _LayoutKind.books => localizations.mlLayoutBookCovers,
                _LayoutKind.podcasts => localizations.mlLayoutPodcastCovers,
                _LayoutKind.movies => localizations.mlLayoutMovieCovers,
                _LayoutKind.shows => localizations.mlLayoutShowCovers,
                _LayoutKind.music => localizations.mlLayoutCovers,
              },
              sizeLabel: localizations.mlCoverSize,
              on: layout == own,
              size: coverSize ?? CoverGrid.defaultTileWidth,
              onSelect: () => onLayout(own),
              onSize: onCoverSize!,
            ),
            MusicLayout.covers => button(
              own,
              "▦",
              switch (kind) {
                _LayoutKind.books => localizations.mlLayoutBookCovers,
                _LayoutKind.podcasts => localizations.mlLayoutPodcastCovers,
                _LayoutKind.movies => localizations.mlLayoutMovieCovers,
                _LayoutKind.shows => localizations.mlLayoutShowCovers,
                _LayoutKind.music => localizations.mlLayoutCovers,
              },
            ),
          },
        ],
      ],
    );
  }
}

/// What one panel of the split layout lists.
class _PanelSpec {
  const _PanelSpec({
    required this.id,
    required this.heading,
    required this.counts,
    required this.rows,
    required this.sort,
    required this.onSort,
  });

  /// Names the panel, to keep how it is sorted.
  final String id;

  /// The heading of the names column, and of each count column.
  final String heading;
  final List<String> counts;
  final List<_SplitRow> rows;

  /// How it is sorted, and called with the column of a heading clicked.
  final _PanelSort sort;
  final ValueChanged<int> onSort;
}

/// The split layout: panels side by side, each with the counts of what is in
/// it, above the tracks ([bottom]); the bar between them is dragged to give
/// the panels more or less room, and the bars between the panels to give one
/// more of the width and the next less.
class _SplitPanels extends StatelessWidget {
  const _SplitPanels({
    required this.skin,
    required this.colors,
    required this.panels,
    required this.weights,
    required this.onWeights,
    required this.fraction,
    required this.onMoved,
    required this.bottom,
    required this.focus,
    required this.onFocus,
    required this.scrollOf,
    required this.keyOf,
    this.cover,
  });

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final List<_PanelSpec> panels;

  /// A grid of covers in place of the panels.
  final Widget? cover;

  /// The key of a panel, which keeps it when it is moved in the tree.
  final Key Function(String panel) keyOf;

  /// The panel the arrow keys act on, called when one is pressed, and how
  /// each panel scrolls.
  final String focus;
  final ValueChanged<String> onFocus;
  final ScrollController Function(String panel) scrollOf;

  /// The share of the width each panel has (null: equal), and called with
  /// the share the bar after panel `i` moved by and the width it was of.
  final List<double>? weights;
  final void Function(
    int divider,
    double moved,
    double width,
    List<double> leasts,
  )
  onWeights;

  /// The height of the whole, the share of it the panels have, and called
  final double fraction;
  final ValueChanged<double> onMoved;

  /// The tracks.
  final Widget bottom;

  /// The least the panels and the tracks keep of the height, and a panel of
  /// the width. (In a window too small for both, each gets what it can.)
  static const double leastPanels = 60;
  static const double leastTracks = 96;

  /// The least width of [panel]: room for its counts and a little of the
  /// names.
  static double leastWidthOf(_PanelSpec panel) =>
      leastNames + _cellGap * 2 + panel.counts.length * _countWidth;
  static const double leastNames = 40;

  /// The widths of panels that share [available] by [shares], each at least
  /// its [leasts] (when they all cannot have that, in proportion to it).
  static List<double> fit(
    List<double> shares,
    double available,
    List<double> leasts,
  ) {
    final leastTotal = leasts.fold(0.0, (sum, w) => sum + w);
    if (leastTotal >= available) {
      return [
        for (final w in leasts)
          leastTotal == 0 ? 0 : w / leastTotal * available,
      ];
    }
    // Those under their least get it; the others share the rest.
    final widths = [for (final share in shares) share * available];
    final fixed = <int>{};
    var changed = true;
    while (changed) {
      changed = false;
      final free = [
        for (var i = 0; i < widths.length; i++)
          if (!fixed.contains(i)) i,
      ];
      final room = available - fixed.fold(0.0, (sum, i) => sum + leasts[i]);
      final freeShare = free.fold(0.0, (sum, i) => sum + shares[i]);
      for (final i in free) {
        final w = freeShare == 0 ? 0.0 : shares[i] / freeShare * room;
        if (w < leasts[i]) {
          fixed.add(i);
          changed = true;
        }
      }
      if (!changed) {
        for (final i in free) {
          widths[i] = freeShare == 0 ? 0.0 : shares[i] / freeShare * room;
        }
      }
    }
    for (final i in fixed) {
      widths[i] = leasts[i];
    }
    return widths;
  }

  /// The share of the width each of [count] panels has: [saved] if it fits,
  /// else equal shares.
  static List<double> sharesOf(List<double>? saved, int count) {
    if (saved != null &&
        saved.length == count &&
        saved.every((share) => share > 0)) {
      final total = saved.fold(0.0, (sum, share) => sum + share);
      return [for (final share in saved) share / total];
    }
    return List.filled(count, 1 / count);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _build(box.maxHeight),
  );

  Widget _build(double height) {
    // Neither side keeps less than its least: in a window too small for
    // both, the tracks have a little more than half.
    final tracksLeast = min(leastTracks, height * 0.55);
    final panelsLeast = min(
      leastPanels,
      max(0.0, height - tracksLeast - _PaneDivider.width),
    );
    final room = max(panelsLeast, height - _PaneDivider.width - tracksLeast);
    final top = (fraction * height).clamp(panelsLeast, room);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: top,
          child:
              cover ??
              LayoutBuilder(
                builder: (context, row) {
                  final available = max(
                    0.0,
                    row.maxWidth - _PaneDivider.width * (panels.length - 1),
                  );
                  final shares = sharesOf(weights, panels.length);
                  final leasts = [
                    for (final panel in panels) leastWidthOf(panel),
                  ];
                  final widths = fit(shares, available, leasts);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, panel) in panels.indexed) ...[
                        if (i > 0)
                          _PaneDivider(
                            color: colors.normal.withAlpha(90),
                            // By how far it moved, not to where it is now:
                            // several moves can arrive before the next build.
                            onDrag: (dx) =>
                                onWeights(i - 1, dx, available, leasts),
                          ),
                        SizedBox(
                          width: widths[i],
                          child: _PaneFocus(
                            key: keyOf(panel.id),
                            id: panel.id,
                            focus: focus,
                            onFocus: onFocus,
                            colors: colors,
                            child: _SplitPane(
                              skin: skin,
                              colors: colors,
                              panel: panel,
                              controller: scrollOf(panel.id),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
        ),
        _HorizontalDivider(
          color: colors.normal.withAlpha(90),
          onDrag: (dy) => onMoved(dy / height),
        ),
        Expanded(child: bottom),
      ],
    );
  }
}

/// The panels of the split layout of music: the artists with their album and
/// track counts, and the albums of those picked with their year and tracks.
List<_PanelSpec> _musicPanels(
  AppLocalizations l,
  _MusicStats stats, {
  required Map<String, _PanelSort> sorts,
  required void Function(String panel, int column) onSort,
  required Set<String> artists,
  required Set<String> albums,
  required VoidCallback onAll,
  required void Function(String artist, List<String> listed) onArtist,
  required void Function(String album, List<String> listed) onAlbum,
  required VoidCallback onAllAlbums,
  required void Function(String panel, String name) onMenu,
  bool shows = false,
  Map<String, DateTime?>? showDates,
  Map<String, int>? unwatchedShows,
  Map<String, int>? unwatchedSeasons,
}) {
  // A right-click picks the row (when it is not picked) and opens the menu
  // for all it stands for.
  VoidCallback menu(
    String panel,
    String name,
    bool picked,
    VoidCallback pick,
  ) => () {
    if (!picked) pick();
    onMenu(panel, name);
  };
  final artistSort = sorts["artists"] ?? _PanelSort.byName;
  final albumSort = sorts["albums"] ?? _PanelSort.byName;
  var listedArtists = _sortedItems(
    stats.artists,
    artistSort,
    (a) => a.name,
    (a) => [a.albums, a.tracks],
  );
  // The shows the most recent first, until a heading says otherwise.
  if (showDates != null && sorts["artists"] == null) {
    listedArtists = [...listedArtists]
      ..sort((a, b) {
        final x = showDates[a.name];
        final y = showDates[b.name];
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });
  }
  final listedAlbums = _sortedItems(
    stats.albums,
    albumSort,
    (a) => a.name,
    (a) => [a.year, a.tracks],
  );
  final artistNames = [for (final a in listedArtists) a.name];
  final albumNames = [for (final a in listedAlbums) a.name];
  return [
    _PanelSpec(
      id: "artists",
      heading: shows ? l.mlColumnShow : l.mlColumnArtist,
      counts: [
        shows ? l.mlColumnSeasons : l.mlColumnAlbums,
        shows ? l.mlColumnEpisodes : l.mlColumnTracks,
      ],
      sort: artistSort,
      onSort: (column) => onSort("artists", column),
      rows: [
        _SplitRow(
          l.mlAllWithCount(
            shows
                ? l.mlShowCount(artistNames.length)
                : l.mlArtistCount(artistNames.length),
          ),
          [
            "${stats.artists.fold(0, (sum, a) => sum + a.albums)}",
            "${stats.trackCount}",
          ],
          artists.isEmpty && albums.isEmpty,
          onAll,
          menu("artists", "", artists.isEmpty && albums.isEmpty, onAll),
        ),
        for (final artist in listedArtists)
          _SplitRow(
            artist.name,
            [
              "${artist.albums}",
              unwatchedShows == null
                  ? "${artist.tracks}"
                  : "${(unwatchedShows[artist.name] ?? 0) == 0 ? "✓" : unwatchedShows[artist.name]} (${artist.tracks})",
            ],
            artists.contains(artist.name),
            () => onArtist(artist.name, artistNames),
            menu(
              "artists",
              artist.name,
              artists.contains(artist.name),
              () => onArtist(artist.name, artistNames),
            ),
          ),
      ],
    ),
    _PanelSpec(
      id: "albums",
      heading: shows ? l.mlColumnSeason : l.mlColumnAlbum,
      counts: [l.mlColumnYear, shows ? l.mlColumnEpisodes : l.mlColumnTracks],
      sort: albumSort,
      onSort: (column) => onSort("albums", column),
      rows: [
        _SplitRow(
          l.mlAllWithCount(
            shows
                ? l.mlSeasonCount(albumNames.length)
                : l.mlAlbumCount(albumNames.length),
          ),
          ["", "${stats.albums.fold(0, (sum, a) => sum + a.tracks)}"],
          albums.isEmpty,
          onAllAlbums,
          menu("albums", "", albums.isEmpty, onAllAlbums),
        ),
        for (final album in listedAlbums)
          _SplitRow(
            album.name,
            [
              "${album.year ?? ""}",
              unwatchedSeasons == null
                  ? "${album.tracks}"
                  : "${(unwatchedSeasons[album.name] ?? 0) == 0 ? "✓" : unwatchedSeasons[album.name]} (${album.tracks})",
            ],
            albums.contains(album.name),
            () => onAlbum(album.name, albumNames),
            menu(
              "albums",
              album.name,
              albums.contains(album.name),
              () => onAlbum(album.name, albumNames),
            ),
          ),
      ],
    ),
  ];
}

/// The panels of the split layout of movies: the categories (genres) and the
/// server's playlists, each with how many movies it has.
List<_PanelSpec> _moviePanels(
  AppLocalizations l,
  List<TrackTags> movies,
  Map<String, List<String>> playlists, {
  required Map<String, _PanelSort> sorts,
  required void Function(String panel, int column) onSort,
  required Set<String> categories,
  required Set<String> lists,
  required void Function(String name, List<String> listed) onCategory,
  required VoidCallback onAllCategories,
  required void Function(String name, List<String> listed) onList,
  required VoidCallback onAllLists,
  required void Function(List<String> paths) onMenu,
}) {
  final byGenre = <String, List<String>>{};
  for (final movie in movies) {
    for (final genre in movie.genres) {
      (byGenre[genre] ??= []).add(movie.path);
    }
  }
  final known = {for (final movie in movies) movie.path};
  final byList = {
    for (final entry in playlists.entries)
      entry.key: [
        for (final path in entry.value)
          if (known.contains(path)) path,
      ],
  };
  final categorySort = sorts["categories"] ?? _PanelSort.byName;
  final listSort = sorts["lists"] ?? _PanelSort.byName;
  final listedCategories = _sortedItems(
    byGenre.keys.toList(),
    categorySort,
    (name) => name,
    (name) => [byGenre[name]!.length],
  );
  final listedLists = _sortedItems(
    byList.keys.toList(),
    listSort,
    (name) => name,
    (name) => [byList[name]!.length],
  );
  _SplitRow row(
    String name,
    List<String> paths,
    bool picked,
    VoidCallback pick,
  ) => _SplitRow(name, ["${paths.length}"], picked, pick, () {
    if (!picked) pick();
    onMenu(paths);
  });
  return [
    _PanelSpec(
      id: "categories",
      heading: l.mlColumnCategory,
      counts: [l.mlColumnMovies],
      sort: categorySort,
      onSort: (column) => onSort("categories", column),
      rows: [
        row(
          l.mlAllWithCount(l.mlCategoryCount(listedCategories.length)),
          [for (final movie in movies) movie.path],
          categories.isEmpty,
          onAllCategories,
        ),
        for (final name in listedCategories)
          row(
            name,
            byGenre[name]!,
            categories.contains(name),
            () => onCategory(name, listedCategories),
          ),
      ],
    ),
    _PanelSpec(
      id: "lists",
      heading: l.mlColumnPlaylist,
      counts: [l.mlColumnMovies],
      sort: listSort,
      onSort: (column) => onSort("lists", column),
      rows: [
        row(
          l.mlAllWithCount(l.mlPlaylistCount(listedLists.length)),
          [for (final movie in movies) movie.path],
          lists.isEmpty,
          onAllLists,
        ),
        for (final name in listedLists)
          row(
            name,
            byList[name]!,
            lists.contains(name),
            () => onList(name, listedLists),
          ),
      ],
    ),
  ];
}

/// What the split layout of audiobooks lists: the authors, the series of
/// those picked, and the books of those, with counts.
class _BookStats {
  const _BookStats({
    required this.authors,
    required this.series,
    required this.books,
    required this.partCount,
  });

  /// Each author with how many books and parts.
  final List<({String name, int books, int parts})> authors;

  /// Each series of the authors picked with how many books.
  final List<({String name, int books})> series;

  /// Each book of the authors and series picked with how many parts and the
  /// year it came out.
  final List<({String name, int parts, int? year})> books;
  final int partCount;

  /// The stats of [parts], the series being those of the [authors] picked
  /// and the books those of the authors and [series] picked.
  factory _BookStats.of(
    List<TrackTags> parts,
    Set<String> authors,
    Set<String> series,
  ) {
    final booksOf = <String, Set<String>>{};
    final partsOf = <String, int>{};
    final seriesBooks = <String, Set<String>>{};
    final bookParts = <String, int>{};
    final bookYear = <String, int>{};
    for (final part in parts) {
      final author = part.artist;
      final book = part.album;
      if (author != null) {
        partsOf[author] = (partsOf[author] ?? 0) + 1;
        if (book != null) (booksOf[author] ??= {}).add(book);
      }
      final byAuthor = authors.isEmpty || authors.contains(author);
      if (byAuthor && part.series != null && book != null) {
        (seriesBooks[part.series!] ??= {}).add(book);
      }
      if (byAuthor &&
          (series.isEmpty || series.contains(part.series)) &&
          book != null) {
        bookParts[book] = (bookParts[book] ?? 0) + 1;
        if (part.year case final year?) {
          bookYear[book] = min(bookYear[book] ?? year, year);
        }
      }
    }
    return _BookStats(
      authors: [
        for (final name in partsOf.keys)
          (
            name: name,
            books: booksOf[name]?.length ?? 0,
            parts: partsOf[name]!,
          ),
      ],
      series: [
        for (final name in seriesBooks.keys)
          (name: name, books: seriesBooks[name]!.length),
      ],
      books: [
        for (final name in bookParts.keys)
          (name: name, parts: bookParts[name]!, year: bookYear[name]),
      ],
      partCount: parts.length,
    );
  }
}

/// The panels of the split layout of audiobooks: authors, their series, and
/// the books.
List<_PanelSpec> _bookPanels(
  AppLocalizations l,
  _BookStats stats, {
  required Map<String, _PanelSort> sorts,
  required void Function(String panel, int column) onSort,
  required Set<String> authors,
  required Set<String> series,
  required Set<String> books,
  required VoidCallback onAll,
  required void Function(String author, List<String> listed) onAuthor,
  required VoidCallback onAllSeries,
  required void Function(String series, List<String> listed) onSeries,
  required VoidCallback onAllBooks,
  required void Function(String book, List<String> listed) onBook,
  required void Function(String panel, String name) onMenu,
}) {
  VoidCallback menu(
    String panel,
    String name,
    bool picked,
    VoidCallback pick,
  ) => () {
    if (!picked) pick();
    onMenu(panel, name);
  };
  final authorSort = sorts["authors"] ?? _PanelSort.byName;
  final seriesSort = sorts["series"] ?? _PanelSort.byName;
  final bookSort = sorts["books"] ?? _PanelSort.byName;
  final listedAuthors = _sortedItems(
    stats.authors,
    authorSort,
    (a) => a.name,
    (a) => [a.books, a.parts],
  );
  final listedSeries = _sortedItems(
    stats.series,
    seriesSort,
    (a) => a.name,
    (a) => [a.books],
  );
  final listedBooks = _sortedItems(
    stats.books,
    bookSort,
    (a) => a.name,
    (a) => [a.year, a.parts],
  );
  final authorNames = [for (final a in listedAuthors) a.name];
  final seriesNames = [for (final s in listedSeries) s.name];
  final bookNames = [for (final b in listedBooks) b.name];
  return [
    _PanelSpec(
      id: "authors",
      heading: l.mlColumnAuthor,
      counts: [l.mlColumnBooks, l.mlColumnParts],
      sort: authorSort,
      onSort: (column) => onSort("authors", column),
      rows: [
        _SplitRow(
          l.mlAllWithCount(l.mlAuthorCount(authorNames.length)),
          [
            "${stats.authors.fold(0, (sum, a) => sum + a.books)}",
            "${stats.partCount}",
          ],
          authors.isEmpty && series.isEmpty && books.isEmpty,
          onAll,
          menu(
            "authors",
            "",
            authors.isEmpty && series.isEmpty && books.isEmpty,
            onAll,
          ),
        ),
        for (final author in listedAuthors)
          _SplitRow(
            author.name,
            ["${author.books}", "${author.parts}"],
            authors.contains(author.name),
            () => onAuthor(author.name, authorNames),
            menu(
              "authors",
              author.name,
              authors.contains(author.name),
              () => onAuthor(author.name, authorNames),
            ),
          ),
      ],
    ),
    _PanelSpec(
      id: "series",
      heading: l.mlColumnSeries,
      counts: [l.mlColumnBooks],
      sort: seriesSort,
      onSort: (column) => onSort("series", column),
      rows: [
        _SplitRow(
          l.mlAllWithCount(l.mlSeriesCount(seriesNames.length)),
          ["${stats.series.fold(0, (sum, s) => sum + s.books)}"],
          series.isEmpty,
          onAllSeries,
          menu("series", "", series.isEmpty, onAllSeries),
        ),
        for (final item in listedSeries)
          _SplitRow(
            item.name,
            ["${item.books}"],
            series.contains(item.name),
            () => onSeries(item.name, seriesNames),
            menu(
              "series",
              item.name,
              series.contains(item.name),
              () => onSeries(item.name, seriesNames),
            ),
          ),
      ],
    ),
    _PanelSpec(
      id: "books",
      heading: l.mlColumnBook,
      counts: [l.mlColumnYear, l.mlColumnParts],
      sort: bookSort,
      onSort: (column) => onSort("books", column),
      rows: [
        _SplitRow(
          l.mlAllWithCount(l.mlBookCount(bookNames.length)),
          ["", "${stats.books.fold(0, (sum, b) => sum + b.parts)}"],
          books.isEmpty,
          onAllBooks,
          menu("books", "", books.isEmpty, onAllBooks),
        ),
        for (final book in listedBooks)
          _SplitRow(
            book.name,
            ["${book.year ?? ""}", "${book.parts}"],
            books.contains(book.name),
            () => onBook(book.name, bookNames),
            menu(
              "books",
              book.name,
              books.contains(book.name),
              () => onBook(book.name, bookNames),
            ),
          ),
      ],
    ),
  ];
}

/// One row of a split panel: a name and counts at its right.
class _SplitRow {
  const _SplitRow(
    this.name,
    this.counts,
    this.selected,
    this.onTap, [
    this.onMenu,
  ]);

  final String name;
  final List<String> counts;
  final bool selected;
  final VoidCallback onTap;

  /// Right-click: the menu for everything the row stands for.
  final VoidCallback? onMenu;
}

/// How wide each count column of a split panel is.
const double _countWidth = 52;

/// A panel of the split layout: a heading row (a click on a heading sorts by
/// it) and the rows under it, in a list with the skin's scrollbar.
class _SplitPane extends StatelessWidget {
  const _SplitPane({
    required this.skin,
    required this.colors,
    required this.panel,
    required this.controller,
  });

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final _PanelSpec panel;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    TextStyle style(Color color, {bool bold = false}) => TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: bold ? FontWeight.bold : null,
    );
    Widget heading(int column, String label, {double? width}) {
      final sorted = panel.sort.column == column;
      final text = Text(
        sorted ? "$label ${panel.sort.ascending ? "▲" : "▼"}" : label,
        textAlign: column == 0 ? TextAlign.start : TextAlign.right,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style(colors.normal),
      );
      final tappable = _Tap(
        behavior: HitTestBehavior.opaque,
        onTap: () => panel.onSort(column),
        child: text,
      );
      return width == null
          ? Expanded(child: tappable)
          : SizedBox(width: width, child: tappable);
    }

    final needed = _SplitPanels.leastWidthOf(panel);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.normal.withAlpha(90)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _cellGap),
              child: Row(
                children: [
                  heading(0, panel.heading),
                  for (final (i, count) in panel.counts.indexed)
                    heading(i + 1, count, width: _countWidth),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _SkinList(
            skin: skin,
            colors: colors,
            controller: controller,
            itemCount: panel.rows.length,
            itemBuilder: (context, i) {
              final row = panel.rows[i];
              final color = row.selected ? colors.current : colors.normal;
              return _Tap(
                behavior: HitTestBehavior.opaque,
                onTap: row.onTap,
                onSecondaryTap: row.onMenu,
                child: ColoredBox(
                  color: row.selected ? colors.selectedBg : colors.normalBg,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _cellGap),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: style(color, bold: i == 0),
                          ),
                        ),
                        for (final count in row.counts)
                          SizedBox(
                            width: _countWidth,
                            child: Text(
                              count,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              style: style(color),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    // A panel squeezed under what its counts need is clipped, not laid out
    // overflowing.
    return LayoutBuilder(
      builder: (context, box) {
        // Squeezed under its header's height too (a pane dragged shut).
        final width = max(box.maxWidth, needed);
        final height = max(box.maxHeight, _headerHeight + 1);
        if (width == box.maxWidth && height == box.maxHeight) return content;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: content,
          ),
        );
      },
    );
  }
}

/// The bar between the panels and the tracks of the split layout: dragged
/// up or down (the same as [_PaneDivider] is sideways).
class _HorizontalDivider extends StatelessWidget {
  const _HorizontalDivider({required this.color, required this.onDrag});

  final Color color;

  /// Called with how far the pointer moved up or down.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (event) => onDrag(event.delta.dy),
      child: SizedBox(
        height: _PaneDivider.width,
        child: Center(
          child: SizedBox(
            height: _dividerLine,
            child: ColoredBox(color: color.withAlpha(215)),
          ),
        ),
      ),
    ),
  );
}

/// Gives [child] an [Overlay] of its own: dragging a track needs one, and
/// the library window has no [Navigator] to supply it.
class _WithOverlay extends StatefulWidget {
  const _WithOverlay({required this.child});

  final Widget child;

  @override
  State<_WithOverlay> createState() => _WithOverlayState();
}

class _WithOverlayState extends State<_WithOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (context) => widget.child,
  );

  @override
  void didUpdateWidget(_WithOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.label,
    this.leading,
    this.trailing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PlEditConfig colors;
  final String label;

  /// What comes before the label, such as the layout buttons.
  final Widget? leading;

  /// What comes after the search field, such as the sort and filter.
  final Widget? trailing;

  /// Narrower than this, the trailing controls go on a line of their own.
  static const double _narrow = 560;

  /// Narrower than this, the leading buttons go on a line of their own.
  static const double _stackBelow = 240;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final below = trailing != null && box.maxWidth < _narrow;
      // Too narrow for the layout buttons and the field in a line: the
      // buttons get one of their own.
      final stacked = leading != null && box.maxWidth < _stackBelow;
      final search = Row(
        children: [
          if (leading != null && !stacked) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Text("$label:"),
          const SizedBox(width: 4),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.normal.withAlpha(140)),
                color: colors.normalBg,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                child: SizedBox(
                  height: 14,
                  child: _SearchField(
                    controller: controller,
                    focusNode: focusNode,
                    colors: colors,
                  ),
                ),
              ),
            ),
          ),
          if (trailing != null && !below) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      );
      final field = stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: leading,
                ),
                const SizedBox(height: 3),
                search,
              ],
            )
          : search;
      return Padding(
        padding: const EdgeInsets.all(3),
        child: below
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field,
                  const SizedBox(height: 3),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: trailing,
                  ),
                ],
              )
            : field,
      );
    },
  );
}

/// One line of the compact library's menu: what it says, whether it is the
/// choice made (with the arrow of the sort direction, for a sorted column),
/// and what choosing it does. An empty label is a divider.
class _MenuEntry {
  const _MenuEntry({
    required this.label,
    required this.active,
    this.onTap,
    this.arrow,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? arrow;
}

/// The search field and the menu button of the compact library.
class _CompactBar extends StatelessWidget {
  const _CompactBar({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.entries,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PlEditConfig colors;
  final List<_MenuEntry> entries;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(3),
    child: Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.normal.withAlpha(140)),
              color: colors.normalBg,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: SizedBox(
                height: 14,
                child: _SearchField(
                  controller: controller,
                  focusNode: focusNode,
                  colors: colors,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        _CompactMenu(colors: colors, entries: entries),
      ],
    ),
  );
}

/// A small button that drops a list of choices under it.
class _CompactMenu extends StatefulWidget {
  const _CompactMenu({required this.colors, required this.entries});

  final PlEditConfig colors;
  final List<_MenuEntry> entries;

  @override
  State<_CompactMenu> createState() => _CompactMenuState();
}

class _CompactMenuState extends State<_CompactMenu> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final text = DefaultTextStyle.of(context).style;
    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: this,
        onTapOutside: (_) => _portal.hide(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 2),
            child: Align(
              alignment: Alignment.topRight,
              child: TapRegion(
                groupId: this,
                child: DefaultTextStyle(
                  style: text.copyWith(decoration: TextDecoration.none),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.normalBg.withAlpha(255),
                      border: Border.all(color: _legible(colors)),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 160,
                        maxHeight: 220,
                      ),
                      child: SingleChildScrollView(
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in widget.entries)
                                if (entry.label.isEmpty)
                                  SizedBox(
                                    height: 5,
                                    child: Center(
                                      child: SizedBox(
                                        height: 1,
                                        child: ColoredBox(
                                          color: colors.normal.withAlpha(90),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  _Tap(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      entry.onTap?.call();
                                      _portal.hide();
                                    },
                                    child: ColoredBox(
                                      color: entry.active
                                          ? colors.selectedBg
                                          : colors.normalBg,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        child: Text(
                                          entry.arrow != null && entry.active
                                              ? "${entry.arrow} ${entry.label}"
                                              : entry.active
                                              ? "• ${entry.label}"
                                              : entry.label,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: entry.active
                                                ? colors.current
                                                : colors.normal,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: _Tap(
            behavior: HitTestBehavior.opaque,
            onTap: () => _portal.isShowing ? _portal.hide() : _portal.show(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.normalBg,
                border: Border.all(color: colors.normal.withAlpha(90)),
              ),
              child: SizedBox(
                width: 18,
                height: 14,
                child: Center(
                  child: Text(
                    "☰",
                    style: TextStyle(
                      color: colors.normal,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two buttons that choose how movies and shows are ordered and which
/// are listed: each shows its choice, and a click goes on to the next.
class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.colors,
    required this.localizations,
    required this.sort,
    required this.filter,
    required this.shows,
    required this.onSort,
    required this.onFilter,
    required this.hide,
    required this.hideLabel,
    required this.hideTip,
    required this.onHide,
    this.onlyHide = false,
  });

  /// The toggle that leaves out what was watched (or listened to), and
  /// whether it is the only control.
  final bool hide;
  final String hideLabel;
  final String hideTip;
  final ValueChanged<bool> onHide;
  final bool onlyHide;

  final PlEditConfig colors;
  final AppLocalizations localizations;
  final VideoSort sort;
  final VideoFilter filter;
  final bool shows;
  final ValueChanged<VideoSort> onSort;
  final ValueChanged<VideoFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l = localizations;
    Widget button(String text, String tip, VoidCallback onTap, bool active) =>
        _HoverTip(
          message: tip,
          colors: colors,
          child: _Tap(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: active ? colors.selectedBg : colors.normalBg,
                border: Border.all(
                  color: colors.normal.withAlpha(active ? 200 : 90),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 14,
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: active ? colors.current : colors.normal,
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    final sortName = switch (sort) {
      VideoSort.name => l.mlVideoSortName,
      VideoSort.watched => l.mlVideoSortWatched,
      VideoSort.aired => l.mlVideoSortAired,
      VideoSort.added => l.mlVideoSortAdded,
    };
    final filterName = switch (filter) {
      VideoFilter.all => l.mlVideoFilterAll,
      VideoFilter.watching =>
        shows ? l.mlVideoFilterWatching : l.mlVideoFilterInProgress,
      VideoFilter.unwatched => l.mlVideoFilterUnwatched,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!onlyHide) ...[
          button(
            "↓ $sortName",
            l.mlVideoSortTip,
            () => onSort(
              VideoSort.values[(sort.index + 1) % VideoSort.values.length],
            ),
            sort != VideoSort.name,
          ),
          const SizedBox(width: 2),
          button(
            filterName,
            l.mlVideoFilterTip,
            () => onFilter(
              VideoFilter.values[(filter.index + 1) %
                  VideoFilter.values.length],
            ),
            filter != VideoFilter.all,
          ),
          const SizedBox(width: 2),
        ],
        button(hideLabel, hideTip, () => onHide(!hide), hide),
      ],
    );
  }
}

/// A [GestureDetector] that shows the pointing hand over what it covers.
class _Tap extends StatelessWidget {
  const _Tap({
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.behavior,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: behavior,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTap: onSecondaryTap,
      child: child,
    ),
  );
}

/// The tree of sources: each section's heading, with its sources under it.
class _SourceTree extends StatelessWidget {
  const _SourceTree({
    required this.skin,
    required this.colors,
    required this.localizations,
    required this.sections,
    required this.collapsed,
    required this.selectedId,
    required this.onSection,
    required this.onSource,
    required this.onSourceMenu,
    required this.onDrop,
  });

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final AppLocalizations localizations;
  final List<LibrarySourceSection> sections;
  final Set<String> collapsed;
  final String selectedId;
  final ValueChanged<String> onSection;
  final ValueChanged<String> onSource;
  final ValueChanged<LibrarySource> onSourceMenu;

  /// Tracks dropped on a playlist's row.
  final void Function(LibrarySource source, _TrackDrag drag) onDrop;

  String _heading(LibrarySourceSection section) =>
      section.label ??
      switch (section.kind) {
        LibrarySourceKind.local => localizations.mlSectionLocal,
        LibrarySourceKind.videos => localizations.mlSectionVideos,
        LibrarySourceKind.remote => localizations.mlSectionRemote,
        LibrarySourceKind.playlists => localizations.mlSectionPlaylists,
        LibrarySourceKind.podcasts => localizations.mlSectionPodcasts,
        LibrarySourceKind.audiobooks => localizations.mlSectionAudiobooks,
        LibrarySourceKind.statistics => localizations.mlSectionStatistics,
      };

  @override
  Widget build(BuildContext context) {
    final rows = <_BrowserRow>[
      for (final section in sections) ...[
        _BrowserRow(
          "${collapsed.contains(section.id) ? "▸" : "▾"} ${_heading(section)}",
          0,
          false,
          () => onSection(section.id),
        ),
        if (!collapsed.contains(section.id))
          if (section.sources.isEmpty && section.actions.isEmpty)
            _BrowserRow(localizations.mlSectionNoSources, 1, false, () {})
          else ...[
            for (final source in section.sources)
              _BrowserRow(
                source.label,
                1,
                source.id == selectedId,
                () => onSource(source.id),
                onSecondaryTap: source.playlistId == null
                    ? null
                    : () => onSourceMenu(source),
                // Dropping a playlist's own entries on it would only copy them.
                acceptsDrag: source.playlistId == null
                    ? null
                    : (drag) => drag.playlistId != source.playlistId,
                onDrop: (drag) => onDrop(source, drag),
              ),
            for (final action in section.actions)
              _BrowserRow(action.label, 1, false, action.onTap),
          ],
      ],
    ];
    return _SkinList(
      skin: skin,
      colors: colors,
      itemCount: rows.length,
      itemBuilder: (context, i) => _BrowserItem(row: rows[i], colors: colors),
    );
  }
}

/// The artists, each followed by its albums when picked.
class _BrowserList extends StatelessWidget {
  const _BrowserList({
    required this.controller,
    required this.onRows,
    required this.skin,
    required this.colors,
    required this.allArtists,
    required this.allAlbums,
    required this.library,
    required this.query,
    required this.artists,
    required this.albums,
    required this.onAll,
    required this.onArtist,
    required this.onAlbum,
    required this.onArtistMenu,
    required this.onAlbumMenu,
  });

  final ScrollController controller;

  /// Told the rows listed, in order, each time they are.
  final ValueChanged<List<_BrowserRow>> onRows;
  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final String allArtists;
  final String allAlbums;
  final MediaLibrary library;
  final String query;
  final Set<String> artists;
  final Set<String> albums;
  final VoidCallback onAll;

  /// Called with the artist clicked and every artist listed, in order.
  final void Function(String artist, List<String> listed) onArtist;

  /// Called with the artist the album is listed under (none under "All
  /// Artists"), the album, and every album listed, in order.
  final void Function(String? artist, String album, List<String> listed)
  onAlbum;

  /// Right-click on an artist, or on an album (with the artist it is listed
  /// under, none under "All Artists"): the menu for all of its tracks.
  final void Function(String artist) onArtistMenu;
  final void Function(String? artist, String album) onAlbumMenu;

  @override
  Widget build(BuildContext context) {
    final names = library.artistsMatching(query);
    // The albums shown, in order: under each picked artist, or all of them
    // after the artists when none is.
    final listed = <String>[
      for (final name in names)
        if (artists.contains(name))
          ...library.albums(artist: name, query: query),
      if (artists.isEmpty) ...library.albums(query: query),
    ];
    final rows = <_BrowserRow>[
      _BrowserRow(allArtists, 0, artists.isEmpty && albums.isEmpty, onAll),
      for (final name in names) ...[
        _BrowserRow(
          name,
          0,
          artists.contains(name),
          () => onArtist(name, names),
          // Picks the artist (when it is not picked) and opens the menu.
          onSecondaryTap: () {
            if (!artists.contains(name)) onArtist(name, names);
            onArtistMenu(name);
          },
        ),
        if (artists.contains(name))
          for (final title in library.albums(artist: name, query: query))
            _BrowserRow(
              title,
              1,
              albums.contains(title),
              () => onAlbum(name, title, listed),
              onSecondaryTap: () {
                if (!albums.contains(title)) onAlbum(name, title, listed);
                onAlbumMenu(name, title);
              },
            ),
      ],
      if (artists.isEmpty)
        for (final title in library.albums(query: query))
          _BrowserRow(
            title,
            1,
            albums.contains(title),
            () => onAlbum(null, title, listed),
            onSecondaryTap: () {
              if (!albums.contains(title)) onAlbum(null, title, listed);
              onAlbumMenu(null, title);
            },
          ),
    ];
    onRows(rows);
    return _SkinList(
      skin: skin,
      colors: colors,
      controller: controller,
      itemCount: rows.length,
      itemBuilder: (context, i) => _BrowserItem(row: rows[i], colors: colors),
    );
  }
}

class _BrowserRow {
  const _BrowserRow(
    this.text,
    this.indent,
    this.selected,
    this.onTap, {
    this.onSecondaryTap,
    this.acceptsDrag,
    this.onDrop,
    this.trailing,
    this.bold = false,
  });

  final String text;

  /// Whether the text is bold, to set the row apart from the others.
  final bool bold;

  /// Text at the right edge of the row, such as a count.
  final ({String strong, String rest})? trailing;
  final int indent;
  final bool selected;
  final VoidCallback onTap;

  /// Right-click, if the row has a menu.
  final VoidCallback? onSecondaryTap;

  /// Whether the row takes this drag; null for a row that takes none.
  final bool Function(_TrackDrag drag)? acceptsDrag;

  /// Tracks dropped on the row.
  final void Function(_TrackDrag drag)? onDrop;
}

/// What is dragged out of a track list: the files, and for a saved
/// playlist, which playlist and which of its entries they are.
class _TrackDrag {
  const _TrackDrag(this.paths, {this.playlistId, this.indices = const []});

  final List<String> paths;
  final int? playlistId;
  final List<int> indices;
}

class _BrowserItem extends StatelessWidget {
  const _BrowserItem({required this.row, required this.colors});

  final _BrowserRow row;
  final PlEditConfig colors;

  @override
  Widget build(BuildContext context) {
    final accepts = row.acceptsDrag;
    return DragTarget<_TrackDrag>(
      onWillAcceptWithDetails: (details) =>
          accepts != null && accepts(details.data),
      onAcceptWithDetails: (details) => row.onDrop?.call(details.data),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        final highlight = row.selected || hovered;
        return _Tap(
          behavior: HitTestBehavior.opaque,
          onTap: row.onTap,
          onSecondaryTap: row.onSecondaryTap,
          child: ColoredBox(
            color: highlight ? colors.selectedBg : colors.normalBg,
            child: Padding(
              padding: EdgeInsets.only(left: 3.0 + row.indent * 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlight ? colors.current : colors.normal,
                        fontSize: 11,
                        fontWeight: row.bold ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                  if (row.trailing case final trailing?)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 3),
                      // The number of new episodes in bold, then the total.
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: trailing.strong,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: trailing.rest),
                          ],
                        ),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: highlight ? colors.current : colors.normal,
                          fontSize: 11,
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

/// How the Media Library lays out music: the artists and albums in one list
/// beside the tracks, in two panels above the tracks, or the tracks alone.
enum MusicLayout { browser, split, tracks, covers }

/// How movies and shows are ordered: by name, or the most recent first by
/// when they were last watched, came out or were added.
enum VideoSort { name, watched, aired, added }

/// Which movies and shows are listed: all, those started but not finished
/// (a movie in progress, a show with episodes watched and still to watch),
/// or those with something not watched yet.
enum VideoFilter { all, watching, unwatched }

DateTime? _videoDate(TrackTags track, VideoSort sort) => switch (sort) {
  VideoSort.name => null,
  VideoSort.watched => track.lastWatched,
  VideoSort.aired => track.published,
  VideoSort.added => track.added,
};

/// The latest of each show's episodes' dates by [sort], by show.
Map<String, DateTime?> _showDates(List<TrackTags> tracks, VideoSort sort) {
  final dates = <String, DateTime?>{};
  for (final track in tracks) {
    final name = track.artist;
    final date = _videoDate(track, sort);
    if (name == null) continue;
    final was = dates[name];
    dates[name] = was == null || (date != null && date.isAfter(was))
        ? date
        : was;
  }
  return dates;
}

/// How many of [tracks] are not watched, by what [key] says of each (those
/// [only] lets through).
Map<String, int> _unwatched(
  List<TrackTags> tracks,
  String? Function(TrackTags track) key, {
  bool Function(TrackTags track)? only,
}) {
  final counts = <String, int>{};
  for (final track in tracks) {
    final name = key(track);
    if (name == null || !(only?.call(track) ?? true)) continue;
    counts[name] = (counts[name] ?? 0) + ((track.progress ?? 0) < 1 ? 1 : 0);
  }
  return counts;
}

/// [tracks] without the movies, or the shows, [filter] leaves out.
List<TrackTags> _filterVideos(
  List<TrackTags> tracks,
  VideoFilter filter, {
  required bool shows,
}) {
  if (filter == VideoFilter.all) return tracks;
  bool started(TrackTags t) => (t.progress ?? 0) > 0;
  bool pending(TrackTags t) => (t.progress ?? 0) < 1;
  if (!shows) {
    return [
      for (final t in tracks)
        if (filter == VideoFilter.watching
            ? started(t) && pending(t)
            : pending(t))
          t,
    ];
  }
  final byShow = <String?, List<TrackTags>>{};
  for (final t in tracks) {
    (byShow[t.artist] ??= []).add(t);
  }
  bool keep(List<TrackTags> episodes) => filter == VideoFilter.watching
      ? episodes.any(started) && episodes.any(pending)
      : episodes.any(pending);
  return [
    for (final t in tracks)
      if (keep(byShow[t.artist]!)) t,
  ];
}

/// How thick the lines of the dividers between panels are.
const double _dividerLine = 2;

/// The columns of the track lists: a podcast's episodes show [podcast], the
/// tracks of music [music]. [album] is the podcast of an episode.
enum LibraryColumn {
  number,
  album,
  title,
  published,
  length,
  progress,
  artist,
  genre,
  showName,
  season,
  episode,
  year,
  aired,
  added,
  lastWatched;

  /// The columns of the episodes of a podcast, in their usual order.
  static const podcast = [number, album, title, published, length, progress];

  /// The columns of music, in their usual order.
  static const music = [artist, album, number, title, length, genre];

  /// The columns of movies.
  static const movies = [title, year, length, progress, added, genre];

  /// The columns of the episodes of TV shows.
  static const shows = [
    showName,
    season,
    episode,
    title,
    aired,
    length,
    progress,
  ];

  /// The columns of the parts of audiobooks: the book first, so that the
  /// parts of a book are listed together.
  static const book = [album, number, title, length, progress];

  /// How wide the column is; the title takes what the others leave.
  double? get width => switch (this) {
    number => _numberWidth,
    album => _podcastWidth,
    title => null,
    published => _publishedWidth,
    length => _lengthWidth,
    progress => _progressWidth,
    artist => _podcastWidth,
    genre => _genreWidth,
    showName => _podcastWidth,
    season => _numberWidth + 20,
    episode => _numberWidth + 20,
    year => _numberWidth + 12,
    aired => _publishedWidth,
    added => _publishedWidth,
    lastWatched => _publishedWidth,
  };

  /// [tracks] grouped by book (by title) and in the order of the parts of
  /// each.
  static List<TrackTags> sortedByBook(List<TrackTags> tracks) =>
      [...tracks]..sort((a, b) {
        final book = (a.album ?? "").toLowerCase().compareTo(
          (b.album ?? "").toLowerCase(),
        );
        return book != 0
            ? book
            : (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });

  /// [tracks] ordered by this column; ties and missing values keep the
  /// order of the podcast's episodes, and missing values go last.
  static List<TrackTags> sorted(
    List<TrackTags> tracks,
    LibraryColumn column,
    bool ascending,
  ) {
    int compare(TrackTags a, TrackTags b) {
      Comparable<Object>? key(TrackTags t) => switch (column) {
        number => t.trackNumber,
        album => (t.album ?? "").toLowerCase(),
        title => (t.title ?? "").toLowerCase(),
        published => t.published,
        length => t.duration,
        progress => t.progress,
        artist => (t.artist ?? "").toLowerCase(),
        genre => t.genres.isEmpty ? null : t.genres.first.toLowerCase(),
        showName => (t.artist ?? "").toLowerCase(),
        season => t.discNumber,
        episode => t.trackNumber,
        year => t.year,
        aired => t.published,
        added => t.added,
        lastWatched => t.lastWatched,
      };
      final x = key(a);
      final y = key(b);
      if (x == null && y == null) return 0;
      // Missing values go last whichever way the list is sorted.
      if (x == null) return ascending ? 1 : -1;
      if (y == null) return ascending ? -1 : 1;
      return x.compareTo(y);
    }

    final result = [...tracks]
      ..sort(ascending ? compare : (a, b) => compare(b, a));
    return result;
  }
}

/// How many episodes each podcast of [tracks] has, and how many of them are
/// not played (not heard as far as [completion] says).
Map<String, ({int total, int unplayed})> _episodeCounts(
  Iterable<TrackTags> tracks,
  PodcastCompletion completion,
) {
  final counts = <String, ({int total, int unplayed})>{};
  for (final track in tracks) {
    final album = track.album;
    if (album == null) continue;
    final was = counts[album] ?? (total: 0, unplayed: 0);
    counts[album] = (
      total: was.total + 1,
      unplayed:
          was.unplayed +
          (completion.isCompletedAt(track.progress ?? 0, track.duration)
              ? 0
              : 1),
    );
  }
  return counts;
}

/// The podcast view: the podcasts on the left, when there is more than one,
/// and the sortable list of their episodes.
class _PodcastBrowser extends StatelessWidget {
  const _PodcastBrowser({
    required this.skin,
    required this.colors,
    required this.localizations,
    required this.panels,
    required this.cover,
    required this.splitFraction,
    required this.onSplitMoved,
    required this.splitWeights,
    required this.onSplitWeights,
    required this.onGroupMenu,
    required this.audiobooks,
    required this.podcasts,
    required this.counts,
    required this.picked,
    required this.onAll,
    required this.onPodcast,
    required this.tracks,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onContextMenu,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columns,
    required this.onMoveColumn,
    required this.widths,
    required this.onResizeColumn,
    required this.onResetColumn,
    required this.coverCollapsed,
    required this.onToggleCover,
    required this.detailsExtra,
    required this.onGrowDetails,
    required this.tableKey,
    required this.focus,
    required this.onFocus,
    required this.scrollOf,
    required this.keyOf,
    required this.onListRows,
    required this.onOpenArtwork,
    required this.onPlayAt,
    required this.coverProvider,
    required this.scanning,
    required this.empty,
  });

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final AppLocalizations localizations;

  /// The panels of the split layout of audiobooks, above the parts, and the
  /// share of the height they have; null for the list of podcasts or books
  /// beside the episodes.
  final List<_PanelSpec>? panels;

  /// A grid of covers above the episodes, in place of the list of podcasts.
  final Widget? cover;
  final double splitFraction;
  final ValueChanged<double> onSplitMoved;
  final List<double>? splitWeights;
  final void Function(
    int divider,
    double moved,
    double width,
    List<double> leasts,
  )
  onSplitWeights;

  /// Right-click on a podcast or book in the list (null: on "All"): the menu
  /// for all of its tracks.
  final void Function(String? podcast) onGroupMenu;

  /// Whether these are audiobooks: books and their parts rather than
  /// podcasts and their episodes.
  final bool audiobooks;
  final List<String> podcasts;

  /// How many episodes each podcast has, and how many of them are not
  /// played, by podcast.
  final Map<String, ({int total, int unplayed})> counts;
  final Set<String> picked;
  final VoidCallback onAll;
  final ValueChanged<String> onPodcast;
  final List<TrackTags> tracks;
  final Set<String> selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onContextMenu;
  final LibraryColumn? sortColumn;
  final bool sortAscending;
  final ValueChanged<LibraryColumn> onSort;

  /// The columns in order, and called with a column dropped on another.
  final List<LibraryColumn> columns;
  final void Function(LibraryColumn moved, LibraryColumn target) onMoveColumn;

  /// The widths columns were dragged to, and called as one is dragged or
  /// reset to its usual width.
  final Map<LibraryColumn, double> widths;
  final void Function(LibraryColumn column, double width) onResizeColumn;
  final ValueChanged<LibraryColumn> onResetColumn;
  final bool coverCollapsed;
  final VoidCallback onToggleCover;
  final double detailsExtra;
  final void Function(double more, double most) onGrowDetails;

  /// The panel the arrow keys act on, called when one is pressed, how each
  /// scrolls, and told the rows of the list of podcasts or books.
  final String focus;
  final ValueChanged<String> onFocus;
  final ScrollController Function(String panel) scrollOf;
  final Key Function(String panel) keyOf;
  final ValueChanged<List<_BrowserRow>> onListRows;

  /// The key of the table of episodes.
  final Key tableKey;

  /// Opens the cover in a window of its own.
  final void Function(String title, ImageProvider image)? onOpenArtwork;
  final void Function(String path, Duration at)? onPlayAt;

  final ImageProvider Function(String url) coverProvider;
  final bool scanning;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    // The episodes of several podcasts say which one each is from.
    final showPodcast = podcasts.length > 1 && picked.length != 1;
    final shown = [
      for (final column in columns)
        if ((column != LibraryColumn.album || showPodcast) &&
            // A book has no date to show.
            !(audiobooks && column == LibraryColumn.published))
          column,
    ];
    final Widget tracksTable = empty
        ? Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              scanning ? localizations.mlTrackCount(0) : localizations.mlEmpty,
            ),
          )
        : _TrackTable(
            key: tableKey,
            music: false,
            audiobooks: audiobooks,
            skin: skin,
            colors: colors,
            localizations: localizations,
            tracks: tracks,
            selected: selected,
            onSelect: onSelect,
            onPlay: onPlay,
            onContextMenu: onContextMenu,
            sortColumn: sortColumn,
            sortAscending: sortAscending,
            onSort: onSort,
            columns: shown,
            widths: widths,
            onMoveColumn: onMoveColumn,
            onResizeColumn: onResizeColumn,
            onResetColumn: onResetColumn,
          );
    final Widget episodes = _PaneFocus(
      id: "tracks",
      focus: focus,
      onFocus: onFocus,
      colors: colors,
      child: tracksTable,
    );
    // What the details show: the episode selected, else the podcast picked
    // (or the only one).
    final episode = selected.isEmpty
        ? null
        : tracks.where((t) => t.path == selected.last).firstOrNull;
    final podcast = picked.length == 1
        ? picked.single
        : (podcasts.length == 1 ? podcasts.single : null);
    final details = episode != null
        ? _episodeDetails(episode)
        : (podcast == null ? null : _podcastDetails(podcast));
    ({String strong, String rest}) count(({int total, int unplayed}) c) =>
        (strong: "${c.unplayed}", rest: " (${c.total})");
    final rows = <_BrowserRow>[
      _BrowserRow(
        audiobooks
            ? localizations.mlAllAudiobooks
            : localizations.mlAllPodcasts,
        0,
        picked.isEmpty,
        onAll,
        onSecondaryTap: () {
          if (picked.isNotEmpty) onAll();
          onGroupMenu(null);
        },
        bold: true,
        // A book is not counted in its parts.
        trailing: audiobooks
            ? null
            : count((
                total: counts.values.fold(0, (sum, c) => sum + c.total),
                unplayed: counts.values.fold(0, (sum, c) => sum + c.unplayed),
              )),
      ),
      for (final title in podcasts)
        _BrowserRow(
          title,
          0,
          picked.contains(title),
          () => onPodcast(title),
          onSecondaryTap: () {
            if (!picked.contains(title)) onPodcast(title);
            onGroupMenu(title);
          },
          trailing: audiobooks || counts[title] == null
              ? null
              : count(counts[title]!),
        ),
    ];
    onListRows(rows);
    // One podcast has nothing to pick between.
    final panels = this.panels;
    final cover = this.cover;
    final Widget main = cover != null
        ? _SplitPanels(
            skin: skin,
            colors: colors,
            panels: const [],
            cover: cover,
            focus: focus,
            onFocus: onFocus,
            scrollOf: scrollOf,
            keyOf: keyOf,
            weights: null,
            onWeights: (a, b, c, d) {},
            fraction: splitFraction,
            onMoved: onSplitMoved,
            bottom: episodes,
          )
        : panels != null
        ? LayoutBuilder(
            builder: (context, pane) => _SplitPanels(
              skin: skin,
              colors: colors,
              panels: panels,
              focus: focus,
              onFocus: onFocus,
              scrollOf: scrollOf,
              keyOf: keyOf,
              weights: splitWeights,
              onWeights: onSplitWeights,
              fraction: splitFraction,
              onMoved: onSplitMoved,
              bottom: episodes,
            ),
          )
        : podcasts.length < 2
        ? episodes
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 160,
                child: _PaneFocus(
                  key: keyOf("list"),
                  id: "list",
                  focus: focus,
                  onFocus: onFocus,
                  colors: colors,
                  child: _SkinList(
                    skin: skin,
                    colors: colors,
                    controller: scrollOf("list"),
                    itemCount: rows.length,
                    itemBuilder: (context, i) =>
                        _BrowserItem(row: rows[i], colors: colors),
                  ),
                ),
              ),
              _PaneDivider(color: colors.normal.withAlpha(90), onDrag: (_) {}),
              Expanded(child: episodes),
            ],
          );
    if (details == null) return main;
    return LayoutBuilder(
      builder: (context, pane) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: main),
          // Across both columns, under the podcasts and the episodes.
          _DetailsPanel(
            key: ValueKey(details.cover?.key),
            details: details,
            colors: colors,
            label: localizations.mlDetails,
            maxHeight: pane.maxHeight / 2,
            totalMax: max(0, pane.maxHeight * 0.6 - 21),
            collapsed: coverCollapsed,
            onToggle: onToggleCover,
            extra: detailsExtra,
            onGrow: onGrowDetails,
            onOpenArtwork: onOpenArtwork == null
                ? null
                : (image) => onOpenArtwork!(details.title, image),
            onSeek: switch ((details.path, onPlayAt)) {
              (final path?, final play?) => (at) => play(path, at),
              _ => null,
            },
          ),
        ],
      ),
    );
  }

  /// What to say of [track], an episode.
  _Details _episodeDetails(TrackTags track) => _Details(
    title: track.title ?? _TrackItem.label(track),
    meta: [
      ?track.album,
      if (track.published != null) _TrackItem.date(track.published),
      if (track.duration != null) _TrackItem.time(track.duration),
    ].join("  ·  "),
    text: track.description,
    path: track.path,
    length: track.duration,
    cover: _urlCover(track.imageUrl ?? _podcastCover(track.album)),
  );

  /// What to say of the podcast [name].
  _Details _podcastDetails(String name) {
    final episodes = tracks.where((t) => t.album == name).toList();
    final first = episodes.firstOrNull;
    final count = counts[name];
    return _Details(
      title: name,
      meta: [
        if (first?.artist case final author? when author != name) author,
        if (count != null && !audiobooks) "${count.unplayed} (${count.total})",
      ].join("  ·  "),
      text: first?.showDescription,
      cover: _urlCover(_podcastCover(name)),
    );
  }

  _Cover? _urlCover(String? url) =>
      url == null ? null : _Cover(url, () async => coverProvider(url));

  /// The picture of the podcast [name]: the one most of its episodes have.
  String? _podcastCover(String? name) {
    final counts = <String, int>{};
    for (final track in tracks) {
      if (track.album != name) continue;
      if (track.imageUrl case final url?) {
        counts[url] = (counts[url] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// What the details panel says of an episode or a podcast.
class _Details {
  const _Details({
    required this.title,
    required this.meta,
    required this.text,
    required this.cover,
    this.path,
    this.length,
  });

  /// The episode this is about, and how long it is (null for a podcast).
  final String? path;
  final Duration? length;

  final String title;

  /// One line under the title: the podcast, date and length of an episode,
  /// or the author and episode counts of a podcast.
  final String meta;

  /// What it is about, as plain text.
  final String? text;

  /// Its picture, if it has one.
  final _Cover? cover;
}

/// A picture to show: [key] names it (a different key is a different
/// picture), [load] fetches it, null when it can't be.
class _Cover {
  const _Cover(this.key, this.load);

  final String key;
  final Future<ImageProvider?> Function() load;
}

/// The panel under the podcasts and episodes: the picture on the left at
/// [_coverWidth] wide in its own shape (up to half the pane), what is known
/// of the episode or podcast on the right, and a heading that folds it away.
/// Without a picture, or when it can't be loaded, only the text shows.
class _DetailsPanel extends StatefulWidget {
  const _DetailsPanel({
    required this.details,
    required this.colors,
    required this.label,
    required this.maxHeight,
    required this.totalMax,
    required this.collapsed,
    required this.onToggle,
    required this.extra,
    required this.onGrow,
    required this.onOpenArtwork,
    required this.onSeek,
    super.key,
  });

  final _Details details;

  /// Called with a time in the text that was clicked.
  final ValueChanged<Duration>? onSeek;
  final PlEditConfig colors;
  final String label;

  /// The tallest the picture may be, and the tallest the whole body of the
  /// panel (picture and what was dragged on top) may be, so that the lists
  /// above it keep room.
  final double maxHeight;
  final double totalMax;
  final bool collapsed;
  final VoidCallback onToggle;

  /// How much taller than usual the panel was dragged, and called as its
  /// top edge is dragged with how much taller (shorter, negative) to make it
  /// and the most it can be.
  final double extra;
  final void Function(double more, double most) onGrow;

  /// Called with the picture when it is clicked, to open it in a window.
  final void Function(ImageProvider image)? onOpenArtwork;

  /// How long the panel takes to slide away or back.
  static const slide = Duration(milliseconds: 200);

  /// How wide the picture is, and how tall the panel is at least.
  static const double coverWidth = 160;
  static const double minHeight = 96;

  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  bool _failed = false;

  /// The picture, once it has been loaded.
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final key = widget.details.cover?.key;
    try {
      final image = await widget.details.cover?.load();
      if (mounted && key == widget.details.cover?.key) {
        setState(() => _image = image);
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not load the picture",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "LibraryView",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final details = widget.details;
    final image = _image;
    final cover = image != null && !_failed;
    TextStyle style({bool bold = false}) => TextStyle(
      color: colors.normal,
      fontSize: 11,
      fontWeight: bold ? FontWeight.bold : null,
    );
    // The most it can grow: it and the lists above share the pane.
    final most = max(0.0, widget.totalMax - _DetailsPanel.minHeight);
    final extra = widget.extra.clamp(0.0, most);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The top edge: dragged up the panel is taller, back down it is
        // never shorter than it usually is.
        if (!widget.collapsed)
          _HorizontalDivider(
            color: colors.normal.withAlpha(90),
            onDrag: (dy) => widget.onGrow(-dy, most),
          ),
        _Tap(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: widget.collapsed
                  ? Border(top: BorderSide(color: colors.normal.withAlpha(90)))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: Text(
                "${widget.collapsed ? "▸" : "▾"} ${widget.label}",
                maxLines: 1,
                softWrap: false,
                style: style(),
              ),
            ),
          ),
        ),
        // Slides down out of view and back up, rising from the bottom of the
        // pane; kept laid out while folded, so the picture stays loaded.
        ClipRect(
          child: AnimatedAlign(
            duration: _DetailsPanel.slide,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            heightFactor: widget.collapsed ? 0 : 1,
            // [extra] taller than the picture makes it; the text fills the
            // extra, and the picture stays where it is, at the top left.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.totalMax),
              child: Padding(
                padding: EdgeInsets.only(bottom: extra),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // As tall as the picture (at least [minHeight]), which
                    // sets the panel's height.
                    Align(
                      alignment: Alignment.topLeft,
                      heightFactor: 1,
                      child: SizedBox(
                        width: cover ? _DetailsPanel.coverWidth : 0,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: min(
                              _DetailsPanel.minHeight,
                              widget.maxHeight,
                            ),
                            maxHeight: widget.maxHeight,
                          ),
                          child: cover
                              ? MouseRegion(
                                  cursor: widget.onOpenArtwork == null
                                      ? MouseCursor.defer
                                      : SystemMouseCursors.click,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    // In a window of its own.
                                    onTap: widget.onOpenArtwork == null
                                        ? null
                                        : () => widget.onOpenArtwork!(image),
                                    child: Image(
                                      image: image,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topCenter,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                                  if (mounted) {
                                                    setState(
                                                      () => _failed = true,
                                                    );
                                                  }
                                                });
                                            return const SizedBox.shrink();
                                          },
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      left: cover ? _DetailsPanel.coverWidth : 0,
                      right: 0,
                      top: 0,
                      bottom: -extra,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(details.title, style: style(bold: true)),
                            if (details.meta.isNotEmpty)
                              Text(details.meta, style: style()),
                            if (details.text case final text?) ...[
                              const SizedBox(height: 6),
                              DescriptionText(
                                text: text,
                                style: style(),
                                linkColor: _linkColor(colors),
                                selectionColor: colors.selectedBg.withAlpha(
                                  160,
                                ),
                                length: details.length,
                                onSeek: widget.onSeek,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How wide [column] is: as the user dragged it, else its usual width; null
/// for the title when it was never dragged, which takes what the others
/// leave.
double? _widthOf(Map<LibraryColumn, double> widths, LibraryColumn column) =>
    widths[column] ?? column.width;

/// The least width of the episode list: the title gets [_titleMinWidth]
/// beside the other columns unless it was dragged to a width; narrower, the
/// list scrolls sideways.
double _episodesMinWidth(
  List<LibraryColumn> columns,
  Map<LibraryColumn, double> widths,
) =>
    columns.fold(
      0.0,
      (sum, c) => sum + (_widthOf(widths, c) ?? _titleMinWidth),
    ) +
    6;

/// How narrow a column can be dragged.
const double _columnMinWidth = 24;

/// The space either side of a cell's text, which sets the columns a little
/// apart.
const double _cellGap = 3;

/// The height of the headings row.
const double _headerHeight = 16;

const double _titleMinWidth = 160;

/// The episodes: the headings and rows scroll sideways together when the
/// window is narrower than the columns, while the vertical scrollbar stays
/// at the right edge, and a horizontal one shows below.
class _TrackTable extends StatefulWidget {
  const _TrackTable({
    required this.music,
    super.key,
    required this.skin,
    required this.colors,
    required this.localizations,
    required this.tracks,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onContextMenu,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.columns,
    required this.widths,
    required this.onMoveColumn,
    required this.onResizeColumn,
    required this.onResetColumn,
    this.audiobooks = false,
  });

  /// Whether the columns are those of music rather than of episodes.
  final bool music;

  /// Whether the episodes are the parts of audiobooks.
  final bool audiobooks;
  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final AppLocalizations localizations;
  final List<TrackTags> tracks;
  final Set<String> selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onContextMenu;
  final LibraryColumn? sortColumn;
  final bool sortAscending;
  final ValueChanged<LibraryColumn> onSort;
  final List<LibraryColumn> columns;
  final Map<LibraryColumn, double> widths;
  final void Function(LibraryColumn moved, LibraryColumn target) onMoveColumn;
  final void Function(LibraryColumn column, double width) onResizeColumn;
  final ValueChanged<LibraryColumn> onResetColumn;

  @override
  State<_TrackTable> createState() => _TrackTableState();
}

class _TrackTableState extends State<_TrackTable> {
  final ScrollController _sideways = ScrollController();
  ScrollController? _ownRows;

  /// Scrolls the rows; the library reads it (by the table's key) to keep the
  /// track the arrow keys reach in view.
  ScrollController get scroll => _rows;

  ScrollController get _rows => _ownRows ??= ScrollController();

  @override
  void dispose() {
    _sideways.dispose();
    _ownRows?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth = _episodesMinWidth(widget.columns, widget.widths);
      final viewport = constraints.maxWidth - SkinScrollbar.width;
      final scrolls = viewport < minWidth;
      final bar = scrolls ? SkinScrollbar.width : 0.0;
      // Squeezed under its headings and a row there is nothing to show (and
      // no room to lay out).
      if (constraints.maxHeight - bar < _headerHeight + _SkinList.rowHeight) {
        return const SizedBox.shrink();
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false, overscroll: false),
                    child: SingleChildScrollView(
                      controller: _sideways,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrolls ? minWidth : viewport,
                        height: constraints.maxHeight - bar,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _EpisodeHeader(
                              music: widget.music,
                              audiobooks: widget.audiobooks,
                              skin: widget.skin,
                              colors: widget.colors,
                              localizations: widget.localizations,
                              column: widget.sortColumn,
                              ascending: widget.sortAscending,
                              onSort: widget.onSort,
                              columns: widget.columns,
                              widths: widget.widths,
                              onMoveColumn: widget.onMoveColumn,
                              onResizeColumn: widget.onResizeColumn,
                              onResetColumn: widget.onResetColumn,
                            ),
                            Expanded(
                              child: _TrackList(
                                skin: widget.skin,
                                tracks: widget.tracks,
                                colors: widget.colors,
                                selected: widget.selected,
                                onSelect: widget.onSelect,
                                onPlay: widget.onPlay,
                                onContextMenu: widget.onContextMenu,
                                columns: widget.columns,
                                widths: widget.widths,
                                controller: _rows,
                                showScrollbar: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (scrolls)
                  SizedBox(
                    height: SkinScrollbar.width,
                    child: _ListScrollbar(
                      skin: widget.skin,
                      colors: widget.colors,
                      controller: _sideways,
                      axis: Axis.horizontal,
                    ),
                  ),
              ],
            ),
          ),
          // Beside the rows, not the headings, and always in view.
          SizedBox(
            width: SkinScrollbar.width,
            child: Column(
              children: [
                const SizedBox(height: _headerHeight),
                Expanded(
                  child: _ListScrollbar(
                    skin: widget.skin,
                    colors: widget.colors,
                    controller: _rows,
                  ),
                ),
                SizedBox(height: bar),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The widths of the episode list's columns after the title.
const double _numberWidth = 36;
const double _podcastWidth = 120;
const double _publishedWidth = 84;
const double _lengthWidth = 60;
const double _progressWidth = 72;
const double _genreWidth = 90;

/// The headings above the episodes: click one to sort by it, drag one onto
/// another to move it there, drag the edge between two to resize a column
/// (double-click it for the usual width). The sorted one has an
/// arrow.
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({
    required this.music,
    required this.audiobooks,
    required this.skin,
    required this.colors,
    required this.localizations,
    required this.column,
    required this.ascending,
    required this.onSort,
    required this.columns,
    required this.widths,
    required this.onMoveColumn,
    required this.onResizeColumn,
    required this.onResetColumn,
  });

  /// Whether the columns are those of music rather than of episodes.
  final bool music;

  /// Whether the episodes are the parts of audiobooks.
  final bool audiobooks;
  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final AppLocalizations localizations;
  final LibraryColumn? column;
  final bool ascending;
  final ValueChanged<LibraryColumn> onSort;
  final List<LibraryColumn> columns;
  final Map<LibraryColumn, double> widths;
  final void Function(LibraryColumn moved, LibraryColumn target) onMoveColumn;
  final void Function(LibraryColumn column, double width) onResizeColumn;
  final ValueChanged<LibraryColumn> onResetColumn;

  String _label(LibraryColumn column) => switch (column) {
    LibraryColumn.number => localizations.mlColumnNumber,
    LibraryColumn.album =>
      music
          ? localizations.mlColumnAlbum
          : audiobooks
          ? localizations.mlColumnBook
          : localizations.mlColumnPodcast,
    LibraryColumn.title =>
      music || audiobooks
          ? localizations.mlColumnTitle
          : localizations.mlColumnEpisode,
    LibraryColumn.published => localizations.mlColumnPublished,
    LibraryColumn.length => localizations.mlColumnLength,
    LibraryColumn.progress => localizations.mlColumnProgress,
    LibraryColumn.artist => localizations.mlColumnArtist,
    LibraryColumn.genre => localizations.mlColumnGenre,
    LibraryColumn.showName => localizations.mlColumnShow,
    LibraryColumn.season => localizations.mlColumnSeason,
    LibraryColumn.episode => localizations.mlColumnEpisode,
    LibraryColumn.year => localizations.mlColumnYear,
    LibraryColumn.aired => localizations.mlColumnAired,
    LibraryColumn.added => localizations.mlColumnAdded,
    LibraryColumn.lastWatched => localizations.mlColumnLastWatched,
  };

  @override
  Widget build(BuildContext context) {
    // The title takes what the other columns leave, so a column after it is
    // resized from its left edge (the one that moves), the others from their
    // right.
    final flex = columns.indexWhere((c) => _widthOf(widths, c) == null);
    Widget cell(LibraryColumn own) {
      final label = _label(own);
      final fromLeft = flex >= 0 && columns.indexOf(own) > flex;
      Widget text(String shown, {Color? background}) => ColoredBox(
        color: background ?? const Color(0x00000000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _cellGap),
          child: Text(
            shown,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.normal,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );
      final width = _widthOf(widths, own);
      final cell = Builder(
        builder: (cellContext) => Stack(
          children: [
            Positioned.fill(
              child: DragTarget<LibraryColumn>(
                onWillAcceptWithDetails: (details) => details.data != own,
                onAcceptWithDetails: (details) =>
                    onMoveColumn(details.data, own),
                builder: (context, candidates, _) => Draggable<LibraryColumn>(
                  data: own,
                  maxSimultaneousDrags: 1,
                  feedback: SizedBox(
                    width: width ?? _titleMinWidth,
                    child: text(label, background: colors.selectedBg),
                  ),
                  // Dragging a heading moves its column: the skin's move
                  // cursor says so.
                  child: MouseRegion(
                    cursor:
                        skin?.cursor(SkinCursor.plTitleBar) ??
                        SystemMouseCursors.grab,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSort(own),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: candidates.isEmpty
                              ? null
                              : Border(left: BorderSide(color: colors.current)),
                        ),
                        child: text(
                          column == own
                              ? "$label ${ascending ? "▲" : "▼"}"
                              : label,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: fromLeft ? 0 : null,
              right: fromLeft ? null : 0,
              top: 0,
              bottom: 0,
              width: _ColumnResizeHandle.width,
              child: _ColumnResizeHandle(
                fromLeft: fromLeft,
                color: colors.normal.withAlpha(90),
                cursor:
                    skin?.cursor(SkinCursor.plWsSize) ??
                    SystemMouseCursors.resizeColumn,
                currentWidth: () => (cellContext.size ?? Size.zero).width,
                onResize: (width) => onResizeColumn(own, width),
                onReset: () => onResetColumn(own),
              ),
            ),
          ],
        ),
      );
      return width == null
          ? Expanded(child: cell)
          : SizedBox(width: width, child: cell);
    }

    return SizedBox(
      height: _headerHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.normal.withAlpha(90)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Row(children: [for (final column in columns) cell(column)]),
        ),
      ),
    );
  }
}

/// The edge of a heading that is dragged to resize its column: [onResize] is
/// told the width the column should have as the pointer moves from where it
/// was pressed.
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.fromLeft,
    required this.color,
    required this.cursor,
    required this.currentWidth,
    required this.onResize,
    required this.onReset,
  });

  /// The width of the grip, a wider target than its line.
  static const double width = 5;

  /// Whether the grip is on the column's left edge: dragging it left makes
  /// the column wider.
  final bool fromLeft;
  final Color color;
  final MouseCursor cursor;
  final double Function() currentWidth;
  final ValueChanged<double> onResize;
  final VoidCallback onReset;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  double _start = 0;
  double _moved = 0;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _start = widget.currentWidth();
        _moved = 0;
      },
      // Moves while a button is down; hovering is a different event.
      onPointerMove: (event) {
        _moved += widget.fromLeft ? -event.delta.dx : event.delta.dx;
        widget.onResize(_start + _moved);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        child: Align(
          alignment: widget.fromLeft
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: SizedBox(
            width: 1,
            child: ColoredBox(color: widget.color),
          ),
        ),
      ),
    ),
  );
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.skin,
    required this.tracks,
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onContextMenu,
    this.playlistId,
    this.onMove,
    this.columns,
    this.widths = const {},
    this.controller,
    this.showScrollbar = true,
  });

  /// The columns of podcast episodes, in order; null for the plain rows of
  /// a track list.
  final List<LibraryColumn>? columns;

  /// The widths columns were dragged to.
  final Map<LibraryColumn, double> widths;

  /// Scrolls the rows, and whether their scrollbar is drawn beside them.
  final ScrollController? controller;
  final bool showScrollbar;

  final ClassicSkinData? skin;
  final List<TrackTags> tracks;
  final PlEditConfig colors;
  final Set<String> selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onContextMenu;

  /// The saved playlist these are the entries of, if they are.
  final int? playlistId;

  /// Entries (by index) dropped before the entry at the second index.
  final void Function(List<int> indices, int to)? onMove;

  /// What dragging the track at [i] takes along: the whole selection when
  /// it is part of it.
  _TrackDrag _dragOf(int i) {
    final path = tracks[i].path;
    final indices = selected.contains(path)
        ? [
            for (final (j, track) in tracks.indexed)
              if (selected.contains(track.path)) j,
          ]
        : [i];
    return _TrackDrag(
      [for (final j in indices) tracks[j].path],
      playlistId: playlistId,
      indices: indices,
    );
  }

  @override
  Widget build(BuildContext context) => _SkinList(
    skin: skin,
    colors: colors,
    controller: controller,
    showScrollbar: showScrollbar,
    itemCount: tracks.length,
    itemBuilder: (context, i) {
      final track = tracks[i];
      return _TrackItem(
        track: track,
        colors: colors,
        columns: columns,
        widths: widths,
        selected: selected.contains(track.path),
        onSelect: () => onSelect(track.path),
        onPlay: () => onPlay(track.path),
        onContextMenu: () => onContextMenu(track.path),
        drag: () => _dragOf(i),
        onDropped: playlistId == null || onMove == null
            ? null
            : (drag) {
                if (drag.playlistId != playlistId) return;
                // Dragged down it lands after the row it is dropped on.
                final down = drag.indices.first < i;
                onMove!(drag.indices, down ? i + 1 : i);
              },
      );
    },
  );
}

class _TrackItem extends StatelessWidget {
  const _TrackItem({
    required this.track,
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onPlay,
    required this.onContextMenu,
    required this.drag,
    this.onDropped,
    this.columns,
    this.widths = const {},
  });

  /// Shows the columns of a podcast episode, in order; null for a track's
  /// plain row.
  final List<LibraryColumn>? columns;
  final Map<LibraryColumn, double> widths;

  final TrackTags track;
  final PlEditConfig colors;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final VoidCallback onContextMenu;

  /// What dragging the row takes along.
  final _TrackDrag Function() drag;

  /// Entries of the same playlist dropped on the row, if it takes them.
  final void Function(_TrackDrag drag)? onDropped;

  /// "Artist - Title", or the file name without its extension when the
  /// file has no title.
  static String label(TrackTags track) {
    final title = track.title;
    if (title == null || title.trim().isEmpty) {
      final name = track.path.split(RegExp(r"[\\/]")).last;
      final dot = name.lastIndexOf(".");
      return dot > 0 ? name.substring(0, dot) : name;
    }
    final artist = track.artist;
    return artist == null || artist.isEmpty ? title : "$artist - $title";
  }

  /// `2023-01-03`, or nothing without a date.
  static String date(DateTime? date) {
    if (date == null) return "";
    final local = date.toLocal();
    return "${local.year.toString().padLeft(4, "0")}-"
        "${local.month.toString().padLeft(2, "0")}-"
        "${local.day.toString().padLeft(2, "0")}";
  }

  /// `m:ss`, or `h:mm:ss` from an hour on.
  static String time(Duration? duration) {
    if (duration == null) return "";
    String two(int n) => n.toString().padLeft(2, "0");
    final seconds = two(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:${two(duration.inMinutes.remainder(60))}:$seconds";
    }
    return "${duration.inMinutes}:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final shown = selected ? colors.current : colors.normal;
    final color = OfflineFolders.contains(context, track.path)
        ? shown.withAlpha(110)
        : shown;
    final order = columns;
    Widget cell(LibraryColumn column) {
      final style = TextStyle(color: color, fontSize: 11);
      final Widget content = switch (column) {
        LibraryColumn.number => Text(
          "${track.trackNumber ?? ""}",
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
        LibraryColumn.album => Text(
          track.album ?? "",
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        LibraryColumn.artist => Text(
          track.artist ?? "",
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        LibraryColumn.genre => Text(
          track.genres.join(", "),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        LibraryColumn.showName => Text(
          track.artist ?? "",
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        LibraryColumn.season => Text(
          "${track.discNumber ?? ""}",
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
        LibraryColumn.episode => Text(
          "${track.trackNumber ?? ""}",
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
        LibraryColumn.year => Text(
          "${track.year ?? ""}",
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
        LibraryColumn.aired => Text(
          date(track.published),
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
        LibraryColumn.added => Text(
          date(track.added),
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
        LibraryColumn.lastWatched => Text(
          date(track.lastWatched),
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
        LibraryColumn.title => Text(
          track.title ?? label(track),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        LibraryColumn.published => Text(
          date(track.published),
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
        LibraryColumn.length => Text(
          time(track.duration),
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: style,
        ),
        LibraryColumn.progress => _ProgressBar(
          progress: track.progress,
          colors: colors,
          color: color,
        ),
      };
      final padded = Padding(
        padding: const EdgeInsets.symmetric(horizontal: _cellGap),
        child: content,
      );
      final width = _widthOf(widths, column);
      return width == null
          ? Expanded(child: padded)
          : SizedBox(width: width, child: padded);
    }

    final row = order != null
        ? Row(children: [for (final column in order) cell(column)])
        : Row(
            children: [
              Expanded(
                child: Text(
                  label(track),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11),
                ),
              ),
              Text(
                time(track.duration),
                style: TextStyle(color: color, fontSize: 11),
              ),
            ],
          );
    return DragTarget<_TrackDrag>(
      onWillAcceptWithDetails: (details) => onDropped != null,
      onAcceptWithDetails: (details) => onDropped?.call(details.data),
      builder: (context, candidates, _) => Draggable<_TrackDrag>(
        data: drag(),
        maxSimultaneousDrags: 1,
        feedback: DefaultTextStyle.merge(
          style: TextStyle(color: colors.current, fontSize: 11),
          child: ColoredBox(
            color: colors.selectedBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                label(track),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: colors.current,
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
        child: _Tap(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onDoubleTap: onPlay,
          onSecondaryTap: onContextMenu,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.selectedBg : colors.normalBg,
              border: candidates.isEmpty
                  ? null
                  : Border(top: BorderSide(color: colors.current)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

/// How much of an episode was played: a flat bar, square-cornered, with the
/// percentage over it. Nothing for an episode that was not started.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.colors,
    required this.color,
  });

  final double? progress;
  final PlEditConfig colors;

  /// The text color of the row.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = progress;
    if (fraction == null || fraction <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.normal.withAlpha(90)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0, 1),
                  heightFactor: 1,
                  child: ColoredBox(color: colors.normal.withAlpha(110)),
                ),
              ),
            ),
            Text(
              "${(fraction * 100).round()}%",
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: color, fontSize: 10, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.buttonBuilder,
    required this.colors,
    required this.status,
    required this.playLabel,
    required this.addLabel,
    required this.onAdd,
    required this.enqueueLabel,
    required this.enabled,
    required this.onPlay,
    required this.onEnqueue,
  });

  final Widget Function(String label, bool enabled, VoidCallback onPressed)?
  buttonBuilder;
  final PlEditConfig colors;
  final Widget status;
  final String playLabel;
  final String addLabel;
  final VoidCallback onAdd;
  final String enqueueLabel;
  final bool enabled;
  final VoidCallback onPlay;
  final VoidCallback onEnqueue;

  @override
  Widget build(BuildContext context) {
    // A skin's component holder with `noshowcmdbar="1"` has its own.
    if (WasabiComponentOptions.maybeOf(context)?.noCommandBar ?? false) {
      return const SizedBox.shrink();
    }
    final skinned = buttonBuilder;
    if (skinned != null) {
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            skinned(addLabel, true, onAdd),
            const SizedBox(width: 6),
            Expanded(child: status),
            skinned(enqueueLabel, enabled, onEnqueue),
            const SizedBox(width: 3),
            skinned(playLabel, enabled, onPlay),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      // The same strip as under the visualization and the video.
      child: StripFrame(
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              StripButton(label: addLabel, onPressed: onAdd),
              const SizedBox(width: 2),
              Expanded(child: status),
              StripButton(
                label: enqueueLabel,
                enabled: enabled,
                onPressed: onEnqueue,
              ),
              StripButton(
                label: playLabel,
                enabled: enabled,
                onPressed: onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Scanning. 12 files" with dots that count up to three and start over.
/// The dots not shown yet are still laid out (invisibly), so the text keeps
/// the same width.
@visibleForTesting
class ScanningText extends StatefulWidget {
  const ScanningText({
    required this.localizations,
    required this.count,
    super.key,
  });

  final AppLocalizations localizations;
  final int count;

  @override
  State<ScanningText> createState() => _ScanningTextState();
}

class _ScanningTextState extends State<ScanningText> {
  static const _marker = "\u0000";
  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      setState(() => _dots = _dots % 3 + 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The translation places the dots; split it where the marker landed.
    final text = widget.localizations.mlScanning(widget.count, _marker);
    final at = text.indexOf(_marker);
    final before = at < 0 ? text : text.substring(0, at);
    final after = at < 0 ? "" : text.substring(at + 1);
    final color = DefaultTextStyle.of(context).style.color;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before),
          TextSpan(text: "." * _dots),
          TextSpan(
            text: "." * (3 - _dots),
            style: TextStyle(color: color?.withAlpha(0)),
          ),
          TextSpan(text: after),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A list of rows 14 high with the skin's scrollbar, scrolled a row at a
/// time by the wheel.
class _SkinList extends StatefulWidget {
  const _SkinList({
    required this.skin,
    required this.colors,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.showScrollbar = true,
  });

  static const double rowHeight = 14;

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Scrolls the list, when something else (a scrollbar elsewhere) needs to
  /// follow it; the list makes its own otherwise.
  final ScrollController? controller;

  /// Whether the scrollbar is drawn beside the rows.
  final bool showScrollbar;

  @override
  State<_SkinList> createState() => _SkinListState();
}

class _SkinListState extends State<_SkinList> {
  ScrollController? _own;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  void _scrollRows(int rows) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // Land on whole rows.
    final row = (position.pixels / _SkinList.rowHeight).round() + rows;
    _controller.jumpTo(
      (row * _SkinList.rowHeight).clamp(0, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = SkinWheelScroll(
      rowsPerNotch: 1,
      onScroll: _scrollRows,
      // Hide the platform scrollbar; the skinned one replaces it.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(
          context,
        ).copyWith(scrollbars: false, overscroll: false),
        child: ListView.builder(
          controller: _controller,
          // The wheel and the scrollbar do the scrolling.
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.itemCount,
          itemExtent: _SkinList.rowHeight,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
    if (!widget.showScrollbar) return rows;
    // No bar in a list too narrow to hold it (a pane dragged nearly shut).
    // The list stays at one place in the tree either way: two lists on the
    // one controller, even for a frame, is an error.
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: rows),
          if (box.maxWidth > SkinScrollbar.width)
            SizedBox(
              width: SkinScrollbar.width,
              child: _ListScrollbar(
                skin: widget.skin,
                colors: widget.colors,
                controller: _controller,
              ),
            ),
        ],
      ),
    );
  }
}

/// The scrollbar of a list: the skin's own, or one in the list colors for
/// skins that have none.
class _ListScrollbar extends StatelessWidget {
  const _ListScrollbar({
    required this.skin,
    required this.colors,
    required this.controller,
    this.axis = Axis.vertical,
  });

  final ClassicSkinData? skin;
  final PlEditConfig colors;
  final ScrollController controller;
  final Axis axis;

  @override
  Widget build(BuildContext context) => switch (skin) {
    final skin? => SkinScrollbar(
      skin: skin,
      controller: controller,
      axis: axis,
    ),
    null => _ThemedScrollbar(
      colors: colors,
      controller: controller,
      axis: axis,
    ),
  };
}

/// The search text. An [EditableText] needs an [Overlay] for its selection
/// handles, which the embedded window doesn't have, so it gets its own.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.colors,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PlEditConfig colors;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (context) => EditableText(
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: TextStyle(
        color: _legible(widget.colors),
        fontSize: 11,
        fontFamily: widget.colors.fontName.isEmpty
            ? "Arial"
            : widget.colors.fontName,
      ),
      cursorColor: _legible(widget.colors),
      backgroundCursorColor: widget.colors.selectedBg,
      selectionColor: widget.colors.selectedBg,
    ),
  );

  @override
  void didUpdateWidget(_SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.text,
    child: Overlay(initialEntries: [_entry]),
  );
}

/// The bar between the artists and the tracks: drag it sideways to resize
/// the panes.
class _PaneDivider extends StatelessWidget {
  const _PaneDivider({required this.color, required this.onDrag});

  /// The width of the bar, a wider target than its line.
  static const double width = 5;

  final Color color;

  /// Called with how far the pointer moved sideways.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      // Moves while a button is down; hovering is a different event.
      onPointerMove: (event) => onDrag(event.delta.dx),
      child: SizedBox(
        width: width,
        child: Center(
          // A clear line, not a hint of one.
          child: SizedBox(
            width: _dividerLine,
            child: ColoredBox(color: color.withAlpha(215)),
          ),
        ),
      ),
    ),
  );
}

/// A scrollbar in the skin's list colours, for skins that have no scrollbar
/// bitmaps of their own: dragging the thumb scrolls, pressing the track
/// pages.
class _ThemedScrollbar extends StatefulWidget {
  const _ThemedScrollbar({
    required this.colors,
    required this.controller,
    this.axis = Axis.vertical,
  });

  final PlEditConfig colors;
  final ScrollController controller;
  final Axis axis;

  @override
  State<_ThemedScrollbar> createState() => _ThemedScrollbarState();
}

class _ThemedScrollbarState extends State<_ThemedScrollbar> {
  /// Where in the thumb the press was, while dragging.
  double? _grab;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ThemedScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The thumb's top and height in a track of [track] pixels, or null when
  /// everything fits.
  (double, double)? _thumb(double track) {
    final controller = widget.controller;
    if (controller.positions.length != 1) return null;
    final position = controller.position;
    // Not before the list has been laid out once.
    if (!position.hasContentDimensions) return null;
    final max = position.maxScrollExtent;
    if (max <= 0) return null;
    final view = position.viewportDimension;
    final height = (track * view / (view + max))
        .clamp(min(16.0, track), track)
        .toDouble();
    return ((track - height) * position.pixels / max, height);
  }

  void _dragTo(double y, double track) {
    final thumb = _thumb(track);
    if (thumb == null) return;
    final position = widget.controller.position;
    final room = track - thumb.$2;
    if (room <= 0) return;
    final top = (y - (_grab ?? thumb.$2 / 2)).clamp(0.0, room);
    widget.controller.jumpTo(top / room * position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = widget.axis == Axis.horizontal;
      final track = horizontal ? constraints.maxWidth : constraints.maxHeight;
      final thumb = _thumb(track);
      double along(Offset offset) => horizontal ? offset.dx : offset.dy;
      // The list's size changes (a new search, a resize) don't notify the
      // controller: look again once it has been laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _thumb(track) != thumb) setState(() {});
      });
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          final thumb = _thumb(track);
          if (thumb == null) return;
          final y = along(event.localPosition);
          _grab = y >= thumb.$1 && y <= thumb.$1 + thumb.$2
              ? y - thumb.$1
              : null;
          if (_grab == null) _dragTo(y, track);
        },
        onPointerMove: (event) => _dragTo(along(event.localPosition), track),
        onPointerUp: (_) => _grab = null,
        onPointerCancel: (_) => _grab = null,
        child: CustomPaint(
          size: Size.infinite,
          painter: _ThemedScrollbarPainter(
            thumb: thumb,
            track: widget.colors.normalBg,
            color: widget.colors.normal,
            horizontal: horizontal,
          ),
        ),
      );
    },
  );
}

class _ThemedScrollbarPainter extends CustomPainter {
  const _ThemedScrollbarPainter({
    required this.thumb,
    required this.track,
    required this.color,
    required this.horizontal,
  });

  final (double, double)? thumb;
  final Color track;
  final Color color;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.15),
    );
    final thumb = this.thumb;
    if (thumb == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        horizontal
            ? Rect.fromLTWH(thumb.$1 + 1, 1, thumb.$2 - 2, size.height - 2)
            : Rect.fromLTWH(1, thumb.$1 + 1, size.width - 2, thumb.$2 - 2),
        const Radius.circular(2),
      ),
      Paint()..color = color.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_ThemedScrollbarPainter oldDelegate) =>
      horizontal != oldDelegate.horizontal ||
      thumb != oldDelegate.thumb ||
      track != oldDelegate.track ||
      color != oldDelegate.color;
}
