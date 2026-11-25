import "dart:async";

import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_shell.dart";
import "../../../../library/library_source_manager.dart";
import "../../../remote_source/classes/remote_source_type.dart";
import "../../../remote_source/widgets/preferences_subpage_header.dart";
import "../../../remote_source/widgets/remote_source_card.dart";
import "../../../remote_source/widgets/source_type_picker.dart";
import "../../widgets/remote_sources/remote_source.dart";

/// Preferences > General Preferences > Remote sources: the servers and online
/// accounts in the Media Library's tree.
class LibraryPreferencesPage extends StatelessWidget {
  const LibraryPreferencesPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) =>
      RemoteSourcesView(sources: shell.sources);
}

/// The list of [sources], and the views that add and edit them.
class RemoteSourcesView extends StatefulWidget {
  const RemoteSourcesView({required this.sources, super.key});

  final LibrarySourceManager sources;

  @override
  State<RemoteSourcesView> createState() => _RemoteSourcesViewState();
}

class _RemoteSourcesViewState extends State<RemoteSourcesView> {
  /// Whether the kinds of source are shown to pick from. With no sources they
  /// are part of the list instead.
  bool _picking = false;

  /// The type of the source being added, or null when none is.
  RemoteSourceType? _adding;

  /// The source being edited, or null when none is.
  RemoteSourceConfig? _editing;

  LibrarySourceManager get _sources => widget.sources;

  void _showList() => setState(() {
    _picking = false;
    _adding = null;
    _editing = null;
  });

  void _pick(RemoteSourceType type) => setState(() => _adding = type);

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    final type = editing?.type ?? _adding;
    if (type != null) {
      return SourceForm(
        key: ValueKey(editing?.id ?? "new-${type.name}"),
        sources: _sources,
        editing: editing,
        type: type,
        // Back from a new source returns to where its type was picked.
        onBack: editing == null
            ? () => setState(() => _adding = null)
            : _showList,
        onDone: _showList,
      );
    }
    return ListenableBuilder(
      listenable: _sources,
      builder: (context, _) =>
          _picking ? _buildPicker(context) : _buildList(context),
    );
  }

  Widget _buildPicker(BuildContext context) {
    return Column(
      children: [
        PreferencesSubpageHeader(
          title: AppLocalizations.of(context).libraryChooseSourceType,
          onBack: _showList,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [SourceTypePicker(onPicked: _pick)],
          ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final remotes = _sources.remotes;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizations.libraryRemoteSources,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(localizations.libraryRemoteSourcesHint, style: quiet),
                ],
              ),
            ),
            if (remotes.isNotEmpty) ...[
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => setState(() => _picking = true),
                icon: const Icon(Icons.add, size: 18),
                label: Text(localizations.libraryAddSource),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (remotes.isEmpty) ...[
          Text(localizations.libraryNoRemoteSources),
          const SizedBox(height: 16),
          Text(
            localizations.libraryChooseSourceType,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SourceTypePicker(onPicked: _pick),
        ],
        for (final remote in remotes)
          Padding(
            key: ValueKey(remote.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: RemoteSourceCard(
              source: remote,
              loading: _sources.isLoading(remote.id),
              error: _sources.errorOf(remote.id),
              onEdit: () => setState(() => _editing = remote),
              onRemove: () => unawaited(_sources.remove(remote.id)),
            ),
          ),
      ],
    );
  }
}
