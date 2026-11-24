import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

/// Asks whether to continue the episode [title] at [position] or play it
/// from the start; [onAnswer] gets true to resume.
class ResumePage extends StatelessWidget {
  const ResumePage({
    required this.title,
    required this.position,
    required this.onAnswer,
    super.key,
  });

  final String title;
  final Duration position;
  final ValueChanged<bool> onAnswer;

  /// `1:02:03` or `12:34`.
  static String clock(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, "0");
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, "0");
    return h > 0 ? "$h:$m:$s" : "${duration.inMinutes}:$s";
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localizations.resumePrompt(title, clock(position))),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => onAnswer(false),
                child: Text(localizations.resumeStartOver),
              ),
              const SizedBox(width: 8),
              FilledButton(
                autofocus: true,
                onPressed: () => onAnswer(true),
                child: Text(localizations.resumeContinue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
