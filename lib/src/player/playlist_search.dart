import "playlist.dart";

/// One playlist entry that matched a search, with how well.
class PlaylistMatch {
  const PlaylistMatch(this.index, this.score);

  /// The entry's index in the playlist.
  final int index;

  /// Higher is a better match.
  final int score;
}

/// Fuzzy search over the playlist: the words of a query must each be found
/// in the entry's title, tags or file name (case-insensitively, in any
/// order). A word is found as it is, or, from three letters on, as a looser
/// match: its letters in order in a short stretch of text ("bhmn" finds
/// "Bohemian").
class PlaylistSearch {
  const PlaylistSearch._();

  /// The words of [query], lower case.
  static List<String> words(String query) => [
    for (final word in query.toLowerCase().split(RegExp(r"\s+")))
      if (word.isNotEmpty) word,
  ];

  /// What [entry] is searched in: everything the playlist can show about it.
  static String haystack(PlaylistEntry entry) {
    final location = entry.location;
    final name = location.split(RegExp(r"[\\/]")).last;
    return [
      entry.title,
      entry.artist,
      entry.album,
      entry.trackTitle,
      ...entry.genres,
      name,
    ].whereType<String>().where((s) => s.isNotEmpty).join("\n").toLowerCase();
  }

  /// How well [word] is found in [text], or null: 100 for a match at the
  /// start of a word, 80 elsewhere, and under 60 for letters in order (the
  /// closer together, the better).
  static int? scoreWord(String word, String text) {
    final at = text.indexOf(word);
    if (at >= 0) {
      final startsWord = at == 0 || !_isLetter(text.codeUnitAt(at - 1));
      return startsWord ? 100 : 80;
    }
    if (word.length < 3) return null;
    // The letters in order, within a stretch no longer than twice the
    // word, so that a long title does not match everything.
    final maxSpan = word.length * 2;
    final first = word.codeUnitAt(0);
    int? best;
    for (
      var start = text.indexOf(String.fromCharCode(first));
      start >= 0;
      start = text.indexOf(String.fromCharCode(first), start + 1)
    ) {
      var pos = start;
      var ok = true;
      for (var i = 1; i < word.length; i++) {
        pos = text.indexOf(String.fromCharCode(word.codeUnitAt(i)), pos + 1);
        if (pos < 0 || pos - start >= maxSpan) {
          ok = false;
          break;
        }
      }
      if (ok) {
        final span = pos - start + 1;
        final score = 59 - (span - word.length);
        if (best == null || score > best) best = score;
      }
    }
    return best;
  }

  static bool _isLetter(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      unit > 0x7f;

  /// How well [entry] matches the [words], or null when a word is missing.
  static int? scoreEntry(List<String> words, PlaylistEntry entry) {
    final text = haystack(entry);
    var total = 0;
    for (final word in words) {
      final score = scoreWord(word, text);
      if (score == null) return null;
      total += score;
    }
    return total;
  }

  /// The entries of [playlist] that match [query], best first (the
  /// playlist's order among equals). Empty for an empty query.
  static List<PlaylistMatch> search(Playlist playlist, String query) {
    final queryWords = words(query);
    if (queryWords.isEmpty) return const [];
    final entries = playlist.entries;
    final matches = <PlaylistMatch>[];
    for (var i = 0; i < entries.length; i++) {
      final score = scoreEntry(queryWords, entries[i]);
      if (score != null) matches.add(PlaylistMatch(i, score));
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
    return matches;
  }
}
