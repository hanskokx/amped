// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Amped';

  @override
  String get playlistEditor => 'Playlist Editor';

  @override
  String get preferences => 'Preferences...';

  @override
  String get menuAmped => 'Amped...';

  @override
  String get play => 'Play';

  @override
  String get file => 'File...';

  @override
  String get url => 'URL...';

  @override
  String get folder => 'Folder...';

  @override
  String get skins => 'Skins';

  @override
  String get options => 'Options';

  @override
  String get playback => 'Playback';

  @override
  String get previous => 'Previous';

  @override
  String get pause => 'Pause';

  @override
  String get stop => 'Stop';

  @override
  String get next => 'Next';

  @override
  String get random => 'Random';

  @override
  String get videoPlay => 'Play';

  @override
  String get videoBack15 => 'Back 15 seconds';

  @override
  String get videoForward15 => 'Forward 15 seconds';

  @override
  String get videoAudio => 'Audio track';

  @override
  String get videoTrackUnsupported => 'Unsupported';

  @override
  String get alwaysOnTopVideoOnly => 'Always on top (Video only)';

  @override
  String get videoSubtitles => 'Subtitles';

  @override
  String get videoSubtitlesOff => 'Off';

  @override
  String videoSubtitleTrack(int number) {
    return 'Track $number';
  }

  @override
  String get videoCast => 'Cast to a device';

  @override
  String get videoCastSearching => 'Looking for devices…';

  @override
  String get videoCastNone => 'No Chromecast found';

  @override
  String get videoCastSearchAgain => 'Search again';

  @override
  String get videoCastStop => 'Stop casting';

  @override
  String videoCastingTo(String device) {
    return 'Casting to $device';
  }

  @override
  String get videoCastUnsupported => 'This kind of video can\'t be cast';

  @override
  String get videoCastFailed => 'Couldn\'t cast to the device';

  @override
  String get videoExitFullscreen => 'Exit fullscreen';

  @override
  String get videoVolume => 'Volume';

  @override
  String get videoPosition => 'Position';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get visualizerTitle => 'Visualizer';

  @override
  String get repeat => 'Repeat';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get exit => 'Exit';

  @override
  String get timeElapsed => 'Time elapsed';

  @override
  String get timeRemaining => 'Time remaining';

  @override
  String get alwaysOnTop => 'Always On Top';

  @override
  String get playbackNotifications => 'Playback Notifications';

  @override
  String get showNotification => 'Show Notification';

  @override
  String get nativeNotifications => 'Use System Notifications';

  @override
  String get doubleSizeMode => 'Doublesize mode';

  @override
  String get mainWindowShade => 'Main Window Shade';

  @override
  String get skinBrowser => 'Skin Browser...';

  @override
  String get colorThemes => 'Color Themes';

  @override
  String get shareColorThemes => 'Share Between Skins';

  @override
  String get skinMenu => 'Skin';

  @override
  String get onlineSkinBrowser => 'Online Skin Browser...';

  @override
  String get skinBrowserSearchHint => 'Search the Webamp skin library';

  @override
  String get skinBrowserInstall => 'Download and install';

  @override
  String get skinBrowserPrevious => 'Previous skin';

  @override
  String get skinBrowserNext => 'Next skin';

  @override
  String get skinBrowserInstalled => 'Installed';

  @override
  String get skinBrowserNoResults => 'No skins found.';

  @override
  String skinBrowserError(String error) {
    return 'Couldn\'t reach the skin library: $error';
  }

  @override
  String get skinBrowserNoPreview => 'No preview available';

  @override
  String get skinBrowserRetry => 'Retry';

  @override
  String get skinBrowserCredit =>
      'Skins from skins.webamp.org, the classic player Skin Museum.';

  @override
  String get windows => 'Windows';

  @override
  String get skinLayouts => 'Layouts';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get video => 'Video';

  @override
  String get library => 'Library';

  @override
  String get visualization => 'Visualization';

  @override
  String get settings => 'Settings';

  @override
  String get windowShade => 'Window Shade';

  @override
  String get quit => 'Quit';

  @override
  String get load => 'Load';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get preset => 'Preset...';

  @override
  String get autoLoadPreset => 'Auto-load preset...';

  @override
  String get fromEqf => 'From EQF...';

  @override
  String get toEqf => 'To EQF...';

  @override
  String get reset => 'Reset';

  @override
  String get playItems => 'Play item(s)';

  @override
  String get removeItems => 'Remove item(s)';

  @override
  String get cropFiles => 'Crop files';

  @override
  String get editMetadata => 'Edit metadata for selection...';

  @override
  String get viewFileInfo => 'View file info...';

  @override
  String get playlistEntry => 'Playlist entry';

  @override
  String get bookmarkItems => 'Bookmark item(s)';

  @override
  String get rateItems => 'Rate items';

  @override
  String get noRating => 'No rating';

  @override
  String get exploreItemsFolder => 'Explore item(s) folder';

  @override
  String get addFiles => 'Add file(s)';

  @override
  String get addFolder => 'Add folder';

  @override
  String get addUrl => 'Add URL';

  @override
  String get removeSelected => 'Remove selected';

  @override
  String get cropSelected => 'Crop selected';

  @override
  String get clearPlaylist => 'Clear playlist';

  @override
  String get remove => 'Remove...';

  @override
  String get removeAction => 'Remove';

  @override
  String get cancel => 'Cancel';

  @override
  String get tagLookupRetry => 'Retry';

  @override
  String get tagLookupPrivacy =>
      'Looking up a song sends its fingerprint and length to AcoustID and the matching recording\'s ID to MusicBrainz. Nothing else about you or your files is sent.';

  @override
  String get removeMissingFiles => 'Remove missing files from playlist';

  @override
  String get physicallyRemoveFiles => 'Physically remove selected file(s)';

  @override
  String get selectAll => 'Select all';

  @override
  String get selectNone => 'Select none';

  @override
  String get invertSelection => 'Invert selection';

  @override
  String get sort => 'Sort';

  @override
  String get misc => 'Misc';

  @override
  String get sortByTitle => 'Sort list by title';

  @override
  String get sortByFilename => 'Sort list by filename';

  @override
  String get sortByPath => 'Sort list by path and filename';

  @override
  String get sortByArtist => 'Sort list by artist';

  @override
  String get sortByAlbum => 'Sort list by album';

  @override
  String get sortByArtistAlbum => 'Sort list by artist and album';

  @override
  String get reverseList => 'Reverse list';

  @override
  String get randomizeList => 'Randomize list';

  @override
  String get sortingPlaylist => 'Sorting playlist...';

  @override
  String sortingReadingTags(int done, int total) {
    return 'Sorting playlist: reading tags $done/$total';
  }

  @override
  String get fileInfo => 'File info';

  @override
  String get fileInfoEllipsis => 'File info...';

  @override
  String get playlistEntryEllipsis => 'Playlist entry...';

  @override
  String get generateHtmlPlaylist => 'Generate HTML playlist';

  @override
  String get rebuildTitles => 'Rebuild titles on selection';

  @override
  String get openPlaylist => 'Open playlist...';

  @override
  String get savePlaylist => 'Save playlist...';

  @override
  String get newPlaylist => 'New playlist (clear)';

  @override
  String get mlNewPlaylist => 'New playlist';

  @override
  String get mlImportPlaylist => 'Import playlist from file...';

  @override
  String get mlExportPlaylist => 'Export playlist...';

  @override
  String get mlAddMedia => 'Add media to Library...';

  @override
  String get mlAddPlaylist => 'Add current playlist to Library';

  @override
  String get mlAddMediaTitle => 'Add media to Library';

  @override
  String get mediaLibraryPreferences => 'Media Library';

  @override
  String get watchFolders => 'Watch folders';

  @override
  String get watchFoldersHint =>
      'Audio files in these folders are added to the Local source, and removed from it again when they are deleted.';

  @override
  String get watchFoldersEmpty => 'No folders are watched.';

  @override
  String get watchFoldersAddTitle => 'Watch folder';

  @override
  String get watchFoldersAdd => 'Add...';

  @override
  String get watchFoldersRemove => 'Stop watching';

  @override
  String get mlSearch => 'Search';

  @override
  String get mlEnqueue => 'Enqueue';

  @override
  String get mlCancelPrompt => 'Press again to cancel';

  @override
  String get mlRemoveFromLibrary => 'Remove item(s) from Library';

  @override
  String get mlAddMediaButton => 'Add media...';

  @override
  String get mlAllArtists => 'All Artists';

  @override
  String get mlAllAlbums => 'All Albums';

  @override
  String get mlAllPodcasts => 'All Podcasts';

  @override
  String get mlColumnNumber => '#';

  @override
  String newEpisodeTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new episodes',
      one: 'New episode',
    );
    return '$_temp0';
  }

  @override
  String newEpisodeLine(String podcast, String episode) {
    return '$podcast: $episode';
  }

  @override
  String newEpisodeMore(int count) {
    return 'and $count more';
  }

  @override
  String get sourceRefreshTitle => 'Background refresh';

  @override
  String get sourceRefreshEnabled => 'Refresh in the background';

  @override
  String get sourceRefreshHint =>
      'Looks at the source again while Amped runs. New podcast episodes are announced.';

  @override
  String get sourceRefreshEvery => 'Refresh every';

  @override
  String get sourceRefreshFirst => 'First refresh after starting';

  @override
  String get sourceCompletedTitle => 'Count an episode as played';

  @override
  String get sourceCompletedPercent => 'From a percentage played';

  @override
  String get sourceCompletedRemaining => 'When this much is left';

  @override
  String get sourceCompletedHint =>
      'Played episodes are left out of the number of new episodes, and are not offered for resuming.';

  @override
  String percentValue(int percent) {
    return '$percent%';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String get artworkTitle => 'Artwork';

  @override
  String get mlDetails => 'Details';

  @override
  String get mlColumnTitle => 'Title';

  @override
  String get mlColumnArtist => 'Artist';

  @override
  String get mlColumnAlbum => 'Album';

  @override
  String get mlColumnGenre => 'Genre';

  @override
  String get mlSectionAudiobooks => 'Audiobooks';

  @override
  String get mlAllAudiobooks => 'All Audiobooks';

  @override
  String get mlColumnBook => 'Book';

  @override
  String get mlColumnAlbums => 'Albums';

  @override
  String get mlColumnTracks => 'Tracks';

  @override
  String mlAllWithCount(String count) {
    return 'All ($count)';
  }

  @override
  String get mlHideWatched => 'Hide watched';

  @override
  String get mlHideWatchedTip =>
      'Leave out movies and episodes that were watched, and the seasons and shows made of them';

  @override
  String get mlHideListened => 'Hide listened to';

  @override
  String get mlHideListenedTip =>
      'Leave out episodes and parts that were listened to, and the podcasts and books made of them';

  @override
  String get mlCoverSize => 'Cover size';

  @override
  String get mlLayoutCovers => 'Artist and album covers beside the tracks';

  @override
  String get mlLayoutBooksList => 'Books beside the parts';

  @override
  String get mlLayoutBooksSplit =>
      'Author, series and book panels above the parts';

  @override
  String get mlLayoutPodcastsList => 'Podcasts beside the episodes';

  @override
  String get mlLayoutShowsList => 'Shows and seasons beside the episodes';

  @override
  String get mlLayoutShowsSplit => 'Show and season panels above the episodes';

  @override
  String get mlLayoutMovies => 'Movies only';

  @override
  String get mlLayoutMovieCategories =>
      'Category and playlist panels above the movies';

  @override
  String get mlColumnAired => 'Aired';

  @override
  String get mlColumnAdded => 'Added';

  @override
  String get mlColumnLastWatched => 'Last watched';

  @override
  String get mlVideoSortName => 'Name';

  @override
  String get mlVideoSortWatched => 'Recently watched';

  @override
  String get mlVideoSortAired => 'Recently aired';

  @override
  String get mlVideoSortAdded => 'Recently added';

  @override
  String get mlVideoSortTip => 'Order by (click for the next)';

  @override
  String get mlVideoFilterAll => 'All';

  @override
  String get mlVideoFilterWatching => 'Watching';

  @override
  String get mlVideoFilterInProgress => 'In progress';

  @override
  String get mlVideoFilterUnwatched => 'Unwatched';

  @override
  String get mlVideoFilterTip => 'Show (click for the next)';

  @override
  String get mlColumnCategory => 'Category';

  @override
  String get mlColumnPlaylist => 'Playlist';

  @override
  String get mlColumnMovies => 'Movies';

  @override
  String mlCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count categories',
      one: '1 category',
    );
    return '$_temp0';
  }

  @override
  String mlPlaylistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists',
      one: '1 playlist',
    );
    return '$_temp0';
  }

  @override
  String get mlLayoutBookCovers => 'Book covers above the parts';

  @override
  String get mlLayoutPodcastCovers => 'Podcast covers above the episodes';

  @override
  String get mlLayoutMovieCovers =>
      'Category and playlist panels above the movie covers';

  @override
  String get mlLayoutShowCovers => 'Covers of the shows, seasons and episodes';

  @override
  String get mlLayoutEpisodes => 'Episodes only';

  @override
  String get mlLayoutTracks => 'Tracks only';

  @override
  String get mlLayoutBrowser => 'Artists and albums beside the tracks';

  @override
  String get mlLayoutSplit => 'Artist and album panels above the tracks';

  @override
  String get mlColumnAuthor => 'Author';

  @override
  String get mlColumnSeries => 'Series';

  @override
  String get mlColumnBooks => 'Books';

  @override
  String get mlColumnParts => 'Parts';

  @override
  String mlAuthorCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count authors',
      one: '1 author',
    );
    return '$_temp0';
  }

  @override
  String mlSeriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count series',
      one: '1 series',
    );
    return '$_temp0';
  }

  @override
  String mlBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get mlColumnYear => 'Year';

  @override
  String get mlColumnPodcast => 'Podcast';

  @override
  String get mlColumnEpisode => 'Episode';

  @override
  String get mlColumnPublished => 'Published';

  @override
  String get mlColumnLength => 'Length';

  @override
  String get mlColumnProgress => 'Played';

  @override
  String get resumeTitle => 'Resume playback';

  @override
  String resumePrompt(String title, String position) {
    return 'You stopped \"$title\" at $position. Resume from there?';
  }

  @override
  String get resumeContinue => 'Resume';

  @override
  String get resumeStartOver => 'Start over';

  @override
  String get mlSectionPlaylists => 'Playlists';

  @override
  String get mlSectionStatistics => 'Statistics';

  @override
  String get mlStatsMostPlayed => 'Most played';

  @override
  String get mlStatsMostPlayedVideos => 'Most played videos';

  @override
  String get mlStatsMostPlayedPodcasts => 'Most played podcasts';

  @override
  String get mlStatsRecentlyPlayed => 'Recently played';

  @override
  String get mlStatsNothingPlayed => 'Nothing played yet.';

  @override
  String mlStatsPlays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '1 play',
    );
    return '$_temp0';
  }

  @override
  String get mlNewPlaylistRow => 'New playlist...';

  @override
  String get mlNewPlaylistTitle => 'New playlist';

  @override
  String mlPlaylistCopyName(String name) {
    return '$name copy';
  }

  @override
  String get mlMenuDuplicatePlaylist => 'Duplicate';

  @override
  String get mlMenuAddToPlaylist => 'Add to playlist';

  @override
  String get mlMenuNewPlaylist => 'New playlist...';

  @override
  String get mlSavePlaylistRow => 'Save current playlist...';

  @override
  String get mlImportPlaylistRow => 'Import playlist...';

  @override
  String get mlSavePlaylistTitle => 'Save playlist';

  @override
  String get mlPlaylistNamePrompt => 'Name of the playlist:';

  @override
  String get mlPlaylistDefaultName => 'New playlist';

  @override
  String get mlRenamePlaylistTitle => 'Rename playlist';

  @override
  String get mlMenuRenamePlaylist => 'Rename...';

  @override
  String get mlMenuExportPlaylist => 'Export...';

  @override
  String get mlMenuDeletePlaylist => 'Delete playlist';

  @override
  String get mlExportPlaylistTitle => 'Export playlist';

  @override
  String get mlImportPlaylistTitle => 'Import playlists';

  @override
  String get mlSavePlaylistButton => 'Save current playlist';

  @override
  String get mlSourceLocal => 'Local';

  @override
  String get mlSectionLocal => 'Library';

  @override
  String get mlSectionVideos => 'Videos';

  @override
  String mlSourceMovies(String name) {
    return '$name - Movies';
  }

  @override
  String mlSourceShows(String name) {
    return '$name - TV shows';
  }

  @override
  String get mlColumnShow => 'Show';

  @override
  String get mlColumnSeason => 'Season';

  @override
  String get mlColumnSeasons => 'Seasons';

  @override
  String get mlColumnEpisodes => 'Episodes';

  @override
  String mlShowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shows',
      one: '1 show',
    );
    return '$_temp0';
  }

  @override
  String mlSeasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons',
      one: '1 season',
    );
    return '$_temp0';
  }

  @override
  String get mlSourceAllVideos => 'All videos';

  @override
  String get mlSectionRemote => 'Remote';

  @override
  String get mlSectionPodcasts => 'Podcasts';

  @override
  String get mlSectionNoSources => 'None added';

  @override
  String get mlSourceUnavailable => 'This source can\'t be browsed yet.';

  @override
  String get mlEmpty =>
      'The library is empty. Click Add media... to add folders.';

  @override
  String mlScanning(int count, String dots) {
    return 'Scanning$dots $count files';
  }

  @override
  String mlTrackCount(int count) {
    return '$count items';
  }

  @override
  String mlMenuPlay(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Play items',
      one: 'Play item',
    );
    return '$_temp0';
  }

  @override
  String mlMenuEnqueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Enqueue items',
      one: 'Enqueue item',
    );
    return '$_temp0';
  }

  @override
  String mlMenuRemove(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove items from Library',
      one: 'Remove item from Library',
    );
    return '$_temp0';
  }

  @override
  String mlMenuMarkPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mark episodes as played',
      one: 'Mark episode as played',
    );
    return '$_temp0';
  }

  @override
  String mlMenuMarkUnplayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mark episodes as unplayed',
      one: 'Mark episode as unplayed',
    );
    return '$_temp0';
  }

  @override
  String mlMenuMarkBookPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mark books as finished',
      one: 'Mark book as finished',
    );
    return '$_temp0';
  }

  @override
  String mlMenuMarkBookUnplayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mark books as not started',
      one: 'Mark book as not started',
    );
    return '$_temp0';
  }

  @override
  String get mlMenuRefreshBooks => 'Refresh audiobooks';

  @override
  String get mlMenuRefreshPodcast => 'Refresh podcast';

  @override
  String mlMenuBookmark(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bookmark items',
      one: 'Bookmark item',
    );
    return '$_temp0';
  }

  @override
  String mlMenuRate(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rate items',
      one: 'Rate item',
    );
    return '$_temp0';
  }

  @override
  String mlMenuExplore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Explore items folders',
      one: 'Explore item folder',
    );
    return '$_temp0';
  }

  @override
  String get mlMenuGenerate => 'Generate playlist';

  @override
  String get mlGenerateSameArtist => 'More by the same artists';

  @override
  String get mlGenerateSameAlbum => 'From the same albums';

  @override
  String get mlGenerateSameGenre => 'In the same genres';

  @override
  String get mlGenerateSimilar => 'Similar (artist, genre or album)';

  @override
  String mlMenuEditMetadata(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Edit metadata for items...',
      one: 'Edit metadata for item...',
    );
    return '$_temp0';
  }

  @override
  String mlMenuFileInfo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'View file info for items...',
      one: 'View file info...',
    );
    return '$_temp0';
  }

  @override
  String mlArtistCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artists',
      one: '1 artist',
    );
    return '$_temp0';
  }

  @override
  String mlAlbumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String mlSelectedTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get mlClearLibrary => 'Clear Library';

  @override
  String get mlOpenLibrary => 'Open Media Library';

  @override
  String get mlCloseLibrary => 'Close Media Library';

  @override
  String get mlPreferences => 'Media Library Preferences...';

  @override
  String get startStopPlugin => 'Start/Stop plug-in';

  @override
  String get configurePlugin => 'Configure plug-in...';

  @override
  String get selectPlugin => 'Select plug-in...';

  @override
  String get mainWindow => 'Main Window';

  @override
  String get mediaLibrary => 'Media Library';

  @override
  String get skinWindow => 'Skin Window';

  @override
  String get skinSettings => 'Skin Settings…';

  @override
  String get skinWindows => 'Skin Windows';

  @override
  String get skinWindowsHint =>
      'Panels this skin brings of its own, such as its color and opacity settings.';

  @override
  String get skinWindowsHintInactive =>
      'Put this skin on to open the panels it brings of its own.';

  @override
  String get modernSettingsWindows => 'Windows';

  @override
  String get modernSettingsSkinOptions => 'Skin options';

  @override
  String get thinger => 'Thinger';

  @override
  String get ampedEqualizerWindow => 'Amped Equalizer';

  @override
  String get ampedPlaylistWindow => 'Amped Playlist Editor';

  @override
  String get ampedVideoWindow => 'Amped Video';

  @override
  String get ampedLibraryWindow => 'Amped Library';

  @override
  String get ampedThingerWindow => 'Amped Thinger';

  @override
  String get ampedVisualizationWindow => 'Amped Visualization';

  @override
  String get ampedAlbumArtWindow => 'Amped Album Art';

  @override
  String get albumArt => 'Album Art';

  @override
  String get refreshAlbumArt => 'Refresh album art';

  @override
  String get getAlbumArt => 'Get album art';

  @override
  String get openAlbumArtFolder => 'Open folder';

  @override
  String get lockAspectRatio => 'Lock aspect ratio';

  @override
  String get ampedPresetsTitle => 'Amped EQ Presets';

  @override
  String get ampedAutoLoadPresetsTitle => 'Amped EQ Auto-load Presets';

  @override
  String get ampedPreferencesTitle => 'Amped Preferences';

  @override
  String get updateTitle => 'Update available';

  @override
  String updateAvailable(String version) {
    return 'Amped $version is available.';
  }

  @override
  String get updateIgnore => 'Ignore';

  @override
  String get updateDownload => 'Go to downloads';

  @override
  String get aboutAmpedTitle => 'About Amped';

  @override
  String get configureVisualizationTitle => 'Configure Visualization';

  @override
  String settingsUnavailable(String page) {
    return '$page settings are not available yet.';
  }

  @override
  String get generalPreferences => 'General Preferences';

  @override
  String get fileTypes => 'File Types';

  @override
  String get playlist => 'Playlist';

  @override
  String get titles => 'Titles';

  @override
  String get stationInfo => 'Station Info';

  @override
  String get localization => 'Localization';

  @override
  String get skinsInstalled => 'Installed';

  @override
  String get skinsOnline => 'Browser';

  @override
  String get modernSettings => 'Skin Settings';

  @override
  String get plugins => 'Plug-ins';

  @override
  String get input => 'Input';

  @override
  String get output => 'Output';

  @override
  String get dspEffect => 'DSP/Effect';

  @override
  String get generalPurpose => 'General Purpose';

  @override
  String get modernSkin => 'Modern skin';

  @override
  String get classicSkin => 'Classic skin';

  @override
  String get bampSkin => 'Bamp skin';

  @override
  String get audaciousSkin => 'Audacious skin';

  @override
  String get skinInstallHint =>
      'You can also open a .wsz or .wal file with Amped, or drop it on the dock icon or any Amped window.';

  @override
  String get addEllipsis => 'Add...';

  @override
  String get visualizationPlugins => 'Visualization plug-ins';

  @override
  String get configureActivePlugin => 'Configure active plug-in';

  @override
  String get start => 'Start';

  @override
  String get ampedTagline => 'Crank it up.';

  @override
  String get aboutReportBug => 'Report a bug';

  @override
  String get aboutReportBugNote =>
      'The issue page is open, with the latest log lines filled in. The whole log is on your clipboard: paste it into the report if it was cut short. Nothing is sent until you submit it there.';

  @override
  String get aboutReportBugFailed =>
      'The issue page could not be opened. The log is on your clipboard.';

  @override
  String get macAboutMenu => 'About Amped';

  @override
  String get macHideMenu => 'Hide Amped';

  @override
  String get macQuitMenu => 'Quit Amped';

  @override
  String get openAction => 'Open';

  @override
  String get close => 'Close';

  @override
  String get noPresets => 'No presets';

  @override
  String get presetName => 'Preset name';

  @override
  String get defaultPreset => 'Default';

  @override
  String get enterPresetName => 'Enter a preset name.';

  @override
  String get pluginNoConfiguration => 'This plug-in has no configuration.';

  @override
  String get ok => 'OK';

  @override
  String get defaults => 'Defaults';

  @override
  String get color => 'Color';

  @override
  String get red => 'Red';

  @override
  String get green => 'Green';

  @override
  String get blue => 'Blue';

  @override
  String get eqPresetClassical => 'Classical';

  @override
  String get eqPresetClub => 'Club';

  @override
  String get eqPresetDance => 'Dance';

  @override
  String get eqPresetFlat => 'Flat';

  @override
  String get eqPresetLaptop => 'Laptop speakers/headphones';

  @override
  String get eqPresetLargeHall => 'Large hall';

  @override
  String get eqPresetParty => 'Party';

  @override
  String get eqPresetPop => 'Pop';

  @override
  String get eqPresetReggae => 'Reggae';

  @override
  String get eqPresetRock => 'Rock';

  @override
  String get eqPresetSoft => 'Soft';

  @override
  String get eqPresetSka => 'Ska';

  @override
  String get eqPresetFullBass => 'Full Bass';

  @override
  String get eqPresetSoftRock => 'Soft Rock';

  @override
  String get eqPresetFullTreble => 'Full Treble';

  @override
  String get eqPresetFullBassTreble => 'Full Bass & Treble';

  @override
  String get eqPresetLive => 'Live';

  @override
  String get eqPresetTechno => 'Techno';

  @override
  String get eqPresetHall => 'Hall';

  @override
  String get eqPresetRoom => 'Room';

  @override
  String get eqPresetArena => 'Arena';

  @override
  String get eqPresetStudio => 'Studio';

  @override
  String get eqPresetStadium => 'Stadium';

  @override
  String get eqPresetSpace => 'Space';

  @override
  String get addSkinsTitle => 'Add Skins';

  @override
  String get audioFiles => 'Audio files';

  @override
  String get videoFiles => 'Video files';

  @override
  String get videoAutoOpen => 'Show the video window when a video starts';

  @override
  String get videoAutoClose => 'Hide the video window when the video stops';

  @override
  String get videoStopOnClose =>
      'Stop playback when the video window is closed';

  @override
  String get videoStopOnCloseHint =>
      'Hold Shift while closing the window to keep playing.';

  @override
  String get playlistFiles => 'Playlist files';

  @override
  String get allFiles => 'All files (*.*)';

  @override
  String get allSupportedTypes => 'All supported types';

  @override
  String get skinFiles => 'skins (*.wsz;*.wal)';

  @override
  String get openFilesTitle => 'Open file(s)';

  @override
  String get openFolderTitle => 'Open folder';

  @override
  String get openUrlTitle => 'Open URL';

  @override
  String get addFilesToPlaylistTitle => 'Add file(s) to playlist';

  @override
  String get addFolderToPlaylistTitle => 'Add folder to playlist';

  @override
  String get addUrlToPlaylistTitle => 'Add URL to playlist';

  @override
  String get loadPlaylistTitle => 'Load playlist';

  @override
  String get m3uPlaylistType => 'M3U Playlist (*.m3u)';

  @override
  String get plsPlaylistType => 'PLS Playlist (*.pls)';

  @override
  String get m3u8PlaylistType => 'M3U8 Playlist (*.m3u8)';

  @override
  String get savePlaylistTitle => 'Save playlist';

  @override
  String get eqFiles => 'EQ files (*.eqf)';

  @override
  String get loadEqFileTitle => 'Load EQ file';

  @override
  String get saveEqFileTitle => 'Save EQ file';

  @override
  String get saveAsTypeLabel => 'Save as type:';

  @override
  String get enterUrlPrompt => 'Enter the URL of a file to play:';

  @override
  String get jumpToFileTitle => 'Jump to file';

  @override
  String get jumpToFileHint => 'Search the playlist';

  @override
  String get jumpToFileNoMatches => 'No matches';

  @override
  String get fileInfoTitle => 'File Info';

  @override
  String get basicInfo => 'Basic Info';

  @override
  String get advancedTab => 'Advanced';

  @override
  String get metadataGroup => 'Metadata';

  @override
  String get formatInfoGroup => 'Format Info';

  @override
  String get replayGainGroup => 'Replay Gain';

  @override
  String get tagTrack => 'Track #';

  @override
  String get tagDisc => 'Disc #';

  @override
  String get tagBpm => 'BPM';

  @override
  String get tagTitle => 'Title';

  @override
  String get tagArtist => 'Artist';

  @override
  String get tagAlbum => 'Album';

  @override
  String get tagAlbumArtist => 'Album Artist';

  @override
  String get tagYear => 'Year';

  @override
  String get tagGenre => 'Genre';

  @override
  String get tagComment => 'Comment';

  @override
  String get tagComposer => 'Composer';

  @override
  String get tagPublisher => 'Publisher';

  @override
  String get tagAcoustIdFingerprint => 'AcoustID Fingerprint';

  @override
  String get genreListTooltip => 'Genres';

  @override
  String get formatMp3 => 'MPEG audio';

  @override
  String get formatFlac => 'FLAC';

  @override
  String get formatOggVorbis => 'Ogg Vorbis';

  @override
  String get formatOggOpus => 'Ogg Opus';

  @override
  String get formatOggSpeex => 'Ogg Speex';

  @override
  String get formatOggFlac => 'Ogg FLAC';

  @override
  String get formatApeTagged => 'APE-tagged audio';

  @override
  String get formatWav => 'WAV';

  @override
  String get formatUnknown => 'Unknown format';

  @override
  String formatInfoTags(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get formatInfoNoTags => 'Tags: none';

  @override
  String formatInfoSize(int bytes) {
    return 'Size: $bytes bytes';
  }

  @override
  String formatInfoLength(int seconds) {
    return 'Length: $seconds seconds';
  }

  @override
  String formatInfoBitrate(int kbps) {
    return 'Bitrate: $kbps kbps';
  }

  @override
  String formatInfoSampleRate(int hz) {
    return 'Sample rate: $hz Hz';
  }

  @override
  String get channelsMono => 'Mono';

  @override
  String get channelsStereo => 'Stereo';

  @override
  String channelsCount(int count) {
    return '$count channels';
  }

  @override
  String replayGainTrack(String gain) {
    return 'Track gain: $gain';
  }

  @override
  String replayGainAlbum(String gain) {
    return 'Album gain: $gain';
  }

  @override
  String fileInfoReadError(String error) {
    return 'Can\'t read this file\'s tags: $error';
  }

  @override
  String fileInfoWriteError(String error) {
    return 'Couldn\'t save the tags: $error';
  }

  @override
  String get fileInfoNoRawTags => 'This file has no tags.';

  @override
  String get artworkTab => 'Artwork';

  @override
  String get id3v1Tab => 'ID3v1';

  @override
  String get id3v2Tab => 'ID3v2';

  @override
  String get includeId3v1 => 'Include ID3v1 tag in file';

  @override
  String get includeId3v2 => 'Include ID3v2 tag in file';

  @override
  String get copyToId3v1 => 'Copy to ID3v1';

  @override
  String get copyToId3v2 => 'Copy to ID3v2';

  @override
  String get artworkEditorGroup => 'Artwork editor';

  @override
  String get artworkTypeLabel => 'Artwork type:';

  @override
  String get loadArtwork => 'Load Artwork...';

  @override
  String get uploadArtwork => 'Choose...';

  @override
  String get downloadArtwork => 'Download';

  @override
  String get artworkStoredInDatabase =>
      'This file can\'t hold artwork, so the cover was kept in Amped\'s database.';

  @override
  String get artworkNotFound =>
      'No artwork found. Check the Artist and Album fields.';

  @override
  String get changeArtwork => 'Change...';

  @override
  String get saveArtworkAs => 'Save As...';

  @override
  String get deleteArtwork => 'Delete';

  @override
  String get noImage => '(no image)';

  @override
  String artworkDetails(
    String type,
    String width,
    String height,
    String origin,
    String format,
  ) {
    return '$type: ${width}x$height, origin: $origin, type: $format';
  }

  @override
  String get artworkOriginEmbedded => 'embedded';

  @override
  String get unknownMime => 'unknown';

  @override
  String get imageFiles => 'Image Files';

  @override
  String get loadArtworkTitle => 'Load Artwork';

  @override
  String get saveArtworkTitle => 'Save Artwork';

  @override
  String get jpegFiles => 'JPEG Files';

  @override
  String get pngFiles => 'PNG Files';

  @override
  String get gifFiles => 'GIF Files';

  @override
  String get bmpFiles => 'BMP Files';

  @override
  String get webpFiles => 'WebP Files';

  @override
  String get artworkNotAnImage => 'That file isn\'t an image amped can embed.';

  @override
  String get artworkNotEditable => 'Pictures can\'t be stored in this file.';

  @override
  String fileInfoPicturesReadError(String error) {
    return 'Couldn\'t read the pictures: $error';
  }

  @override
  String get artworkTypeOther => 'Other';

  @override
  String get artworkTypeFileIcon => 'File icon (32x32 PNG)';

  @override
  String get artworkTypeOtherFileIcon => 'Other file icon';

  @override
  String get artworkTypeFrontCover => 'Front cover';

  @override
  String get artworkTypeBackCover => 'Back cover';

  @override
  String get artworkTypeLeaflet => 'Leaflet page';

  @override
  String get artworkTypeMedia => 'Media (label side)';

  @override
  String get artworkTypeLeadArtist => 'Lead artist';

  @override
  String get artworkTypeArtist => 'Artist';

  @override
  String get artworkTypeConductor => 'Conductor';

  @override
  String get artworkTypeBand => 'Band';

  @override
  String get artworkTypeComposer => 'Composer';

  @override
  String get artworkTypeLyricist => 'Lyricist';

  @override
  String get artworkTypeRecordingLocation => 'Recording location';

  @override
  String get artworkTypeDuringRecording => 'During recording';

  @override
  String get artworkTypeDuringPerformance => 'During performance';

  @override
  String get artworkTypeVideoCapture => 'Video screen capture';

  @override
  String get artworkTypeBrightFish => 'A bright coloured fish';

  @override
  String get artworkTypeIllustration => 'Illustration';

  @override
  String get artworkTypeBandLogo => 'Band logo';

  @override
  String get artworkTypePublisherLogo => 'Publisher logo';

  @override
  String get fileInfoNotEditable =>
      'This field can\'t be stored in this file type.';

  @override
  String get tagNameColumn => 'Name';

  @override
  String get tagValueColumn => 'Value';

  @override
  String get editMetadataTitle => 'Edit Item Metadata';

  @override
  String itemsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items selected',
      one: '1 item selected',
    );
    return '$_temp0';
  }

  @override
  String filesUnreadableSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files can\'t be read and will be left alone.',
      one: '1 file can\'t be read and will be left alone.',
    );
    return '$_temp0';
  }

  @override
  String updatingFiles(int done, int total) {
    return 'Updating $done of $total...';
  }

  @override
  String get updateAction => 'Update';

  @override
  String get fieldNotStorable => 'These files can\'t store this field';

  @override
  String fieldMultipleValues(int count) {
    return '$count different values, kept unless ticked';
  }

  @override
  String fieldSetInSome(int filled, int total) {
    return 'Set in $filled of $total files';
  }

  @override
  String fieldNotStorableIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Not saved to $count files that can\'t store it',
      one: 'Not saved to 1 file that can\'t store it',
    );
    return '$_temp0';
  }

  @override
  String filesNotUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files couldn\'t be updated:',
      one: '1 file couldn\'t be updated:',
    );
    return '$_temp0';
  }

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsEnabledHint =>
      'Turn this off to disable all notifications, in-app and system.';

  @override
  String get skinNotifications => 'Skin Notifications';

  @override
  String get notificationShowAlways => 'Show always';

  @override
  String get notificationShowWindowshade => 'Show with windowshade / minimized';

  @override
  String get notificationShowMinimized => 'Show only when minimized';

  @override
  String get notificationDisableFullscreen => 'Disable in fullscreen';

  @override
  String get notificationShowArtwork => 'Show now playing artwork';

  @override
  String get notificationFadeIn => 'Fade in time';

  @override
  String get notificationHold => 'Hold time';

  @override
  String get notificationFadeOut => 'Fade out time';

  @override
  String notificationSeconds(String seconds) {
    return '$seconds s';
  }

  @override
  String get inAppNotifications => 'In-App Notifications';

  @override
  String get newEpisodeNotifications => 'New episodes';

  @override
  String get newEpisodeClickAction => 'When you click the notification';

  @override
  String get newEpisodeClickNothing => 'Do nothing';

  @override
  String get newEpisodeClickEnqueue => 'Add the new episodes to the playlist';

  @override
  String get newEpisodeClickPlay => 'Play the new episodes';

  @override
  String get notificationPosition => 'Notification position';

  @override
  String notificationPositionDisplayed(String position) {
    return 'Displayed $position';
  }

  @override
  String get notificationPositionTopLeft => 'top left';

  @override
  String get notificationPositionTopCenter => 'top center';

  @override
  String get notificationPositionTopRight => 'top right';

  @override
  String get notificationPositionBottomLeft => 'bottom left';

  @override
  String get notificationPositionBottomCenter => 'bottom center';

  @override
  String get notificationPositionBottomRight => 'bottom right';

  @override
  String get lookUpTagsEllipsis => 'Look up tags...';

  @override
  String get lookUpTagsTooltip =>
      'Identify this song by its sound (AcoustID) and fetch its tags from MusicBrainz.';

  @override
  String get tagLookupTitle => 'Look Up Tags';

  @override
  String get tagLookupSearching =>
      'Fingerprinting the song and searching MusicBrainz...';

  @override
  String get tagLookupNoMatch =>
      'AcoustID doesn\'t know this recording, so there are no tags to suggest.';

  @override
  String get tagLookupMissingKey =>
      'Tag lookup isn\'t available in this build of Amped: it has no AcoustID API key.';

  @override
  String get tagLookupInvalidKey =>
      'AcoustID didn\'t accept this build\'s API key, so tags can\'t be looked up.';

  @override
  String tagLookupFingerprintFailed(String error) {
    return 'This file couldn\'t be fingerprinted: $error';
  }

  @override
  String get tagLookupBusy =>
      'The lookup service is busy right now. Wait a moment, then try again.';

  @override
  String get tagLookupUnreachable =>
      'Couldn\'t reach the lookup service. Check your internet connection, then try again.';

  @override
  String get tagLookupPickHint =>
      'Pick the release this file is from. Its tags go into the fields; nothing is saved until you press OK.';

  @override
  String get tagLookupUse => 'Use these tags';

  @override
  String get tagLookupMatchLabel => 'match';

  @override
  String tagLookupAlbum(String album) {
    return 'Album: $album';
  }

  @override
  String tagLookupReleasedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Released $dateString';
  }

  @override
  String tagLookupReleasedMonth(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Released $dateString';
  }

  @override
  String tagLookupReleasedYear(String year) {
    return 'Released $year';
  }

  @override
  String tagLookupTrackOf(String track, String total) {
    return 'Track $track of $total';
  }

  @override
  String tagLookupTrack(String track) {
    return 'Track $track';
  }

  @override
  String tagLookupDisc(String disc) {
    return 'Disc $disc';
  }

  @override
  String get tagLookupApplied =>
      'Filled in from MusicBrainz. Press OK to save them.';

  @override
  String get saved => 'Saved';

  @override
  String get applyAction => 'Apply';

  @override
  String skinsSummary(String name) {
    return 'Active skin: $name';
  }

  @override
  String get skinsSummaryHint =>
      'Choose a skin in Browser. A modern skin also has its options and color themes there.';

  @override
  String get skinPreview => 'Preview';

  @override
  String skinNotValid(String name) {
    return '$name is not a skin.';
  }

  @override
  String get skinNoPreview => 'No preview is available for this skin.';

  @override
  String get skinComments => 'Comments';

  @override
  String get skinDropTarget =>
      'Drop a .wsz or .wal skin here, or tap to find one';

  @override
  String get modernSettingsOptions => 'Options';

  @override
  String get modernSettingsColorThemes => 'Color Themes';

  @override
  String get modernSettingsNeedsApply =>
      'Apply this skin to change its options and color themes.';

  @override
  String get modernSettingsNoOptions => 'This skin has no options.';

  @override
  String get colorThemeCustom => 'Custom';

  @override
  String get colorThemeClone => 'Clone...';

  @override
  String get colorThemeEdit => 'Edit';

  @override
  String get colorThemeNewName => 'Theme name';

  @override
  String get colorThemeNoThemes => 'This skin has no color themes.';

  @override
  String get colorThemeRed => 'Red';

  @override
  String get colorThemeGreen => 'Green';

  @override
  String get colorThemeBlue => 'Blue';

  @override
  String get colorThemeGray => 'Grayscale';

  @override
  String get colorThemeGrayNone => 'Off';

  @override
  String get colorThemeGrayBrightest => 'Brightest channel';

  @override
  String get colorThemeGrayAverage => 'Average of channels';

  @override
  String get colorThemeBoost => 'Boost';

  @override
  String get remoteLoginTitle => 'Sign in to network share';

  @override
  String remoteLoginPrompt(String server) {
    return 'Enter the name and password for $server:';
  }

  @override
  String remoteLoginFailed(String error) {
    return 'The server did not accept the sign-in: $error';
  }

  @override
  String get remoteLoginUser => 'Name';

  @override
  String get remoteLoginPassword => 'Password';

  @override
  String get remoteLoginSignIn => 'Sign in';

  @override
  String remoteBuffering(
    int percent,
    String speed,
    String elapsed,
    String remaining,
  ) {
    return 'Buffering $percent% - $speed/s - $elapsed elapsed, $remaining left';
  }

  @override
  String remoteBufferingUnknown(String received, String speed, String elapsed) {
    return 'Buffering $received - $speed/s - $elapsed elapsed';
  }

  @override
  String get libraryRemoteSources => 'Remote sources';

  @override
  String get libraryNoRemoteSources => 'No remote sources added.';

  @override
  String get libraryAddNavidrome => 'Add Navidrome/Subsonic...';

  @override
  String get libraryAddPlex => 'Add Plex...';

  @override
  String get libraryAddJellyfin => 'Add Jellyfin...';

  @override
  String get libraryAddPodcast => 'Add podcast...';

  @override
  String get libraryAddAudiobookshelf => 'Add Audiobookshelf...';

  @override
  String get librarySourceFeedUrl => 'RSS feed URL';

  @override
  String get librarySourceApiToken => 'API token';

  @override
  String get librarySourcePodcastSearch => 'Search iTunes';

  @override
  String get librarySourceToken => 'Plex token';

  @override
  String get librarySourcePlexSignIn => 'Sign in with Plex';

  @override
  String get librarySourcePlexWaiting => 'Waiting for plex.tv...';

  @override
  String get librarySourcePlexUser => 'Present as';

  @override
  String get librarySourcePlexPin => 'PIN';

  @override
  String get libraryEditSource => 'Edit';

  @override
  String get libraryRemoveSource => 'Remove';

  @override
  String get librarySourceName => 'Name';

  @override
  String get librarySourceServer => 'Server address';

  @override
  String get librarySourcePasswordKeep =>
      'Leave empty to keep the saved password';

  @override
  String get librarySourceSave => 'Save';

  @override
  String get librarySourceChecking => 'Connecting...';

  @override
  String librarySourceFailed(String error) {
    return 'Could not connect: $error';
  }

  @override
  String get libraryAddSoundCloud => 'Add SoundCloud...';

  @override
  String get librarySoundCloudProOnly => 'SoundCloud Pro subscribers only';

  @override
  String get librarySoundCloudInstructions =>
      'SoundCloud only gives application keys to Pro subscribers (Artist Pro), so you bring your own key:\n1. Subscribe to SoundCloud Pro, then open soundcloud.com/you/apps (or follow developers.soundcloud.com/docs/building-with-ai).\n2. Register a new application, with any name and description.\n3. Copy its Client ID and Client Secret into the fields below.\n4. Enter the address of the profile whose public tracks and likes you want to browse, such as https://soundcloud.com/artist. To browse your own library instead, tick the sign-in option and add the redirect URI it shows to the application.\nThe secret is kept in your system\'s secure storage.';

  @override
  String get librarySoundCloudProfile => 'Profile URL';

  @override
  String get librarySoundCloudClientId => 'Client ID';

  @override
  String get librarySoundCloudClientSecret => 'Client Secret';

  @override
  String get librarySoundCloudSecretKeep =>
      'Leave empty to keep the saved secret';

  @override
  String get librarySoundCloudBrowserSignIn =>
      'Sign in with SoundCloud in my browser (my own tracks and likes)';

  @override
  String librarySoundCloudRedirectHint(String address) {
    return 'For this, add $address as a redirect URI of your SoundCloud application first. Your browser opens to approve the sign-in when you save.';
  }

  @override
  String get librarySourceWaitingForBrowser => 'Waiting for the browser...';
}
