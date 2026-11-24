import "dart:math";

import "../player/tag_cache.dart";

/// What a generated playlist has in common with its seed tracks.
enum PlaylistCriterion {
  /// Tracks by an artist of the seeds.
  artist,

  /// Tracks of an album of the seeds.
  album,

  /// Tracks in a genre of the seeds.
  genre,

  /// Tracks that share an artist, an album or a genre with the seeds, the
  /// ones that share the most first.
  similar,
}

/// Builds playlists from the Media Library's tags and some seed tracks.
class PlaylistGenerator {
  const PlaylistGenerator._();

  /// How many tracks a generated playlist has at most, the seeds included.
  static const defaultLimit = 50;

  /// The playlist for [seeds]: the seeds themselves, then the tracks of
  /// [library] that match [criterion], at most [limit] in all. The matches
  /// are in random order ([random]); for [PlaylistCriterion.similar] the
  /// closer ones come before the others.
  static List<String> generate({
    required Iterable<TrackTags> library,
    required List<TrackTags> seeds,
    required PlaylistCriterion criterion,
    int limit = defaultLimit,
    Random? random,
  }) {
    if (seeds.isEmpty) return const [];
    final seedPaths = {for (final seed in seeds) seed.path};
    final artists = {for (final s in seeds) ?_key(s.artist)};
    final albums = {for (final s in seeds) ?_key(s.album)};
    final genres = {
      for (final s in seeds)
        for (final genre in s.genres) ?_key(genre),
    };

    int score(TrackTags track) {
      final byArtist = artists.contains(_key(track.artist));
      final byAlbum = albums.contains(_key(track.album));
      final byGenre = track.genres.any((g) => genres.contains(_key(g)));
      return switch (criterion) {
        PlaylistCriterion.artist => byArtist ? 1 : 0,
        PlaylistCriterion.album => byAlbum ? 1 : 0,
        PlaylistCriterion.genre => byGenre ? 1 : 0,
        PlaylistCriterion.similar =>
          (byArtist ? 3 : 0) + (byGenre ? 2 : 0) + (byAlbum ? 1 : 0),
      };
    }

    final matches = [
      for (final track in library)
        if (!seedPaths.contains(track.path) && score(track) > 0)
          (track: track, score: score(track)),
    ]..shuffle(random);
    // The sort is stable, so ties stay in the shuffled order.
    _sortByScore(matches);
    return [
      for (final seed in seeds) seed.path,
      for (final match in matches) match.track.path,
    ].take(max(limit, 0)).toList();
  }

  static void _sortByScore(List<({TrackTags track, int score})> list) {
    // List.sort is not guaranteed stable; keep the shuffled index as the
    // tie-breaker.
    final order = {for (var i = 0; i < list.length; i++) list[i].track.path: i};
    list.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : order[a.track.path]!.compareTo(order[b.track.path]!);
    });
  }

  static String? _key(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
