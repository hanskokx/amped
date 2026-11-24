import "dart:async";
import "dart:io";

import "remote_credentials.dart";
import "remote_file_system.dart";
import "remote_location.dart";
import "remote_stream_server.dart";
import "smb_file_system.dart";
import "webdav_file_system.dart";

/// Opens the connection to the share [location] is on.
typedef RemoteFileSystemFactory = Future<RemoteFileSystem> Function(
  RemoteLocation location,
);

/// Folders and files on network shares (SMB, WebDAV), for the playlist
/// and the player.
///
/// A share's folder is listed (recursively) to find its tracks. A video is
/// streamed from the share ([stream]); an audio track is copied to a
/// temporary file before it plays ([fetch]), since SoLoud only reads local
/// files.
class RemoteFiles {
  RemoteFiles({
    Map<RemoteScheme, RemoteFileSystemFactory>? factories,
    this._cacheDirectory,
    this.keptFiles = 3,
    this.store,
    this.prompt,
  }) : _factories = factories ?? defaultFactories;

  /// The real protocols.
  static final Map<RemoteScheme, RemoteFileSystemFactory> defaultFactories = {
    RemoteScheme.smb: SmbFileSystem.connect,
    RemoteScheme.webdav: WebDavFileSystem.connect,
  };

  /// The instance the app uses.
  static final RemoteFiles shared = RemoteFiles(
    store: SecureCredentialStore(),
  );

  /// Where the names and passwords of servers are kept; null keeps none.
  final RemoteCredentialStore? store;

  /// Asks for a name and password when a server wants one; null never asks.
  RemoteLoginPrompt? prompt;

  /// The sign-in question being asked; the next waits for it.
  Future<void> _asking = Future.value();

  /// How many fetched files stay on disk (the newest ones).
  final int keptFiles;

  final Map<RemoteScheme, RemoteFileSystemFactory> _factories;
  Directory? _cacheDirectory;
  final Map<String, Future<String>> _fetching = {};

  /// How deep a folder is searched, so a loop of links ends.
  static const int _maxDepth = 16;

  /// Whether [location] is on a network share rather than a disk or a web
  /// stream.
  static bool isRemote(String location) => RemoteLocation.isRemote(location);

  /// Connects to the server of [location].
  ///
  /// A name and password in the URL are used as they are. Otherwise the
  /// ones saved for the server are, and with none saved the server is tried
  /// as a guest first. When the server turns that down, the user is asked
  /// (with the saved name and password filled in) until it works or they
  /// cancel, and what worked is saved.
  Future<RemoteFileSystem> _connect(RemoteLocation location) async {
    final factory = _factories[location.scheme];
    if (factory == null) {
      throw RemoteFileException("Unsupported scheme '${location.uri.scheme}'");
    }
    if (location.user != null) return factory(location);
    final server = location.server;
    var login = await store?.read(server);
    var asked = false;
    while (true) {
      try {
        final system = await factory(
          login == null
              ? location
              : location.withLogin(login.user, login.password),
        );
        if (asked && login != null) await store?.write(server, login);
        return system;
      } on RemoteAuthException catch (failure) {
        final ask = prompt;
        if (ask == null) rethrow;
        final failed = login;
        final entered = await _ask(ask, server, failed, failure.message);
        if (entered == null) rethrow;
        login = entered;
        asked = true;
      }
    }
  }

  /// Asks one question at a time. If another caller got the server to
  /// accept a different login meanwhile, that one is used without asking.
  Future<RemoteLogin?> _ask(
    RemoteLoginPrompt ask,
    String server,
    RemoteLogin? failed,
    String message,
  ) {
    final turn = _asking.then((_) async {
      final saved = await store?.read(server);
      if (saved != null && saved != failed) return saved;
      return ask(
        RemoteLoginRequest(
          server,
          login: failed,
          error: failed == null ? null : message,
        ),
      );
    });
    _asking = turn.then((_) {}, onError: (_) {});
    return turn;
  }

  /// The URLs of the files [accept]ed in the folder at [folder], and in the
  /// folders below it, in name order. A [folder] that is not a folder (or
  /// can't be reached) gives an empty list.
  Future<List<String>> listFiles(
    String folder,
    bool Function(String name) accept,
  ) async {
    final location = RemoteLocation.tryParse(folder);
    if (location == null) return const [];
    final RemoteFileSystem system;
    try {
      system = await _connect(location);
    } on Object catch (error) {
      throw RemoteFileException(
        "Could not connect to ${location.display}: $error",
      );
    }
    try {
      final found = <String>[];
      await _walk(system, location, accept, found, 0);
      found.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return found;
    } finally {
      await system.close();
    }
  }

