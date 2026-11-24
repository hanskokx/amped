import "dart:async";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";

import "../player/playlist.dart";
import "../player/tag_cache.dart";

/// Reads the tags of files, null for one that can't be read.
typedef TagReader = Future<List<TrackTags?>> Function(List<String> files);

/// The tracks the user added to the Media Library, with their tags. Which
/// files are in the library, and their tags, live in the SQLite tag cache
/// (see [open]), so the library is there on the next start and a file is
/// read only once.
class MediaLibrary extends ChangeNotifier {
  MediaLibrary({TagReader? readTags, bool Function(String path)? accepts})
    : _readTags = readTags ?? _defaultReader,
      accepts = accepts ?? Playlist.isAudio;

  /// A library of the video files instead of the audio files.
  MediaLibrary.videos({TagReader? readTags})
    : this(readTags: readTags, accepts: Playlist.isVideo);

  /// Which files the library takes when files or folders are added, and
  /// which of the files of the shared store are its own when it opens.
  final bool Function(String path) accepts;

  static Future<List<TrackTags?>> _defaultReader(List<String> files) =>
      readTagsInBackground(files);

  /// How many files one tag read covers.
  static const _batchSize = 32;

  final TagReader _readTags;
  final Map<String, TrackTags> _tracks = {};
  List<TrackTags>? _sorted;
  TagCache? _cache;
  LibraryStore? _store;
  bool _scanning = false;
  int _scanned = 0;
  bool _cancelRequested = false;
  bool _disposed = false;

  /// Every track, sorted by artist, album, disc, track number and title.
  List<TrackTags> get tracks =>
      _sorted ??= (_tracks.values.toList()..sort(compareTracks));

  bool get isEmpty => _tracks.isEmpty;

  /// The tags of the track at [path], or null when it is not in the library.
  TrackTags? tagsOf(String path) => _tracks[path];

  /// Whether files are being added.
  bool get scanning => _scanning;

  /// How many files the running scan has added so far.
  int get scanned => _scanned;

  /// Stops the running scan after the batch it is on. What was added so far
  /// stays. Does nothing when no scan is running.
  void cancel() {
    if (_scanning) _cancelRequested = true;
  }

  /// How tracks are ordered in the library.
  static int compareTracks(TrackTags a, TrackTags b) {
    final byArtist = _compareText(a.artist, b.artist);
    if (byArtist != 0) return byArtist;
    final byAlbum = _compareText(a.album, b.album);
    if (byAlbum != 0) return byAlbum;
    final byDisc = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
    if (byDisc != 0) return byDisc;
    final byNumber = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
    if (byNumber != 0) return byNumber;
    final byTitle = _compareText(a.title, b.title);
    return byTitle != 0 ? byTitle : a.path.compareTo(b.path);
  }

  static int _compareText(String? a, String? b) =>
      (a ?? "").toLowerCase().compareTo((b ?? "").toLowerCase());

  /// The artists of the tracks, sorted; tracks without one count as
  /// `null` and are left out.
  List<String> get artists => _distinct(tracks.map((t) => t.artist));

  /// The artists of the tracks that match [query] (see [search]), sorted.
  List<String> artistsMatching(String query) {
    final words = _words(query);
    return _distinct(
      tracks.where((t) => _matches(t, words)).map((t) => t.artist),
    );
  }

  /// The albums of [artist]'s tracks (of all tracks when null) that match
  /// [query] (see [search]).
  List<String> albums({String? artist, String query = ""}) {
    final words = _words(query);
    return _distinct(
      tracks
          .where(
            (t) => (artist == null || t.artist == artist) && _matches(t, words),
          )
          .map((t) => t.album),
    );
  }

  static List<String> _words(String query) => query
      .toLowerCase()
      .split(RegExp(r"\s+"))
      .where((w) => w.isNotEmpty)
      .toList();

