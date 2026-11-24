import "package:amped_l10n/amped_l10n.dart";

/// The pages of the Preferences dialog, in the order they appear in its tree.
enum PreferencesPage {
  notifications,
  mediaLibrary,
  remoteSources,
  video,
  skins,
  skinsInstalled,
  skinsOnline,
  visualization,
}

/// The label and tree depth of a [PreferencesPage].
extension PreferencesPageX on PreferencesPage {
  /// The localized name shown for this page in the sidebar.
  String label(AppLocalizations localizations) => switch (this) {
    PreferencesPage.notifications => localizations.notifications,
    PreferencesPage.mediaLibrary => localizations.mediaLibraryPreferences,
    PreferencesPage.remoteSources => localizations.libraryRemoteSources,
    PreferencesPage.video => localizations.video,
    PreferencesPage.skins => localizations.skins,
    PreferencesPage.skinsInstalled => localizations.skinsInstalled,
    PreferencesPage.skinsOnline => localizations.skinsOnline,
    PreferencesPage.visualization => localizations.visualization,
  };

  /// The indentation level in the sidebar: one for the children of Skins,
  /// zero for everything else.
  int get depth => switch (this) {
    PreferencesPage.skinsInstalled || PreferencesPage.skinsOnline => 1,
    _ => 0,
  };
}
