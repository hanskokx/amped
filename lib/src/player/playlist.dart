import "dart:async";
import "dart:collection";
import "dart:io";
import "dart:isolate";
import "dart:math";

import "package:amped/src/player/mp3_info.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_youtube/amped_youtube.dart";
import "package:audio_metadata_reader/audio_metadata_reader.dart";
import "package:flutter/foundation.dart";

import "../remote/remote_files.dart";
import "../remote/remote_location.dart";
import "../tags/tag_io.dart";
import "shared_youtube.dart";
import "tag_cache.dart";

/// One playlist entry: a local file or a URL.
class PlaylistEntry implements ClassicPlaylistEntry {
  PlaylistEntry(this.location) : title = _defaultTitle(location);

  /// The file path or URL.
  final String location;

  /// Whether the file is on a watched folder that can't be reached now (a
  /// network share that is not mounted): it is shown greyed out.
  @override
  bool unavailable = false;

  /// The display title: "Artist - Title" from the tags when available,
  /// otherwise the file name without its extension (the classic player's default title
  /// format).
  @override
  String title;

  /// What a playing station says is on now (its `StreamTitle`, usually
  /// "Artist - Title"), shown in place of [title] while it plays; the entry
  /// keeps [title] (the station's name from the playlist file) and this is
  /// never saved. Null when the entry isn't a playing station.
  String? streamTitle;

  /// The title of what is playing on this entry: [streamTitle] while a
  /// station sends one, otherwise [title].
  String get playingTitle => streamTitle ?? title;

  /// Whether [title] came from a playlist file (`#EXTINF`, `TitleN=`); the
  /// original keeps such "cached" titles instead of re-reading the tags.
  bool titleFromList = false;

  /// The tag fields, once read (for the OS media session).
  String? artist;
  String? album;
  String? trackTitle;

  /// The genres from the tags, once read (empty when there are none).
  List<String> genres = const [];

  /// The track and disc numbers from the tags, once read (for the album
  /// sorts).
  int? trackNumber;
  int? discNumber;

  /// The track length, once known (from the tags or the decoder).
  @override
  Duration? duration;

  /// The bitrate in kbps and sample rate in Hz, once known.
  int? bitrate;
  int? sampleRate;

  /// The number of audio channels, once known (lights the main window's
  /// mono or stereo indicator).
  @override
  int? channels;

  /// Whether this entry's tags have been read (or tried), from the tag
  /// cache or the file, or are being read.
  bool _tagsRead = false;

  /// Whether this entry has been looked up in the tag cache.
  bool _cacheChecked = false;

  /// Counts the tag reads started for this entry, so that only the latest
  /// one's tags are applied.
  int _tagReadId = 0;

  /// The read of this entry's tags, once started.
  Future<void>? _tagsReading;

  bool get isUrl => location.contains("://");

  /// Whether this is a track of a remote source (`amped-source://`), whose
  /// tags the tag cache holds though it is no file.
  bool get isSource => SourceLocation.isSource(location);

  /// Whether a [Playlist] reads this entry's tags: files, and source tracks
  /// from the cache. Streams have none.
  bool get hasTags => !isUrl || isSource;

