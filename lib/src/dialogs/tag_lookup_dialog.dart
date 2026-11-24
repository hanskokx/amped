import "dart:async";

import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../tags/tag_lookup.dart";
import "../tags/tag_model.dart";

/// The File Info dialog's "Look up tags..." box: runs the lookup, then lists
/// the releases it found for the user to pick one. Closes with the picked
/// [TagLookupPick], or null. It writes nothing itself.
class TagLookupDialog extends StatefulWidget {
  const TagLookupDialog({
    required this.path,
    required this.lookup,
    this.cachedFingerprint = "",
    super.key,
  });

  final String path;
  final TagLookupFn lookup;

  /// The fingerprint already in the file's tags, if any.
  final String cachedFingerprint;

  @override
  State<TagLookupDialog> createState() => _TagLookupDialogState();
}

class _TagLookupDialogState extends State<TagLookupDialog> {
  TagLookupResult? _result;
  TagLookupException? _error;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final result = await widget.lookup(
        widget.path,
        cachedFingerprint: widget.cachedFingerprint,
      );
      if (mounted) setState(() => _result = result);
    } on TagLookupException catch (error) {
      if (mounted) setState(() => _error = error);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = TagLookupException(
            TagLookupFailure.network,
            "$error",
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final result = _result;
    final candidates = result?.candidates;
    final error = _error;
    final canPick = candidates != null && candidates.isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      // A definite size, not just a maximum, so the box lays out even where
      // nothing above gives it a height to fill: most of the window it is
      // in, up to a size that stays comfortable to read.
      child: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 32).clamp(320.0, 680.0),
        height: (MediaQuery.sizeOf(context).height - 32).clamp(340.0, 560.0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                localizations.tagLookupTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              // Which file this is for, to check the matches against.
              Text(
                widget.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: error != null
                    ? _LookupMessage(
                        text: _TagLookupText.failure(error, localizations),
                        // The technical reason, small and quiet.
                        detail: error.failure == TagLookupFailure.network
                            ? error.detail
                            : null,
                      )
                    : candidates == null
                    ? _LookupProgress(text: localizations.tagLookupSearching)
                    : candidates.isEmpty
                    ? _LookupMessage(text: localizations.tagLookupNoMatch)
                    : _CandidateList(
                        candidates: candidates,
                        selected: _selected,
                        onSelected: (index) =>
                            setState(() => _selected = index),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                localizations.tagLookupPrivacy,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (error?.failure == TagLookupFailure.network) ...[
                    FilledButton(
                      onPressed: _retry,
                      child: Text(localizations.tagLookupRetry),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(localizations.cancel),
                  ),
                  if (canPick) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        TagLookupPick(
                          candidates[_selected],
                          result!.fingerprint.fingerprint,
                        ),
                      ),
                      child: Text(localizations.tagLookupUse),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the user picked, and the fingerprint to cache in the file's tags.
class TagLookupPick {
  const TagLookupPick(this.candidate, this.fingerprint);

  final TagCandidate candidate;
  final String fingerprint;
}

/// The messages for lookup failures.
abstract final class _TagLookupText {
  static String failure(
    TagLookupException error,
    AppLocalizations localizations,
  ) => switch (error.failure) {
    TagLookupFailure.missingApiKey => localizations.tagLookupMissingKey,
    TagLookupFailure.invalidApiKey => localizations.tagLookupInvalidKey,
    TagLookupFailure.fingerprintFailed =>
      localizations.tagLookupFingerprintFailed(error.detail),
    TagLookupFailure.network =>
      busy(error)
          ? localizations.tagLookupBusy
          : localizations.tagLookupUnreachable,
  };

  /// Whether the service answered "slow down" (503) or "too many requests"
  /// (429), as opposed to not being reachable at all.
  static bool busy(TagLookupException error) =>
      error.detail.contains("HTTP 503") || error.detail.contains("HTTP 429");
}

class _LookupProgress extends StatelessWidget {
  const _LookupProgress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _LookupMessage extends StatelessWidget {
  const _LookupMessage({required this.text, this.detail});

  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(text, textAlign: TextAlign.center),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateList extends StatelessWidget {
  const _CandidateList({
    required this.candidates,
    required this.selected,
    required this.onSelected,
  });

  final List<TagCandidate> candidates;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          localizations.tagLookupPickHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RadioGroup<int>(
            groupValue: selected,
            onChanged: (index) {
              if (index != null) onSelected(index);
            },
            child: ListView(
              children: [
                for (final (index, candidate) in candidates.indexed)
                  _CandidateTile(index: index, candidate: candidate),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.index, required this.candidate});

  final int index;
  final TagCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final title = [
      candidate[TagField.artist],
      candidate[TagField.title],
    ].where((part) => part.isNotEmpty).join(" - ");
    final album = candidate[TagField.album];
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    // What kind of release it is, only when that says something: a plain
    // official album is the usual case.
    final kind = [
      ?_releaseKind(candidate.releaseType),
      if (candidate.releaseStatus != null &&
          candidate.releaseStatus != "Official")
        candidate.releaseStatus!,
    ].join(", ");
    final track = _trackOf(candidate, localizations);
    final released = _released(candidate.date, localizations);
    final percent = (candidate.score * 100).round();
    return RadioListTile<int>(
      dense: true,
      value: index,
      // The match, large, at the far side.
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$percent%",
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(localizations.tagLookupMatchLabel, style: quiet),
        ],
      ),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (album.isNotEmpty)
            Text(
              kind.isEmpty
                  ? localizations.tagLookupAlbum(album)
                  : "${localizations.tagLookupAlbum(album)} ($kind)",
            ),
          // The track number first and plainer; the date, which tells
          // releases apart less often, after it and dimmer.
          Text.rich(
            TextSpan(
              style: quiet?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
              children: [
                ?track == null ? null : TextSpan(text: track),
                if (track != null && released != null)
                  const TextSpan(text: " · "),
                ?released == null
                    ? null
                    : TextSpan(
                        text: released,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A MusicBrainz release group type as a reader would say it; null for a
/// plain album.
String? _releaseKind(String? type) => switch (type) {
  null || "" || "Album" => null,
  "Album + Live" => "Live album",
  "Album + Compilation" => "Compilation",
  "Album + Soundtrack" => "Soundtrack",
  final other => other.replaceAll(" + ", ", "),
};

/// "Released Jun 9, 2018", "Released Jun 2018" or "Released 2018", from a
/// `YYYY[-MM[-DD]]` date; null when there is none.
String? _released(String? date, AppLocalizations localizations) {
  if (date == null || date.length < 4) return null;
  final parts = date.split("-");
  final year = int.tryParse(parts[0]);
  final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
  final day = parts.length > 2 ? int.tryParse(parts[2]) : null;
  if (year == null) return null;
  if (month != null && month >= 1 && month <= 12) {
    if (day != null && day >= 1 && day <= 31) {
      return localizations.tagLookupReleasedOn(DateTime(year, month, day));
    }
    return localizations.tagLookupReleasedMonth(DateTime(year, month));
  }
  return localizations.tagLookupReleasedYear(parts[0]);
}

/// "Track 1 of 10" (and "Disc 2" beyond the first disc); null without a
/// track number.
String? _trackOf(TagCandidate candidate, AppLocalizations localizations) {
  final track = candidate[TagField.track];
  if (track.isEmpty) return null;
  final pieces = track.split("/");
  final text = pieces.length > 1 && pieces[1].isNotEmpty
      ? localizations.tagLookupTrackOf(pieces[0], pieces[1])
      : localizations.tagLookupTrack(pieces[0]);
  final disc = candidate[TagField.disc];
  return disc.isEmpty || disc == "1"
      ? text
      : "$text, ${localizations.tagLookupDisc(disc)}";
}
