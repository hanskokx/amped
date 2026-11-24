import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../app/amped_shell.dart";
import "../../../skin/webamp_skin_library.dart";
import "../preferences_page.dart";
import "pages/library_preferences_page.dart";
import "pages/notification_preferences_page.dart";
import "pages/skin_browser_page.dart";
import "pages/skins_pages.dart";
import "pages/video_page.dart";
import "pages/vis_page.dart";
import "pages/watch_folders_page.dart";
import "preferences_sidebar.dart";

/// The Preferences dialog with the original's page tree. Only some pages
/// have been implemented so far.
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final navigation = shell.preferences;
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) {
        final localizations = AppLocalizations.of(context);
        final page = navigation.page;
        return Row(
          children: [
            PreferencesSidebar(navigation: navigation),
            const VerticalDivider(width: 1),
            Expanded(
              // Pages are mounted on their first visit, then kept alive by
              // the IndexedStack, so switching back doesn't rebuild them.
              child: IndexedStack(
                index: PreferencesPage.values.indexOf(page),
                children: [
                  for (final candidate in PreferencesPage.values)
                    if (navigation.hasVisited(candidate))
                      KeyedSubtree(
                        key: ValueKey(candidate),
                        child: switch (candidate) {
                          PreferencesPage.skins => SkinsOverviewPage(
                            shell: shell,
                          ),
                          PreferencesPage.skinsInstalled => SkinsBrowserPage(
                            shell: shell,
                            onAddSkin: shell.skinInstaller.addSkins,
                          ),
                          PreferencesPage.skinsOnline => SkinBrowserPage(
                            library: WebampSkinLibrary(),
                            install: shell.skins.importArchive,
                          ),
                          PreferencesPage.visualization => VisPage(
                            shell: shell,
                          ),
                          PreferencesPage.video => VideoPage(
                            player: shell.player,
                          ),
                          PreferencesPage.mediaLibrary => WatchFoldersPage(
                            shell: shell,
                          ),
                          PreferencesPage.remoteSources =>
                            LibraryPreferencesPage(shell: shell),
                          PreferencesPage.notifications =>
                            NotificationPreferencesPage(shell: shell),
                          _ => _UnavailablePage(
                            label: candidate.label(localizations),
                          ),
                        },
                      )
                    else
                      const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The placeholder for a Preferences page that isn't implemented yet.
class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(AppLocalizations.of(context).settingsUnavailable(label)),
  );
}
