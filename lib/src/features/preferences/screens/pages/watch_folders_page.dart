import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_shell.dart";

/// Preferences > General Preferences > Media Library: the folders that are
/// watched for audio files to add to the Local source.
class WatchFoldersPage extends StatelessWidget {
  const WatchFoldersPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: shell.watchFolders,
      builder: (context, _) {
        final folders = shell.watchFolders.folders;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              localizations.watchFolders,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              localizations.watchFoldersHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(localizations.watchFoldersEmpty),
              ),
            for (final folder in folders)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(folder),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: localizations.watchFoldersRemove,
                  onPressed: () => shell.watchFolders.remove(folder),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: shell.libraryActions.addWatchFolder,
                child: Text(localizations.watchFoldersAdd),
              ),
            ),
          ],
        );
      },
    );
  }
}
