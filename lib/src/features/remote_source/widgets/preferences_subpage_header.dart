import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

/// The top of a view opened from the Remote sources list: the way back, and
/// what the view is.
class PreferencesSubpageHeader extends StatelessWidget {
  const PreferencesSubpageHeader({
    required this.title,
    required this.onBack,
    this.leading,
    super.key,
  });

  final String title;

  /// Null while going back isn't possible.
  final VoidCallback? onBack;

  /// Shown before the title.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: AppLocalizations.of(context).libraryBack,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
