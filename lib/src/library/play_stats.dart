import "dart:async";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";

import "../player/tag_cache.dart";

/// One line of a play statistics list.
@immutable
class PlayRow {
  const PlayRow({
    required this.label,
    required this.plays,
    required this.lastPlayed,
    this.location,
  });

  /// "Artist - Title" for a song or video; the name of a podcast.
  final String label;
  final int plays;
  final DateTime lastPlayed;

  /// What to play when the row is opened; null for a whole podcast.
  final String? location;
}

/// How often the user played things, for the Media Library's "Most played"
/// lists. Songs, videos and podcasts are all counted; the songs are the
/// main list, the others have lists of their own, and podcasts are counted
/// by podcast rather than by episode.
class PlayStats extends ChangeNotifier {
  PlayStats(this._storeOf);

  /// The store, which may open after this does; null while there is none.
  final PlayStatsStore? Function() _storeOf;
  final Map<String, PlayStat> _stats = {};
  bool _disposed = false;

  /// Reads what was counted before.
  Future<void> load() async {
    try {
      final stats = await _storeOf()?.playStats();
      if (_disposed || stats == null) return;
      for (final stat in stats) {
        _stats[stat.location] = stat;
      }
      notifyListeners();
    } on Object catch (error) {
      Arcane.log(
        "Could not read the play statistics",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "PlayStats",
      );
    }
  }

  /// Counts a play of [location]. Never throws.
  Future<void> record(
    String location,
    PlayKind kind, {
    String? title,
    String? artist,
    String? album,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final was = _stats[location];
    _stats[location] = PlayStat(
      location: location,
      kind: kind,
      plays: (was?.plays ?? 0) + 1,
      lastPlayed: now,
      title: title ?? was?.title,
      artist: artist ?? was?.artist,
      album: album ?? was?.album,
    );
    if (!_disposed) notifyListeners();
    try {
      await _storeOf()?.recordPlay(
        location,
        kind,
        title: title,
        artist: artist,
        album: album,
        at: now,
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not keep the play count",
        metadata: {"location": location, "error": "$error"},
        level: Level.warning,
        module: "PlayStats",
      );
    }
  }

  /// How often [location] was played.
  int playsOf(String location) => _stats[location]?.plays ?? 0;

  /// The most played of [kind] first, the most recently played of equally
  /// played first. Podcasts are summed by podcast.
  List<PlayRow> mostPlayed(PlayKind kind) => [..._rows(kind)]
    ..sort((a, b) {
      final byPlays = b.plays.compareTo(a.plays);
      return byPlays != 0 ? byPlays : b.lastPlayed.compareTo(a.lastPlayed);
    });

  /// What of [kind] was played last, the most recent first.
  List<PlayRow> recentlyPlayed(PlayKind kind) =>
      [..._rows(kind)]..sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));

  Iterable<PlayRow> _rows(PlayKind kind) {
    final stats = _stats.values.where((s) => s.kind == kind);
    if (kind != PlayKind.podcast) {
      return [
        for (final s in stats)
          PlayRow(
            label: _label(s),
            plays: s.plays,
            lastPlayed: s.lastPlayed,
            location: s.location,
          ),
      ];
    }
    final byPodcast = <String, PlayRow>{};
    for (final s in stats) {
      final name = s.album ?? s.artist ?? s.title ?? s.location;
      final was = byPodcast[name];
      byPodcast[name] = PlayRow(
        label: name,
        plays: (was?.plays ?? 0) + s.plays,
        lastPlayed: was != null && was.lastPlayed.isAfter(s.lastPlayed)
            ? was.lastPlayed
            : s.lastPlayed,
      );
    }
    return byPodcast.values;
  }

  static String _label(PlayStat s) {
    final title = s.title ?? s.location.split(RegExp(r"[\\/]")).last;
    final artist = s.artist;
    return artist == null || artist.isEmpty ? title : "$artist - $title";
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
