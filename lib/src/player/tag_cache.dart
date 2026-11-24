import "dart:async";
import "dart:io";
import "dart:isolate";
import "dart:math";

import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter/foundation.dart";
import "package:sqlite3/sqlite3.dart";

export "package:amped_media_source/amped_media_source.dart" show TrackTags;

/// Tags already read from files, kept so that a file is read only once.
/// Like the classic player's cached `#EXTINF` titles, a cached row is trusted: the file
/// is not checked for changes.
abstract interface class TagCache {
  /// The cached tags of those of [paths] that have them, by path.
  Future<Map<String, TrackTags>> lookup(List<String> paths);

  /// Adds or replaces the rows of [tags].
  Future<void> store(List<TrackTags> tags);

  Future<void> close();
}

/// Which files the Media Library holds. A [TagCache] that also implements
/// this keeps the library's membership beside the tags (whose rows it never
/// trims away while the file is in the library).
abstract interface class LibraryStore {
  /// The paths in the library.
  Future<List<String>> libraryPaths();

  Future<void> addToLibrary(List<String> paths);

  Future<void> removeFromLibrary(List<String> paths);
}

/// One entry of a [SavedPlaylist].
@immutable
class SavedPlaylistItem {
  const SavedPlaylistItem(this.location, {this.title, this.duration});

  /// A file path or a URL.
  final String location;

  /// The title the playlist recorded, if any.
  final String? title;
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is SavedPlaylistItem &&
      other.location == location &&
      other.title == title &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(location, title, duration);
}

/// A playlist the user keeps in the Media Library, to load into the player
/// later. Unlike the player's own playlist it is only changed on request.
@immutable
class SavedPlaylist {
  const SavedPlaylist(this.id, this.name, this.items);

  final int id;
  final String name;
  final List<SavedPlaylistItem> items;

  SavedPlaylist renamed(String name) => SavedPlaylist(id, name, items);
}

/// Where the Media Library keeps its [SavedPlaylist]s. A [TagCache] that
/// also implements this keeps them beside the tags (never trimmed away).
abstract interface class PlaylistStore {
  /// Every saved playlist, oldest first.
  Future<List<SavedPlaylist>> savedPlaylists();

  /// Keeps a new playlist and returns its id.
  Future<int> createPlaylist(String name, List<SavedPlaylistItem> items);

  Future<void> renamePlaylist(int id, String name);

  Future<void> deletePlaylist(int id);

  /// Replaces the entries of the playlist.
  Future<void> setPlaylistItems(int id, List<SavedPlaylistItem> items);
}

/// Cover art kept beside the tags for files that can't hold pictures
/// themselves. Like the library, it is the user's own: never trimmed away.
abstract interface class ArtworkStore {
  /// The stored cover of the file at [path], or null.
  Future<Uint8List?> storedArtwork(String path);

  /// Keeps [bytes] (an encoded image) as the cover of [path].
  Future<void> storeArtwork(String path, Uint8List bytes);
}

/// How far the user got in a track of a remote source (a podcast episode).
@immutable
class PlaybackProgress {
  const PlaybackProgress(this.position, this.duration, {this.finished = false});

  final Duration position;
  final Duration duration;

  /// Played to the end, whatever [position] says.
  final bool finished;

  /// How much was played, 0 to 1.
  double get fraction => finished
      ? 1
      : duration <= Duration.zero
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);

  @override
  bool operator ==(Object other) =>
      other is PlaybackProgress &&
      other.position == position &&
      other.duration == duration &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(position, duration, finished);
}

/// Where the player's progress in remote tracks is kept. A [TagCache] that
/// also implements this keeps it beside the tags (never trimmed away: it is
/// the user's own).
abstract interface class ProgressStore {
  /// The progress of every location that starts with [prefix], by location.
  Future<Map<String, PlaybackProgress>> progressWithPrefix(String prefix);

  /// Keeps [progress] as that of [location].
  Future<void> saveProgress(String location, PlaybackProgress progress);
}

/// What a played item is, which decides where its play count is listed.
enum PlayKind { music, video, podcast }

/// How often an item was played, and when last.
@immutable
class PlayStat {
  const PlayStat({
    required this.location,
    required this.kind,
    required this.plays,
    required this.lastPlayed,
    this.title,
    this.artist,
    this.album,
  });

  final String location;
  final PlayKind kind;
  final int plays;
  final DateTime lastPlayed;
  final String? title;

