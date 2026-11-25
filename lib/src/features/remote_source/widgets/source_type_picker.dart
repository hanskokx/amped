import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../classes/remote_source_type.dart";
import "source_panel.dart";
import "source_type_icon.dart";

/// The kinds of source that can be added, each with what it brings. Two
/// columns when there is room for them.
class SourceTypePicker extends StatelessWidget {
  const SourceTypePicker({required this.onPicked, super.key});

  final ValueChanged<RemoteSourceType> onPicked;

  static const _gap = 8.0;
  static const _twoColumns = 480.0;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= _twoColumns
            ? (constraints.maxWidth - _gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final type in RemoteSourceType.values)
              SizedBox(
                width: width,
                child: SourcePanel(
                  key: ValueKey(type),
                  onTap: () => onPicked(type),
                  child: ConstrainedBox(
                    // The same height whether or not the text wraps.
                    constraints: const BoxConstraints(minHeight: 72),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SourceTypeIcon(type),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  type.title(localizations),
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  type.description(localizations),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
