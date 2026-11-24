import "dart:async";

import "track_tags.dart";

/// Where a source is and who it signs in as: what a [RemoteLibrarySource] is
/// built from. The password (or token) is handed over separately, from the
/// secure store.
class SourceConnection {
  const SourceConnection({
    required this.id,
    required this.server,
    required this.user,
  });

  /// The source's stable id, which names its tracks.
  final String id;

  /// The server's address: `https://music.example.com`.
  final String server;
  final String user;
}

/// Opens the connection to a source of one type.
typedef RemoteLibrarySourceFactory =
    RemoteLibrarySource Function(SourceConnection connection, String password);

/// The tracks of one remote source: what each source type provides.
abstract class RemoteLibrarySource {
  /// Throws when the server can't be reached or refuses the sign-in.
  Future<void> check();

  /// Hands every track to [add], a page at a time.
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  );

  /// The URL that plays the item [id], signed for now.
  FutureOr<String> streamUrl(String id);

  /// The URL of the picture of the item [id], or null when the server has
  /// none to give by id (the library's own tracks may know one).
  FutureOr<String?> coverUrl(String id) => null;

  /// Hands every video to [add], a page at a time. Most servers have none.
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  void close();
}

/// A [RemoteLibrarySource] whose server has playlists of videos.
abstract interface class HasVideoPlaylists {
  /// The playlists, each with the paths of its items, by name.
  Future<Map<String, List<String>>> loadVideoPlaylists();
}

/// A [RemoteLibrarySource] whose server keeps where the user stopped playing.
abstract interface class ResumesPlayback {
  /// Where the user stopped the item [id], or null when it was not started,
  /// is finished or the server doesn't say.
  Future<Duration?> resumePosition(String id);
}

/// A [RemoteLibrarySource] whose server also has audiobooks.
abstract interface class HasBooks {
  /// Hands every audiobook (each audio file a track) to [add], a book at a
  /// time.
  Future<void> loadBooks(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  );
}

/// A [RemoteLibrarySource] that is told how far the user got in its items.
abstract interface class ReportsProgress {
  /// Tells the server that the user got to [position] of the [duration] long
  /// item [id], or finished it. Throws when it can't.
  Future<void> reportProgress(
    String id,
    Duration position,
    Duration duration, {
    required bool finished,
  });
}

/// A [RemoteLibrarySource] whose sign-in changes while it is used (an OAuth token
/// that was refreshed): the manager saves [refreshedPassword] after using it.
abstract interface class RefreshesCredentials {
  /// The new text for the saved password, or null when nothing changed.
  String? get refreshedPassword;
}