  /// The artist of a song; the channel or show of a video or episode.
  final String? artist;

  /// The album of a song; the podcast of an episode.
  final String? album;
}

/// Where how often things were played is kept. A [TagCache] that also
/// implements this keeps it beside the tags (never trimmed away: it is the
/// user's own).
abstract interface class PlayStatsStore {
  /// Counts one more play of [location], remembering its labels.
  Future<void> recordPlay(
    String location,
    PlayKind kind, {
    String? title,
    String? artist,
    String? album,
    DateTime? at,
  });

  /// The play counts of everything that was played.
  Future<List<PlayStat>> playStats();
}

/// A [TagCache] in a map, for tests.
class MemoryTagCache
    implements
        TagCache,
        LibraryStore,
        ArtworkStore,
        PlaylistStore,
        ProgressStore,
        PlayStatsStore {
  /// The play counts, by location.
  final Map<String, PlayStat> plays = {};

  @override
  Future<void> recordPlay(
    String location,
    PlayKind kind, {
    String? title,
    String? artist,
    String? album,
    DateTime? at,
  }) async {
    plays[location] = PlayStat(
      location: location,
      kind: kind,
      plays: (plays[location]?.plays ?? 0) + 1,
      lastPlayed: at ?? DateTime.now(),
      title: title,
      artist: artist,
      album: album,
    );
  }

  @override
  Future<List<PlayStat>> playStats() async => plays.values.toList();

  /// The saved progress, by location.
  final Map<String, PlaybackProgress> progress = {};

  @override
  Future<Map<String, PlaybackProgress>> progressWithPrefix(
    String prefix,
  ) async => {
    for (final entry in progress.entries)
      if (entry.key.startsWith(prefix)) entry.key: entry.value,
  };

  @override
  Future<void> saveProgress(String location, PlaybackProgress value) async =>
      progress[location] = value;

  /// The cached rows, by path.
  final Map<String, TrackTags> rows = {};

  /// The paths looked up so far, in order.
  final List<String> lookups = [];

  /// The paths stored so far, in order.
  final List<String> stores = [];

  @override
  Future<Map<String, TrackTags>> lookup(List<String> paths) async {
    lookups.addAll(paths);
    return {
      for (final path in paths)
        if (rows[path] case final tags?) path: tags,
    };
  }

  @override
  Future<void> store(List<TrackTags> tags) async {
    stores.addAll([for (final tag in tags) tag.path]);
    for (final tag in tags) {
      rows[tag.path] = tag;
    }
  }

  /// The stored covers, by path.
  final Map<String, Uint8List> artwork = {};

  @override
  Future<Uint8List?> storedArtwork(String path) async => artwork[path];

  @override
  Future<void> storeArtwork(String path, Uint8List bytes) async =>
      artwork[path] = bytes;

  /// The paths in the library, in the order they were added.
  final Set<String> library = {};

  @override
  Future<List<String>> libraryPaths() async => library.toList();

  @override
  Future<void> addToLibrary(List<String> paths) async => library.addAll(paths);

  @override
  Future<void> removeFromLibrary(List<String> paths) async =>
      library.removeAll(paths);

  /// The saved playlists, by id.
  final Map<int, SavedPlaylist> playlists = {};
  int _nextPlaylistId = 1;

  @override
  Future<List<SavedPlaylist>> savedPlaylists() async =>
      playlists.values.toList();

  @override
  Future<int> createPlaylist(String name, List<SavedPlaylistItem> items) async {
    final id = _nextPlaylistId++;
    playlists[id] = SavedPlaylist(id, name, List.of(items));
    return id;
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    if (playlists[id] case final playlist?) {
      playlists[id] = playlist.renamed(name);
    }
  }

  @override
  Future<void> deletePlaylist(int id) async => playlists.remove(id);

  @override
  Future<void> setPlaylistItems(int id, List<SavedPlaylistItem> items) async {
    if (playlists[id] case final playlist?) {
      playlists[id] = SavedPlaylist(id, playlist.name, List.of(items));
    }
  }

  @override
  Future<void> close() async {}
}

