/// What a file's path says about the track, to rank tag lookup candidates:
/// `Artist/Album (Year)/07. Title.mp3`, `.../Artist - Album - 07 - Title.mp3`
/// and the like.
library;

import "tag_lookup.dart";
import "tag_model.dart";

class PathHints {
  const PathHints({this.artist, this.album, this.title, this.track, this.year});

  final String? artist;
  final String? album;
  final String? title;
  final int? track;
  final String? year;

  /// Reads [path]: the file name for track number and title, its folder for
  /// the album (and year), the one above for the artist.
  factory PathHints.parse(String path) {
    final parts = path.split(RegExp(r"[\\/]")).where((p) => p.isNotEmpty);
    final names = parts.toList();
    if (names.isEmpty) return const PathHints();
    var stem = names.last;
    final dot = stem.lastIndexOf(".");
    if (dot > 0) stem = stem.substring(0, dot);

    int? track;
    String? title;
    final leading = RegExp(
      r"^(?:\d{1,2}-)?(\d{1,3})(?:\s*[-._)]\s*|\s+)(.+)$",
    ).firstMatch(stem);
    if (leading != null) {
      track = int.tryParse(leading[1]!);
      title = leading[2]!.trim();
    } else {
      // "Artist - Album - 01 - Title": the track number between dashes.
      final pieces = stem.split(RegExp(r"\s+-\s+"));
      final at = pieces.indexWhere((p) => RegExp(r"^\d{1,3}$").hasMatch(p));
      if (at >= 0 && at < pieces.length - 1) {
        track = int.tryParse(pieces[at]);
        title = pieces.sublist(at + 1).join(" - ");
      } else {
        title = stem.trim();
      }
    }

    String? album;
    String? year;
    if (names.length >= 2) {
      var folder = names[names.length - 2];
      final trailing = RegExp(r"\s*[\(\[](\d{4})[\)\]]\s*$").firstMatch(folder);
      final leadingYear = RegExp(r"^(\d{4})\s*[-._]\s*").firstMatch(folder);
      if (trailing != null) {
        year = trailing[1];
        folder = folder.substring(0, trailing.start);
      } else if (leadingYear != null) {
        year = leadingYear[1];
        folder = folder.substring(leadingYear.end);
      }
      album = folder.trim();
    }
    final artist = names.length >= 3 ? names[names.length - 3] : null;
    return PathHints(
      artist: artist,
      album: album,
      title: title,
      track: track,
      year: year,
    );
  }

  /// How well [candidate] fits what the path says: higher is better.
  double score(TagCandidate candidate) {
    var score = 0.0;
    score += _text(candidate[TagField.title], title) * 3;
    score += _text(candidate[TagField.album], album) * 3;
    final artistFit = [
      _text(candidate[TagField.artist], artist),
      _text(candidate[TagField.albumArtist], artist),
    ].reduce((a, b) => a > b ? a : b);
    score += artistFit * 2;
    // "7/10" or "7".
    final candidateTrack = int.tryParse(
      candidate[TagField.track].split("/").first,
    );
    if (track != null && candidateTrack == track) score += 2;
    if (year != null && candidate[TagField.year] == year) score += 1;
    return score;
  }
}

/// 1 for the same text, a half when one holds the other, else 0.
double _text(String candidate, String? hint) {
  if (hint == null) return 0;
  final a = _normalize(candidate);
  final b = _normalize(hint);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  return a.contains(b) || b.contains(a) ? 0.5 : 0;
}

String _normalize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp("[‘’‛`]"), "'")
    .replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), "");

/// [candidates] with those that fit the path of [file] first, the rest in
/// the order they came (so, among equal fits, the lookup's own order).
List<TagCandidate> rankByPath(List<TagCandidate> candidates, String file) {
  final hints = PathHints.parse(file);
  final scored =
      [
        for (final (index, candidate) in candidates.indexed)
          (candidate, hints.score(candidate), index),
      ]..sort((a, b) {
        final byScore = b.$2.compareTo(a.$2);
        return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
      });
  return [for (final entry in scored) entry.$1];
}
