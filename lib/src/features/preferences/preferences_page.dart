import "package:amped_l10n/amped_l10n.dart";

/// The pages of the Preferences dialog, in the order they appear in its tree.
enum PreferencesPage {
  general,
  notifications,
  fileTypes,
  playlist,
  titles,
  playback,
  mediaLibrary,
  remoteSources,
  stationInfo,
  video,
  localization,
  skins,
  skinsInstalled,
  skinsOnline,
  plugins,
  input,
  output,
  visualization,
  dspEffect,
  generalPurpose,
}

/// The label and tree depth of a [PreferencesPage].
extension PreferencesPageX on PreferencesPage {
  /// The localized name shown for this page in the sidebar.
  String label(AppLocalizations localizations) => switch (this) {
    PreferencesPage.general => localizations.generalPreferences,
    PreferencesPage.notifications => localizations.notifications,
    PreferencesPage.fileTypes => localizations.fileTypes,
    PreferencesPage.playlist => localizations.playlist,
    PreferencesPage.titles => localizations.titles,
    PreferencesPage.playback => localizations.playback,
    PreferencesPage.mediaLibrary => localizations.mediaLibraryPreferences,
    PreferencesPage.remoteSources => localizations.libraryRemoteSources,
    PreferencesPage.stationInfo => localizations.stationInfo,
    PreferencesPage.video => localizations.video,
    PreferencesPage.localization => localizations.localization,
    PreferencesPage.skins => localizations.skins,
    PreferencesPage.skinsInstalled => localizations.skinsInstalled,
    PreferencesPage.skinsOnline => localizations.skinsOnline,
    PreferencesPage.plugins => localizations.plugins,
    PreferencesPage.input => localizations.input,
    PreferencesPage.output => localizations.output,
    PreferencesPage.visualization => localizations.visualization,
    PreferencesPage.dspEffect => localizations.dspEffect,
    PreferencesPage.generalPurpose => localizations.generalPurpose,
  };

  /// The indentation level in the sidebar: zero for categories, one for
  /// their children.
  int get depth => switch (this) {
    PreferencesPage.general ||
    PreferencesPage.skins ||
    PreferencesPage.plugins => 0,
    _ => 1,
  };
}
