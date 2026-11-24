import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:url_launcher/url_launcher.dart";

/// A piece of a description: plain text, a link, or a time in the episode.
sealed class DescriptionPart {
  const DescriptionPart(this.text);

  /// The text as it is written.
  final String text;
}

class PlainPart extends DescriptionPart {
  const PlainPart(super.text);
}

class LinkPart extends DescriptionPart {
  const LinkPart(super.text, this.uri);

  final Uri uri;
}

class TimePart extends DescriptionPart {
  const TimePart(super.text, this.at);

  /// Where in the episode it points.
  final Duration at;
}

/// Splits [text] into plain text, links and times.
///
/// Links are written with `https://` or `http://`, or bare (`plus.npr.org`,
/// `example.com/show`) when they end in a well-known top-level domain; the
/// punctuation after one belongs to the sentence. Times are `12:34` or
/// `1:02:03` in parentheses or brackets, or on their own (at the start of a
/// line or after a space, followed by a space, a dash or the end), unless a
/// clock time (`10:30 PM`) or beyond the end of the episode, which is [length]
/// when known.
List<DescriptionPart> parseDescription(String text, {Duration? length}) {
  final matches = <({int start, int end, DescriptionPart part})>[];

  for (final match in _links.allMatches(text)) {
    var end = match.end;
    var found = text.substring(match.start, end);
    // The sentence's punctuation, and a bracket that was not opened inside.
    while (found.isNotEmpty) {
      final last = found[found.length - 1];
      final unbalanced =
          (last == ")" && !found.contains("(")) ||
          (last == "]" && !found.contains("["));
      if (".,;:!?'\"".contains(last) || unbalanced) {
        found = found.substring(0, found.length - 1);
        end--;
      } else {
        break;
      }
    }
    final uri = Uri.tryParse(
      found.contains("://") ? found : "https://$found",
    );
    if (uri == null || !uri.hasAuthority || !uri.host.contains(".")) continue;
    matches.add((start: match.start, end: end, part: LinkPart(found, uri)));
  }

  for (final match in _times.allMatches(text)) {
    final start = match.start;
    final end = match.end;
    if (matches.any((m) => start < m.end && end > m.start)) continue;
    final clock = match.group(2)!;
    final enclosed = match.group(1) != null || match.group(3) != null;
    if (!enclosed) {
      // On its own: after the start or a space, before a space, a dash or
      // the end, and not a clock time.
      final before = start == 0 ? " " : text[start - 1];
      final after = end >= text.length ? " " : text[end];
      if (!(before == " " || before == "\n" || before == "\t")) continue;
      if (!(after == " " ||
          after == "\n" ||
          after == "\t" ||
          "-–—:".contains(after))) {
        continue;
      }
      final tail = text.substring(end).trimLeft().toLowerCase();
      if (RegExp(r"^(a\.?m|p\.?m)\b").hasMatch(tail)) continue;
    }
    final parts = clock.split(":").map(int.parse).toList();
    final seconds = parts.length == 3
        ? parts[0] * 3600 + parts[1] * 60 + parts[2]
        : parts[0] * 60 + parts[1];
    if (parts.length == 3 ? parts[1] > 59 || parts[2] > 59 : parts[1] > 59) {
      continue;
    }
    final at = Duration(seconds: seconds);
    if (length != null && length > Duration.zero && at > length) continue;
    // Only the time itself is the link, not its brackets.
    final from = start + (match.group(1)?.length ?? 0);
    matches.add((
      start: from,
      end: from + clock.length,
      part: TimePart(clock, at),
    ));
  }

  matches.sort((a, b) => a.start.compareTo(b.start));
  final parts = <DescriptionPart>[];
  var at = 0;
  for (final match in matches) {
    if (match.start < at) continue;
    if (match.start > at) parts.add(PlainPart(text.substring(at, match.start)));
    parts.add(match.part);
    at = match.end;
  }
  if (at < text.length) parts.add(PlainPart(text.substring(at)));
  return parts;
}

const _topLevels =
    "com|org|net|edu|gov|io|co|uk|fr|de|nl|be|ca|au|us|info|fm|tv|me|app|dev|"
    "ly|link|news|media|podcast|show|ai|eu|es|it|se|no|dk|ch|at|nz|ie|in|jp|"
    "club|xyz|page|fyi|live|site|online|store|shop|FM|audio|today|world";

/// An address: with a scheme, or a bare one ending in a top-level domain,
/// not part of an email address or a longer word.
final RegExp _links = RegExp(
  r"""(?:https?://[^\s<>"]+)|"""
  r"""(?<![@\w./-])(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:"""
  "$_topLevels"
  r""")\b(?![@\w-])(?:/[^\s<>"]*)?""",
  caseSensitive: false,
);

/// `[12:34]`, `(1:02:03)` or a bare time; group 1 and 3 are the opening and
/// closing bracket, group 2 the time.
final RegExp _times = RegExp(r"([(\[])?\b(\d{1,2}:\d{2}(?::\d{2})?)\b([)\]])?");

/// Shows a description: the links open in the browser and the times call
/// [onSeek] (when it is given), and the text can be selected and copied.
class DescriptionText extends StatefulWidget {
  const DescriptionText({
    required this.text,
    required this.style,
    required this.linkColor,
    this.length,
    this.onSeek,
    this.selectionColor,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;

  /// What a selection is highlighted with.
  final Color? selectionColor;

  /// How long the episode is, to leave out times beyond it.
  final Duration? length;

  /// Called with a time that was clicked; times are plain text without it.
  final ValueChanged<Duration>? onSeek;

  @override
  State<DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<DescriptionText> {
  final List<TapGestureRecognizer> _recognizers = [];
  final FocusNode _focus = FocusNode(debugLabel: "description");

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final link = widget.style.copyWith(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final spans = <InlineSpan>[];
    for (final part in parseDescription(widget.text, length: widget.length)) {
      switch (part) {
        case PlainPart(:final text):
          spans.add(TextSpan(text: text));
        case LinkPart(:final text, :final uri):
          spans.add(
            TextSpan(
              text: text,
              style: link,
              mouseCursor: SystemMouseCursors.click,
              recognizer: _tap(
                () => launchUrl(uri, mode: LaunchMode.externalApplication),
              ),
            ),
          );
        case TimePart(:final text, :final at):
          final onSeek = widget.onSeek;
          spans.add(
            onSeek == null
                ? TextSpan(text: text)
                : TextSpan(
                    text: text,
                    style: link,
                    mouseCursor: SystemMouseCursors.click,
                    recognizer: _tap(() => onSeek(at)),
                  ),
          );
      }
    }
    // The text cursor over text that can be selected (and while selecting);
    // links and times keep the pointing hand.
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: DefaultSelectionStyle(
        mouseCursor: SystemMouseCursors.text,
        selectionColor: widget.selectionColor,
        child: SelectableRegion(
          focusNode: _focus,
          selectionControls: emptyTextSelectionControls,
          child: Text.rich(TextSpan(children: spans), style: widget.style),
        ),
      ),
    );
  }
}
