import "package:amped_l10n/amped_l10n.dart";
import "package:amped_update_checker/amped_update_checker.dart";
import "package:material_ui/material_ui.dart";

/// Announces [release] with its notes; [onAnswer] gets true to go to the
/// downloads, false to ignore it.
class UpdatePage extends StatelessWidget {
  const UpdatePage({
    required this.release,
    required this.onAnswer,
    super.key,
  });

  final UpdateInfo? release;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            localizations.updateAvailable(release?.version ?? ""),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(release?.notes ?? ""),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => onAnswer(false),
                child: Text(localizations.updateIgnore),
              ),
              const SizedBox(width: 8),
              FilledButton(
                autofocus: true,
                onPressed: () => onAnswer(true),
                child: Text(localizations.updateDownload),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
