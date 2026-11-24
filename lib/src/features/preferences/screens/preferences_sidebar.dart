import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../preferences_navigation.dart";
import "../preferences_page.dart";

/// The page tree on the left of the Preferences dialog.
class PreferencesSidebar extends StatelessWidget {
  const PreferencesSidebar({
    required this.navigation,
    super.key,
  });

  final PreferencesNavigation navigation;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations localizations = AppLocalizations.of(context);
    return SizedBox(
      width: 200,
      child: ListenableBuilder(
        listenable: navigation,
        builder: (context, _) => ListView(
          children: [
            for (final page in PreferencesPage.values)
              ListTile(
                dense: true,
                selected: page == navigation.page,
                contentPadding: EdgeInsets.only(
                  left: 12.0 + page.depth * 16,
                ),
                title: Text(page.label(localizations)),
                onTap: () => navigation.select(page),
              ),
          ],
        ),
      ),
    );
  }
}