  static List<String> _distinct(Iterable<String?> values) {
    final seen = <String>{
      for (final value in values)
        if (value != null && value.trim().isNotEmpty) value,
    };
    return seen.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// The tracks of [artist] and [album] (any when null) whose artist, album,
  /// title or file name contains every word of [query].
  List<TrackTags> search({String query = "", String? artist, String? album}) {
    final words = _words(query);
    return [
      for (final track in tracks)
        if ((artist == null || track.artist == artist) &&
            (album == null || track.album == album) &&
            _matches(track, words))
          track,
    ];
  }

  static bool _matches(TrackTags track, List<String> words) {
    if (words.isEmpty) return true;
    final haystack = [
      track.artist,
      track.album,
      track.title,
      track.path.split(RegExp(r"[\\/]")).last,
    ].whereType<String>().join("\n").toLowerCase();
    return words.every(haystack.contains);
  }

  /// Adds the audio files of [locations]: files as they are, folders with
  /// everything in them. Files that are already in the library are skipped,
  /// and tags the cache has are not read from the files again.
  Future<void> add(Iterable<String> locations) async {
    if (_scanning) return;
    _scanning = true;
    _cancelRequested = false;
    _scanned = 0;
    notifyListeners();
    try {
      final files = <String>[];
      for (final location in locations) {
        files.addAll(await _expand(location));
      }
      // Files already in the library are skipped, and so are repeats.
      await _take(
        {
          for (final file in files)
            if (!_tracks.containsKey(file)) file,
        }.toList(),
      );
    } finally {
      _scanning = false;
      _cancelRequested = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Replaces the tracks with those [producer] hands to its `add` callback,
  /// for a source whose tracks come from a server rather than from files.
  /// Counts as scanning while it runs, and [cancel] stops it.
  Future<void> fill(
    Future<void> Function(
      void Function(List<TrackTags> tracks) add,
      bool Function() isCancelled,
    )
    producer,
  ) async {
    if (_scanning) return;
    _scanning = true;
    _cancelRequested = false;
    _scanned = 0;
    _tracks.clear();
    _sorted = null;
    notifyListeners();
    // Listeners re-sort and rebuild on every notification, so while pages
    // arrive quickly they hear about them at most every 250 ms.
    Timer? pending;
    try {
      await producer((tracks) {
        if (_disposed) return;
        for (final track in tracks) {
          _tracks[track.path] = track;
        }
        _sorted = null;
        _scanned += tracks.length;
        pending ??= Timer(const Duration(milliseconds: 250), () {
          pending = null;
          if (!_disposed) notifyListeners();
        });
      }, () => _disposed || _cancelRequested);
    } finally {
      pending?.cancel();
      _scanning = false;
      _cancelRequested = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Replaces the tracks with [tracks] without touching the store: for a
  /// library that only mirrors others, such as "All videos".
  void replaceWith(Iterable<TrackTags> tracks) {
    if (_disposed) return;
    _tracks
      ..clear()
      ..addEntries([for (final track in tracks) MapEntry(track.path, track)]);
    _sorted = null;
    notifyListeners();
  }

  /// Replaces the tags of the track with the same path, for what a source
  /// knows only for now (such as how much of an episode was played); the
  /// store is not touched.
  void update(TrackTags tags) {
    if (_disposed || !_tracks.containsKey(tags.path)) return;
    _tracks[tags.path] = tags;
    _sorted = null;
    notifyListeners();
  }

  /// Puts [files] in the library, reading the tags the cache lacks.
  Future<void> _take(List<String> files) async {
    for (var start = 0; start < files.length; start += _batchSize) {
      if (_disposed || _cancelRequested) return;
      final batch = files.sublist(
        start,
        (start + _batchSize).clamp(0, files.length),
      );
      final tags = await _tagsOf(batch);
      for (final path in batch) {
        // A file that can't be read is still worth listing.
        _tracks[path] = tags[path] ?? TrackTags(path);
      }
      await _guarded(() async => _store?.addToLibrary(batch));
      _sorted = null;
      _scanned += batch.length;
      if (!_disposed) notifyListeners();
    }
  }

  /// The tags of [files]: from the cache, and from the files for the rest
  /// (which are then cached).
  Future<Map<String, TrackTags>> _tagsOf(List<String> files) async {
    final found = <String, TrackTags>{
      ...?await _guarded(() async => _cache?.lookup(files)),
    };
    final missing = [
      for (final file in files)
        if (!found.containsKey(file)) file,
    ];
    if (missing.isNotEmpty) {
      final read = await _readTags(missing);
      final fresh = read.nonNulls.toList();
      for (final tags in fresh) {
        found[tags.path] = tags;
      }
      await _guarded(() async => _cache?.store(fresh));
    }
    return found;
  }

  /// Runs [action] on the cache; a failure is logged and the library goes
  /// on in memory.
  Future<T?> _guarded<T>(Future<T?> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      Arcane.log(
        "The library's database failed",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "MediaLibrary",
      );
      return null;
    }
  }

  Future<List<String>> _expand(String location) async {
    if (await FileSystemEntity.isDirectory(location)) {
      final files = <String>[];
      await _walk(Directory(location), files);
      files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return files;
    }
    return accepts(location) ? [location] : const [];
  }

  /// Collects the audio files under [directory] into [files].
  ///
  /// Apple Music's library bundle (`Music Library.musiclibrary`) sits in
  /// ~/Music; macOS asks for "media library" access whenever a process
  /// reads inside it, and asks again on every launch. It holds no audio we
  /// can use, so it is not entered.
  Future<void> _walk(Directory directory, List<String> files) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is Directory) {
          if (!_isProtectedBundle(entity.path)) await _walk(entity, files);
        } else if (entity is File && accepts(entity.path)) {
          files.add(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      Arcane.log(
        "Could not scan the folder",
        metadata: {"path": directory.path, "error": "$error"},
        level: Level.warning,
        module: "MediaLibrary",
      );
    }
  }

  static bool _isProtectedBundle(String path) {
    final name = path.split("/").last.toLowerCase();
    return name.endsWith(".musiclibrary") ||
        name.endsWith(".photoslibrary") ||
        name.endsWith(".tvlibrary");
  }

  /// Reads the tags of those of [paths] that are in the library again,
  /// after they were edited.
  Future<void> refresh(Iterable<String> paths) async {
    final known = [
      for (final path in paths)
        if (_tracks.containsKey(path)) path,
    ];
    if (known.isEmpty) return;
    final read = (await _readTags(known)).nonNulls.toList();
    if (_disposed) return;
    for (final tags in read) {
      _tracks[tags.path] = tags;
    }
    _sorted = null;
    notifyListeners();
    await _guarded(() async => _cache?.store(read));
  }

  /// Removes the tracks at [paths] from the library (the files stay).
  Future<void> remove(Iterable<String> paths) async {
    final removed = paths.toList();
    removed.forEach(_tracks.remove);
    _sorted = null;
    notifyListeners();
    await _guarded(() async => _store?.removeFromLibrary(removed));
  }

  /// Empties the library.
  Future<void> clear() => remove(_tracks.keys.toList());

  /// Keeps the library in [cache] (when it is a [LibraryStore], as the
  /// SQLite one is) and loads what it holds. Files whose tags the cache
  /// lost are read again.
  Future<void> open(TagCache cache) async {
    _cache = cache;
    _store = cache is LibraryStore ? cache as LibraryStore : null;
    final stored = await _guarded(() async => _store?.libraryPaths());
    final paths = stored?.where(accepts).toList();
    if (paths == null || paths.isEmpty || _disposed) return;
    _scanning = true;
    _cancelRequested = false;
    _scanned = 0;
    notifyListeners();
    try {
      await _take(paths);
    } finally {
      _scanning = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
