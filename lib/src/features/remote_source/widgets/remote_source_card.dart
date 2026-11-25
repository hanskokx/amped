import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../library/library_source_manager.dart";
import "../classes/remote_source_type.dart";
import "source_panel.dart";
import "source_type_icon.dart";

/// An added source: what and where it is, and how loading it went. Pressing
/// it edits it; removing it is confirmed in the card first.
class RemoteSourceCard extends StatefulWidget {
  const RemoteSourceCard({
    required this.source,
    required this.onEdit,
    required this.onRemove,
    this.loading = false,
    this.error,
    super.key,
  });

  final RemoteSourceConfig source;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  /// Whether the source's tracks are loading.
  final bool loading;

  /// Why they couldn't be loaded, or null.
  final String? error;

  @override
  State<RemoteSourceCard> createState() => _RemoteSourceCardState();
}

class _RemoteSourceCardState extends State<RemoteSourceCard> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final source = widget.source;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final address = switch (source.type) {
      RemoteSourceType.navidrome ||
      RemoteSourceType.jellyfin => "${source.user} · ${source.server}",
      // Their "user" is a stand-in, or an application's key.
      _ => source.server,
    };
    final error = widget.error;
    return SourcePanel(
      onTap: _confirming ? null : widget.onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                SourceTypeIcon(source.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "${source.type.title(localizations)} · $address",
                        style: quiet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.loading)
                        Text(localizations.librarySourceLoading, style: quiet)
                      else if (error != null)
                        Text(
                          localizations.librarySourceFailed(error),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (!_confirming) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: localizations.libraryEditSource,
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: localizations.libraryRemoveSource,
                    onPressed: () => setState(() => _confirming = true),
                  ),
                ],
              ],
            ),
            if (_confirming) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.libraryRemoveConfirm(source.name),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _confirming = false),
                    child: Text(localizations.cancel),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: widget.onRemove,
                    child: Text(localizations.libraryRemoveSource),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
