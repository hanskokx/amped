import "dart:io";

import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _VideoRemote implements RemoteLibrarySource {
  @override
  String? coverUrl(String id) => null;

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
  ) async => add(const [TrackTags("amped-source://x/v1", title: "Movie")]);

  @override
  String streamUrl(String id) => "http://x/$id";

  @override
  void close() {}
}

class _MemoryStore implements RemoteCredentialStore {
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

  test("a video library takes video files and leaves audio alone", () async {
    final dir = Directory.systemTemp.createTempSync("amped_video");
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ["a.mp4", "b.mkv", "c.mp3"]) {
      File("${dir.path}/$name").writeAsStringSync("x");
    }
    final videos = MediaLibrary.videos(readTags: (files) async => const []);
    final audio = MediaLibrary(readTags: (files) async => const []);
    await videos.add([dir.path]);
    await audio.add([dir.path]);
    expect(videos.tracks.map((t) => t.path.split("/").last).toSet(), {
      "a.mp4",
      "b.mkv",
    });
    expect(audio.tracks.map((t) => t.path.split("/").last), ["c.mp3"]);
  });

  test("the Videos section lists all videos, local and each remote", () async {
    final localVideos = MediaLibrary.videos(
      readTags: (files) async => const [],
    );
    localVideos.replaceWith(const [TrackTags("/m/local.mp4")]);
    final manager = LibrarySourceManager(
      local: MediaLibrary(readTags: (files) async => const []),
      localVideos: localVideos,
      credentials: _MemoryStore(),
      remoteFactory: (config, password) => _VideoRemote(),
    );
    addTearDown(manager.dispose);
    final remote = await manager.addNavidrome(
      name: "Server",
      server: "http://x",
      user: "u",
      password: "p",
    );
    LibrarySourceSection? videosSection() => manager
        .sections(localLabel: "Local")
        .where((s) => s.kind == LibrarySourceKind.videos)
        .firstOrNull;
    // Nothing is listed where nothing has videos yet.
    expect(
      videosSection()?.sources.map((s) => s.id),
      isNot(contains("$videoSourcePrefix${remote.id}:movies")),
    );
    await manager.openVideos(remote.id);
    final section = videosSection()!;
    // The remote's video is a movie: no TV shows source for it.
    expect(section.sources.map((s) => s.id), [
      allVideosSourceId,
      "${videoSourcePrefix}local",
      "$videoSourcePrefix${remote.id}:movies",
    ]);
    final all = section.sources.first.library!;
    expect(all.tracks.map((t) => t.path), [
      "/m/local.mp4",
      "amped-source://x/v1",
    ]);
  });
}
