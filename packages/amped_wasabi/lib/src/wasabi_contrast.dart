import "dart:ui";

/// [text] if it can be read on [background], else the nearest colour that
/// can: [text] moved toward white or black, whichever contrasts more with
/// the background, just far enough to reach [minContrast] (WCAG's 4.5:1 for
/// normal text).
///
/// Skins pick their list colours for the look of the whole window and some
/// of them end up as grey on a slightly darker grey (GlassAMP's list text is
/// 100,100,100 on 42,42,42, 2.4:1), which the original shows in a list of
/// its own size and weight but is hard to read in the app's lists.
Color wasabiLegible(Color text, Color background, {double minContrast = 4.5}) {
  final bg = background.a < 1
      ? Color.alphaBlend(background, const Color(0xFF000000))
      : background;
  if (_contrast(text, bg) >= minContrast) return text;
  final target =
      _contrast(const Color(0xFFFFFFFF), bg) >=
          _contrast(const Color(0xFF000000), bg)
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  Color best = target;
  // The smallest step toward the target that reads well.
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(text, target, step / 20)!;
    if (_contrast(candidate, bg) >= minContrast) {
      best = candidate;
      break;
    }
  }
  return best.withValues(alpha: text.a);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
