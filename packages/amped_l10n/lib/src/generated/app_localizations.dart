import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The stable product name used in UI and native app metadata.
  ///
  /// In en, this message translates to:
  /// **'Amped'**
  String get appName;

  /// Title of the Playlist Editor window and the menu entry that shows or hides it.
  ///
  /// In en, this message translates to:
  /// **'Playlist Editor'**
  String get playlistEditor;

  /// Menu entry that opens the Preferences window. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Preferences...'**
  String get preferences;

  /// Label of the main menu opened from the app's skin button; the ellipsis follows the classic player menu.
  ///
  /// In en, this message translates to:
  /// **'Amped...'**
  String get menuAmped;

  /// Transport action and menu entry that starts playback of the current track.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Menu entry that opens a file chooser to play a file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'File...'**
  String get file;

  /// Menu entry that asks for a URL to play. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'URL...'**
  String get url;

  /// Menu entry that opens a folder chooser to play a folder's contents. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Folder...'**
  String get folder;

  /// Top-level menu that lists installed skins and skin tools.
  ///
  /// In en, this message translates to:
  /// **'Skins'**
  String get skins;

  /// Top-level menu holding player options such as always on top and doublesize mode.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// Top-level menu holding the playback controls and modes.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// Transport action and menu entry that jumps to the previous track.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// Transport action and menu entry that pauses or resumes playback.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Transport action and menu entry that stops playback.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// Transport action and menu entry that jumps to the next track.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Menu entry that plays a random track from the playlist.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get random;

  /// Fullscreen video control that resumes a paused video.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get videoPlay;

  /// Fullscreen video control that jumps 15 seconds back.
  ///
  /// In en, this message translates to:
  /// **'Back 15 seconds'**
  String get videoBack15;

  /// Fullscreen video control that jumps 15 seconds forward.
  ///
  /// In en, this message translates to:
  /// **'Forward 15 seconds'**
  String get videoForward15;

  /// Fullscreen video control that picks the audio track.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get videoAudio;

  /// Badge under a subtitle track the player cannot display.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get videoTrackUnsupported;

  /// Video window menu entry that keeps just the Video window above the other windows.
  ///
  /// In en, this message translates to:
  /// **'Always on top (Video only)'**
  String get alwaysOnTopVideoOnly;

  /// Fullscreen video control that picks the subtitle track.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get videoSubtitles;

  /// Subtitle picker entry that shows no subtitles.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get videoSubtitlesOff;

  /// Subtitle picker entry for a track the file gives no name or language.
  ///
  /// In en, this message translates to:
  /// **'Track {number}'**
  String videoSubtitleTrack(int number);

  /// Video control that opens the list of Chromecasts to play the video on.
  ///
  /// In en, this message translates to:
  /// **'Cast to a device'**
  String get videoCast;

  /// Cast list entry shown while Chromecasts are looked for and none is found yet.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices…'**
  String get videoCastSearching;

  /// Cast list entry shown when the search found no Chromecast.
  ///
  /// In en, this message translates to:
  /// **'No Chromecast found'**
  String get videoCastNone;

  /// Cast list entry that looks for Chromecasts again.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get videoCastSearchAgain;

  /// Cast list entry that brings the video back to this computer.
  ///
  /// In en, this message translates to:
  /// **'Stop casting'**
  String get videoCastStop;

  /// Cast list heading while the video plays on a device. {device} is its name.
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String videoCastingTo(String device);

  /// Cast list message for a video in a format the devices can't play (Matroska, for one).
  ///
  /// In en, this message translates to:
  /// **'This kind of video can\'t be cast'**
  String get videoCastUnsupported;

  /// Cast list message when the video could not be played on the chosen device.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cast to the device'**
  String get videoCastFailed;

  /// Fullscreen video control that leaves fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get videoExitFullscreen;

  /// Fullscreen video volume slider.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get videoVolume;

  /// Fullscreen video progress bar.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get videoPosition;

  /// Menu entry that shows the video or visualization fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// Title of the visualizer view and its menu entry.
  ///
  /// In en, this message translates to:
  /// **'Visualizer'**
  String get visualizerTitle;

  /// Toggle for repeating the playlist when it reaches the end.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// Toggle for playing the playlist in random order.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// Menu entry that quits the app (Windows and Linux wording; macOS uses Quit).
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exit;

  /// Option to show elapsed time in the main window's time display.
  ///
  /// In en, this message translates to:
  /// **'Time elapsed'**
  String get timeElapsed;

  /// Option to show remaining time in the main window's time display.
  ///
  /// In en, this message translates to:
  /// **'Time remaining'**
  String get timeRemaining;

  /// Option that keeps the player windows above other applications.
  ///
  /// In en, this message translates to:
  /// **'Always On Top'**
  String get alwaysOnTop;

  /// Menu entry that toggles the now-playing notification shown when the track changes.
  ///
  /// In en, this message translates to:
  /// **'Playback Notifications'**
  String get playbackNotifications;

  /// Menu entry that shows the now-playing notification right away.
  ///
  /// In en, this message translates to:
  /// **'Show Notification'**
  String get showNotification;

  /// Preference that sends playback notifications through the operating system instead of drawing them in-app.
  ///
  /// In en, this message translates to:
  /// **'Use System Notifications'**
  String get nativeNotifications;

  /// Option that scales the player windows to twice their size. Named after the classic player's feature.
  ///
  /// In en, this message translates to:
  /// **'Doublesize mode'**
  String get doubleSizeMode;

  /// Menu entry that collapses the main window to a narrow title strip.
  ///
  /// In en, this message translates to:
  /// **'Main Window Shade'**
  String get mainWindowShade;

  /// Menu entry that opens the skin browser. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Skin Browser...'**
  String get skinBrowser;

  /// Menu that lists the color themes of the active modern skin.
  ///
  /// In en, this message translates to:
  /// **'Color Themes'**
  String get colorThemes;

  /// Option that applies the chosen color theme to every skin that has a theme of the same name.
  ///
  /// In en, this message translates to:
  /// **'Share Between Skins'**
  String get shareColorThemes;

  /// Menu holding skin options for the active modern skin.
  ///
  /// In en, this message translates to:
  /// **'Skin'**
  String get skinMenu;

  /// Menu entry that opens the online skin browser. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Online Skin Browser...'**
  String get onlineSkinBrowser;

  /// Placeholder in the search field of the online skin browser.
  ///
  /// In en, this message translates to:
  /// **'Search the Webamp skin library'**
  String get skinBrowserSearchHint;

  /// Button that downloads the previewed skin and installs it.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get skinBrowserInstall;

  /// Tooltip of the button that shows the previous skin in the online skin browser.
  ///
  /// In en, this message translates to:
  /// **'Previous skin'**
  String get skinBrowserPrevious;

  /// Tooltip of the button that shows the next skin in the online skin browser.
  ///
  /// In en, this message translates to:
  /// **'Next skin'**
  String get skinBrowserNext;

  /// Label shown on a skin in the online browser that is already installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get skinBrowserInstalled;

  /// Message shown when a search in the online skin browser finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No skins found.'**
  String get skinBrowserNoResults;

  /// Message shown when the online skin library can't be reached. {error} is the technical reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the skin library: {error}'**
  String skinBrowserError(String error);

  /// Message shown in place of a skin's preview image when none exists.
  ///
  /// In en, this message translates to:
  /// **'No preview available'**
  String get skinBrowserNoPreview;

  /// Button that retries loading the online skin library after a failure.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get skinBrowserRetry;

  /// Credit line naming the source of the online skins.
  ///
  /// In en, this message translates to:
  /// **'Skins from skins.webamp.org, the classic player Skin Museum.'**
  String get skinBrowserCredit;

  /// Top-level menu that shows or hides the player windows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get windows;

  /// Submenu listing the layouts (window modes) a modern skin's main window can take, to switch between them.
  ///
  /// In en, this message translates to:
  /// **'Layouts'**
  String get skinLayouts;

  /// Name of the Equalizer window and its menu entry.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// Name of the Video window and its menu entry.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// Name of the Media Library window in menus.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// Name of the Visualization window and its menu entry.
  ///
  /// In en, this message translates to:
  /// **'Visualization'**
  String get visualization;

  /// Menu entry that opens settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Menu entry that collapses the focused window to a narrow title strip.
  ///
  /// In en, this message translates to:
  /// **'Window Shade'**
  String get windowShade;

  /// Menu entry that quits the app.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get quit;

  /// Equalizer preset menu entry that loads a preset.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// Equalizer preset menu entry that saves a preset.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Equalizer preset menu entry that deletes a preset.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Menu entry that opens the equalizer preset submenu. The trailing ellipsis follows the classic player menu.
  ///
  /// In en, this message translates to:
  /// **'Preset...'**
  String get preset;

  /// Menu entry for presets that load automatically for matching tracks.
  ///
  /// In en, this message translates to:
  /// **'Auto-load preset...'**
  String get autoLoadPreset;

  /// Menu entry that imports equalizer presets from an .eqf file.
  ///
  /// In en, this message translates to:
  /// **'From EQF...'**
  String get fromEqf;

  /// Menu entry that exports equalizer presets to an .eqf file.
  ///
  /// In en, this message translates to:
  /// **'To EQF...'**
  String get toEqf;

  /// Button that resets the equalizer sliders to their defaults.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Playlist context-menu entry that plays the selected items.
  ///
  /// In en, this message translates to:
  /// **'Play item(s)'**
  String get playItems;

  /// Playlist context-menu entry that removes the selected items from the playlist.
  ///
  /// In en, this message translates to:
  /// **'Remove item(s)'**
  String get removeItems;

  /// Playlist context-menu entry that removes every item except the selected ones.
  ///
  /// In en, this message translates to:
  /// **'Crop files'**
  String get cropFiles;

  /// Playlist context-menu entry that edits the tags of the selected files.
  ///
  /// In en, this message translates to:
  /// **'Edit metadata for selection...'**
  String get editMetadata;

  /// Playlist context-menu entry that opens the file info dialog for the selected item.
  ///
  /// In en, this message translates to:
  /// **'View file info...'**
  String get viewFileInfo;

  /// Title for the playlist entry editor and context-menu group.
  ///
  /// In en, this message translates to:
  /// **'Playlist entry'**
  String get playlistEntry;

  /// Playlist context-menu entry that adds the selected items to bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmark item(s)'**
  String get bookmarkItems;

  /// Playlist context-menu submenu for rating the selected items.
  ///
  /// In en, this message translates to:
  /// **'Rate items'**
  String get rateItems;

  /// Entry in the rating menu that clears an item's rating.
  ///
  /// In en, this message translates to:
  /// **'No rating'**
  String get noRating;

  /// Playlist context-menu entry that reveals the selected item's folder in the file manager.
  ///
  /// In en, this message translates to:
  /// **'Explore item(s) folder'**
  String get exploreItemsFolder;

  /// Playlist menu entry that adds files. The '(s)' follows the classic player's wording for one or more.
  ///
  /// In en, this message translates to:
  /// **'Add file(s)'**
  String get addFiles;

  /// Playlist menu entry that adds the contents of a folder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolder;

  /// Playlist menu entry that adds a URL.
  ///
  /// In en, this message translates to:
  /// **'Add URL'**
  String get addUrl;

  /// Playlist menu entry that removes the selected items.
  ///
  /// In en, this message translates to:
  /// **'Remove selected'**
  String get removeSelected;

  /// Playlist menu entry that keeps only the selected items.
  ///
  /// In en, this message translates to:
  /// **'Crop selected'**
  String get cropSelected;

  /// Playlist menu entry that removes every item.
  ///
  /// In en, this message translates to:
  /// **'Clear playlist'**
  String get clearPlaylist;

  /// Playlist menu entry that opens the remove submenu. The trailing ellipsis follows the classic player menu.
  ///
  /// In en, this message translates to:
  /// **'Remove...'**
  String get remove;

  /// Confirmation button of a removal dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// Button that dismisses a dialog without making changes.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button in the tag lookup dialog that repeats a failed lookup.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get tagLookupRetry;

  /// Privacy notice in the tag lookup dialog. It lists exactly what is sent to AcoustID and MusicBrainz.
  ///
  /// In en, this message translates to:
  /// **'Looking up a song sends its fingerprint and length to AcoustID and the matching recording\'s ID to MusicBrainz. Nothing else about you or your files is sent.'**
  String get tagLookupPrivacy;

  /// Playlist menu entry that removes items whose files no longer exist.
  ///
  /// In en, this message translates to:
  /// **'Remove missing files from playlist'**
  String get removeMissingFiles;

  /// Playlist menu entry that deletes the selected files from disk, not just from the playlist.
  ///
  /// In en, this message translates to:
  /// **'Physically remove selected file(s)'**
  String get physicallyRemoveFiles;

  /// Playlist menu entry that selects every item.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// Playlist menu entry that clears the selection.
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get selectNone;

  /// Playlist menu entry that selects what is unselected and the reverse.
  ///
  /// In en, this message translates to:
  /// **'Invert selection'**
  String get invertSelection;

  /// Label of the Sort button and menu in the playlist editor.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// Label of the Misc button and menu in the playlist editor.
  ///
  /// In en, this message translates to:
  /// **'Misc'**
  String get misc;

  /// Playlist menu entry that sorts the list by track title.
  ///
  /// In en, this message translates to:
  /// **'Sort list by title'**
  String get sortByTitle;

  /// Playlist menu entry that sorts the list by file name.
  ///
  /// In en, this message translates to:
  /// **'Sort list by filename'**
  String get sortByFilename;

  /// Playlist menu entry that sorts the list by folder path, then file name.
  ///
  /// In en, this message translates to:
  /// **'Sort list by path and filename'**
  String get sortByPath;

  /// Playlist menu entry that sorts the list by artist.
  ///
  /// In en, this message translates to:
  /// **'Sort list by artist'**
  String get sortByArtist;

  /// Playlist menu entry that sorts the list by album.
  ///
  /// In en, this message translates to:
  /// **'Sort list by album'**
  String get sortByAlbum;

  /// Playlist menu entry that sorts the list by artist, then album.
  ///
  /// In en, this message translates to:
  /// **'Sort list by artist and album'**
  String get sortByArtistAlbum;

  /// Playlist menu entry that reverses the order of the list.
  ///
  /// In en, this message translates to:
  /// **'Reverse list'**
  String get reverseList;

  /// Playlist menu entry that shuffles the order of the list.
  ///
  /// In en, this message translates to:
  /// **'Randomize list'**
  String get randomizeList;

  /// Status message shown while the playlist is being sorted.
  ///
  /// In en, this message translates to:
  /// **'Sorting playlist...'**
  String get sortingPlaylist;

  /// Status message shown while the playlist is sorted and file tags are read. {done} of {total} files are read so far.
  ///
  /// In en, this message translates to:
  /// **'Sorting playlist: reading tags {done}/{total}'**
  String sortingReadingTags(int done, int total);

  /// Name of the file info dialog used in menus.
  ///
  /// In en, this message translates to:
  /// **'File info'**
  String get fileInfo;

  /// Menu entry that opens the file info dialog. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'File info...'**
  String get fileInfoEllipsis;

  /// Menu entry that opens the playlist entry editor. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Playlist entry...'**
  String get playlistEntryEllipsis;

  /// Playlist menu entry that writes the playlist as an HTML page.
  ///
  /// In en, this message translates to:
  /// **'Generate HTML playlist'**
  String get generateHtmlPlaylist;

  /// Playlist menu entry that re-reads tags and rebuilds the displayed titles of the selected items.
  ///
  /// In en, this message translates to:
  /// **'Rebuild titles on selection'**
  String get rebuildTitles;

  /// Menu entry that opens a playlist file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Open playlist...'**
  String get openPlaylist;

  /// Menu entry that saves the playlist to a file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Save playlist...'**
  String get savePlaylist;

  /// Menu entry that clears the playlist to start a new one.
  ///
  /// In en, this message translates to:
  /// **'New playlist (clear)'**
  String get newPlaylist;

  /// Media Library menu entry that creates an empty playlist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get mlNewPlaylist;

  /// Media Library menu entry that imports a playlist file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Import playlist from file...'**
  String get mlImportPlaylist;

  /// Media Library menu entry that exports a playlist to a file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Export playlist...'**
  String get mlExportPlaylist;

  /// Media Library menu entry that adds folders to the library. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Add media to Library...'**
  String get mlAddMedia;

  /// Media Library menu entry that adds the tracks of the current playlist to the library.
  ///
  /// In en, this message translates to:
  /// **'Add current playlist to Library'**
  String get mlAddPlaylist;

  /// Title of the dialog for adding media folders to the library.
  ///
  /// In en, this message translates to:
  /// **'Add media to Library'**
  String get mlAddMediaTitle;

  /// Preferences page for the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get mediaLibraryPreferences;

  /// Heading of the list of folders that are watched for audio files to add to the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Watch folders'**
  String get watchFolders;

  /// Explains what watch folders do.
  ///
  /// In en, this message translates to:
  /// **'Audio files in these folders are added to the Local source, and removed from it again when they are deleted.'**
  String get watchFoldersHint;

  /// Shown when the list of watch folders is empty.
  ///
  /// In en, this message translates to:
  /// **'No folders are watched.'**
  String get watchFoldersEmpty;

  /// Title of the dialog for picking a folder to watch.
  ///
  /// In en, this message translates to:
  /// **'Watch folder'**
  String get watchFoldersAddTitle;

  /// Button that picks a folder to watch.
  ///
  /// In en, this message translates to:
  /// **'Add...'**
  String get watchFoldersAdd;

  /// Tooltip of the button that removes a folder from the watch folders.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get watchFoldersRemove;

  /// Label of the Media Library search field.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get mlSearch;

  /// Media Library button that appends the selected tracks to the playlist.
  ///
  /// In en, this message translates to:
  /// **'Enqueue'**
  String get mlEnqueue;

  /// Hint shown on the Add media button while a scan runs: pressing it again cancels the scan.
  ///
  /// In en, this message translates to:
  /// **'Press again to cancel'**
  String get mlCancelPrompt;

  /// Media Library menu entry that removes the selected items from the library without deleting files.
  ///
  /// In en, this message translates to:
  /// **'Remove item(s) from Library'**
  String get mlRemoveFromLibrary;

  /// Label of the Media Library button that adds folders. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Add media...'**
  String get mlAddMediaButton;

  /// First entry of the artist list in the Media Library; selecting it shows every artist.
  ///
  /// In en, this message translates to:
  /// **'All Artists'**
  String get mlAllArtists;

  /// First entry of the album list in the Media Library; selecting it shows every album.
  ///
  /// In en, this message translates to:
  /// **'All Albums'**
  String get mlAllAlbums;

  /// First entry of the podcast list in the Media Library's podcast view; selecting it shows the episodes of every podcast.
  ///
  /// In en, this message translates to:
  /// **'All Podcasts'**
  String get mlAllPodcasts;

  /// Heading of the episode number column in the Media Library's podcast view.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get mlColumnNumber;

  /// Title of the notification that says a podcast has new episodes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{New episode} other{{count} new episodes}}'**
  String newEpisodeTitle(int count);

  /// A line of the new-episode notification: the podcast, then the episode's title.
  ///
  /// In en, this message translates to:
  /// **'{podcast}: {episode}'**
  String newEpisodeLine(String podcast, String episode);

  /// Last line of the new-episode notification when there are more episodes than it lists.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String newEpisodeMore(int count);

  /// Heading of the source settings that say whether and how often a source is looked at again while Amped runs.
  ///
  /// In en, this message translates to:
  /// **'Background refresh'**
  String get sourceRefreshTitle;

  /// Switch in a source's settings.
  ///
  /// In en, this message translates to:
  /// **'Refresh in the background'**
  String get sourceRefreshEnabled;

  /// Explains the background refresh switch.
  ///
  /// In en, this message translates to:
  /// **'Looks at the source again while Amped runs. New podcast episodes are announced.'**
  String get sourceRefreshHint;

  /// Label of the choice of how often a source is refreshed.
  ///
  /// In en, this message translates to:
  /// **'Refresh every'**
  String get sourceRefreshEvery;

  /// Label of the choice of how long after Amped starts a source is first refreshed.
  ///
  /// In en, this message translates to:
  /// **'First refresh after starting'**
  String get sourceRefreshFirst;

  /// Heading of the podcast source settings that say when an episode counts as played.
  ///
  /// In en, this message translates to:
  /// **'Count an episode as played'**
  String get sourceCompletedTitle;

  /// Choice: an episode counts as played once this share of it was heard.
  ///
  /// In en, this message translates to:
  /// **'From a percentage played'**
  String get sourceCompletedPercent;

  /// Choice: an episode counts as played once no more than this much time of it is left.
  ///
  /// In en, this message translates to:
  /// **'When this much is left'**
  String get sourceCompletedRemaining;

  /// Explains when an episode counts as played.
  ///
  /// In en, this message translates to:
  /// **'Played episodes are left out of the number of new episodes, and are not offered for resuming.'**
  String get sourceCompletedHint;

  /// A percentage.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String percentValue(int percent);

  /// A length of time in hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String durationHours(int count);

  /// A length of time in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String durationMinutes(int count);

  /// A length of time in seconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String durationSeconds(int count);

  /// Title of the window that shows a picture from the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get artworkTitle;

  /// Heading of the panel with the picture and description of a podcast or episode in the Media Library's podcast view; clicking it folds the panel away or shows it again.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get mlDetails;

  /// Heading of the title column in the Media Library's list of music.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get mlColumnTitle;

  /// Heading of the artist column in the Media Library's list of music.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get mlColumnArtist;

  /// Heading of the album column in the Media Library's list of music.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get mlColumnAlbum;

  /// Heading of the genre column in the Media Library's list of music.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get mlColumnGenre;

  /// Heading of the Media Library's source tree section with the audiobooks of servers.
  ///
  /// In en, this message translates to:
  /// **'Audiobooks'**
  String get mlSectionAudiobooks;

  /// First entry of the book list in the Media Library's audiobook view; selecting it shows the parts of every book.
  ///
  /// In en, this message translates to:
  /// **'All Audiobooks'**
  String get mlAllAudiobooks;

  /// Heading of the column with the audiobook a part belongs to.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get mlColumnBook;

  /// Heading of the column with how many albums an artist has, in the Media Library's split panels.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get mlColumnAlbums;

  /// Heading of the column with how many tracks an artist or album has, in the Media Library's split panels.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get mlColumnTracks;

  /// First row of a split panel, standing for everything in it; the count is such as '3 artists'.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String mlAllWithCount(String count);

  /// Toggle in the Media Library that leaves out the movies, episodes, seasons and shows that were watched.
  ///
  /// In en, this message translates to:
  /// **'Hide watched'**
  String get mlHideWatched;

  /// Tooltip of the toggle that hides what was watched.
  ///
  /// In en, this message translates to:
  /// **'Leave out movies and episodes that were watched, and the seasons and shows made of them'**
  String get mlHideWatchedTip;

  /// Toggle in the Media Library that leaves out the podcast episodes and audiobook parts that were listened to.
  ///
  /// In en, this message translates to:
  /// **'Hide listened to'**
  String get mlHideListened;

  /// Tooltip of the toggle that hides what was listened to.
  ///
  /// In en, this message translates to:
  /// **'Leave out episodes and parts that were listened to, and the podcasts and books made of them'**
  String get mlHideListenedTip;

  /// Tooltip of the arrow beside the covers button of the Media Library, which opens a slider for how big the covers are.
  ///
  /// In en, this message translates to:
  /// **'Cover size'**
  String get mlCoverSize;

  /// Tooltip of the button that shows the Media Library as a grid of covers above the tracks.
  ///
  /// In en, this message translates to:
  /// **'Artist and album covers beside the tracks'**
  String get mlLayoutCovers;

  /// Tooltip of the Media Library button that lists the audiobooks beside their parts.
  ///
  /// In en, this message translates to:
  /// **'Books beside the parts'**
  String get mlLayoutBooksList;

  /// Tooltip of the Media Library button that shows panels of authors, series and books above the parts.
  ///
  /// In en, this message translates to:
  /// **'Author, series and book panels above the parts'**
  String get mlLayoutBooksSplit;

  /// Tooltip of the Media Library button that lists the podcasts beside their episodes.
  ///
  /// In en, this message translates to:
  /// **'Podcasts beside the episodes'**
  String get mlLayoutPodcastsList;

  /// Tooltip of the Media Library button that lists TV shows and seasons beside the episodes.
  ///
  /// In en, this message translates to:
  /// **'Shows and seasons beside the episodes'**
  String get mlLayoutShowsList;

  /// Tooltip of the Media Library button that shows panels of TV shows and seasons above the episodes.
  ///
  /// In en, this message translates to:
  /// **'Show and season panels above the episodes'**
  String get mlLayoutShowsSplit;

  /// Tooltip of the Media Library button that lists only the movies.
  ///
  /// In en, this message translates to:
  /// **'Movies only'**
  String get mlLayoutMovies;

  /// Tooltip of the Media Library button that shows a server's categories and playlists beside its movies.
  ///
  /// In en, this message translates to:
  /// **'Category and playlist panels above the movies'**
  String get mlLayoutMovieCategories;

  /// Heading of the column with when a movie or episode came out, in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Aired'**
  String get mlColumnAired;

  /// Heading of the column with when an item was added to its server, in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get mlColumnAdded;

  /// Heading of the column with when a movie or episode was last watched, in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Last watched'**
  String get mlColumnLastWatched;

  /// Choice of how movies and shows are ordered: by name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mlVideoSortName;

  /// Choice of how movies and shows are ordered: the last watched first.
  ///
  /// In en, this message translates to:
  /// **'Recently watched'**
  String get mlVideoSortWatched;

  /// Choice of how movies and shows are ordered: the newest first.
  ///
  /// In en, this message translates to:
  /// **'Recently aired'**
  String get mlVideoSortAired;

  /// Choice of how movies and shows are ordered: the last added to the server first.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get mlVideoSortAdded;

  /// Tooltip of the button that changes how movies and shows are ordered.
  ///
  /// In en, this message translates to:
  /// **'Order by (click for the next)'**
  String get mlVideoSortTip;

  /// Choice of which movies and shows are listed: all of them.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mlVideoFilterAll;

  /// Choice of which shows are listed: those with episodes watched and others still to watch.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get mlVideoFilterWatching;

  /// Choice of which movies are listed: those started and not finished.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get mlVideoFilterInProgress;

  /// Choice of which movies and shows are listed: those with something not watched yet.
  ///
  /// In en, this message translates to:
  /// **'Unwatched'**
  String get mlVideoFilterUnwatched;

  /// Tooltip of the button that changes which movies and shows are listed.
  ///
  /// In en, this message translates to:
  /// **'Show (click for the next)'**
  String get mlVideoFilterTip;

  /// Heading of the panel of categories (genres) of movies in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get mlColumnCategory;

  /// Heading of the panel of a server's playlists in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get mlColumnPlaylist;

  /// Heading of the count of movies in a panel of the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get mlColumnMovies;

  /// How many categories.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 category} other{{count} categories}}'**
  String mlCategoryCount(int count);

  /// How many playlists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 playlist} other{{count} playlists}}'**
  String mlPlaylistCount(int count);

  /// Tooltip of the Media Library button that shows the audiobooks as a grid of covers above their parts.
  ///
  /// In en, this message translates to:
  /// **'Book covers above the parts'**
  String get mlLayoutBookCovers;

  /// Tooltip of the Media Library button that shows the podcasts as a grid of covers above their episodes.
  ///
  /// In en, this message translates to:
  /// **'Podcast covers above the episodes'**
  String get mlLayoutPodcastCovers;

  /// Tooltip of the Media Library button that shows movies as a grid of covers under the category and playlist panels.
  ///
  /// In en, this message translates to:
  /// **'Category and playlist panels above the movie covers'**
  String get mlLayoutMovieCovers;

  /// Tooltip of the Media Library button that shows TV shows, their seasons and their episodes as grids of covers.
  ///
  /// In en, this message translates to:
  /// **'Covers of the shows, seasons and episodes'**
  String get mlLayoutShowCovers;

  /// Tooltip of the Media Library button that lists only the episodes of TV shows.
  ///
  /// In en, this message translates to:
  /// **'Episodes only'**
  String get mlLayoutEpisodes;

  /// Tooltip of the Media Library button that shows the tracks with no artists or albums beside them.
  ///
  /// In en, this message translates to:
  /// **'Tracks only'**
  String get mlLayoutTracks;

  /// Tooltip of the Media Library button that lists the artists and their albums beside the tracks.
  ///
  /// In en, this message translates to:
  /// **'Artists and albums beside the tracks'**
  String get mlLayoutBrowser;

  /// Tooltip of the Media Library button that shows the artists and the albums in two panels above the tracks.
  ///
  /// In en, this message translates to:
  /// **'Artist and album panels above the tracks'**
  String get mlLayoutSplit;

  /// Heading of the authors panel of the Media Library's audiobooks.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get mlColumnAuthor;

  /// Heading of the series panel of the Media Library's audiobooks.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get mlColumnSeries;

  /// Heading of the column with how many books an author or series has.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get mlColumnBooks;

  /// Heading of the column with how many parts (audio files) an author or book has.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get mlColumnParts;

  /// How many authors, in the first row of the authors panel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 author} other{{count} authors}}'**
  String mlAuthorCount(int count);

  /// How many series, in the first row of the series panel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 series} other{{count} series}}'**
  String mlSeriesCount(int count);

  /// How many books, in the first row of the books panel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 book} other{{count} books}}'**
  String mlBookCount(int count);

  /// Heading of the column with the year an album or book came out, in the Media Library's panels.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get mlColumnYear;

  /// Heading of the column with the podcast an episode belongs to, in the Media Library's podcast view when episodes of several podcasts are listed.
  ///
  /// In en, this message translates to:
  /// **'Podcast'**
  String get mlColumnPodcast;

  /// Heading of the episode title column in the Media Library's podcast view.
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get mlColumnEpisode;

  /// Heading of the release date column in the Media Library's podcast view.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get mlColumnPublished;

  /// Heading of the duration column in the Media Library's podcast view.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get mlColumnLength;

  /// Heading of the column with how much of an episode was played, in the Media Library's podcast view.
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get mlColumnProgress;

  /// Title of the window that asks whether to continue a podcast episode where it was left off.
  ///
  /// In en, this message translates to:
  /// **'Resume playback'**
  String get resumeTitle;

  /// Question of the resume window.
  ///
  /// In en, this message translates to:
  /// **'You stopped \"{title}\" at {position}. Resume from there?'**
  String resumePrompt(String title, String position);

  /// Button of the resume window that continues from where the episode was left off.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeContinue;

  /// Button of the resume window that plays the episode from its beginning.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get resumeStartOver;

  /// Heading of the Media Library's source tree section with the saved playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get mlSectionPlaylists;

  /// Heading of the Media Library's source tree section with the play statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get mlSectionStatistics;

  /// Media Library source that lists the songs played most often.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get mlStatsMostPlayed;

  /// Media Library source that lists the videos played most often.
  ///
  /// In en, this message translates to:
  /// **'Most played videos'**
  String get mlStatsMostPlayedVideos;

  /// Media Library source that lists the podcasts played most often (episodes counted per podcast).
  ///
  /// In en, this message translates to:
  /// **'Most played podcasts'**
  String get mlStatsMostPlayedPodcasts;

  /// Media Library source that lists the songs played last.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get mlStatsRecentlyPlayed;

  /// Shown in a play statistics list when nothing was played yet.
  ///
  /// In en, this message translates to:
  /// **'Nothing played yet.'**
  String get mlStatsNothingPlayed;

  /// How often an item was played, in a play statistics list. {count} is the number of plays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 play} other{{count} plays}}'**
  String mlStatsPlays(int count);

  /// Media Library source tree entry that creates an empty playlist.
  ///
  /// In en, this message translates to:
  /// **'New playlist...'**
  String get mlNewPlaylistRow;

  /// Title of the dialog that asks for the name of a new playlist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get mlNewPlaylistTitle;

  /// The name of a duplicated saved playlist. {name} is the original's name.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String mlPlaylistCopyName(String name);

  /// Saved playlist context menu entry that makes a copy of the playlist.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get mlMenuDuplicatePlaylist;

  /// Media Library context menu submenu that adds the selected tracks to a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get mlMenuAddToPlaylist;

  /// Entry of the Add to playlist submenu that asks for a name and saves the selected tracks as a new playlist.
  ///
  /// In en, this message translates to:
  /// **'New playlist...'**
  String get mlMenuNewPlaylist;

  /// Row under the saved playlists in the Media Library's source tree; saves the player's playlist as a new saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Save current playlist...'**
  String get mlSavePlaylistRow;

  /// Row under the saved playlists in the Media Library's source tree; reads playlist files into new saved playlists.
  ///
  /// In en, this message translates to:
  /// **'Import playlist...'**
  String get mlImportPlaylistRow;

  /// Title of the prompt for the name of a new saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Save playlist'**
  String get mlSavePlaylistTitle;

  /// Text of the prompt for the name of a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Name of the playlist:'**
  String get mlPlaylistNamePrompt;

  /// Name suggested for a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get mlPlaylistDefaultName;

  /// Title of the prompt for the new name of a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Rename playlist'**
  String get mlRenamePlaylistTitle;

  /// Context menu item of a saved playlist in the Media Library that renames it.
  ///
  /// In en, this message translates to:
  /// **'Rename...'**
  String get mlMenuRenamePlaylist;

  /// Context menu item of a saved playlist in the Media Library that writes it to a file.
  ///
  /// In en, this message translates to:
  /// **'Export...'**
  String get mlMenuExportPlaylist;

  /// Context menu item of a saved playlist in the Media Library that deletes it.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get mlMenuDeletePlaylist;

  /// Title of the file dialog that exports a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Export playlist'**
  String get mlExportPlaylistTitle;

  /// Title of the file dialog that picks playlist files to import.
  ///
  /// In en, this message translates to:
  /// **'Import playlists'**
  String get mlImportPlaylistTitle;

  /// Button in the Media Library that saves the player's playlist as a saved playlist.
  ///
  /// In en, this message translates to:
  /// **'Save current playlist'**
  String get mlSavePlaylistButton;

  /// Name of the source in the Media Library's source tree that holds the music added from this computer.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get mlSourceLocal;

  /// Heading of the Media Library's source tree section with the local source.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get mlSectionLocal;

  /// Heading of the Media Library's source tree section with the videos of each source.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get mlSectionVideos;

  /// Media Library source under Videos: the movies of the server {name}.
  ///
  /// In en, this message translates to:
  /// **'{name} - Movies'**
  String mlSourceMovies(String name);

  /// Media Library source under Videos: the TV shows of the server {name}.
  ///
  /// In en, this message translates to:
  /// **'{name} - TV shows'**
  String mlSourceShows(String name);

  /// Heading of the panel of TV shows in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get mlColumnShow;

  /// Heading of the panel of seasons in the Media Library.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get mlColumnSeason;

  /// Heading of the count of a show's seasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get mlColumnSeasons;

  /// Heading of the count of a season's episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get mlColumnEpisodes;

  /// How many TV shows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 show} other{{count} shows}}'**
  String mlShowCount(int count);

  /// How many seasons.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 season} other{{count} seasons}}'**
  String mlSeasonCount(int count);

  /// Name of the source in the Media Library's Videos section that lists the videos of all sources.
  ///
  /// In en, this message translates to:
  /// **'All videos'**
  String get mlSourceAllVideos;

  /// Heading of the Media Library's source tree section with the remote sources that were added.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get mlSectionRemote;

  /// Heading of the Media Library's source tree section with the podcasts that were added.
  ///
  /// In en, this message translates to:
  /// **'Podcasts'**
  String get mlSectionPodcasts;

  /// Shown under a Media Library source tree section that has no sources yet.
  ///
  /// In en, this message translates to:
  /// **'None added'**
  String get mlSectionNoSources;

  /// Message in the Media Library's track pane when the selected source has no tracks to list.
  ///
  /// In en, this message translates to:
  /// **'This source can\'t be browsed yet.'**
  String get mlSourceUnavailable;

  /// Message shown when the library has no tracks yet.
  ///
  /// In en, this message translates to:
  /// **'The library is empty. Click Add media... to add folders.'**
  String get mlEmpty;

  /// Status shown while the library scans folders. {dots} is an animated trailing dot string, {count} the files found so far.
  ///
  /// In en, this message translates to:
  /// **'Scanning{dots} {count} files'**
  String mlScanning(int count, String dots);

  /// Status showing how many tracks the library list shows. {count} is the number of tracks.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String mlTrackCount(int count);

  /// Media Library context menu entry that replaces the playlist with the selected tracks and plays them. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Play item} other{Play items}}'**
  String mlMenuPlay(int count);

  /// Media Library context menu entry that appends the selected tracks to the playlist. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Enqueue item} other{Enqueue items}}'**
  String mlMenuEnqueue(int count);

  /// Media Library context menu entry that removes the selected tracks from the library without deleting files. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Remove item from Library} other{Remove items from Library}}'**
  String mlMenuRemove(int count);

  /// Media Library context menu entry that marks the selected podcast episodes as played.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Mark episode as played} other{Mark episodes as played}}'**
  String mlMenuMarkPlayed(int count);

  /// Media Library context menu entry that marks the selected podcast episodes as not played.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Mark episode as unplayed} other{Mark episodes as unplayed}}'**
  String mlMenuMarkUnplayed(int count);

  /// Media Library context menu entry that marks the selected audiobooks as finished.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Mark book as finished} other{Mark books as finished}}'**
  String mlMenuMarkBookPlayed(int count);

  /// Media Library context menu entry that marks the selected audiobooks as not started.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Mark book as not started} other{Mark books as not started}}'**
  String mlMenuMarkBookUnplayed(int count);

  /// Media Library context menu entry that loads an audiobook server's books again.
  ///
  /// In en, this message translates to:
  /// **'Refresh audiobooks'**
  String get mlMenuRefreshBooks;

  /// Media Library context menu entry that loads a podcast's episodes from its server again.
  ///
  /// In en, this message translates to:
  /// **'Refresh podcast'**
  String get mlMenuRefreshPodcast;

  /// Media Library context menu entry that bookmarks the selected tracks. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Bookmark item} other{Bookmark items}}'**
  String mlMenuBookmark(int count);

  /// Media Library context menu entry that opens the rating submenu for the selected tracks. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Rate item} other{Rate items}}'**
  String mlMenuRate(int count);

  /// Media Library context menu entry that shows the selected tracks in the system file manager. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Explore item folder} other{Explore items folders}}'**
  String mlMenuExplore(int count);

  /// Media Library context menu submenu whose entries enqueue a playlist built from the selected tracks.
  ///
  /// In en, this message translates to:
  /// **'Generate playlist'**
  String get mlMenuGenerate;

  /// Entry of the Generate playlist submenu: tracks by the artists of the selected tracks.
  ///
  /// In en, this message translates to:
  /// **'More by the same artists'**
  String get mlGenerateSameArtist;

  /// Entry of the Generate playlist submenu: tracks of the albums of the selected tracks.
  ///
  /// In en, this message translates to:
  /// **'From the same albums'**
  String get mlGenerateSameAlbum;

  /// Entry of the Generate playlist submenu: tracks in the genres of the selected tracks.
  ///
  /// In en, this message translates to:
  /// **'In the same genres'**
  String get mlGenerateSameGenre;

  /// Entry of the Generate playlist submenu: tracks that share an artist, a genre or an album with the selected tracks, the closest first.
  ///
  /// In en, this message translates to:
  /// **'Similar (artist, genre or album)'**
  String get mlGenerateSimilar;

  /// Media Library context menu entry that opens the metadata editor for the selected tracks. The trailing ellipsis marks that a dialog opens. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Edit metadata for item...} other{Edit metadata for items...}}'**
  String mlMenuEditMetadata(int count);

  /// Media Library context menu entry that opens the file info dialog for each selected track in turn. The trailing ellipsis marks that a dialog opens. {count} is how many tracks are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{View file info...} other{View file info for items...}}'**
  String mlMenuFileInfo(int count);

  /// Part of the Media Library status line: how many artists are selected, shown before the album and track counts, e.g. "1 artist, 3 albums, 16 tracks". {count} is the number of selected artists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 artist} other{{count} artists}}'**
  String mlArtistCount(int count);

  /// Part of the Media Library status line: how many albums are selected, e.g. "1 artist, 3 albums, 16 tracks". {count} is the number of selected albums.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 album} other{{count} albums}}'**
  String mlAlbumCount(int count);

  /// Part of the Media Library status line: how many tracks are selected, or listed when only an artist or album is selected, e.g. "1 artist, 3 albums, 16 tracks". {count} is the number of tracks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String mlSelectedTrackCount(int count);

  /// Media Library menu entry that removes every track from the library.
  ///
  /// In en, this message translates to:
  /// **'Clear Library'**
  String get mlClearLibrary;

  /// Menu entry that opens the Media Library window.
  ///
  /// In en, this message translates to:
  /// **'Open Media Library'**
  String get mlOpenLibrary;

  /// Menu entry that closes the Media Library window.
  ///
  /// In en, this message translates to:
  /// **'Close Media Library'**
  String get mlCloseLibrary;

  /// Menu entry that opens the Media Library preferences. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Media Library Preferences...'**
  String get mlPreferences;

  /// Menu entry that starts or stops the selected visualization plug-in.
  ///
  /// In en, this message translates to:
  /// **'Start/Stop plug-in'**
  String get startStopPlugin;

  /// Menu entry that opens the selected plug-in's configuration. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Configure plug-in...'**
  String get configurePlugin;

  /// Menu entry that chooses the visualization plug-in. The trailing ellipsis marks that a window opens.
  ///
  /// In en, this message translates to:
  /// **'Select plug-in...'**
  String get selectPlugin;

  /// Name of the Main Window in the Windows menu.
  ///
  /// In en, this message translates to:
  /// **'Main Window'**
  String get mainWindow;

  /// Name of the Media Library window in the Windows menu.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get mediaLibrary;

  /// Generic name for a window a modern skin defines of its own.
  ///
  /// In en, this message translates to:
  /// **'Skin Window'**
  String get skinWindow;

  /// Menu entry that opens the active skin's own settings window.
  ///
  /// In en, this message translates to:
  /// **'Skin Settings…'**
  String get skinSettings;

  /// Heading of the windows the active modern skin defines of its own, in the Options menu and Preferences.
  ///
  /// In en, this message translates to:
  /// **'Skin Windows'**
  String get skinWindows;

  /// Explains the list of the skin's own windows in Skin Settings.
  ///
  /// In en, this message translates to:
  /// **'Panels this skin brings of its own, such as its color and opacity settings.'**
  String get skinWindowsHint;

  /// Shown instead of the skin's windows while another skin is on.
  ///
  /// In en, this message translates to:
  /// **'Put this skin on to open the panels it brings of its own.'**
  String get skinWindowsHintInactive;

  /// Tab of Skin Settings that lists the skin's own windows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get modernSettingsWindows;

  /// Heading of the switches a skin's own windows carry, listed in Skin Settings.
  ///
  /// In en, this message translates to:
  /// **'Skin options'**
  String get modernSettingsSkinOptions;

  /// Name of the Thinger window, the classic player combined browser, in the Windows menu.
  ///
  /// In en, this message translates to:
  /// **'Thinger'**
  String get thinger;

  /// Native window title of the Equalizer window.
  ///
  /// In en, this message translates to:
  /// **'Amped Equalizer'**
  String get ampedEqualizerWindow;

  /// Native window title of the Playlist Editor window.
  ///
  /// In en, this message translates to:
  /// **'Amped Playlist Editor'**
  String get ampedPlaylistWindow;

  /// Native window title of the Video window.
  ///
  /// In en, this message translates to:
  /// **'Amped Video'**
  String get ampedVideoWindow;

  /// Native window title of the Media Library window.
  ///
  /// In en, this message translates to:
  /// **'Amped Library'**
  String get ampedLibraryWindow;

  /// Native window title of the Thinger window.
  ///
  /// In en, this message translates to:
  /// **'Amped Thinger'**
  String get ampedThingerWindow;

  /// Native window title of the Visualization window.
  ///
  /// In en, this message translates to:
  /// **'Amped Visualization'**
  String get ampedVisualizationWindow;

  /// Native window title of the Album Art window.
  ///
  /// In en, this message translates to:
  /// **'Amped Album Art'**
  String get ampedAlbumArtWindow;

  /// Name of the Album Art window in menus.
  ///
  /// In en, this message translates to:
  /// **'Album Art'**
  String get albumArt;

  /// Album Art menu entry that reloads the artwork for the current track.
  ///
  /// In en, this message translates to:
  /// **'Refresh album art'**
  String get refreshAlbumArt;

  /// Album Art menu entry that downloads artwork for the current track.
  ///
  /// In en, this message translates to:
  /// **'Get album art'**
  String get getAlbumArt;

  /// Album Art menu entry that opens the folder holding the artwork in the file manager.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openAlbumArtFolder;

  /// Album Art option that keeps the window square-proportioned while it is resized.
  ///
  /// In en, this message translates to:
  /// **'Lock aspect ratio'**
  String get lockAspectRatio;

  /// Title of the equalizer presets dialog.
  ///
  /// In en, this message translates to:
  /// **'Amped EQ Presets'**
  String get ampedPresetsTitle;

  /// Title of the equalizer auto-load presets dialog.
  ///
  /// In en, this message translates to:
  /// **'Amped EQ Auto-load Presets'**
  String get ampedAutoLoadPresetsTitle;

  /// Title of the Preferences window.
  ///
  /// In en, this message translates to:
  /// **'Amped Preferences'**
  String get ampedPreferencesTitle;

  /// Title of the window that announces a new release of Amped.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateTitle;

  /// Heading of the update window.
  ///
  /// In en, this message translates to:
  /// **'Amped {version} is available.'**
  String updateAvailable(String version);

  /// Button of the update window that dismisses it.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get updateIgnore;

  /// Button of the update window that opens the page to download the new release from.
  ///
  /// In en, this message translates to:
  /// **'Go to downloads'**
  String get updateDownload;

  /// Title of the About dialog.
  ///
  /// In en, this message translates to:
  /// **'About Amped'**
  String get aboutAmpedTitle;

  /// Title of the visualization plug-in configuration dialog.
  ///
  /// In en, this message translates to:
  /// **'Configure Visualization'**
  String get configureVisualizationTitle;

  /// Placeholder shown on a Preferences page that is not built yet. {page} is the page name.
  ///
  /// In en, this message translates to:
  /// **'{page} settings are not available yet.'**
  String settingsUnavailable(String page);

  /// Preferences page for general options.
  ///
  /// In en, this message translates to:
  /// **'General Preferences'**
  String get generalPreferences;

  /// Preferences page that chooses which file types open with Amped.
  ///
  /// In en, this message translates to:
  /// **'File Types'**
  String get fileTypes;

  /// Preferences page and generic name for the playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// Preferences page for how track titles are formatted.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get titles;

  /// Preferences page for internet radio station information.
  ///
  /// In en, this message translates to:
  /// **'Station Info'**
  String get stationInfo;

  /// Preferences page for the interface language.
  ///
  /// In en, this message translates to:
  /// **'Localization'**
  String get localization;

  /// Tab of the skins preferences that lists installed skins.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get skinsInstalled;

  /// Tab of the skins preferences that shows the online skin browser.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get skinsOnline;

  /// Tab of the skins preferences for the active modern skin's options and color themes.
  ///
  /// In en, this message translates to:
  /// **'Skin Settings'**
  String get modernSettings;

  /// Preferences section that lists plug-ins.
  ///
  /// In en, this message translates to:
  /// **'Plug-ins'**
  String get plugins;

  /// Plug-in category: input plug-ins that decode audio formats.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get input;

  /// Plug-in category: output plug-ins that play audio.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get output;

  /// Plug-in category: DSP and effect plug-ins that change the audio signal.
  ///
  /// In en, this message translates to:
  /// **'DSP/Effect'**
  String get dspEffect;

  /// Plug-in category: general purpose plug-ins.
  ///
  /// In en, this message translates to:
  /// **'General Purpose'**
  String get generalPurpose;

  /// Label that marks a skin as a modern (Wasabi 3 and 5, Wasabi) skin.
  ///
  /// In en, this message translates to:
  /// **'Modern skin'**
  String get modernSkin;

  /// Label that marks a skin as an original bitmap skin.
  ///
  /// In en, this message translates to:
  /// **'Classic skin'**
  String get classicSkin;

  /// Label that marks a skin as one made for Bamp and converted to classic bitmaps.
  ///
  /// In en, this message translates to:
  /// **'Bamp skin'**
  String get bampSkin;

  /// Label that marks a skin as one made for Audacious and converted to classic bitmaps.
  ///
  /// In en, this message translates to:
  /// **'Audacious skin'**
  String get audaciousSkin;

  /// Instructions for installing a skin archive.
  ///
  /// In en, this message translates to:
  /// **'You can also open a .wsz or .wal file with Amped, or drop it on the dock icon or any Amped window.'**
  String get skinInstallHint;

  /// Button that opens a chooser to add an item. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Add...'**
  String get addEllipsis;

  /// Heading of the list of visualization plug-ins.
  ///
  /// In en, this message translates to:
  /// **'Visualization plug-ins'**
  String get visualizationPlugins;

  /// Button that opens the configuration of the active plug-in.
  ///
  /// In en, this message translates to:
  /// **'Configure active plug-in'**
  String get configureActivePlugin;

  /// Button that starts the selected plug-in.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// Tagline shown under the app name in the About dialog.
  ///
  /// In en, this message translates to:
  /// **'Crank it up.'**
  String get ampedTagline;

  /// Button in the About dialog that opens a new issue on the issue tracker, with the log filled in.
  ///
  /// In en, this message translates to:
  /// **'Report a bug'**
  String get aboutReportBug;

  /// Shown in the About dialog after Report a bug, where the log went.
  ///
  /// In en, this message translates to:
  /// **'The issue page is open, with the latest log lines filled in. The whole log is on your clipboard: paste it into the report if it was cut short. Nothing is sent until you submit it there.'**
  String get aboutReportBugNote;

  /// Shown in the About dialog when the browser did not open for Report a bug.
  ///
  /// In en, this message translates to:
  /// **'The issue page could not be opened. The log is on your clipboard.'**
  String get aboutReportBugFailed;

  /// macOS application menu entry that opens the About dialog.
  ///
  /// In en, this message translates to:
  /// **'About Amped'**
  String get macAboutMenu;

  /// macOS application menu entry that hides the app.
  ///
  /// In en, this message translates to:
  /// **'Hide Amped'**
  String get macHideMenu;

  /// macOS application menu entry that quits the app.
  ///
  /// In en, this message translates to:
  /// **'Quit Amped'**
  String get macQuitMenu;

  /// Confirmation button of an open dialog.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openAction;

  /// Button that closes a window or dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Message shown when there are no equalizer presets.
  ///
  /// In en, this message translates to:
  /// **'No presets'**
  String get noPresets;

  /// Label of the field for naming an equalizer preset.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get presetName;

  /// Name of the built-in equalizer preset that has no adjustment.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultPreset;

  /// Validation message shown when saving a preset without a name.
  ///
  /// In en, this message translates to:
  /// **'Enter a preset name.'**
  String get enterPresetName;

  /// Message shown when a plug-in has no configuration dialog.
  ///
  /// In en, this message translates to:
  /// **'This plug-in has no configuration.'**
  String get pluginNoConfiguration;

  /// Confirmation button of a dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Button that restores settings to their default values.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get defaults;

  /// Label of a color setting.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// Label of the red channel of a color.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// Label of the green channel of a color.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// Label of the blue channel of a color.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// Name of the built-in "Classical" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get eqPresetClassical;

  /// Name of the built-in "Club" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Club'**
  String get eqPresetClub;

  /// Name of the built-in "Dance" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Dance'**
  String get eqPresetDance;

  /// Name of the built-in "Flat" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get eqPresetFlat;

  /// Name of the built-in "Laptop speakers/headphones" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Laptop speakers/headphones'**
  String get eqPresetLaptop;

  /// Name of the built-in "Large hall" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Large hall'**
  String get eqPresetLargeHall;

  /// Name of the built-in "Party" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get eqPresetParty;

  /// Name of the built-in "Pop" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get eqPresetPop;

  /// Name of the built-in "Reggae" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Reggae'**
  String get eqPresetReggae;

  /// Name of the built-in "Rock" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get eqPresetRock;

  /// Name of the built-in "Soft" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get eqPresetSoft;

  /// Name of the built-in "Ska" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Ska'**
  String get eqPresetSka;

  /// Name of the built-in "Full Bass" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Full Bass'**
  String get eqPresetFullBass;

  /// Name of the built-in "Soft Rock" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Soft Rock'**
  String get eqPresetSoftRock;

  /// Name of the built-in "Full Treble" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Full Treble'**
  String get eqPresetFullTreble;

  /// Name of the built-in "Full Bass & Treble" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Full Bass & Treble'**
  String get eqPresetFullBassTreble;

  /// Name of the built-in "Live" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get eqPresetLive;

  /// Name of the built-in "Techno" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Techno'**
  String get eqPresetTechno;

  /// Name of the built-in "Hall" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Hall'**
  String get eqPresetHall;

  /// Name of the built-in "Room" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get eqPresetRoom;

  /// Name of the built-in "Arena" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Arena'**
  String get eqPresetArena;

  /// Name of the built-in "Studio" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get eqPresetStudio;

  /// Name of the built-in "Stadium" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Stadium'**
  String get eqPresetStadium;

  /// Name of the built-in "Space" equalizer preset, as in the classic player's preset list.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get eqPresetSpace;

  /// Title of the dialog for choosing skin files to install.
  ///
  /// In en, this message translates to:
  /// **'Add Skins'**
  String get addSkinsTitle;

  /// File type filter in file dialogs for audio files.
  ///
  /// In en, this message translates to:
  /// **'Audio files'**
  String get audioFiles;

  /// File type filter in file dialogs for video files.
  ///
  /// In en, this message translates to:
  /// **'Video files'**
  String get videoFiles;

  /// Video preference: open the video window automatically when a video starts playing.
  ///
  /// In en, this message translates to:
  /// **'Show the video window when a video starts'**
  String get videoAutoOpen;

  /// Video preference: close the video window automatically when the video stops.
  ///
  /// In en, this message translates to:
  /// **'Hide the video window when the video stops'**
  String get videoAutoClose;

  /// Video preference: stop playback when the video window is closed.
  ///
  /// In en, this message translates to:
  /// **'Stop playback when the video window is closed'**
  String get videoStopOnClose;

  /// Hint under the stop-on-close video preference explaining the Shift shortcut.
  ///
  /// In en, this message translates to:
  /// **'Hold Shift while closing the window to keep playing.'**
  String get videoStopOnCloseHint;

  /// File type filter in file dialogs for playlist files.
  ///
  /// In en, this message translates to:
  /// **'Playlist files'**
  String get playlistFiles;

  /// File type filter in file dialogs that matches every file. The pattern in parentheses is literal.
  ///
  /// In en, this message translates to:
  /// **'All files (*.*)'**
  String get allFiles;

  /// File type filter in file dialogs that matches every format Amped can play.
  ///
  /// In en, this message translates to:
  /// **'All supported types'**
  String get allSupportedTypes;

  /// File type filter in file dialogs for skin archives. The patterns in parentheses are literal.
  ///
  /// In en, this message translates to:
  /// **'skins (*.wsz;*.wal)'**
  String get skinFiles;

  /// Title of the dialog for choosing files to open.
  ///
  /// In en, this message translates to:
  /// **'Open file(s)'**
  String get openFilesTitle;

  /// Title of the dialog for choosing a folder to open.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolderTitle;

  /// Title of the dialog for entering a URL to open.
  ///
  /// In en, this message translates to:
  /// **'Open URL'**
  String get openUrlTitle;

  /// Title of the dialog for choosing files to add to the playlist.
  ///
  /// In en, this message translates to:
  /// **'Add file(s) to playlist'**
  String get addFilesToPlaylistTitle;

  /// Title of the dialog for choosing a folder to add to the playlist.
  ///
  /// In en, this message translates to:
  /// **'Add folder to playlist'**
  String get addFolderToPlaylistTitle;

  /// Title of the dialog for entering a URL to add to the playlist.
  ///
  /// In en, this message translates to:
  /// **'Add URL to playlist'**
  String get addUrlToPlaylistTitle;

  /// Title of the dialog for choosing a playlist file to load.
  ///
  /// In en, this message translates to:
  /// **'Load playlist'**
  String get loadPlaylistTitle;

  /// Save dialog file type for M3U playlists. The pattern in parentheses is literal.
  ///
  /// In en, this message translates to:
  /// **'M3U Playlist (*.m3u)'**
  String get m3uPlaylistType;

  /// Save dialog file type for PLS playlists. The pattern in parentheses is literal.
  ///
  /// In en, this message translates to:
  /// **'PLS Playlist (*.pls)'**
  String get plsPlaylistType;

  /// Save dialog file type for M3U8 (UTF-8 M3U) playlists. The pattern in parentheses is literal.
  ///
  /// In en, this message translates to:
  /// **'M3U8 Playlist (*.m3u8)'**
  String get m3u8PlaylistType;

  /// Title of the dialog for saving the playlist to a file.
  ///
  /// In en, this message translates to:
  /// **'Save playlist'**
  String get savePlaylistTitle;

  /// File type filter in file dialogs for equalizer preset files. The pattern in parentheses is literal.
  ///
  /// In en, this message translates to:
  /// **'EQ files (*.eqf)'**
  String get eqFiles;

  /// Title of the dialog for choosing an equalizer preset file to load.
  ///
  /// In en, this message translates to:
  /// **'Load EQ file'**
  String get loadEqFileTitle;

  /// Title of the dialog for saving equalizer presets to a file.
  ///
  /// In en, this message translates to:
  /// **'Save EQ file'**
  String get saveEqFileTitle;

  /// Label of the file type selector in save dialogs.
  ///
  /// In en, this message translates to:
  /// **'Save as type:'**
  String get saveAsTypeLabel;

  /// Prompt above the URL field in the open URL dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter the URL of a file to play:'**
  String get enterUrlPrompt;

  /// Title of the Jump to file dialog, which finds a track in the playlist by typing.
  ///
  /// In en, this message translates to:
  /// **'Jump to file'**
  String get jumpToFileTitle;

  /// Placeholder in the search field of the Jump to file dialog.
  ///
  /// In en, this message translates to:
  /// **'Search the playlist'**
  String get jumpToFileHint;

  /// Message shown in Jump to file when nothing matches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get jumpToFileNoMatches;

  /// Title of the file info dialog.
  ///
  /// In en, this message translates to:
  /// **'File Info'**
  String get fileInfoTitle;

  /// Tab of the file info dialog with the common tags.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get basicInfo;

  /// Tab of the file info dialog with raw tag details.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedTab;

  /// Group heading in the file info dialog for tags.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get metadataGroup;

  /// Group heading in the file info dialog for technical format details.
  ///
  /// In en, this message translates to:
  /// **'Format Info'**
  String get formatInfoGroup;

  /// Group heading in the file info dialog for ReplayGain loudness values.
  ///
  /// In en, this message translates to:
  /// **'Replay Gain'**
  String get replayGainGroup;

  /// Label of the track number field. The number sign stands for 'number'.
  ///
  /// In en, this message translates to:
  /// **'Track #'**
  String get tagTrack;

  /// Label of the disc number field. The number sign stands for 'number'.
  ///
  /// In en, this message translates to:
  /// **'Disc #'**
  String get tagDisc;

  /// Label of the beats-per-minute field.
  ///
  /// In en, this message translates to:
  /// **'BPM'**
  String get tagBpm;

  /// Label of the track title field.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get tagTitle;

  /// Label of the artist field.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get tagArtist;

  /// Label of the album field.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get tagAlbum;

  /// Label of the album artist field.
  ///
  /// In en, this message translates to:
  /// **'Album Artist'**
  String get tagAlbumArtist;

  /// Label of the release year field.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get tagYear;

  /// Label of the genre field.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get tagGenre;

  /// Label of the comment field.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get tagComment;

  /// Label of the composer field.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get tagComposer;

  /// Label of the publisher field.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get tagPublisher;

  /// Label of the field holding the file's AcoustID audio fingerprint.
  ///
  /// In en, this message translates to:
  /// **'AcoustID Fingerprint'**
  String get tagAcoustIdFingerprint;

  /// Tooltip of the button that opens the list of standard genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genreListTooltip;

  /// Name of the MP3 container shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'MPEG audio'**
  String get formatMp3;

  /// Name of the FLAC format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'FLAC'**
  String get formatFlac;

  /// Name of the Ogg Vorbis format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'Ogg Vorbis'**
  String get formatOggVorbis;

  /// Name of the Ogg Opus format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'Ogg Opus'**
  String get formatOggOpus;

  /// Name of the Ogg Speex format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'Ogg Speex'**
  String get formatOggSpeex;

  /// Name of the Ogg FLAC format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'Ogg FLAC'**
  String get formatOggFlac;

  /// Name shown in the file info format details for Monkey's Audio, Musepack, WavPack, TTA and TAK files, whose tags are APEv2.
  ///
  /// In en, this message translates to:
  /// **'APE-tagged audio'**
  String get formatApeTagged;

  /// Name of the WAV format shown in the file info format details.
  ///
  /// In en, this message translates to:
  /// **'WAV'**
  String get formatWav;

  /// Shown in the file info format details when the file's format is not recognized.
  ///
  /// In en, this message translates to:
  /// **'Unknown format'**
  String get formatUnknown;

  /// Format details line listing the tag formats in the file. {tags} is a comma-separated list such as ID3v2.
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}'**
  String formatInfoTags(String tags);

  /// Format details line shown when the file has no tags.
  ///
  /// In en, this message translates to:
  /// **'Tags: none'**
  String get formatInfoNoTags;

  /// Format details line with the file size. {bytes} is the size in bytes.
  ///
  /// In en, this message translates to:
  /// **'Size: {bytes} bytes'**
  String formatInfoSize(int bytes);

  /// Format details line with the track length. {seconds} is the length in seconds.
  ///
  /// In en, this message translates to:
  /// **'Length: {seconds} seconds'**
  String formatInfoLength(int seconds);

  /// Format details line with the bitrate. {kbps} is kilobits per second.
  ///
  /// In en, this message translates to:
  /// **'Bitrate: {kbps} kbps'**
  String formatInfoBitrate(int kbps);

  /// Format details line with the sample rate. {hz} is hertz.
  ///
  /// In en, this message translates to:
  /// **'Sample rate: {hz} Hz'**
  String formatInfoSampleRate(int hz);

  /// Format details value for a one-channel file.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get channelsMono;

  /// Format details value for a two-channel file.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get channelsStereo;

  /// Format details value for a file with another number of channels. {count} is the channel count.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String channelsCount(int count);

  /// Format details line with the track's ReplayGain value. {gain} is the formatted gain, such as -6.2 dB.
  ///
  /// In en, this message translates to:
  /// **'Track gain: {gain}'**
  String replayGainTrack(String gain);

  /// Format details line with the album's ReplayGain value. {gain} is the formatted gain, such as -6.2 dB.
  ///
  /// In en, this message translates to:
  /// **'Album gain: {gain}'**
  String replayGainAlbum(String gain);

  /// Error shown when a file's tags can't be read. {error} is the technical reason.
  ///
  /// In en, this message translates to:
  /// **'Can\'t read this file\'s tags: {error}'**
  String fileInfoReadError(String error);

  /// Error shown when tags can't be saved to a file. {error} is the technical reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the tags: {error}'**
  String fileInfoWriteError(String error);

  /// Message shown in the advanced tab when the file has no tags to list.
  ///
  /// In en, this message translates to:
  /// **'This file has no tags.'**
  String get fileInfoNoRawTags;

  /// Tab of the file info dialog for cover art.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get artworkTab;

  /// Tab of the file info dialog for the ID3v1 tag. ID3v1 is a format name.
  ///
  /// In en, this message translates to:
  /// **'ID3v1'**
  String get id3v1Tab;

  /// Tab of the file info dialog for the ID3v2 tag. ID3v2 is a format name.
  ///
  /// In en, this message translates to:
  /// **'ID3v2'**
  String get id3v2Tab;

  /// Checkbox that writes an ID3v1 tag into the file when saving.
  ///
  /// In en, this message translates to:
  /// **'Include ID3v1 tag in file'**
  String get includeId3v1;

  /// Checkbox that writes an ID3v2 tag into the file when saving.
  ///
  /// In en, this message translates to:
  /// **'Include ID3v2 tag in file'**
  String get includeId3v2;

  /// Button that copies the current fields into the ID3v1 tag.
  ///
  /// In en, this message translates to:
  /// **'Copy to ID3v1'**
  String get copyToId3v1;

  /// Button that copies the current fields into the ID3v2 tag.
  ///
  /// In en, this message translates to:
  /// **'Copy to ID3v2'**
  String get copyToId3v2;

  /// Group heading of the artwork editor in the file info dialog.
  ///
  /// In en, this message translates to:
  /// **'Artwork editor'**
  String get artworkEditorGroup;

  /// Label of the selector that chooses what kind of picture an artwork is.
  ///
  /// In en, this message translates to:
  /// **'Artwork type:'**
  String get artworkTypeLabel;

  /// Button that loads an image file as artwork. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Load Artwork...'**
  String get loadArtwork;

  /// Button that opens a chooser to pick an image. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Choose...'**
  String get uploadArtwork;

  /// Button that downloads artwork for the file.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadArtwork;

  /// Notice shown when the file format can't hold artwork, so the cover is stored in Amped's own database instead.
  ///
  /// In en, this message translates to:
  /// **'This file can\'t hold artwork, so the cover was kept in Amped\'s database.'**
  String get artworkStoredInDatabase;

  /// Message shown when an artwork search finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No artwork found. Check the Artist and Album fields.'**
  String get artworkNotFound;

  /// Button that replaces the current artwork. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Change...'**
  String get changeArtwork;

  /// Button that saves the artwork to an image file. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get saveArtworkAs;

  /// Button that removes the artwork.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteArtwork;

  /// Placeholder shown where artwork would be when there is none.
  ///
  /// In en, this message translates to:
  /// **'(no image)'**
  String get noImage;

  /// Details line under an artwork. {type} is the artwork type, {width} and {height} are pixel sizes, {origin} says where it is stored and {format} is the image format.
  ///
  /// In en, this message translates to:
  /// **'{type}: {width}x{height}, origin: {origin}, type: {format}'**
  String artworkDetails(
    String type,
    String width,
    String height,
    String origin,
    String format,
  );

  /// Artwork origin value meaning the picture is embedded in the file.
  ///
  /// In en, this message translates to:
  /// **'embedded'**
  String get artworkOriginEmbedded;

  /// Shown in artwork details when the image format is unknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknownMime;

  /// File type filter in file dialogs for image files.
  ///
  /// In en, this message translates to:
  /// **'Image Files'**
  String get imageFiles;

  /// Title of the dialog for choosing an artwork image.
  ///
  /// In en, this message translates to:
  /// **'Load Artwork'**
  String get loadArtworkTitle;

  /// Title of the dialog for saving artwork to an image file.
  ///
  /// In en, this message translates to:
  /// **'Save Artwork'**
  String get saveArtworkTitle;

  /// File type filter in file dialogs for JPEG images.
  ///
  /// In en, this message translates to:
  /// **'JPEG Files'**
  String get jpegFiles;

  /// File type filter in file dialogs for PNG images.
  ///
  /// In en, this message translates to:
  /// **'PNG Files'**
  String get pngFiles;

  /// File type filter in file dialogs for GIF images.
  ///
  /// In en, this message translates to:
  /// **'GIF Files'**
  String get gifFiles;

  /// File type filter in file dialogs for BMP images.
  ///
  /// In en, this message translates to:
  /// **'BMP Files'**
  String get bmpFiles;

  /// File type filter in file dialogs for WebP images.
  ///
  /// In en, this message translates to:
  /// **'WebP Files'**
  String get webpFiles;

  /// Error shown when the chosen file isn't an image Amped can embed.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t an image amped can embed.'**
  String get artworkNotAnImage;

  /// Error shown when the file's format can't store pictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures can\'t be stored in this file.'**
  String get artworkNotEditable;

  /// Error shown when a file's pictures can't be read. {error} is the technical reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the pictures: {error}'**
  String fileInfoPicturesReadError(String error);

  /// Artwork type choice: other. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get artworkTypeOther;

  /// Artwork type choice: file icon, a 32x32 PNG. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'File icon (32x32 PNG)'**
  String get artworkTypeFileIcon;

  /// Artwork type choice: other file icon. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Other file icon'**
  String get artworkTypeOtherFileIcon;

  /// Artwork type choice: front cover. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Front cover'**
  String get artworkTypeFrontCover;

  /// Artwork type choice: back cover. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Back cover'**
  String get artworkTypeBackCover;

  /// Artwork type choice: leaflet page. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Leaflet page'**
  String get artworkTypeLeaflet;

  /// Artwork type choice: media label side. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Media (label side)'**
  String get artworkTypeMedia;

  /// Artwork type choice: lead artist. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Lead artist'**
  String get artworkTypeLeadArtist;

  /// Artwork type choice: artist. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artworkTypeArtist;

  /// Artwork type choice: conductor. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Conductor'**
  String get artworkTypeConductor;

  /// Artwork type choice: band. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get artworkTypeBand;

  /// Artwork type choice: composer. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get artworkTypeComposer;

  /// Artwork type choice: lyricist. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Lyricist'**
  String get artworkTypeLyricist;

  /// Artwork type choice: recording location. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Recording location'**
  String get artworkTypeRecordingLocation;

  /// Artwork type choice: taken during recording. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'During recording'**
  String get artworkTypeDuringRecording;

  /// Artwork type choice: taken during performance. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'During performance'**
  String get artworkTypeDuringPerformance;

  /// Artwork type choice: video screen capture. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Video screen capture'**
  String get artworkTypeVideoCapture;

  /// Artwork type choice: a bright coloured fish (an ID3 standard picture type). Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'A bright coloured fish'**
  String get artworkTypeBrightFish;

  /// Artwork type choice: illustration. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Illustration'**
  String get artworkTypeIllustration;

  /// Artwork type choice: band logo. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Band logo'**
  String get artworkTypeBandLogo;

  /// Artwork type choice: publisher logo. Matches the ID3v2 picture types.
  ///
  /// In en, this message translates to:
  /// **'Publisher logo'**
  String get artworkTypePublisherLogo;

  /// Tooltip on a field that the file's format can't store.
  ///
  /// In en, this message translates to:
  /// **'This field can\'t be stored in this file type.'**
  String get fileInfoNotEditable;

  /// Column heading for the tag name in the advanced tag list.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tagNameColumn;

  /// Column heading for the tag value in the advanced tag list.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get tagValueColumn;

  /// Title of the dialog that edits tags of the selected files.
  ///
  /// In en, this message translates to:
  /// **'Edit Item Metadata'**
  String get editMetadataTitle;

  /// Count of items selected in the metadata editor. {count} is the number of items; singular and plural forms are provided.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item selected} other{{count} items selected}}'**
  String itemsSelected(int count);

  /// Warning in the metadata editor about files that can't be read. {count} is the number of files.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file can\'t be read and will be left alone.} other{{count} files can\'t be read and will be left alone.}}'**
  String filesUnreadableSkipped(int count);

  /// Progress text while tags are saved to files. {done} of {total} files are done.
  ///
  /// In en, this message translates to:
  /// **'Updating {done} of {total}...'**
  String updatingFiles(int done, int total);

  /// Button that saves the edited fields to the selected files.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateAction;

  /// Notice that the selected files can't store a field.
  ///
  /// In en, this message translates to:
  /// **'These files can\'t store this field'**
  String get fieldNotStorable;

  /// Hint on a field whose value differs among the selected files. {count} is the number of distinct values.
  ///
  /// In en, this message translates to:
  /// **'{count} different values, kept unless ticked'**
  String fieldMultipleValues(int count);

  /// Hint on a field that is filled in only for some selected files. {filled} of {total} files have a value.
  ///
  /// In en, this message translates to:
  /// **'Set in {filled} of {total} files'**
  String fieldSetInSome(int filled, int total);

  /// Hint on a field that some selected files can't store. {count} is the number of files; singular and plural forms are provided.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Not saved to 1 file that can\'t store it} other{Not saved to {count} files that can\'t store it}}'**
  String fieldNotStorableIn(int count);

  /// Heading above the list of files that couldn't be updated. {count} is the number of files; singular and plural forms are provided.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file couldn\'t be updated:} other{{count} files couldn\'t be updated:}}'**
  String filesNotUpdated(int count);

  /// Preferences page and heading for notification settings.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// Hint under the master notifications switch.
  ///
  /// In en, this message translates to:
  /// **'Turn this off to disable all notifications, in-app and system.'**
  String get notificationsEnabledHint;

  /// Heading of the group of notification settings taken from the skin.
  ///
  /// In en, this message translates to:
  /// **'Skin Notifications'**
  String get skinNotifications;

  /// Notification option: show the notification whatever the window state.
  ///
  /// In en, this message translates to:
  /// **'Show always'**
  String get notificationShowAlways;

  /// Notification option: show the notification when the main window is shaded or minimized.
  ///
  /// In en, this message translates to:
  /// **'Show with windowshade / minimized'**
  String get notificationShowWindowshade;

  /// Notification option: show the notification only when the main window is minimized.
  ///
  /// In en, this message translates to:
  /// **'Show only when minimized'**
  String get notificationShowMinimized;

  /// Notification option: suppress notifications while a window is fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Disable in fullscreen'**
  String get notificationDisableFullscreen;

  /// Notification option: include the now-playing artwork in the notification.
  ///
  /// In en, this message translates to:
  /// **'Show now playing artwork'**
  String get notificationShowArtwork;

  /// Label of the setting for how long the notification takes to fade in.
  ///
  /// In en, this message translates to:
  /// **'Fade in time'**
  String get notificationFadeIn;

  /// Label of the setting for how long the notification stays fully visible.
  ///
  /// In en, this message translates to:
  /// **'Hold time'**
  String get notificationHold;

  /// Label of the setting for how long the notification takes to fade out.
  ///
  /// In en, this message translates to:
  /// **'Fade out time'**
  String get notificationFadeOut;

  /// Value label of a duration setting. {seconds} is the number of seconds, as text.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String notificationSeconds(String seconds);

  /// Heading of the group of notification settings for notifications drawn by Amped.
  ///
  /// In en, this message translates to:
  /// **'In-App Notifications'**
  String get inAppNotifications;

  /// Heading of the notification settings for newly added podcast episodes.
  ///
  /// In en, this message translates to:
  /// **'New episodes'**
  String get newEpisodeNotifications;

  /// Label of the setting for what clicking the notification of new podcast episodes does.
  ///
  /// In en, this message translates to:
  /// **'When you click the notification'**
  String get newEpisodeClickAction;

  /// Choice for clicking the new-episode notification: it only goes away.
  ///
  /// In en, this message translates to:
  /// **'Do nothing'**
  String get newEpisodeClickNothing;

  /// Choice for clicking the new-episode notification: the episodes are added to the end of the playlist.
  ///
  /// In en, this message translates to:
  /// **'Add the new episodes to the playlist'**
  String get newEpisodeClickEnqueue;

  /// Choice for clicking the new-episode notification: the episodes are added to the playlist and the first one plays.
  ///
  /// In en, this message translates to:
  /// **'Play the new episodes'**
  String get newEpisodeClickPlay;

  /// Label of the setting for where on the screen notifications appear.
  ///
  /// In en, this message translates to:
  /// **'Notification position'**
  String get notificationPosition;

  /// Summary of the chosen notification position. {position} is one of the notification position names.
  ///
  /// In en, this message translates to:
  /// **'Displayed {position}'**
  String notificationPositionDisplayed(String position);

  /// Notification position name: top left of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'top left'**
  String get notificationPositionTopLeft;

  /// Notification position name: top center of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'top center'**
  String get notificationPositionTopCenter;

  /// Notification position name: top right of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'top right'**
  String get notificationPositionTopRight;

  /// Notification position name: bottom left of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'bottom left'**
  String get notificationPositionBottomLeft;

  /// Notification position name: bottom center of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'bottom center'**
  String get notificationPositionBottomCenter;

  /// Notification position name: bottom right of the screen. Lowercase because it is inserted into a sentence.
  ///
  /// In en, this message translates to:
  /// **'bottom right'**
  String get notificationPositionBottomRight;

  /// Button that starts a tag lookup. The trailing ellipsis marks that a dialog opens.
  ///
  /// In en, this message translates to:
  /// **'Look up tags...'**
  String get lookUpTagsEllipsis;

  /// Tooltip of the tag lookup button, explaining what it does.
  ///
  /// In en, this message translates to:
  /// **'Identify this song by its sound (AcoustID) and fetch its tags from MusicBrainz.'**
  String get lookUpTagsTooltip;

  /// Title of the tag lookup dialog.
  ///
  /// In en, this message translates to:
  /// **'Look Up Tags'**
  String get tagLookupTitle;

  /// Progress message while the song is fingerprinted and searched.
  ///
  /// In en, this message translates to:
  /// **'Fingerprinting the song and searching MusicBrainz...'**
  String get tagLookupSearching;

  /// Message shown when AcoustID doesn't recognize the recording.
  ///
  /// In en, this message translates to:
  /// **'AcoustID doesn\'t know this recording, so there are no tags to suggest.'**
  String get tagLookupNoMatch;

  /// Message shown when this build has no AcoustID API key, so lookup can't work.
  ///
  /// In en, this message translates to:
  /// **'Tag lookup isn\'t available in this build of Amped: it has no AcoustID API key.'**
  String get tagLookupMissingKey;

  /// Message shown when AcoustID rejects this build's API key.
  ///
  /// In en, this message translates to:
  /// **'AcoustID didn\'t accept this build\'s API key, so tags can\'t be looked up.'**
  String get tagLookupInvalidKey;

  /// Message shown when the file couldn't be fingerprinted. {error} is the technical reason.
  ///
  /// In en, this message translates to:
  /// **'This file couldn\'t be fingerprinted: {error}'**
  String tagLookupFingerprintFailed(String error);

  /// Message shown when the lookup service is rate-limited or overloaded.
  ///
  /// In en, this message translates to:
  /// **'The lookup service is busy right now. Wait a moment, then try again.'**
  String get tagLookupBusy;

  /// Message shown when the lookup service can't be reached over the network.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the lookup service. Check your internet connection, then try again.'**
  String get tagLookupUnreachable;

  /// Instruction above the list of candidate releases in the tag lookup dialog.
  ///
  /// In en, this message translates to:
  /// **'Pick the release this file is from. Its tags go into the fields; nothing is saved until you press OK.'**
  String get tagLookupPickHint;

  /// Button that fills the editor fields with the chosen candidate's tags.
  ///
  /// In en, this message translates to:
  /// **'Use these tags'**
  String get tagLookupUse;

  /// Small label under the match percentage of a candidate, as in '87% match'. The number is shown separately.
  ///
  /// In en, this message translates to:
  /// **'match'**
  String get tagLookupMatchLabel;

  /// Candidate detail line with the album name. {album} is the album title.
  ///
  /// In en, this message translates to:
  /// **'Album: {album}'**
  String tagLookupAlbum(String album);

  /// Candidate detail line with a full release date. {date} is a date.
  ///
  /// In en, this message translates to:
  /// **'Released {date}'**
  String tagLookupReleasedOn(DateTime date);

  /// Candidate detail line with a release month. {date} is a month and year.
  ///
  /// In en, this message translates to:
  /// **'Released {date}'**
  String tagLookupReleasedMonth(DateTime date);

  /// Candidate detail line with only a release year. {year} is the year.
  ///
  /// In en, this message translates to:
  /// **'Released {year}'**
  String tagLookupReleasedYear(String year);

  /// Candidate detail line with track position and count. {track} is the track number, {total} the number of tracks.
  ///
  /// In en, this message translates to:
  /// **'Track {track} of {total}'**
  String tagLookupTrackOf(String track, String total);

  /// Candidate detail line with only the track number. {track} is the track number.
  ///
  /// In en, this message translates to:
  /// **'Track {track}'**
  String tagLookupTrack(String track);

  /// Candidate detail line with the disc number. {disc} is the disc number.
  ///
  /// In en, this message translates to:
  /// **'Disc {disc}'**
  String tagLookupDisc(String disc);

  /// Message shown after a candidate's tags were filled into the editor.
  ///
  /// In en, this message translates to:
  /// **'Filled in from MusicBrainz. Press OK to save them.'**
  String get tagLookupApplied;

  /// Status shown after settings or tags were saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// Button that applies the chosen setting, such as a skin.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyAction;

  /// Summary line of the active skin on the skins preferences page. {name} is the skin name.
  ///
  /// In en, this message translates to:
  /// **'Active skin: {name}'**
  String skinsSummary(String name);

  /// Hint under the active skin summary.
  ///
  /// In en, this message translates to:
  /// **'Choose a skin in Browser. A modern skin also has its options and color themes there.'**
  String get skinsSummaryHint;

  /// Heading above a skin's preview image.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get skinPreview;

  /// Error shown when a chosen file isn't a skin. {name} is the file name.
  ///
  /// In en, this message translates to:
  /// **'{name} is not a skin.'**
  String skinNotValid(String name);

  /// Message shown when no preview image exists for a skin.
  ///
  /// In en, this message translates to:
  /// **'No preview is available for this skin.'**
  String get skinNoPreview;

  /// Heading of the panel with the comments a skin's author wrote, below the skin preview.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get skinComments;

  /// Prompt on the area where a skin file can be dropped or picked.
  ///
  /// In en, this message translates to:
  /// **'Drop a skin archive here, or tap to find one'**
  String get skinDropTarget;

  /// Heading of the skin options group in the modern skin settings.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get modernSettingsOptions;

  /// Heading of the color themes group in the modern skin settings.
  ///
  /// In en, this message translates to:
  /// **'Color Themes'**
  String get modernSettingsColorThemes;

  /// Message shown when the skin has to be applied before its settings can be changed.
  ///
  /// In en, this message translates to:
  /// **'Apply this skin to change its options and color themes.'**
  String get modernSettingsNeedsApply;

  /// Message shown when a modern skin has no options.
  ///
  /// In en, this message translates to:
  /// **'This skin has no options.'**
  String get modernSettingsNoOptions;

  /// Name of the user-defined color theme.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get colorThemeCustom;

  /// Button that copies the selected color theme under a new name. The trailing ellipsis marks that a name is asked.
  ///
  /// In en, this message translates to:
  /// **'Clone...'**
  String get colorThemeClone;

  /// Button that edits the selected color theme.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get colorThemeEdit;

  /// Label of the field for naming a color theme.
  ///
  /// In en, this message translates to:
  /// **'Theme name'**
  String get colorThemeNewName;

  /// Message shown when a modern skin has no color themes.
  ///
  /// In en, this message translates to:
  /// **'This skin has no color themes.'**
  String get colorThemeNoThemes;

  /// Label of the red slider of a color theme.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorThemeRed;

  /// Label of the green slider of a color theme.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorThemeGreen;

  /// Label of the blue slider of a color theme.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorThemeBlue;

  /// Label of the grayscale setting of a color theme.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get colorThemeGray;

  /// Grayscale setting value: no grayscale conversion.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get colorThemeGrayNone;

  /// Grayscale setting value: gray is taken from the brightest color channel.
  ///
  /// In en, this message translates to:
  /// **'Brightest channel'**
  String get colorThemeGrayBrightest;

  /// Grayscale setting value: gray is the average of the color channels.
  ///
  /// In en, this message translates to:
  /// **'Average of channels'**
  String get colorThemeGrayAverage;

  /// Label of the setting that boosts the theme's color intensity.
  ///
  /// In en, this message translates to:
  /// **'Boost'**
  String get colorThemeBoost;

  /// Title of the window that asks for the name and password of a network share (SMB, FTP or WebDAV server).
  ///
  /// In en, this message translates to:
  /// **'Sign in to network share'**
  String get remoteLoginTitle;

  /// Prompt above the fields of the network share sign-in window.
  ///
  /// In en, this message translates to:
  /// **'Enter the name and password for {server}:'**
  String remoteLoginPrompt(String server);

  /// Shown in the network share sign-in window when the saved or entered name and password were turned down.
  ///
  /// In en, this message translates to:
  /// **'The server did not accept the sign-in: {error}'**
  String remoteLoginFailed(String error);

  /// Label of the user name field of the network share sign-in window.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get remoteLoginUser;

  /// Label of the password field of the network share sign-in window.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get remoteLoginPassword;

  /// Confirmation button of the network share sign-in window.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get remoteLoginSignIn;

  /// Shown in the song title while a track is copied from a network share before it plays, when its size is known. The speed includes its unit, for example 3.1 MB.
  ///
  /// In en, this message translates to:
  /// **'Buffering {percent}% - {speed}/s - {elapsed} elapsed, {remaining} left'**
  String remoteBuffering(
    int percent,
    String speed,
    String elapsed,
    String remaining,
  );

  /// Shown in the song title while a track is copied from a network share before it plays, when its size is not known. Sizes include their unit, for example 3.1 MB.
  ///
  /// In en, this message translates to:
  /// **'Buffering {received} - {speed}/s - {elapsed} elapsed'**
  String remoteBufferingUnknown(String received, String speed, String elapsed);

  /// Preferences > Library: heading of the list of remote servers.
  ///
  /// In en, this message translates to:
  /// **'Remote sources'**
  String get libraryRemoteSources;

  /// Preferences > Library: shown when no server was added.
  ///
  /// In en, this message translates to:
  /// **'No remote sources added.'**
  String get libraryNoRemoteSources;

  /// Preferences > Remote sources: explanation under the heading.
  ///
  /// In en, this message translates to:
  /// **'Music, videos, podcasts and audiobooks from your servers and online accounts. They appear in the Media Library.'**
  String get libraryRemoteSourcesHint;

  /// Preferences > Remote sources: button that opens the list of kinds of source that can be added.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get libraryAddSource;

  /// Preferences > Remote sources: heading of the list of kinds of source.
  ///
  /// In en, this message translates to:
  /// **'Choose what to add'**
  String get libraryChooseSourceType;

  /// Preferences > Remote sources: heading of the form that adds a source.
  ///
  /// In en, this message translates to:
  /// **'Add {type}'**
  String libraryAddSourceTitle(String type);

  /// Preferences > Remote sources: heading of the form that edits a source.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String libraryEditSourceTitle(String name);

  /// Preferences > Remote sources: a kind of source.
  ///
  /// In en, this message translates to:
  /// **'Navidrome / Subsonic'**
  String get libraryTypeNavidrome;

  /// Preferences > Remote sources: a kind of source.
  ///
  /// In en, this message translates to:
  /// **'Podcast'**
  String get libraryTypePodcast;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Music from your Navidrome or Subsonic server'**
  String get libraryDescribeNavidrome;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Tracks and likes. Needs SoundCloud Pro'**
  String get libraryDescribeSoundCloud;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Music and videos from a Plex Media Server'**
  String get libraryDescribePlex;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Music and videos from a Jellyfin server'**
  String get libraryDescribeJellyfin;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Subscribe by searching or by RSS feed'**
  String get libraryDescribePodcast;

  /// Preferences > Remote sources: what a kind of source is.
  ///
  /// In en, this message translates to:
  /// **'Podcasts and audiobooks from your server'**
  String get libraryDescribeAudiobookshelf;

  /// Preferences > Remote sources: asks before removing a source.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}? Its saved sign-in is forgotten.'**
  String libraryRemoveConfirm(String name);

  /// Preferences > Remote sources: button that returns to the previous view.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get libraryBack;

  /// Preferences > Remote sources: shown on a source whose tracks are loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get librarySourceLoading;

  /// Preferences > Remote sources: button that checks the server and adds the source.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get librarySourceConnect;

  /// Preferences > Remote sources: button that adds a podcast.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get librarySourceSubscribe;

  /// Preferences > Remote sources: label of a source's name field.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get librarySourceNameOptional;

  /// Preferences > Remote sources: hint in the podcast search field.
  ///
  /// In en, this message translates to:
  /// **'Podcast name or topic'**
  String get libraryPodcastSearchHint;

  /// Preferences > Remote sources: shown when a podcast search finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No podcasts found.'**
  String get libraryPodcastNoResults;

  /// Preferences > Remote sources: shown between the podcast search and the address field.
  ///
  /// In en, this message translates to:
  /// **'Or enter the feed address yourself:'**
  String get libraryPodcastOrFeed;

  /// Preferences > Remote sources: shown after signing in at plex.tv.
  ///
  /// In en, this message translates to:
  /// **'Signed in to Plex. Check the server address, then connect.'**
  String get libraryPlexSignedIn;

  /// Preferences > Remote sources: shown under the Plex sign-in button.
  ///
  /// In en, this message translates to:
  /// **'Or enter the server address and token yourself:'**
  String get libraryPlexOrToken;

  /// Preferences > Remote sources: heading that opens a source's other settings.
  ///
  /// In en, this message translates to:
  /// **'Background refresh and playback'**
  String get librarySourceOptions;

  /// Preferences > Remote sources: heading that opens the other settings of a source without episodes.
  ///
  /// In en, this message translates to:
  /// **'Background refresh'**
  String get librarySourceOptionsRefresh;

  /// Preferences > Remote sources: summary of a source's background refresh.
  ///
  /// In en, this message translates to:
  /// **'Refreshes every {interval}'**
  String libraryRefreshSummaryOn(String interval);

  /// Preferences > Remote sources: summary when a source is not refreshed in the background.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get libraryRefreshSummaryOff;

  /// Preferences > Remote sources: label of the field for the name to sign in with.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get librarySourceUser;

  /// Preferences > Library: label of the field for a podcast's RSS feed address.
  ///
  /// In en, this message translates to:
  /// **'RSS feed URL'**
  String get librarySourceFeedUrl;

  /// Preferences > Library: label of the field for an Audiobookshelf server's API token.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get librarySourceApiToken;

  /// Preferences > Library: label of the field that searches the iTunes podcast directory.
  ///
  /// In en, this message translates to:
  /// **'Search iTunes'**
  String get librarySourcePodcastSearch;

  /// Preferences > Library: label of the field for a Plex server's X-Plex-Token.
  ///
  /// In en, this message translates to:
  /// **'Plex token'**
  String get librarySourceToken;

  /// Preferences > Library: button that opens plex.tv in the browser to sign in.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Plex'**
  String get librarySourcePlexSignIn;

  /// Preferences > Library: shown while the user approves the sign-in on the Plex website.
  ///
  /// In en, this message translates to:
  /// **'Waiting for plex.tv...'**
  String get librarySourcePlexWaiting;

  /// Preferences > Library > Plex: label of the choice of which Plex Home user to present as.
  ///
  /// In en, this message translates to:
  /// **'Present as'**
  String get librarySourcePlexUser;

  /// Preferences > Library > Plex: label of the field for the PIN of the chosen Plex Home user.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get librarySourcePlexPin;

  /// Preferences > Library: button that edits a remote source.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get libraryEditSource;

  /// Preferences > Library: button that removes a folder or remote source.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get libraryRemoveSource;

  /// Preferences > Library: label of a remote source's name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get librarySourceName;

  /// Preferences > Library: label of a remote source's address field, such as https://music.example.com.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get librarySourceServer;

  /// Preferences > Library: hint of the password field when editing a source.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the saved password'**
  String get librarySourcePasswordKeep;

  /// Preferences > Library: button that checks the server and saves the source.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get librarySourceSave;

  /// Preferences > Library: shown while the server is being contacted.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get librarySourceChecking;

  /// Preferences > Library: why the server could not be added.
  ///
  /// In en, this message translates to:
  /// **'Could not connect: {error}'**
  String librarySourceFailed(String error);

  /// Preferences > Library: heading of the notice on the SoundCloud form saying the feature needs a SoundCloud Pro subscription.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud Pro subscribers only'**
  String get librarySoundCloudProOnly;

  /// Preferences > Library: how to register a SoundCloud application and get an API key. Lines are separated by newlines.
  ///
  /// In en, this message translates to:
  /// **'SoundCloud only gives application keys to Pro subscribers (Artist Pro), so you bring your own key:\n1. Subscribe to SoundCloud Pro, then open soundcloud.com/you/apps (or follow developers.soundcloud.com/docs/building-with-ai).\n2. Register a new application, with any name and description.\n3. Copy its Client ID and Client Secret into the fields below.\n4. Enter the address of the profile whose public tracks and likes you want to browse, such as https://soundcloud.com/artist. To browse your own library instead, tick the sign-in option and add the redirect URI it shows to the application.\nThe secret is kept in your system\'s secure storage.'**
  String get librarySoundCloudInstructions;

  /// Preferences > Library: label of the SoundCloud profile address field, such as https://soundcloud.com/artist.
  ///
  /// In en, this message translates to:
  /// **'Profile URL'**
  String get librarySoundCloudProfile;

  /// Preferences > Library: label of the SoundCloud application's client id field.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get librarySoundCloudClientId;

  /// Preferences > Library: label of the SoundCloud application's client secret field.
  ///
  /// In en, this message translates to:
  /// **'Client Secret'**
  String get librarySoundCloudClientSecret;

  /// Preferences > Library: hint of the client secret field when editing a SoundCloud source.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the saved secret'**
  String get librarySoundCloudSecretKeep;

  /// Preferences > Library: checkbox on the SoundCloud form. Ticked, the library of the signed-in user is shown instead of a profile's public tracks.
  ///
  /// In en, this message translates to:
  /// **'Sign in with SoundCloud in my browser (my own tracks and likes)'**
  String get librarySoundCloudBrowserSignIn;

  /// Preferences > Library: shown under the browser sign-in checkbox of the SoundCloud form. {address} is a web address on this computer.
  ///
  /// In en, this message translates to:
  /// **'For this, add {address} as a redirect URI of your SoundCloud application first. Your browser opens to approve the sign-in when you save.'**
  String librarySoundCloudRedirectHint(String address);

  /// Preferences > Library: shown on the save button while the user approves a sign-in in their browser.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the browser...'**
  String get librarySourceWaitingForBrowser;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