  Future<void> _walk(
    RemoteFileSystem system,
    RemoteLocation folder,
    bool Function(String name) accept,
    List<String> found,
    int depth,
  ) async {
    final List<RemoteEntry> entries;
    try {
      entries = await system.list(folder.path);
    } on Object {
      // A folder that can't be read (or isn't one) has nothing to add.
      if (depth == 0) rethrow;
      return;
    }
    for (final entry in entries) {
      final child = RemoteLocation.tryParse(folder.child(entry.name));
      if (child == null) continue;
      if (entry.isDirectory) {
        if (depth < _maxDepth) {
          await _walk(system, child, accept, found, depth + 1);
        }
      } else if (accept(entry.name)) {
        found.add(child.toString());
      }
    }
  }

  /// The files in the folder the file at [location] is in, and in a
  /// `Subs`-like folder there, as file name to URL. Empty when the share
  /// can't be read.
  Future<List<MapEntry<String, String>>> neighbours(
    String location,
    List<String> subfolders,
  ) async {
    final remote = RemoteLocation.tryParse(location);
    if (remote == null || remote.segments.isEmpty) return const [];
    final found = <MapEntry<String, String>>[];
    final RemoteFileSystem system;
    try {
      system = await _connect(remote);
    } on Object {
      return const [];
    }
    try {
      final parent =
          "/${remote.segments.sublist(0, remote.segments.length - 1).join("/")}";
      Future<void> scan(String path, String prefix) async {
        final List<RemoteEntry> entries;
        try {
          entries = await system.list(path);
        } on Object {
          return;
        }
        for (final entry in entries) {
          if (entry.isDirectory) continue;
          found.add(
            MapEntry(entry.name, remote.sibling("$prefix${entry.name}")),
          );
        }
      }

      final entries = await system.list(parent);
      await scan(parent, "");
      for (final entry in entries) {
        if (entry.isDirectory &&
            subfolders.contains(entry.name.toLowerCase())) {
          await scan(
            parent == "/" ? "/${entry.name}" : "$parent/${entry.name}",
            "${entry.name}/",
          );
        }
      }
    } on Object {
      // Nothing to add.
    } finally {
      await system.close();
    }
    return found;
  }

  final RemoteStreamServer _server = RemoteStreamServer();

  /// A URL on this machine that serves the file at [location] as it is read,
  /// with seeking, for a player that opens URLs. Throws when the file
  /// can't be reached.
  Future<String> stream(String location) async {
    final remote = RemoteLocation.tryParse(location);
    if (remote == null || remote.segments.isEmpty) {
      throw RemoteFileException("Not a file on a network share: $location");
    }
    return _server.serve(remote.path, () => _connect(remote));
  }

  /// Stops serving streams.
  Future<void> dispose() => _server.close();

  /// Copies the file at [location] to this machine and returns the path of
  /// the copy. A file fetched before is not fetched again. Throws when it
  /// can't be fetched.
  ///
  /// [onProgress] hears how the download goes (not at all for a file that
  /// was fetched before).
  Future<String> fetch(
    String location, {
    void Function(RemoteProgress progress)? onProgress,
  }) {
    return _fetching[location] ??= _fetch(location, onProgress).whenComplete(
      () {
        _fetching.remove(location);
      },
    );
  }

  Future<String> _fetch(
    String location,
    void Function(RemoteProgress progress)? onProgress,
  ) async {
    final remote = RemoteLocation.tryParse(location);
    if (remote == null || remote.segments.isEmpty) {
      throw RemoteFileException("Not a file on a network share: $location");
    }
    final directory = await _folder();
    final target = File(
      "${directory.path}${Platform.pathSeparator}"
      "${location.hashCode.toUnsigned(32).toRadixString(16)}_${remote.name}",
    );
    if (target.existsSync() && target.lengthSync() > 0) {
      // Touch it, so it counts as the newest.
      target.setLastModifiedSync(DateTime.now());
      return target.path;
    }
    final partial = File("${target.path}.part");
    final system = await _connect(remote);
    try {
      final clock = Stopwatch()..start();
      onProgress?.call(const RemoteProgress(0, null, Duration.zero));
      await system.download(
        remote.path,
        partial,
        onProgress: onProgress == null
            ? null
            : (received, total) =>
                  onProgress(RemoteProgress(received, total, clock.elapsed)),
      );
      await partial.rename(target.path);
    } on Object {
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    } finally {
      await system.close();
    }
    _prune(directory, target);
    return target.path;
  }

  Future<Directory> _folder() async {
    final existing = _cacheDirectory;
    if (existing != null) {
      if (!existing.existsSync()) await existing.create(recursive: true);
      return existing;
    }
    final folder = Directory(
      "${Directory.systemTemp.path}${Platform.pathSeparator}amped_remote",
    );
    // What an earlier run left behind is not wanted.
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } on FileSystemException {
      // A file still in use; the rest is gone.
    }
    await folder.create(recursive: true);
    return _cacheDirectory = folder;
  }

  /// Deletes all but the newest [keptFiles] files, never [keep].
  void _prune(Directory directory, File keep) {
    try {
      final files = [
        for (final entity in directory.listSync())
          if (entity is File && entity.path != keep.path) entity,
      ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final old in files.skip(keptFiles - 1)) {
        old.deleteSync();
      }
    } on FileSystemException {
      // A file in use stays.
    }
  }
}
