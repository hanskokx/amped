import "package:meta/meta.dart";

/// What the tags of one file say, as plain data that can cross isolates and
/// be kept in a tag cache.
@immutable
class TrackTags {
  const TrackTags(
    this.path, {
    this.artist,
    this.album,
    this.title,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.genres = const [],
    this.imageUrl,
    this.published,
    this.progress,
    this.description,
    this.showDescription,
    this.series,
    this.showImageUrl,
    this.seasonImageUrl,
    this.artistImageUrl,
    this.added,
    this.lastWatched,
  });

  final String path;
  final String? artist;
  final String? album;
  final String? title;
  final int? trackNumber;
  final int? discNumber;

  /// The year it came out.
  final int? year;
  final Duration? duration;

  /// In kbps.
  final int? bitrate;

  /// In Hz.
  final int? sampleRate;
  final int? channels;

  /// Empty when there are none.
  final List<String> genres;

  /// The cover of a remote item (a podcast's or episode's picture); not kept
  /// in the tag cache.
  final String? imageUrl;

  /// When a podcast episode came out; not kept in the tag cache.
  final DateTime? published;

  /// How much of a podcast episode was played, 0 to 1 (1 when finished),
  /// as the server knew it when the source loaded; not kept in the tag cache.
  final double? progress;

  /// What an episode and its podcast are about, as plain text; not kept in
  /// the tag cache.
  final String? description;
  final String? showDescription;

  /// The series an audiobook is in; not kept in the tag cache.
  final String? series;

  /// The poster of an episode's show and season, and the picture of a
  /// track's artist; not kept in the tag cache.
  final String? showImageUrl;
  final String? seasonImageUrl;
  final String? artistImageUrl;

  /// When the item was added to its server, and when it was last watched;
  /// not kept in the tag cache.
  final DateTime? added;
  final DateTime? lastWatched;

  /// These tags with [progress] shown as how much was played.
  TrackTags withProgress(double? progress) => TrackTags(
    path,
    artist: artist,
    album: album,
    title: title,
    trackNumber: trackNumber,
    discNumber: discNumber,
    year: year,
    duration: duration,
    bitrate: bitrate,
    sampleRate: sampleRate,
    channels: channels,
    genres: genres,
    imageUrl: imageUrl,
    published: published,
    progress: progress,
    description: description,
    showDescription: showDescription,
    series: series,
    showImageUrl: showImageUrl,
    seasonImageUrl: seasonImageUrl,
    artistImageUrl: artistImageUrl,
    added: added,
    lastWatched: lastWatched,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackTags &&
      other.path == path &&
      other.artist == artist &&
      other.album == album &&
      other.title == title &&
      other.trackNumber == trackNumber &&
      other.discNumber == discNumber &&
      other.year == year &&
      other.duration == duration &&
      other.bitrate == bitrate &&
      other.sampleRate == sampleRate &&
      other.channels == channels &&
      _sameGenres(other.genres, genres) &&
      other.imageUrl == imageUrl &&
      other.published == published &&
      other.progress == progress &&
      other.description == description &&
      other.showDescription == showDescription &&
      other.series == series &&
      other.showImageUrl == showImageUrl &&
      other.seasonImageUrl == seasonImageUrl &&
      other.artistImageUrl == artistImageUrl &&
      other.added == added &&
      other.lastWatched == lastWatched;

  @override
  int get hashCode => Object.hashAll([
    path,
    artist,
    album,
    title,
    trackNumber,
    discNumber,
    year,
    duration,
    bitrate,
    sampleRate,
    channels,
    ...genres,
    imageUrl,
    published,
    progress,
    description,
    showDescription,
    series,
    showImageUrl,
    seasonImageUrl,
    artistImageUrl,
    added,
    lastWatched,
  ]);
}

/// Tags already read from files, kept so that a file is read only once.

bool _sameGenres(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