  static String _defaultTitle(String location) {
    final remote = RemoteLocation.tryParse(location);
    if (remote != null && remote.name.isNotEmpty) {
      final dot = remote.name.lastIndexOf(".");
      return dot > 0 ? remote.name.substring(0, dot) : remote.name;
    }
    if (location.contains("://")) return location;
    final name = location.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf(".");
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// One entry of a playlist file: its location and, when the file records
/// them, its title and length.
class ListItem {
  const ListItem(this.location, {this.title, this.duration});

  final String location;
  final String? title;
  final Duration? duration;
}

/// How [Playlist.sort] orders entries (the MISC > Sort list menu).
enum PlaylistSort {
  title,
  fileName,
  path,

  /// By artist tag.
  artist,

  /// By album tag, then disc and track number.
  album,

  /// By artist tag, then album, then disc and track number.
  artistAlbum;

  /// Whether this sort needs the entries' tags.
  bool get usesTags => index >= artist.index;
}

/// The playlist: entries, the current entry, and the selection, with the
/// editing operations of the original playlist editor.
class Playlist extends ChangeNotifier implements ClassicPlaylist {
  /// [random] drives shuffle picks and Randomize list (tests pass a seeded
  /// one).
  ///
  /// [tagCache] keeps the tags read from files, so each file is read once.
  Playlist({
    Random? random,
    this.tagCache,
    RemoteFiles? remoteFiles,
    YouTubeResolver? youtube,
  }) : _random = random ?? Random(),
       _remoteFiles = remoteFiles ?? RemoteFiles.shared,
       _youtube = youtube ?? sharedYouTube;

  /// Reads YouTube playlists.
  final YouTubeResolver _youtube;

  /// Lists the folders on network shares.
  final RemoteFiles _remoteFiles;

  /// Where tags read from files are kept between runs. Entries with a
  /// cached row take their tags from it, and their files are not touched;
  /// only the others are read, and their tags are added. Null when there is
  /// none (or it failed), and every file is read.
  TagCache? tagCache;

  /// The file extensions that can be played (the formats SoLoud decodes).
  static const Set<String> audioExtensions = {
    "mp3",
    "wav",
    "ogg",
    "oga",
    "opus",
    "flac",
  };

  /// Audio formats SoLoud cannot decode, played by decoding them with
  /// media_kit first (see [needsDecoder]): Ogg Speex, Monkey's Audio,
  /// Musepack, WavPack, TTA, TAK and OptimFROG. Ogg FLAC shares `.oga` and
  /// `.ogg` with Vorbis and Opus, so it is told apart by content.
  static const Set<String> decodedExtensions = {
    "spx",
    "ape",
    "mac",
    "mpc",
    "mp+",
    "mpp",
    "wv",
    "tta",
    "tak",
    "ofr",
  };

  /// The video file extensions that can be played: the sound through
  /// SoLoud, the picture in the Video window (the original's in_nsv,
  /// in_dshow, in_avi, in_mkv, in_mp4 and in_flv types, and today's).
  static const Set<String> videoExtensions = {
    "avi",
    "mpg",
    "mpeg",
    "m2v",
    "mp4",
    "m4v",
    "mkv",
    "webm",
    "mov",
    "wmv",
    "asf",
    "flv",
    "nsv",
    "ogv",
    "3gp",
    "ts",
  };

  /// Playlist file extensions that can be loaded.
  static const Set<String> listExtensions = {"m3u", "m3u8", "pls"};

  final List<PlaylistEntry> _entries = [];
  final Set<int> _selected = {};
  int _current = -1;

  /// Whether the current entry was picked with [setCurrent] (played, skipped
  /// to, or restored) rather than defaulted to the first entry.
  bool _currentChosen = false;
  final Random _random;

  /// Whether the entries changed since the playlist was last saved or loaded
  /// (`plneedsave`). Moving the current entry or selecting does not count.
  bool modified = false;

  @override
  List<PlaylistEntry> get entries => List.unmodifiable(_entries);

  @override
  int get length => _entries.length;

  @override
  bool get isEmpty => _entries.isEmpty;

  /// The index of the current entry, or -1 when there is none.
  @override
  int get current => _current;

  @override
  PlaylistEntry? get currentEntry =>
      _current >= 0 && _current < _entries.length ? _entries[_current] : null;

  /// Whether there is a current entry that was picked, not just defaulted to
  /// the first entry when the playlist was filled.
  bool get hasChosenCurrent => _currentChosen && _current >= 0;

  @override
  Set<int> get selected => Set.unmodifiable(_selected);

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf(".");
    return dot < 0 ? "" : name.substring(dot + 1).toLowerCase();
  }

  static bool isAudio(String path) =>
      audioExtensions.contains(extensionOf(path)) ||
      decodedExtensions.contains(extensionOf(path));

  /// Whether [path] is a sound SoLoud cannot decode, so media_kit decodes
  /// it first: by extension, or for `.ogg` and `.oga` by content (Ogg
  /// Speex and Ogg FLAC; Vorbis and Opus stay with SoLoud).
  static bool needsDecoder(String path) {
    final extension = extensionOf(path);
    if (decodedExtensions.contains(extension)) return true;
    if (extension != "ogg" && extension != "oga") return false;
    return switch (detectFormat(path)) {
      TagFormat.oggSpeex || TagFormat.oggFlac => true,
      _ => false,
    };
  }

  static bool isVideo(String path) =>
      videoExtensions.contains(extensionOf(path));

  /// Whether [path] is a file the playlist takes: sound or video.
  static bool isPlayable(String path) => isAudio(path) || isVideo(path);

  static bool isList(String path) => listExtensions.contains(extensionOf(path));

  // --- Adding ---------------------------------------------------------------

  /// Appends [locations]: audio and video files and URLs as entries, folders
  /// as their audio and video files (recursively, in path order), and playlist files as their
  /// contents. Returns the index of the first added entry, or -1.
  ///
  /// Titles a playlist file records are kept as they are, like the
  /// original's cached `#EXTINF` titles, unless [trustListTitles] is false:
  /// then they only show until the tags are read.
  Future<int> add(
    Iterable<String> locations, {
    bool trustListTitles = true,
  }) async {
    var first = -1;
    final watch = Stopwatch()..start();
    var total = 0;
    if (_addsRunning++ == 0) _addFound = 0;
    notifyListeners();
    try {
      for (final location in locations) {
        final started = watch.elapsedMilliseconds;
        var found = 0;
        await _expand(location, (items) {
          found += items.length;
          _addFound += items.length;
          final index = _append(items, trustListTitles: trustListTitles);
          if (first < 0) first = index;
        });
        total += found;
        Arcane.log(
          "Added entries from a location",
          metadata: {
            "entries": found,
            "location": location,
            "elapsedMs": watch.elapsedMilliseconds - started,
          },
          level: Level.info,
          module: "Playlist",
        );
      }
    } finally {
      _addsRunning--;
      notifyListeners();
    }
    if (total > 0) {
      Arcane.log(
        "Added entries",
        metadata: {"entries": total, "elapsedMs": watch.elapsedMilliseconds},
        level: Level.info,
        module: "Playlist",
      );
    }
    return first;
  }

  /// Appends [items] as entries and queues their tags to be read. Returns
  /// the index of the first one.
  int _append(List<ListItem> items, {required bool trustListTitles}) {
    final first = _entries.length;
    final added = [
      for (final item in items)
        PlaylistEntry(item.location)
          ..duration = item.duration
          ..titleFromList =
              trustListTitles && item.title != null && item.title!.isNotEmpty
          ..title = item.title != null && item.title!.isNotEmpty
              ? item.title!
              : PlaylistEntry._defaultTitle(item.location),
    ];
    _entries.addAll(added);
    if (_current < 0) {
      _current = first;
      _currentChosen = false;
    }
    modified = true;
    notifyListeners();
    _readTags(added);
    return first;
  }

  int _addsRunning = 0;
  int _addFound = 0;

  /// The number of entries found so far while files, folders or playlist
  /// files are being added; null when nothing is being added.
  @override
  int? get addingCount => _addsRunning > 0 ? _addFound : null;

  /// How many files a folder scan collects before appending them, or, when
  /// it is slow, how long it waits.
  static const _addBatchSize = 500;
  static const _addBatchInterval = Duration(milliseconds: 250);

  /// Replaces the playlist with [locations] and makes the first one current.
  /// Returns whether anything was added.
  Future<bool> replace(
    Iterable<String> locations, {
    bool trustListTitles = true,
  }) async {
    clear();
    return await add(locations, trustListTitles: trustListTitles) >= 0;
  }

  /// Marks the entries for which [isOffline] holds as unavailable, and
  /// tells the listeners when that changed any.
  void refreshAvailability(bool Function(String location) isOffline) {
    var changed = false;
    for (final entry in _entries) {
      final offline = isOffline(entry.location);
      if (entry.unavailable != offline) {
        entry.unavailable = offline;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Replaces the playlist with the playlist file at [path] (Load list);
  /// the result counts as saved, so [modified] is cleared. The list amped
  /// saved itself on exit is loaded with [trustListTitles] false, since the
  /// tag cache knows its files' tags better than its titles do.
  Future<bool> load(String path, {bool trustListTitles = true}) async {
    final loaded = await replace([path], trustListTitles: trustListTitles);
    modified = false;
    return loaded;
  }

  /// Hands the items [location] stands for to [found], in batches: a folder
  /// as its audio and video files, recursively in path order, as they are
  /// found, so a large folder fills the list while it is scanned.
  Future<void> _expand(
    String location,
    void Function(List<ListItem> items) found,
  ) async {
    final remote = RemoteLocation.tryParse(location);
    if (remote != null) {
      final items = await _expandRemote(remote);
      if (items.isNotEmpty) found(items);
    } else if (YouTubeLink.tryParse(location) case final link?) {
      final single = link.videoUrl;
      final videos = await _youtube.playlist(single ?? link.playlistUrl!);
      if (single != null && videos.isEmpty) {
        // The title can't be looked up; the video may still play.
        found([ListItem(single)]);
        return;
      }
      if (videos.isNotEmpty) {
        found([
          for (final video in videos)
            ListItem(video.url, title: video.title, duration: video.duration),
        ]);
      }
    } else if (location.contains("://")) {
      found([ListItem(location)]);
    } else if (await FileSystemEntity.isDirectory(location)) {
      final pending = <ListItem>[];
      final lap = Stopwatch()..start();
      final folders = <String>[];
      void flush() {
        if (pending.isEmpty) return;
        found(List.of(pending));
        pending.clear();
        lap.reset();
      }

      await _scanFolder(location, (path) {
        pending.add(ListItem(path));
        if (pending.length >= _addBatchSize ||
            lap.elapsed >= _addBatchInterval) {
          flush();
        }
      }, folders);
      flush();
      Arcane.log(
        "Scanned folders",
        metadata: {"folders": folders.length, "location": location},
        level: Level.info,
        module: "Playlist",
      );
    } else if (isList(location)) {
      final items = await readList(location);
      if (items.isNotEmpty) found(items);
    } else if (isPlayable(location)) {
      found([ListItem(location)]);
    }
  }

  /// Walks [folder] in path order, calling [onFile] for each playable file
  /// and noting every folder in [folders]. Unreadable folders are skipped.
  Future<void> _scanFolder(
    String folder,
    void Function(String path) onFile,
    List<String> folders,
  ) async {
    folders.add(folder);
    final List<FileSystemEntity> children;
    try {
      children = await Directory(folder).list().toList();
    } on FileSystemException catch (error) {
      Arcane.log(
        "Could not scan the folder",
        metadata: {"folder": folder, "error": "$error"},
        level: Level.warning,
        module: "Playlist",
      );
      return;
    }
    children.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );
    for (final child in children) {
      if (child is File) {
        if (isPlayable(child.path)) onFile(child.path);
      } else if (child is Directory) {
        await _scanFolder(child.path, onFile, folders);
      }
    }
  }

  /// A file on a network share is one entry; a folder there (a URL ending
  /// in a slash, or a name that isn't a file) is the playable files in it
  /// and below it. A folder that can't be read adds nothing.
  Future<List<ListItem>> _expandRemote(RemoteLocation remote) async {
    if (!remote.looksLikeFolder && isPlayable(remote.name)) {
      return [ListItem(remote.toString())];
    }
    try {
      if (!remote.looksLikeFolder && isList(remote.name)) {
        // The list is copied here, then read; what it names is looked up
        // on the share it came from.
        final copy = await _remoteFiles.fetch(remote.toString());
        return await readList(copy, resolve: remote.sibling);
      }
      final files = await _remoteFiles.listFiles(remote.toString(), isPlayable);
      return [for (final file in files) ListItem(file)];
    } on Object catch (error) {
      Arcane.log(
        "Could not open the source",
        metadata: {"source": remote.display, "error": "$error"},
        level: Level.warning,
        module: "Playlist",
      );
      return const [];
    }
  }

  /// How many files one background tag read covers. Small, so that tags
  /// show up steadily even for a long list on a slow (network) volume.
  static const _tagBatchSize = 16;

  /// How many entries one tag cache lookup covers: enough that a long list
  /// gets its cached tags in a few round trips.
  static const _cacheBatchSize = 500;

  /// Entries whose tags are still to be looked up in the cache, in order.
  final Queue<PlaylistEntry> _tagQueue = Queue();

  /// Entries the cache had no tags for, still to be read from their files.
  final Queue<PlaylistEntry> _fileQueue = Queue();
  bool _readingTags = false;

  /// Queues [entries] to have their titles, durations, bitrates and sample
  /// rates read in the background: first from the tag cache, a large batch
  /// at a time, then the rest from their files, a small batch at a time, the
  /// current entry first.
  void _readTags(List<PlaylistEntry> entries) {
    final queued = entries.where((entry) => entry.hasTags).toList();
    _tagsTotal += queued.length;
    _tagQueue.addAll(queued);
    if (!_readingTags) unawaited(_drainTagQueue());
  }

  /// Entries queued for tag reading since the queue was last empty, and how
  /// many of them are done, for the log.
  int _tagsTotal = 0;
  int _tagsDone = 0;
  int _tagFileBatches = 0;
  final Stopwatch _tagWatch = Stopwatch();

  Future<void> _drainTagQueue() async {
    _readingTags = true;
    _tagWatch
      ..reset()
      ..start();
    try {
      while (_tagQueue.isNotEmpty || _fileQueue.isNotEmpty) {
        if (_tagQueue.isNotEmpty) {
          final batch = <PlaylistEntry>[];
          while (batch.length < _cacheBatchSize && _tagQueue.isNotEmpty) {
            final entry = _tagQueue.removeFirst();
            if (!entry._tagsRead) batch.add(entry);
          }
          final misses = await _takeCached(batch);
          // A source track the cache knows nothing about has no file to read.
          _fileQueue.addAll(misses.where((entry) => !entry.isSource));
          _tagsDone += batch.length - misses.length;
          Arcane.log(
            "Tag cache lookup",
            metadata: {
              "done": _tagsDone,
              "total": _tagsTotal,
              "misses": misses.length,
              "batch": batch.length,
            },
            level: Level.info,
            module: "Playlist",
          );
          continue;
        }
        final batch = <PlaylistEntry>[];
        final current = currentEntry;
        if (current != null && !current.isUrl && !current._tagsRead) {
          batch.add(current);
        }
        while (batch.length < _tagBatchSize && _fileQueue.isNotEmpty) {
          final entry = _fileQueue.removeFirst();
          if (!entry._tagsRead && !identical(entry, current)) batch.add(entry);
        }
        if (batch.isNotEmpty) {
          await _readTagsOf(batch);
          _tagsDone += batch.length;
          if (++_tagFileBatches % 10 == 0 || _fileQueue.isEmpty) {
            Arcane.log(
              "Reading tags",
              metadata: {
                "done": _tagsDone,
                "total": _tagsTotal,
                "batch": _tagFileBatches,
              },
              level: Level.info,
              module: "Playlist",
            );
          }
        }
      }
      if (_tagsTotal > 0) {
        Arcane.log(
          "Read tags",
          metadata: {
            "entries": _tagsTotal,
            "elapsedMs": _tagWatch.elapsedMilliseconds,
          },
          level: Level.info,
          module: "Playlist",
        );
      }
    } finally {
      _tagsTotal = _tagsDone = _tagFileBatches = 0;
      _readingTags = false;
    }
  }

  /// The cached tags of those of [entries] not yet looked up, by path, a
  /// batch at a time. A failing cache is dropped, so files are read instead.
  Future<Map<String, TrackTags>> _lookUp(List<PlaylistEntry> entries) async {
    final unchecked = [
      for (final entry in entries)
        if (!entry._cacheChecked) entry,
    ];
    final rows = <String, TrackTags>{};
    for (var start = 0; start < unchecked.length; start += _cacheBatchSize) {
      final cache = tagCache;
      if (cache == null) break;
      final batch = unchecked.sublist(
        start,
        min(start + _cacheBatchSize, unchecked.length),
      );
      try {
        rows.addAll(
          await cache.lookup([for (final entry in batch) entry.location]),
        );
      } on Object catch (error) {
        _dropTagCache(error);
      }
    }
    for (final entry in unchecked) {
      entry._cacheChecked = true;
    }
    return rows;
  }

  /// Applies the cached tags of those of [entries] not yet read; returns the
  /// rest, which the cache had no tags for.
  Future<List<PlaylistEntry>> _takeCached(List<PlaylistEntry> entries) async {
    final rows = await _lookUp(entries);
    final misses = <PlaylistEntry>[];
    var applied = false;
    for (final entry in entries) {
      if (entry._tagsRead) continue; // Read meanwhile.
      final row = rows[entry.location];
      if (row == null) {
        misses.add(entry);
        continue;
      }
      entry._tagsRead = true;
      _applyTags(entry, row);
      applied = true;
    }
    if (applied) notifyListeners();
    return misses;
  }

  /// Applies the cached tags of the source tracks among [entries] (the
  /// whole playlist when null) that don't have theirs yet: the cache gets a
  /// source's rows as it loads, maybe after the playlist was filled.
  Future<void> takeSourceTags([List<PlaylistEntry>? entries]) async {
    final pending = [
      for (final entry in entries ?? _entries)
        if (entry.isSource && !entry._tagsRead) entry,
    ];
    if (pending.isEmpty) return;
    for (final entry in pending) {
      entry._cacheChecked = false;
    }
    await _takeCached(pending);
  }

  /// Stops using the tag cache after [error], reading files instead.
  void _dropTagCache(Object error) {
    final cache = tagCache;
    if (cache == null) return;
    Arcane.log(
      "Tag cache failed, reading files instead",
      metadata: {"error": "$error"},
      level: Level.warning,
      module: "Playlist",
    );
    tagCache = null;
    unawaited(cache.close().catchError((Object _) {}));
  }

  /// Tag reads that have started but not yet been applied.
  final Set<Future<void>> _tagReads = {};

  /// Completes once [entry]'s tags have been read (or tried), reading them
  /// now when they are still waiting in the queue.
  Future<void> tagsRead(PlaylistEntry entry) {
    if (entry.isSource) return takeSourceTags([entry]);
    if (entry.isUrl) return Future.value();
    if (!entry._tagsRead) return _readTagsOf([entry]);
    return entry._tagsReading ?? Future.value();
  }

  /// Reads the tags of [entries], from the tag cache when it has them and
  /// otherwise from their files (in a background isolate), and applies them.
  /// With a [reread] other than [_Reread.none], the files are read whatever
  /// the cache holds, and the rows that changed are updated.
  Future<void> _readTagsOf(
    List<PlaylistEntry> entries, {
    _Reread reread = _Reread.none,
  }) {
    final read = _readAndApplyTags(entries, reread: reread);
    _tagReads.add(read);
    for (final entry in entries) {
      entry._tagsReading = read;
    }
    return read.whenComplete(() => _tagReads.remove(read));
  }

  Future<void> _readAndApplyTags(
    List<PlaylistEntry> entries, {
    required _Reread reread,
  }) async {
    final ids = Map<PlaylistEntry, int>.identity();
    for (final entry in entries) {
      entry._tagsRead = true;
      ids[entry] = ++entry._tagReadId;
    }
    // Whether no later read of [entry] has started since this one.
    bool latest(PlaylistEntry entry) => entry._tagReadId == ids[entry];
    var files = entries;
    if (reread == _Reread.none) {
      final rows = await _lookUp(entries);
      if (rows.isNotEmpty) {
        files = [];
        for (final entry in entries) {
          final row = rows[entry.location];
          if (row == null) {
            files.add(entry);
          } else if (latest(entry)) {
            _applyTags(entry, row);
          }
        }
        notifyListeners();
      }
    }
    if (files.isEmpty) return;
    final List<TrackTags?> tags;
    try {
      tags = await _readTagsInBackground([
        for (final entry in files) entry.location,
      ]);
    } on Object catch (error) {
      Arcane.log(
        "Tag reading failed",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "Playlist",
      );
      // Let a later read (or sort) try these again.
      for (final entry in files) {
        if (latest(entry)) entry._tagsRead = false;
      }
      return;
    }
    final read = tags.nonNulls.toList();
    final byPath = {for (final tag in read) tag.path: tag};
    for (final entry in files) {
      final tag = byPath[entry.location];
      if (tag == null || !latest(entry)) continue;
      final (title, duration) = (entry.title, entry.duration);
      _applyTags(entry, tag, reread: reread);
      if (reread != _Reread.none &&
          (entry.title != title || entry.duration != duration)) {
        modified = true;
      }
    }
    notifyListeners();
    await _storeTags(read, onlyChanged: reread != _Reread.none);
  }

  /// Adds [tags] to the tag cache; with [onlyChanged], only those that
  /// differ from their rows.
  Future<void> _storeTags(
    List<TrackTags> tags, {
    required bool onlyChanged,
  }) async {
    final cache = tagCache;
    if (cache == null || tags.isEmpty) return;
    try {
      var changed = tags;
      if (onlyChanged) {
        final rows = await cache.lookup([for (final tag in tags) tag.path]);
        changed = [
          for (final tag in tags)
            if (rows[tag.path] != tag) tag,
        ];
      }
      await cache.store(changed);
    } on Object catch (error) {
      _dropTagCache(error);
    }
  }

  /// Gives [entry] what [tags] say. The title becomes "Artist - Title"
  /// unless it came from the playlist file; the length, bitrate, sample
  /// rate and channels fill in what isn't known.
  ///
  /// When [reread], the title is rebuilt even when it came from the playlist
  /// file (back to the file name when the tags have none), and what the tags
  /// know replaces the rest; except that [_Reread.refresh] keeps a known length
  /// (the decoder's, which is more exact than the tags').
  static void _applyTags(
    PlaylistEntry entry,
    TrackTags tags, {
    _Reread reread = _Reread.none,
  }) {
    entry
      ..artist = tags.artist
      ..album = tags.album
      ..trackTitle = tags.title
      ..genres = tags.genres
      ..trackNumber = tags.trackNumber
      ..discNumber = tags.discNumber;
    if (reread != _Reread.none) {
      entry
        ..titleFromList = false
        ..title = PlaylistEntry._defaultTitle(entry.location)
        ..bitrate = tags.bitrate ?? entry.bitrate
        ..sampleRate = tags.sampleRate ?? entry.sampleRate
        ..channels = tags.channels ?? entry.channels;
      if (reread == _Reread.rebuild) {
        entry.duration = tags.duration ?? entry.duration;
      }
    }
    if (!entry.titleFromList && tags.title != null && tags.title!.isNotEmpty) {
      entry.title = tags.artist != null && tags.artist!.isNotEmpty
          ? "${tags.artist} - ${tags.title}"
          : tags.title!;
    }
    entry.duration ??= tags.duration;
    entry.bitrate ??= tags.bitrate;
    entry.sampleRate ??= tags.sampleRate;
    entry.channels ??= tags.channels;
  }

  /// Re-reads the tags of [entry], which has just started playing, from its
  /// file, so that a file tagged since it was cached shows its new tags;
  /// its cache row is updated if they changed.
  Future<void> refreshTags(PlaylistEntry entry) async {
    if (entry.isUrl) return;
    await _readTagsOf([entry], reread: _Reread.refresh);
  }

  /// Counts [refreshAllTags] runs, so that a newer one (or a new list)
  /// stops an older one.
  int _refreshRun = 0;

  /// Re-reads every file entry's tags from its file, in the background and
  /// a small batch at a time, so that tags changed since they were cached
  /// (by another program, or by an earlier run) show up; the entries and
  /// cache rows that changed are updated, and the rest are left alone. Run
  /// at startup, after the list is restored from the cache. First reads of
  /// new entries go first.
  Future<void> refreshAllTags() async {
    final run = ++_refreshRun;
    final entries = [
      for (final entry in _entries)
        if (!entry.isUrl) entry,
    ];
    for (var start = 0; start < entries.length; start += _tagBatchSize) {
      while (_readingTags && run == _refreshRun) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (run != _refreshRun) return;
      final batch = entries.sublist(
        start,
        min(start + _tagBatchSize, entries.length),
      );
      await _readTagsOf(batch, reread: _Reread.refresh);
    }
  }

  /// Re-reads the tags of the file at [path] after they were written (File
  /// info), updating its entries and its tag cache row.
  Future<void> fileTagsChanged(String path) async {
    if (path.contains("://")) return;
    final entries = [
      for (final entry in _entries)
        if (entry.location == path) entry,
    ];
    if (entries.isNotEmpty) {
      await _readTagsOf(entries, reread: _Reread.refresh);
      return;
    }
    // Not in the playlist: only its row (if any) needs to change.
    try {
      final tags = (await _readTagsInBackground([path])).nonNulls.toList();
      await _storeTags(tags, onlyChanged: true);
    } on Object catch (error) {
      Arcane.log(
        "Tag reading failed",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "Playlist",
      );
    }
  }

  /// Re-reads the tags of the selected file entries from their files,
  /// rebuilding their titles and updating the tag cache (MISC > Misc
  /// options > Rebuild titles on selection, `IDC_PLAYLIST_RESET_CACHE`).
  Future<void> rebuildSelectedTitles() => rebuildTitles(_selected);

  /// [rebuildSelectedTitles] for the entries at [indices].
  Future<void> rebuildTitles(Set<int> indices) async {
    final entries = [
      for (final i in indices.toList()..sort())
        if (i >= 0 && i < _entries.length && !_entries[i].isUrl) _entries[i],
    ];
    if (entries.isEmpty) return;
    for (var start = 0; start < entries.length; start += _tagBatchSize) {
      await _readTagsOf(
        entries.sublist(start, min(start + _tagBatchSize, entries.length)),
        reread: _Reread.rebuild,
      );
    }
  }

  /// Records what the decoder learned about [entry] (e.g. a length the tags
  /// did not have).
  void updateEntry(PlaylistEntry entry, {Duration? duration}) {
    if (duration != null && duration > Duration.zero) entry.duration = duration;
    notifyListeners();
  }

  /// Takes what a playing station reports for [entry]: what is on now
  /// ([title], its `StreamTitle`, "Artist - Title"), which becomes the
  /// entry's [PlaylistEntry.streamTitle] while the entry keeps its own
  /// title, and the [bitrate] (kbps) and [sampleRate] (Hz) it announces.
  /// Null values leave the entry as it is.
  void updateStreamEntry(
    PlaylistEntry entry, {
    String? title,
    int? bitrate,
    int? sampleRate,
  }) {
    var changed = false;
    if (title != null && title != entry.streamTitle) {
      entry.streamTitle = title;
      // The artist and title for the OS media session.
      final dash = title.indexOf(" - ");
      entry.artist = dash < 0 ? null : title.substring(0, dash);
      entry.trackTitle = dash < 0 ? title : title.substring(dash + 3);
      changed = true;
    }
    if (bitrate != null && bitrate != entry.bitrate) {
      entry.bitrate = bitrate;
      changed = true;
    }
    if (sampleRate != null && sampleRate != entry.sampleRate) {
      entry.sampleRate = sampleRate;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Forgets what the station on [entry] was playing, once it stops.
  void clearStreamTitle(PlaylistEntry entry) {
    if (entry.streamTitle == null) return;
    entry
      ..streamTitle = null
      ..artist = null
      ..trackTitle = null;
    notifyListeners();
  }

  // --- Current entry and navigation ----------------------------------------

  void setCurrent(int index) {
    if (index < -1 || index >= _entries.length) return;
    _currentChosen = index >= 0;
    if (index == _current) return;
    _current = index;
    // Don't make the playing track wait its turn behind the rest of the list.
    final entry = currentEntry;
    if (entry != null && !entry.isUrl && !entry._tagsRead) {
      unawaited(_readTagsOf([entry]));
    }
    notifyListeners();
  }

  /// The entry after the current one: a random other entry in [shuffle]
  /// mode, wrapping around only with [repeat]. Returns -1 at the end.
  int nextIndex({required bool shuffle, required bool repeat}) {
    if (_entries.isEmpty) return -1;
    if (shuffle) return _randomOther();
    final next = _current + 1;
    if (next < _entries.length) return next;
    return repeat ? 0 : -1;
  }

  /// The entry before the current one (wrapping to the end).
  int previousIndex({required bool shuffle}) {
    if (_entries.isEmpty) return -1;
    if (shuffle) return _randomOther();
    return _current <= 0 ? _entries.length - 1 : _current - 1;
  }

  /// A random entry, any of them (the current one included), or -1 when the
  /// playlist is empty.
  int randomIndex() => _entries.isEmpty ? -1 : _random.nextInt(_entries.length);

  int _randomOther() {
    if (_entries.length == 1) return 0;
    var index = _current;
    while (index == _current) {
      index = _random.nextInt(_entries.length);
    }
    return index;
  }

  // --- Selection -------------------------------------------------------------

  @override
  void select(Set<int> indices) {
    _selected
      ..clear()
      ..addAll(indices.where((i) => i >= 0 && i < _entries.length));
    notifyListeners();
  }

  @override
  void selectAll() => select({for (var i = 0; i < _entries.length; i++) i});

  @override
  void selectNone() => select({});

  @override
  void invertSelection() => select({
    for (var i = 0; i < _entries.length; i++)
      if (!_selected.contains(i)) i,
  });

  // --- Removing ---------------------------------------------------------------

  /// Removes the entries at [indices], keeping the current entry current when
  /// it survives.
  void removeAt(Set<int> indices) {
    if (indices.isEmpty) return;
    final current = currentEntry;
    final kept = <PlaylistEntry>[];
    for (var i = 0; i < _entries.length; i++) {
      if (!indices.contains(i)) kept.add(_entries[i]);
    }
    _replaceEntries(kept, current: current);
  }

  @override
  void removeSelected() => removeAt(_selected);

  /// Keeps only the selected entries (REM > Crop).
  @override
  void crop() => removeAt({
    for (var i = 0; i < _entries.length; i++)
      if (!_selected.contains(i)) i,
  });

  @override
  void clear() {
    if (_entries.isNotEmpty) modified = true;
    _refreshRun++;
    _entries.clear();
    _selected.clear();
    _tagQueue.clear();
    _fileQueue.clear();
    _current = -1;
    _currentChosen = false;
    notifyListeners();
  }

  /// Removes entries whose file no longer exists.
  void removeDeadFiles() => removeAt({
    for (var i = 0; i < _entries.length; i++)
      if (!_entries[i].isUrl && !File(_entries[i].location).existsSync()) i,
  });

  /// Moves entry [from] to position [to], keeping the current entry current
  /// and the selected entries selected.
  void move(int from, int to) {
    final length = _entries.length;
    if (from == to || from < 0 || to < 0 || from >= length || to >= length) {
      return;
    }
    final current = currentEntry;
    final selected = [for (final i in _selected) _entries[i]];
    _entries.insert(to, _entries.removeAt(from));
    _selected
      ..clear()
      ..addAll(selected.map(_entries.indexOf));
    _current = current == null ? -1 : _entries.indexOf(current);
    modified = true;
    notifyListeners();
  }

  /// Moves the selected entries one place up ([delta] -1) or down (1)
  /// (Alt+Up/Down, `ID_PE_MOVEUP`/`DOWN`), keeping them selected.
  void moveSelection(int delta) {
    if (_selected.isEmpty) return;
    final sorted = _selected.toList()..sort();
    if (delta < 0 && sorted.first == 0) return;
    if (delta > 0 && sorted.last == _entries.length - 1) return;
    final current = currentEntry;
    final order = delta < 0 ? sorted : sorted.reversed;
    for (final i in order) {
      final entry = _entries.removeAt(i);
      _entries.insert(i + delta, entry);
    }
    _selected
      ..clear()
      ..addAll(sorted.map((i) => i + delta));
    _current = current == null ? -1 : _entries.indexOf(current);
    modified = true;
    notifyListeners();
  }

  /// Removes repeated locations, keeping the first of each.
  void removeDuplicates() {
    final seen = <String>{};
    removeAt({
      for (var i = 0; i < _entries.length; i++)
        if (!seen.add(_entries[i].location)) i,
    });
  }

  // --- Ordering ---------------------------------------------------------------

  /// Whether a [sort] is under way (reading tags or ordering entries).
  bool get sorting => _sortsRunning > 0;
  int _sortsRunning = 0;

  /// Counts [sort] calls, so only the latest one's order is applied.
  int _sortGeneration = 0;

  /// Sorts by [by] the way the classic player does: case-insensitively, with runs of
  /// digits compared as numbers ("Track 2" before "Track 10"). Title and file
  /// name sorts ignore a leading "The ", so "The Beatles" sorts as "Beatles".
  /// The path sort orders by folder, then by file name within a folder, with
  /// entries that have no folder (URLs) first.
  ///
  /// The artist and album sorts (not in the classic player) first read any tags not yet
  /// read; they also ignore a leading "The ", put entries without the tag
  /// last, and order an album by disc and track number. Ties keep their
  /// current order.
  ///
  /// Long lists are ordered in a background isolate, so the windows stay
  /// responsive; [sorting] is true meanwhile. Entries added while it runs go
  /// at the end, and entries removed stay removed. A sort started while
  /// another runs replaces it.
  Future<void> sort(PlaylistSort by) async {
    final generation = ++_sortGeneration;
    _sortsRunning++;
    if (_sortsRunning == 1) notifyListeners();
    try {
      if (by.usesTags) await _readAllTags();
      final snapshot = List.of(_entries);
      final keys = [for (final entry in snapshot) _sortKey(by, entry)];
      final order = keys.length < _isolateSortMin
          ? sortOrder(keys)
          : await Isolate.run(() => sortOrder(keys));
      if (generation != _sortGeneration) return; // A later sort replaced it.
      final present = Set<PlaylistEntry>.identity()..addAll(_entries);
      final sorted = Set<PlaylistEntry>.identity()..addAll(snapshot);
      _replaceEntries([
        for (final i in order)
          if (present.contains(snapshot[i])) snapshot[i],
        for (final entry in _entries)
          if (!sorted.contains(entry)) entry,
      ], current: currentEntry);
    } finally {
      _sortsRunning--;
      if (_sortsRunning == 0) notifyListeners();
    }
  }

  /// Below this many entries a sort is quicker done on the spot than in an
  /// isolate.
  static const _isolateSortMin = 2000;

  /// What [by] compares for [entry], as plain data that can cross isolates:
  /// components compared in turn by [sortOrder]. Strings are already
  /// lowercased; a null sorts after any value.
  static List<Object?> _sortKey(PlaylistSort by, PlaylistEntry entry) {
    String plain(String s) {
      final lower = s.trim().toLowerCase();
      return lower.startsWith("the ") ? lower.substring(4) : lower;
    }

    String? tag(String? s) => s == null || s.trim().isEmpty ? null : plain(s);
    return switch (by) {
      PlaylistSort.title => [plain(entry.title)],
      PlaylistSort.fileName => [plain(_fileName(entry))],
      PlaylistSort.path => [
        if (_folder(entry).isEmpty) 0 else 1,
        _folder(entry).toLowerCase(),
        _fileName(entry).toLowerCase(),
      ],
      PlaylistSort.artist => [tag(entry.artist)],
      PlaylistSort.album => [
        tag(entry.album),
        entry.discNumber,
        entry.trackNumber,
      ],
      PlaylistSort.artistAlbum => [
        tag(entry.artist),
        tag(entry.album),
        entry.discNumber,
        entry.trackNumber,
      ],
    };
  }

  /// The indices of [keys] in sorted order (see [_sortKey]); ties keep their
  /// order. Runs in an isolate for long lists, so it uses only its argument.
  @visibleForTesting
  static List<int> sortOrder(List<List<Object?>> keys) {
    int compareKeys(List<Object?> a, List<Object?> b) {
      for (var i = 0; i < a.length; i++) {
        final x = a[i], y = b[i];
        if (x == null || y == null) {
          if (x != y) return x == null ? 1 : -1;
          continue;
        }
        final order = x is String
            ? _compareLowered(x, y as String)
            : (x as int).compareTo(y as int);
        if (order != 0) return order;
      }
      return 0;
    }

    return List.generate(keys.length, (i) => i)..sort((i, j) {
      final order = compareKeys(keys[i], keys[j]);
      return order != 0 ? order : i.compareTo(j);
    });
  }

  /// While a sort reads the tags it needs: how many of the files it lacked
  /// tags for have been read, out of how many; null otherwise.
  ({int done, int total})? get sortTagProgress => _sortTagProgress;
  ({int done, int total})? _sortTagProgress;

  /// Reads the tags of every file entry that hasn't had them read: first
  /// from the tag cache, then the rest from their files in chunks a few at a
  /// time (so titles fill in as it goes, and slow disks overlap); and waits
  /// for reads already under way.
  Future<void> _readAllTags() async {
    final unread = [
      for (final entry in await _takeCached([
        for (final entry in _entries)
          if (entry.hasTags && !entry._tagsRead) entry,
      ]))
        if (!entry.isSource) entry,
    ];
    if (unread.isNotEmpty) {
      var done = 0, next = 0;
      _sortTagProgress = (done: 0, total: unread.length);
      notifyListeners();
      Future<void> worker() async {
        while (next < unread.length) {
          final chunk = unread.sublist(
            next,
            next = min(next + _sortTagChunk, unread.length),
          );
          // Skip what the background reader got to meanwhile.
          final toRead = [
            for (final entry in chunk)
              if (!entry._tagsRead) entry,
          ];
          if (toRead.isNotEmpty) await _readTagsOf(toRead);
          done += chunk.length;
          _sortTagProgress = (done: done, total: unread.length);
          notifyListeners();
        }
      }

      try {
        await Future.wait([for (var i = 0; i < _sortTagReaders; i++) worker()]);
      } finally {
        _sortTagProgress = null;
      }
    }
    while (_tagReads.isNotEmpty) {
      await Future.wait(List.of(_tagReads));
    }
  }

  /// Files per tag read while sorting: small, so the progress count moves
  /// every few hundred milliseconds even on a slow network drive (a chunk
  /// reports only when all of it is done).
  static const _sortTagChunk = _tagBatchSize;

  /// How many chunks are read at once.
  static const _sortTagReaders = 4;

  static String _fileName(PlaylistEntry e) =>
      e.location.substring(_folderEnd(e) + 1);

  /// The folder part of a file entry's location, or "" for a URL.
  static String _folder(PlaylistEntry e) =>
      e.isUrl ? "" : e.location.substring(0, max(_folderEnd(e), 0));

  static int _folderEnd(PlaylistEntry e) =>
      e.location.lastIndexOf(Platform.pathSeparator);

  /// The classic player's "logical" string order: case-insensitive, with runs of digits
  /// compared by value, and a digit sorting before any other character.
  @visibleForTesting
  static int compareLogical(String a, String b) =>
      _compareLowered(a.toLowerCase(), b.toLowerCase());

  /// [compareLogical] for strings already lowercased.
  static int _compareLowered(String a, String b) {
    bool isDigit(String s, int i) =>
        s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39;
    int digitsEnd(String s, int i) {
      while (i < s.length && isDigit(s, i)) {
        i++;
      }
      return i;
    }

    int zerosEnd(String s, int i, int end) {
      while (i < end - 1 && s.codeUnitAt(i) == 0x30) {
        i++;
      }
      return i;
    }

    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      final digitA = isDigit(a, i), digitB = isDigit(b, j);
      if (digitA != digitB) return digitA ? -1 : 1;
      if (digitA) {
        // Compare the numbers by value, however long: without leading
        // zeros, the longer is bigger, and equal lengths compare digitwise.
        final endA = digitsEnd(a, i), endB = digitsEnd(b, j);
        final startA = zerosEnd(a, i, endA), startB = zerosEnd(b, j, endB);
        final byLength = (endA - startA).compareTo(endB - startB);
        if (byLength != 0) return byLength;
        for (var k = 0; k < endA - startA; k++) {
          final byDigit = a
              .codeUnitAt(startA + k)
              .compareTo(
                b.codeUnitAt(startB + k),
              );
          if (byDigit != 0) return byDigit;
        }
        i = endA;
        j = endB;
      } else {
        final byChar = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
        if (byChar != 0) return byChar;
        i++;
        j++;
      }
    }
    return (a.length - i).compareTo(b.length - j);
  }

  void reverse() =>
      _replaceEntries(_entries.reversed.toList(), current: currentEntry);

  void randomize() => _replaceEntries(
    List.of(_entries)..shuffle(_random),
    current: currentEntry,
  );

  void _replaceEntries(List<PlaylistEntry> entries, {PlaylistEntry? current}) {
    modified = true;
    _entries
      ..clear()
      ..addAll(entries);
    _selected.clear();
    _current = current == null ? -1 : _entries.indexOf(current);
    if (_current < 0) {
      _currentChosen = false;
      if (_entries.isNotEmpty) _current = 0;
    }
    notifyListeners();
  }

  // --- Playlist files ---------------------------------------------------------

  /// The locations listed in the `.m3u`/`.m3u8`/`.pls` file at [path].
  static Future<List<String>> parseList(String path) async => [
    for (final item in await readList(path)) item.location,
  ];

  /// The entries of the `.m3u`/`.m3u8`/`.pls` file at [path], with the
  /// titles and lengths it records (`#EXTINF:length,title`;
  /// `TitleN=`/`LengthN=`). Relative paths resolve against the list's
  /// folder; a negative length means unknown.
  ///
  /// With [resolve], the locations that aren't URLs go through it instead
  /// (a list fetched from a network share resolves against the share).
  static Future<List<ListItem>> readList(
    String path, {
    String Function(String location)? resolve,
  }) async {
    String text;
    try {
      text = await File(path).readAsString();
    } on Object {
      return const [];
    }
    return parseListText(
      text,
      isPls: extensionOf(path) == "pls",
      folder: File(path).parent.path,
      resolve: resolve,
    );
  }

  /// The entries listed in [text], the contents of a `.pls` file when
  /// [isPls] is true and of an `.m3u`/`.m3u8` file otherwise. Relative
  /// locations resolve against [folder]; without one they stay as written.
  /// With [resolve], the locations that aren't URLs go through it instead.
  static List<ListItem> parseListText(
    String text, {
    required bool isPls,
    String? folder,
    String Function(String location)? resolve,
  }) {
    if (text.startsWith("\uFEFF")) text = text.substring(1);
    String resolveLocation(String location) {
      if (location.contains("://")) return location;
      if (resolve != null) return resolve(location);
      if (location.startsWith("/")) return location;
      if (folder == null) return location;
      return "$folder${Platform.pathSeparator}$location";
    }

    Duration? length(String? seconds) {
      final value = int.tryParse(seconds?.trim() ?? "");
      return value == null || value < 0 ? null : Duration(seconds: value);
    }

    final lines = text.split(RegExp(r"\r?\n")).map((l) => l.trim());
    if (isPls) {
      final fields = <String, Map<String, String>>{};
      final order = <String>[];
      for (final line in lines) {
        final match = RegExp(
          r"^(File|Title|Length)(\d+)=(.*)$",
          caseSensitive: false,
        ).firstMatch(line);
        if (match == null) continue;
        final number = match.group(2)!;
        if (!fields.containsKey(number)) order.add(number);
        (fields[number] ??= {})[match.group(1)!.toLowerCase()] = match.group(
          3,
        )!;
      }
      return [
        for (final number in order)
          if (fields[number]!["file"] case final file?)
            ListItem(
              resolveLocation(file),
              title: fields[number]!["title"],
              duration: length(fields[number]!["length"]),
            ),
      ];
    }
    final items = <ListItem>[];
    String? title;
    Duration? duration;
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.toUpperCase().startsWith("#EXTINF:")) {
        final info = line.substring(8);
        final comma = info.indexOf(",");
        duration = length(comma < 0 ? info : info.substring(0, comma));
        title = comma < 0 ? null : info.substring(comma + 1);
        continue;
      }
      if (line.startsWith("#")) continue;
      items.add(
        ListItem(resolveLocation(line), title: title, duration: duration),
      );
      title = null;
      duration = null;
    }
    return items;
  }

  /// Writes the playlist to [path] in the format its extension names, as the
  /// original's Save playlist does:
  ///
  /// * `.pls`: `FileN=` (relative to the list's folder), with `TitleN=` and
  ///   `LengthN=` for entries whose length is known, then `NumberOfEntries`
  ///   and `Version=2` (`saveplsfn`);
  /// * `.m3u`/`.m3u8`: `#EXTM3U`, then each absolute path, preceded by
  ///   `#EXTINF:length,title` when the length is known; `.m3u8` is UTF-8
  ///   with a byte-order mark (`savem3ufn`).
  ///
  /// Saving clears [modified].
  Future<void> save(String path) async {
    final buffer = StringBuffer();
    if (extensionOf(path) == "pls") {
      final folder = File(path).parent.path + Platform.pathSeparator;
      String relative(String location) => location.startsWith(folder)
          ? location.substring(folder.length)
          : location;
      buffer.write("[playlist]\r\n");
      for (final (i, entry) in _entries.indexed) {
        final n = i + 1;
        buffer.write("File$n=${relative(entry.location)}\r\n");
        final duration = entry.duration;
        if (duration != null) {
          buffer
            ..write("Title$n=${entry.title}\r\n")
            ..write("Length$n=${duration.inSeconds}\r\n");
        }
      }
      buffer
        ..write("NumberOfEntries=${_entries.length}\r\n")
        ..write("Version=2\r\n");
    } else {
      if (extensionOf(path) == "m3u8") buffer.write("\uFEFF");
      buffer.write("#EXTM3U\n");
      for (final entry in _entries) {
        final duration = entry.duration;
        if (duration != null) {
          buffer.write("#EXTINF:${duration.inSeconds},${entry.title}\n");
        }
        buffer.write("${entry.location}\n");
      }
    }
    await File(path).writeAsString(buffer.toString());
    modified = false;
  }
}

/// The embedded cover art of the file at [path] (the front cover when
/// there are several pictures), read in a background isolate; `null` when it
/// has none.
Future<Uint8List?> readArtwork(String path) => Isolate.run(() {
  try {
    final pictures = readMetadata(File(path), getImage: true).pictures;
    if (pictures.isEmpty) return null;
    final front = pictures.where(
      (p) => p.pictureType == PictureType.coverFront,
    );
    return (front.isEmpty ? pictures.first : front.first).bytes;
  } on Object {
    return null;
  }
});

/// Why tags are read from files whatever the tag cache holds.
enum _Reread {
  /// They aren't: the cache is used when it has them.
  none,

  /// Rebuild titles on selection.
  rebuild,

  /// The entry started playing, or its file's tags were edited.
  refresh,
}

/// Reads the tags of [files] in a background isolate (null for a file that
/// can't be read). A top-level function so the isolate's closure captures
/// nothing but [files].
Future<List<TrackTags?>> _readTagsInBackground(List<String> files) =>
    readTagsInBackground(files);

/// [files]' tags, read in a background isolate (null for a file that can't
/// be read).
Future<List<TrackTags?>> readTagsInBackground(List<String> files) =>
    Isolate.run(() => [for (final path in files) _readTrackTags(path)]);

const Set<String> _mp4Extensions = {"mp4", "m4v", "mov"};

/// What the tags of the file at [path] say, or null when it can't be read
/// at all (missing, or on a volume that isn't mounted), so that nothing is
/// cached for it.
TrackTags? _readTrackTags(String path) {
  // The tag readers know audio files and MP4; handing them a film in
  // another container (Matroska, AVI, ...) makes them parse a file of many
  // gigabytes, over a network share perhaps, for no tags. Its length is
  // known once it plays.
  if (Playlist.isVideo(path) &&
      !_mp4Extensions.contains(Playlist.extensionOf(path))) {
    return TrackTags(path);
  }
  final read = _readTrackTagsWithReader(path);
  if (read?.title != null && read?.artist != null) return read;
  // The general tag reader missed some of the text, which it also does for
  // tags it can't parse (an ID3v2.4 tag with an unusual frame, say). The
  // File Info dialog's own reader copes with more: fill in what is missing
  // from it.
  try {
    final fields = readFileTags(path).fields;
    final title = read?.title ?? fields[TagField.title];
    final artist = read?.artist ?? fields[TagField.artist];
    final album = read?.album ?? fields[TagField.album];
    if (title == null && artist == null && album == null) return read;
    int? number(TagField field) =>
        int.tryParse(fields[field]?.split("/").first.trim() ?? "");
    final genres = read?.genres ?? const <String>[];
    return TrackTags(
      path,
      artist: artist,
      album: album,
      title: title,
      genres: [
        if (genres.isNotEmpty)
          ...genres
        else if (fields[TagField.genre] case final genre?)
          genre,
      ],
      trackNumber: read?.trackNumber ?? number(TagField.track),
      discNumber: read?.discNumber ?? number(TagField.disc),
      year: read?.year ?? _yearOfText(fields[TagField.year]),
      duration: read?.duration,
      bitrate: read?.bitrate,
      sampleRate: read?.sampleRate,
      channels: read?.channels,
    );
  } on Object {
    return read;
  }
}

/// The year in [metadata], whichever kind it is.
int? _yearOf(AudioMetadata metadata) => switch (metadata) {
  Mp3Metadata(:final year) => year,
  Mp4Metadata(:final year) => year?.year,
  VorbisMetadata(:final date) => date.isEmpty ? null : date.first.year,
  RiffMetadata(:final year) => year?.year,
  ApeMetadata(:final date) => date?.year,
  _ => null,
};

/// The year at the start of [text] (`2016`, `2016-05-01`), or null.
int? _yearOfText(String? text) {
  final year = int.tryParse(text?.trim().split(RegExp(r"\D")).first ?? "");
  return year != null && year > 0 ? year : null;
}

TrackTags? _readTrackTagsWithReader(String path) {
  final first = _readTrackTagsOnce(path);
  // An MP3 that came back without any text may have been read badly (a
  // network share can answer short): once more before it is cached so.
  if (first != null &&
      path.toLowerCase().endsWith(".mp3") &&
      first.title == null &&
      first.artist == null &&
      first.album == null) {
    return _readTrackTagsOnce(path) ?? first;
  }
  return first;
}

TrackTags? _readTrackTagsOnce(String path) {
  // The tag reader gets FLAC wrong (a PCM bitrate, or nothing at all when
  // it trips over a block it doesn't know), so FLAC's stream info is read
  // here.
  // Nothing here may throw: one odd file would lose its whole batch.
  T? orNull<T>(T Function() read) {
    try {
      return read();
    } on Object {
      return null;
    }
  }

  final flac = orNull(() => readFlacStreamInfo(path));
  final channels = orNull(() => readChannelCount(path));
  final isMp3 = path.toLowerCase().endsWith(".mp3");
  // The tag reader answers a tag it can't decode with a blank string, not
  // null, which would pass for text that is there.
  String? text(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
  try {
    final metadata = readMetadata(File(path));
    final bitrate = metadata.bitrate;
    // Fall back to the MP3's own frame headers when the tags have no
    // length.
    final mp3 = isMp3 && metadata.duration == null
        ? orNull(() => readMp3StreamInfo(path))
        : null;
    // It also misreads some tags without failing (an ID3v2.2 tag can come
    // back empty), so an MP3 with no text gets its ID3 tag read here.
    final id3 =
        isMp3 &&
            (text(metadata.artist) == null ||
                text(metadata.title) == null ||
                text(metadata.album) == null)
        ? orNull(() => readId3Text(path))
        : null;
    return TrackTags(
      path,
      artist: text(metadata.artist) ?? id3?.artist,
      album: text(metadata.album) ?? id3?.album,
      title: text(metadata.title) ?? id3?.title,
      genres: [
        for (final genre in metadata.genres)
          if (genre.trim().isNotEmpty) genre.trim(),
      ],
      trackNumber: metadata.trackNumber,
      discNumber: metadata.discNumber,
      year: _yearOf(metadata),
      duration: flac?.duration ?? metadata.duration ?? mp3?.duration,
      // Tags report bits per second; the classic player shows kbps.
      bitrate:
          flac?.bitrate ??
          (bitrate == null
              ? mp3?.bitrate
              : (bitrate >= 10000 ? bitrate ~/ 1000 : bitrate)),
      sampleRate: flac?.sampleRate ?? metadata.sampleRate ?? mp3?.sampleRate,
      channels: channels,
    );
  } on Object {
    // The tag reader can't parse everything, e.g. the ID3v2.2 tags older
    // iTunes versions wrote, so MP3s get their tags and length read here.
    final mp3 = isMp3 ? orNull(() => readMp3StreamInfo(path)) : null;
    final id3 = isMp3 ? orNull(() => readId3Text(path)) : null;
    if (flac == null && channels == null && mp3 == null && id3 == null) {
      return null;
    }
    return TrackTags(
      path,
      artist: id3?.artist,
      album: id3?.album,
      title: id3?.title,
      duration: flac?.duration ?? mp3?.duration,
      bitrate: flac?.bitrate ?? mp3?.bitrate,
      sampleRate: flac?.sampleRate ?? mp3?.sampleRate,
      channels: channels,
    );
  }
}

/// The sample rate (Hz), length and average bitrate (kbps) of the FLAC file
/// at [path], from its STREAMINFO block; `null` when it isn't FLAC or can't
/// be read. The bitrate is the file size over the length, as the classic player shows
/// it for FLAC.
({int sampleRate, Duration? duration, int? bitrate})? readFlacStreamInfo(
  String path,
) {
  final Uint8List head;
  final int size;
  try {
    final file = File(path).openSync();
    try {
      size = file.lengthSync();
      var start = 0;
      final id3 = file.readSync(10);
      // Some encoders put an ID3v2 tag before the FLAC stream.
      if (id3.length == 10 &&
          id3[0] == 0x49 &&
          id3[1] == 0x44 &&
          id3[2] == 0x33) {
        start =
            10 +
            ((id3[6] & 0x7f) << 21 |
                (id3[7] & 0x7f) << 14 |
                (id3[8] & 0x7f) << 7 |
                (id3[9] & 0x7f));
      }
      file.setPositionSync(start);
      head = file.readSync(8 + 34);
    } finally {
      file.closeSync();
    }
  } on Object {
    return null;
  }
  // "fLaC", then the STREAMINFO block (type 0, always first).
  if (head.length < 8 + 34 ||
      String.fromCharCodes(head.sublist(0, 4)) != "fLaC" ||
      head[4] & 0x7f != 0) {
    return null;
  }
  // After the block and frame sizes: 20 bits of sample rate, 3 of channels,
  // 5 of bits per sample and 36 of total samples.
  final sampleRate = head[18] << 12 | head[19] << 4 | head[20] >> 4;
  if (sampleRate == 0) return null;
  final samples =
      (head[21] & 0x0f) * 0x100000000 +
      (head[22] << 24 | head[23] << 16 | head[24] << 8 | head[25]);
  if (samples == 0) {
    return (sampleRate: sampleRate, duration: null, bitrate: null);
  }
  final seconds = samples / sampleRate;
  return (
    sampleRate: sampleRate,
    duration: Duration(microseconds: (seconds * 1e6).round()),
    bitrate: (size * 8 / seconds / 1000).round(),
  );
}

/// The channel count in the header of the audio file at [path] (WAV,
/// FLAC, MP3, Ogg Vorbis or Opus), or `null` when it can't be told.
int? readChannelCount(String path) {
  final Uint8List head;
  try {
    final file = File(path).openSync();
    try {
      head = file.readSync(64 * 1024);
    } finally {
      file.closeSync();
    }
  } on Object {
    return null;
  }
  bool at(int offset, String text) {
    if (offset + text.length > head.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (head[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  int u32le(int o) =>
      head[o] | head[o + 1] << 8 | head[o + 2] << 16 | head[o + 3] << 24;

  // WAV: the `fmt ` chunk's channel count.
  if (at(0, "RIFF") && at(8, "WAVE")) {
    var o = 12;
    while (o + 8 <= head.length) {
      final size = u32le(o + 4);
      if (at(o, "fmt ") && o + 12 <= head.length) {
        return head[o + 10] | head[o + 11] << 8;
      }
      o += 8 + size + (size & 1);
    }
    return null;
  }
  // FLAC: STREAMINFO, 3 bits after the 20-bit sample rate.
  if (at(0, "fLaC") && head.length >= 8 + 13) {
    return ((head[8 + 12] >> 1) & 7) + 1;
  }
  // Ogg: the Vorbis or Opus identification header in the first page.
  if (at(0, "OggS")) {
    for (var o = 0; o + 16 < head.length && o < 512; o++) {
      if (at(o, "\u0001vorbis")) return head[o + 11];
      if (at(o, "OpusHead")) return head[o + 9];
    }
    return null;
  }
  // MP3: the first frame header after any ID3v2 tag; channel mode 3 is
  // mono.
  var o = 0;
  if (at(0, "ID3") && head.length >= 10) {
    o =
        10 +
        ((head[6] & 0x7f) << 21 |
            (head[7] & 0x7f) << 14 |
            (head[8] & 0x7f) << 7 |
            (head[9] & 0x7f));
    if (o >= head.length) {
      // A large tag (cover art): read on from its end.
      try {
        final file = File(path).openSync()..setPositionSync(o);
        final frames = file.readSync(8 * 1024);
        file.closeSync();
        return _mp3Channels(frames, 0);
      } on Object {
        return null;
      }
    }
  }
  return _mp3Channels(head, o);
}

int? _mp3Channels(Uint8List bytes, int start) {
  for (var o = start; o + 4 <= bytes.length; o++) {
    // Frame sync, a valid version/layer, bitrate and sample rate.
    if (bytes[o] == 0xff &&
        bytes[o + 1] & 0xe0 == 0xe0 &&
        bytes[o + 1] & 0x18 != 0x08 &&
        bytes[o + 1] & 0x06 != 0 &&
        bytes[o + 2] & 0xf0 != 0xf0 &&
        bytes[o + 2] & 0x0c != 0x0c) {
      return (bytes[o + 3] >> 6) == 3 ? 1 : 2;
    }
  }
  return null;
}