/// A [TagCache] in a SQLite database, one row per file path. The database
/// is used from a background isolate, so lookups and writes never hold up
/// the windows.
class SqliteTagCache
    implements
        TagCache,
        LibraryStore,
        ArtworkStore,
        PlaylistStore,
        ProgressStore,
        PlayStatsStore {
  SqliteTagCache._(this._isolate, this._requests, this._replies);

  /// The most the rows may take up before the oldest read are removed:
  /// 10 MB, tens of thousands of files.
  static const defaultMaxBytes = 10 * 1024 * 1024;

  /// Opens (creating if need be) the database at [path], or an in-memory
  /// one for `":memory:"`. Throws when it can't be opened or isn't a
  /// database. Rows are kept until they take up more than [maxBytes]; then
  /// the ones read longest ago are removed.
  static Future<SqliteTagCache> open(
    String path, {
    int maxBytes = defaultMaxBytes,
  }) async {
    final replies = ReceivePort();
    final ready = Completer<Object?>();
    SqliteTagCache? cache;
    replies.listen((message) {
      if (cache != null) {
        cache._onReply(message);
      } else if (!ready.isCompleted) {
        ready.complete(message);
      }
    });
    final isolate = await Isolate.spawn(
      _serve,
      (replies.sendPort, path, maxBytes),
      debugName: "SqliteTagCache",
      onExit: replies.sendPort,
      errorsAreFatal: false,
    );
    final first = await ready.future;
    if (first is! SendPort) {
      replies.close();
      isolate.kill();
      throw TagCacheException("Could not open $path: $first");
    }
    return cache = SqliteTagCache._(isolate, first, replies);
  }

  /// [open], but logs a failure and returns null instead of throwing.
  static Future<SqliteTagCache?> tryOpen(String path) async {
    try {
      if (path != ":memory:") {
        await Directory(File(path).parent.path).create(recursive: true);
      }
      return await open(path);
    } on Object catch (error) {
      Arcane.log(
        "Tag cache unavailable, reading files instead",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "TagCache",
      );
      return null;
    }
  }

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  void _onReply(Object? message) {
    if (message case (final int id, final Object? result)) {
      final completer = _pending.remove(id);
      if (result is TagCacheException) {
        completer?.completeError(result);
      } else {
        completer?.complete(result);
      }
      return;
    }
    // The isolate exited (null) or failed.
    _closed = true;
    for (final completer in _pending.values) {
      completer.completeError(
        TagCacheException("The tag cache stopped: $message"),
      );
    }
    _pending.clear();
  }

  Future<Object?> _send(_Request request) {
    if (_closed) {
      return Future.error(const TagCacheException("The tag cache is closed"));
    }
    final id = _nextId++;
    final completer = _pending[id] = Completer();
    _requests.send((id, request));
    return completer.future;
  }

  @override
  Future<Map<String, TrackTags>> lookup(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final rows = await _send(_Lookup(paths)) as List<TrackTags>;
    return {for (final row in rows) row.path: row};
  }

  @override
  Future<void> store(List<TrackTags> tags) async {
    if (tags.isEmpty) return;
    await _send(_Store(tags));
  }

  @override
  Future<List<String>> libraryPaths() async =>
      await _send(const _LibraryList()) as List<String>;

  @override
  Future<void> addToLibrary(List<String> paths) async {
    if (paths.isEmpty) return;
    await _send(_LibraryAdd(paths));
  }

  @override
  Future<void> removeFromLibrary(List<String> paths) async {
    if (paths.isEmpty) return;
    await _send(_LibraryRemove(paths));
  }

  @override
  Future<Uint8List?> storedArtwork(String path) async =>
      await _send(_ArtworkGet(path)) as Uint8List?;

  @override
  Future<void> storeArtwork(String path, Uint8List bytes) async {
    await _send(_ArtworkSet(path, bytes));
  }

  @override
  Future<Map<String, PlaybackProgress>> progressWithPrefix(
    String prefix,
  ) async =>
      await _send(_ProgressList(prefix)) as Map<String, PlaybackProgress>;

  @override
  Future<void> saveProgress(String location, PlaybackProgress progress) async {
    await _send(_ProgressSet(location, progress));
  }

  @override
  Future<void> recordPlay(
    String location,
    PlayKind kind, {
    String? title,
    String? artist,
    String? album,
    DateTime? at,
  }) async {
    await _send(
      _PlayRecord(
        location,
        kind,
        title,
        artist,
        album,
        (at ?? DateTime.now()).millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<List<PlayStat>> playStats() async =>
      await _send(const _PlayList()) as List<PlayStat>;

  @override
  Future<List<SavedPlaylist>> savedPlaylists() async =>
      await _send(const _PlaylistList()) as List<SavedPlaylist>;

  @override
  Future<int> createPlaylist(
    String name,
    List<SavedPlaylistItem> items,
  ) async => await _send(_PlaylistCreate(name, items)) as int;

  @override
  Future<void> renamePlaylist(int id, String name) async {
    await _send(_PlaylistRename(id, name));
  }

  @override
  Future<void> deletePlaylist(int id) async {
    await _send(_PlaylistDelete(id));
  }

  @override
  Future<void> setPlaylistItems(int id, List<SavedPlaylistItem> items) async {
    await _send(_PlaylistSetItems(id, items));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _send(const _Close());
    _closed = true;
    _replies.close();
    _isolate.kill();
  }
}

/// A failure of the [SqliteTagCache] database.
class TagCacheException implements Exception {
  const TagCacheException(this.message);

  final String message;

  @override
  String toString() => "TagCacheException: $message";
}

sealed class _Request {
  const _Request();
}

class _Lookup extends _Request {
  const _Lookup(this.paths);

  final List<String> paths;
}

class _Store extends _Request {
  const _Store(this.tags);

  final List<TrackTags> tags;
}

class _ArtworkGet extends _Request {
  const _ArtworkGet(this.path);

  final String path;
}

class _ArtworkSet extends _Request {
  const _ArtworkSet(this.path, this.bytes);

  final String path;
  final Uint8List bytes;
}

class _LibraryList extends _Request {
  const _LibraryList();
}

class _LibraryAdd extends _Request {
  const _LibraryAdd(this.paths);

  final List<String> paths;
}

class _LibraryRemove extends _Request {
  const _LibraryRemove(this.paths);

  final List<String> paths;
}

class _PlaylistList extends _Request {
  const _PlaylistList();
}

class _PlaylistCreate extends _Request {
  const _PlaylistCreate(this.name, this.items);

  final String name;
  final List<SavedPlaylistItem> items;
}

class _PlaylistRename extends _Request {
  const _PlaylistRename(this.id, this.name);

  final int id;
  final String name;
}

class _PlaylistDelete extends _Request {
  const _PlaylistDelete(this.id);

  final int id;
}

class _PlaylistSetItems extends _Request {
  const _PlaylistSetItems(this.id, this.items);

  final int id;
  final List<SavedPlaylistItem> items;
}

class _ProgressList extends _Request {
  const _ProgressList(this.prefix);

  final String prefix;
}

class _ProgressSet extends _Request {
  const _ProgressSet(this.location, this.progress);

  final String location;
  final PlaybackProgress progress;
}

class _PlayRecord extends _Request {
  const _PlayRecord(
    this.location,
    this.kind,
    this.title,
    this.artist,
    this.album,
    this.at,
  );

  final String location;
  final PlayKind kind;
  final String? title;
  final String? artist;
  final String? album;
  final int at;
}

class _PlayList extends _Request {
  const _PlayList();
}

class _Close extends _Request {
  const _Close();
}

/// The schema version, in `PRAGMA user_version`. Also bumped when tags are
/// read differently, so old rows are read again (3: MP3 lengths and ID3v2.2
/// text from the files' own headers; 4: text the general reader missed, from
/// the File Info reader; 5: the year).
const _schemaVersion = 5;

/// How many paths one `SELECT … IN (…)` covers.
const _lookupChunk = 500;

/// The background isolate: opens the database, sends back its request port
/// (or the error), then answers requests one at a time.
void _serve((SendPort, String, int) args) {
  final (replies, path, maxBytes) = args;
  final Database db;
  try {
    db = sqlite3.open(path);
    try {
      // Fails ("file is not a database") for a corrupt file.
      db
        ..execute("PRAGMA journal_mode = WAL")
        ..execute("PRAGMA synchronous = NORMAL");
      if (db.userVersion != _schemaVersion) {
        db
          ..execute("DROP TABLE IF EXISTS tags")
          ..userVersion = _schemaVersion;
      }
      db.execute("""
        CREATE TABLE IF NOT EXISTS tags (
          path TEXT NOT NULL PRIMARY KEY,
          artist TEXT,
          album TEXT,
          title TEXT,
          track_number INTEGER,
          disc_number INTEGER,
          year INTEGER,
          duration_us INTEGER,
          bitrate INTEGER,
          sample_rate INTEGER,
          channels INTEGER,
          genres TEXT,
          read_at INTEGER NOT NULL
        )""");
      // Kept when the tag schema changes: the library is the user's own.
      db.execute("""
        CREATE TABLE IF NOT EXISTS library (
          path TEXT NOT NULL PRIMARY KEY,
          added_at INTEGER NOT NULL
        )""");
      // Also the user's own: where they stopped each podcast episode.
      db.execute("""
        CREATE TABLE IF NOT EXISTS playback_progress (
          location TEXT NOT NULL PRIMARY KEY,
          position_ms INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          finished INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )""");
      // Also the user's own: how often each item was played.
      db.execute("""
        CREATE TABLE IF NOT EXISTS play_stats (
          location TEXT NOT NULL PRIMARY KEY,
          kind TEXT NOT NULL,
          title TEXT,
          artist TEXT,
          album TEXT,
          plays INTEGER NOT NULL,
          last_played INTEGER NOT NULL
        )""");
      db.execute("""
        CREATE TABLE IF NOT EXISTS artwork (
          path TEXT NOT NULL PRIMARY KEY,
          data BLOB NOT NULL
        )""");
    } on Object {
      db.close();
      rethrow;
    }
  } on Object catch (error) {
    replies.send("$error");
    return;
  }

  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final (requestId, request) = message as (int, _Request);
    try {
      switch (request) {
        case _Lookup(:final paths):
          replies.send((requestId, _select(db, paths)));
        case _Store(:final tags):
          _insert(db, tags);
          _trim(db, maxBytes);
          replies.send((requestId, null));
        case _ArtworkGet(:final path):
          final rows = db.select(
            "SELECT data FROM artwork WHERE path = ?",
            [path],
          );
          replies.send((
            requestId,
            rows.isEmpty ? null : rows.first["data"] as Uint8List,
          ));
        case _ArtworkSet(:final path, :final bytes):
          db.execute(
            "INSERT OR REPLACE INTO artwork (path, data) VALUES (?, ?)",
            [path, bytes],
          );
          replies.send((requestId, null));
        case _ProgressList(:final prefix):
          replies.send((
            requestId,
            {
              for (final row in db.select(
                "SELECT location, position_ms, duration_ms, finished "
                "FROM playback_progress WHERE substr(location, 1, ?) = ?",
                [prefix.length, prefix],
              ))
                row["location"] as String: PlaybackProgress(
                  Duration(milliseconds: row["position_ms"] as int),
                  Duration(milliseconds: row["duration_ms"] as int),
                  finished: (row["finished"] as int) != 0,
                ),
            },
          ));
        case _ProgressSet(:final location, :final progress):
          db.execute(
            "INSERT OR REPLACE INTO playback_progress (location, "
            "position_ms, duration_ms, finished, updated_at) "
            "VALUES (?, ?, ?, ?, ?)",
            [
              location,
              progress.position.inMilliseconds,
              progress.duration.inMilliseconds,
              progress.finished ? 1 : 0,
              DateTime.now().millisecondsSinceEpoch,
            ],
          );
          replies.send((requestId, null));
        case _PlayRecord(
          :final location,
          :final kind,
          :final title,
          :final artist,
          :final album,
          :final at,
        ):
          db.execute(
            "INSERT INTO play_stats (location, kind, title, artist, album, "
            "plays, last_played) VALUES (?, ?, ?, ?, ?, 1, ?) "
            "ON CONFLICT(location) DO UPDATE SET plays = plays + 1, "
            "kind = excluded.kind, last_played = excluded.last_played, "
            "title = coalesce(excluded.title, title), "
            "artist = coalesce(excluded.artist, artist), "
            "album = coalesce(excluded.album, album)",
            [location, kind.name, title, artist, album, at],
          );
          replies.send((requestId, null));
        case _PlayList():
          replies.send((
            requestId,
            [
              for (final row in db.select(
                "SELECT location, kind, title, artist, album, plays, "
                "last_played FROM play_stats",
              ))
                PlayStat(
                  location: row["location"] as String,
                  kind: PlayKind.values.byName(row["kind"] as String),
                  plays: row["plays"] as int,
                  lastPlayed: DateTime.fromMillisecondsSinceEpoch(
                    row["last_played"] as int,
                  ),
                  title: row["title"] as String?,
                  artist: row["artist"] as String?,
                  album: row["album"] as String?,
                ),
            ],
          ));
        case _LibraryList():
          replies.send((
            requestId,
            [
              for (final row in db.select(
                "SELECT path FROM library ORDER BY added_at, rowid",
              ))
                row["path"] as String,
            ],
          ));
        case _LibraryAdd(:final paths):
          _libraryChange(
            db,
            "INSERT OR IGNORE INTO library (path, added_at) VALUES (?, ?)",
            paths,
            stamp: true,
          );
          replies.send((requestId, null));
        case _LibraryRemove(:final paths):
          _libraryChange(db, "DELETE FROM library WHERE path = ?", paths);
          replies.send((requestId, null));
        case _PlaylistList():
          _ensurePlaylistTables(db);
          replies.send((requestId, _selectPlaylists(db)));
        case _PlaylistCreate(:final name, :final items):
          _ensurePlaylistTables(db);
          replies.send((requestId, _insertPlaylist(db, name, items)));
        case _PlaylistRename(:final id, :final name):
          _ensurePlaylistTables(db);
          db.execute("UPDATE playlists SET name = ? WHERE id = ?", [name, id]);
          replies.send((requestId, null));
        case _PlaylistDelete(:final id):
          _ensurePlaylistTables(db);
          db
            ..execute("BEGIN")
            ..execute("DELETE FROM playlist_items WHERE playlist_id = ?", [id])
            ..execute("DELETE FROM playlists WHERE id = ?", [id])
            ..execute("COMMIT");
          replies.send((requestId, null));
        case _PlaylistSetItems(:final id, :final items):
          _ensurePlaylistTables(db);
          _replacePlaylistItems(db, id, items);
          replies.send((requestId, null));
        case _Close():
          db.close();
          replies.send((requestId, null));
          requests.close();
      }
    } on Object catch (error) {
      replies.send((requestId, TagCacheException("$error")));
    }
  });
}

List<TrackTags> _select(Database db, List<String> paths) {
  final rows = <TrackTags>[];
  for (var start = 0; start < paths.length; start += _lookupChunk) {
    final chunk = paths.sublist(
      start,
      min(start + _lookupChunk, paths.length),
    );
    final marks = List.filled(chunk.length, "?").join(",");
    final result = db.select(
      "SELECT path, artist, album, title, track_number, disc_number, year, "
      "duration_us, bitrate, sample_rate, channels, genres FROM tags "
      "WHERE path IN ($marks)",
      chunk,
    );
    for (final row in result) {
      final duration = row["duration_us"] as int?;
      rows.add(
        TrackTags(
          row["path"] as String,
          artist: row["artist"] as String?,
          album: row["album"] as String?,
          title: row["title"] as String?,
          trackNumber: row["track_number"] as int?,
          discNumber: row["disc_number"] as int?,
          year: row["year"] as int?,
          duration: duration == null ? null : Duration(microseconds: duration),
          bitrate: row["bitrate"] as int?,
          sampleRate: row["sample_rate"] as int?,
          channels: row["channels"] as int?,
          genres: _splitGenres(row["genres"] as String?),
        ),
      );
    }
  }
  return rows;
}

void _insert(Database db, List<TrackTags> tags) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final insert = db.prepare(
    "INSERT OR REPLACE INTO tags (path, artist, album, title, track_number, "
    "disc_number, year, duration_us, bitrate, sample_rate, channels, genres, "
    "read_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  );
  db.execute("BEGIN");
  try {
    for (final tag in tags) {
      insert.execute([
        tag.path,
        tag.artist,
        tag.album,
        tag.title,
        tag.trackNumber,
        tag.discNumber,
        tag.year,
        tag.duration?.inMicroseconds,
        tag.bitrate,
        tag.sampleRate,
        tag.channels,
        tag.genres.isEmpty ? null : tag.genres.join(_genreSeparator),
        now,
      ]);
    }
    db.execute("COMMIT");
  } on Object {
    db.execute("ROLLBACK");
    rethrow;
  } finally {
    insert.close();
  }
}

void _libraryChange(
  Database db,
  String sql,
  List<String> paths, {
  bool stamp = false,
}) {
  final statement = db.prepare(sql);
  final now = DateTime.now().millisecondsSinceEpoch;
  db.execute("BEGIN");
  try {
    for (final path in paths) {
      statement.execute(stamp ? [path, now] : [path]);
    }
    db.execute("COMMIT");
  } on Object {
    db.execute("ROLLBACK");
    rethrow;
  } finally {
    statement.close();
  }
}

/// How much of the database its pages in use take up, in bytes.
int _usedBytes(Database db) {
  int pragma(String name) =>
      db.select("PRAGMA $name").first.values.first! as int;
  final artwork =
      db
              .select("SELECT coalesce(sum(length(data)), 0) FROM artwork")
              .first
              .values
              .first!
          as int;
  // Stored covers are kept whatever the size, so they don't count.
  return max(
    0,
    (pragma("page_count") - pragma("freelist_count")) * pragma("page_size") -
        artwork,
  );
}

/// When the rows take up more than [maxBytes], removes those read longest
/// ago, down to nine tenths of it. Files in the library are kept. Freed
/// pages are reused, so the file stops growing.
void _trim(Database db, int maxBytes) {
  for (var used = _usedBytes(db); used > maxBytes; used = _usedBytes(db)) {
    final rows =
        db
                .select(
                  "SELECT count(*) FROM tags "
                  "WHERE path NOT IN (SELECT path FROM library)",
                )
                .first
                .values
                .first!
            as int;
    if (rows == 0) return;
    final remove = max(1, (rows * (used - maxBytes * 0.9) / used).ceil());
    db.execute(
      "DELETE FROM tags WHERE rowid IN "
      "(SELECT rowid FROM tags WHERE path NOT IN (SELECT path FROM library) "
      "ORDER BY read_at, rowid LIMIT ?)",
      [remove],
    );
  }
}

/// Separates the genres in the `genres` column (a character no genre has).
const _genreSeparator = "\n";

List<String> _splitGenres(String? genres) =>
    genres == null || genres.isEmpty ? const [] : genres.split(_genreSeparator);

List<SavedPlaylist> _selectPlaylists(Database db) {
  final items = <int, List<SavedPlaylistItem>>{};
  for (final row in db.select(
    "SELECT playlist_id, location, title, duration_ms FROM playlist_items "
    "ORDER BY playlist_id, position",
  )) {
    final duration = row["duration_ms"] as int?;
    (items[row["playlist_id"] as int] ??= []).add(
      SavedPlaylistItem(
        row["location"] as String,
        title: row["title"] as String?,
        duration: duration == null ? null : Duration(milliseconds: duration),
      ),
    );
  }
  return [
    for (final row in db.select("SELECT id, name FROM playlists ORDER BY id"))
      SavedPlaylist(
        row["id"] as int,
        row["name"] as String,
        items[row["id"] as int] ?? const [],
      ),
  ];
}

int _insertPlaylist(Database db, String name, List<SavedPlaylistItem> items) {
  db.execute("BEGIN");
  try {
    db.execute("INSERT INTO playlists (name) VALUES (?)", [name]);
    final id = db.lastInsertRowId;
    _insertPlaylistItems(db, id, items);
    db.execute("COMMIT");
    return id;
  } on Object {
    db.execute("ROLLBACK");
    rethrow;
  }
}

void _replacePlaylistItems(Database db, int id, List<SavedPlaylistItem> items) {
  db.execute("BEGIN");
  try {
    db.execute("DELETE FROM playlist_items WHERE playlist_id = ?", [id]);
    _insertPlaylistItems(db, id, items);
    db.execute("COMMIT");
  } on Object {
    db.execute("ROLLBACK");
    rethrow;
  }
}

void _insertPlaylistItems(
  Database db,
  int id,
  List<SavedPlaylistItem> items,
) {
  final insert = db.prepare(
    "INSERT INTO playlist_items "
    "(playlist_id, position, location, title, duration_ms) "
    "VALUES (?, ?, ?, ?, ?)",
  );
  try {
    for (final (position, item) in items.indexed) {
      insert.execute([
        id,
        position,
        item.location,
        item.title,
        item.duration?.inMilliseconds,
      ]);
    }
  } finally {
    insert.close();
  }
}

/// Creates the saved playlists' tables (also the user's own, so kept when
/// the tag schema changes). Made when first used, so a database without
/// playlists takes no room for them.
void _ensurePlaylistTables(Database db) {
  db
    ..execute("""
        CREATE TABLE IF NOT EXISTS playlists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL
        )""")
    ..execute("""
        CREATE TABLE IF NOT EXISTS playlist_items (
          playlist_id INTEGER NOT NULL,
          position INTEGER NOT NULL,
          location TEXT NOT NULL,
          title TEXT,
          duration_ms INTEGER,
          PRIMARY KEY (playlist_id, position)
        )""");
}
