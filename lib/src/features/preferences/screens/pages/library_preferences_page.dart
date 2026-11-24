import "dart:async";

import "package:amped/src/features/remote_source/widgets/add_remote_source_button.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_shell.dart";
import "../../../../library/library_source_manager.dart";
import "../../../remote_source/classes/remote_source_type.dart";
import "../../widgets/remote_sources/remote_source.dart";

/// Preferences > General Preferences > Remote sources: the Navidrome/Subsonic
/// servers in the Media Library's tree.
class LibraryPreferencesPage extends StatefulWidget {
  const LibraryPreferencesPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  State<LibraryPreferencesPage> createState() => _LibraryPreferencesPageState();
}

class _LibraryPreferencesPageState extends State<LibraryPreferencesPage> {
  /// The source being added or edited; null shows the lists.
  RemoteSourceConfig? _editing;

  /// The type of the source being added, or null when none is.
  RemoteSourceType? _adding;

  LibrarySourceManager get _sources => widget.shell.sources;

  @override
  Widget build(BuildContext context) {
    if (_adding != null || _editing != null) {
      return SourceForm(
        key: ValueKey(_editing?.id ?? "new"),
        sources: _sources,
        editing: _editing,
        type: _editing?.type ?? _adding!,
        onDone: () => setState(() {
          _adding = null;
          _editing = null;
        }),
      );
    }
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _sources,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            localizations.libraryRemoteSources,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_sources.remotes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(localizations.libraryNoRemoteSources),
            ),
          for (final RemoteSourceConfig remote in _sources.remotes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(remote.name),
              subtitle: Text(
                switch (remote.type) {
                  RemoteSourceType.soundcloud => "${remote.server}",
                  RemoteSourceType.plex => "${remote.server}",
                  RemoteSourceType.jellyfin =>
                    "${remote.user}@${remote.server}",
                  RemoteSourceType.podcast => remote.server,
                  RemoteSourceType.audiobookshelf => "${remote.server}",
                  RemoteSourceType.navidrome =>
                    "${remote.user}@${remote.server}",
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _editing = remote),
                    child: Text(localizations.libraryEditSource),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_sources.remove(remote.id)),
                    child: Text(localizations.libraryRemoveSource),
                  ),
                ],
              ),
            ),
          for (final RemoteSourceType type in RemoteSourceType.values) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AddRemoteSourceButton(
                type: type,
                onPressed: () => setState(() => _adding = type),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
