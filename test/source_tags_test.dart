import "dart:typed_data";

import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/player/playlist.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _Remote implements RemoteLibrarySource {
  @override
  String? coverUrl(String id) => "http://x/cover/$id";

  @override
  Future<void> check() async {}

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) async {}

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  @override
  String streamUrl(String id) => "http://x/$id";

  @override
  void close() {}
}

class _Store implements RemoteCredentialStore {
  final Map<String, RemoteLogin> logins = {};

  @override
  Future<RemoteLogin?> read(String server) async => logins[server];

  @override
  Future<void> write(String server, RemoteLogin login) async =>
      logins[server] = login;

  @override
  Future<void> delete(String server) async => logins.remove(server);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    "source tracks get their title and details from the tag cache",
    () async {
      final location = SourceLocation.build("navidrome-1", "song-1");
      final cache = MemoryTagCache();
      await cache.store([
        TrackTags(
          location,
          artist: "Artist",
          album: "Album",
          title: "Song",
          trackNumber: 3,
          duration: const Duration(minutes: 7, seconds: 8),
        ),
      ]);
      final playlist = Playlist(tagCache: cache);
      await playlist.add([location]);
      await playlist.tagsRead(playlist.entries.single);
      final entry = playlist.entries.single;
      expect(entry.title, "Artist - Song");
      expect(entry.album, "Album");
      expect(entry.duration, const Duration(minutes: 7, seconds: 8));
    },
  );

  test(
    "source tracks added before their source loaded get tags later",
    () async {
      final location = SourceLocation.build("navidrome-1", "song-1");
      final cache = MemoryTagCache();
      final playlist = Playlist(tagCache: cache);
      await playlist.add([location]);
      await playlist.takeSourceTags();
      expect(playlist.entries.single.title, location);

      await cache.store([TrackTags(location, title: "Song")]);
      await playlist.takeSourceTags();
      expect(playlist.entries.single.title, "Song");
    },
  );

  test("the cover of a source track is downloaded from its server", () async {
    final store = _Store();
    final requested = <Uri>[];
    final manager = LibrarySourceManager(
      local: MediaLibrary(readTags: (files) async => const []),
      credentials: store,
      remoteFactory: (config, password) => _Remote(),
      artworkGet: (uri) async {
        requested.add(uri);
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    addTearDown(manager.dispose);
    final source = await manager.addNavidrome(
      name: "Server",
      server: "http://x",
      user: "u",
      password: "p",
    );
    final location = SourceLocation.build(source.id, "song-1");
    expect(await manager.artwork(location), [1, 2, 3]);
    expect(await manager.artwork(location), [1, 2, 3]);
    expect(requested.map((uri) => "$uri"), ["http://x/cover/song-1"]);
    expect(await manager.artwork(SourceLocation.build("gone", "x")), isNull);
  });
}
