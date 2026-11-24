import "dart:convert";
import "dart:io";

import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/library_sources.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/library/source_settings.dart";
import "package:amped/src/player/tag_cache.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_audiobookshelf/amped_audiobookshelf.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_podcast/amped_podcast.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

const _feed = """
<?xml version="1.0"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
  <title>Show</title>
  <itunes:author>Host</itunes:author>
  <description>About the show.</description>
  <itunes:image href="http://img/show.jpg"/>
  <item>
    <title>Two</title>
    <description><![CDATA[<p>Hello &amp; <b>world</b></p><p>Second.</p>]]></description>
    <pubDate>Tue, 03 Jan 2023 10:00:00 +0000</pubDate>
    <itunes:duration>1:02:03</itunes:duration>
    <itunes:image href="http://img/two.jpg"/>
    <enclosure url="http://audio/two.mp3" type="audio/mpeg"/>
  </item>
  <item>
    <title>One</title>
    <itunes:duration>90</itunes:duration>
    <enclosure url="http://audio/one.mp3" type="audio/mpeg"/>
  </item>
  <item><title>No audio</title></item>
</channel>
</rss>""";

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
  late HttpServer http;
  String address() => "http://127.0.0.1:${http.port}";

  /// What the fake serves as the feed.
  late String feedBody;

  /// The bodies of the progress updates the Audiobookshelf fake received.
  late List<Map<String, dynamic>> patches;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    patches = [];
    feedBody = _feed;
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) {
      final response = request.response;
      final path = request.uri.path;
      final authorized =
          request.headers.value("Authorization") == "Bearer abs-token";
      if (path == "/feed.xml") {
        response
          ..write(feedBody)
          ..close();
      } else if (path == "/search") {
        response
          ..write(
            jsonEncode({
              "results": [
                {
                  "collectionName": "Found",
                  "feedUrl": "http://x/feed",
                  "artworkUrl600": "http://x/a.jpg",
                },
                {"collectionName": "No feed"},
              ],
            }),
          )
          ..close();
      } else if (path.startsWith("/api/") && !authorized) {
        response
          ..statusCode = HttpStatus.unauthorized
          ..close();
      } else if (path == "/api/libraries") {
        response
          ..write(
            jsonEncode({
              "libraries": [
                {"id": "b", "mediaType": "book"},
                {"id": "p", "mediaType": "podcast"},
              ],
            }),
          )
          ..close();
      } else if (path == "/api/libraries/p/items") {
        response
          ..write(
            jsonEncode({
              "results": [
                {"id": "item1"},
              ],
            }),
          )
          ..close();
      } else if (request.method == "PATCH" &&
          path == "/api/me/progress/item1/ep1") {
        utf8.decoder.bind(request).join().then((body) {
          patches.add(jsonDecode(body) as Map<String, dynamic>);
          response.close();
        });
      } else if (path == "/api/me") {
        response
          ..write(
            jsonEncode({
              "mediaProgress": [
                {
                  "libraryItemId": "item1",
                  "episodeId": "ep1",
                  "progress": 0.25,
                  "isFinished": false,
                },
              ],
            }),
          )
          ..close();
      } else if (path == "/api/me/progress/item1/ep1") {
        response
          ..write(
            jsonEncode({
              "currentTime": 754.5,
              "progress": 0.25,
              "isFinished": false,
            }),
          )
          ..close();
      } else if (path == "/api/items/item1") {
        response
          ..write(
            jsonEncode({
              "id": "item1",
              "media": {
                "metadata": {
                  "title": "ABS Show",
                  "author": "Narrator",
                  "description": "<p>The <i>show</i>.</p>",
                },
                "episodes": [
                  {
                    "id": "ep1",
                    "title": "Ep",
                    "description": "About &quot;Ep&quot;<br>Line two",
                    "episode": "4",
                    "publishedAt": 1672574400000,
                    "audioFile": {"ino": "99", "duration": 12.5},
                  },
                ],
              },
            }),
          )
          ..close();
      } else {
        response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  });

  tearDown(() => http.close(force: true));

  test("an RSS feed becomes a podcast with episodes and images", () async {
    final client = RssClient(feed: "${address()}/feed.xml");
    final podcast = await client.podcast();
    client.close();
    expect(podcast.title, "Show");
    expect(podcast.image, "http://img/show.jpg");
    expect(podcast.episodes.map((e) => e.title), ["Two", "One"]);
    expect(podcast.episodes.first.duration, const Duration(seconds: 3723));
    expect(podcast.episodes.first.published, DateTime.utc(2023, 1, 3, 10));
    final tracks = podcast.tracks((e) => e.id);
    expect(tracks.first.imageUrl, "http://img/two.jpg");
    expect(tracks.last.imageUrl, "http://img/show.jpg");
    expect(tracks.last.duration, const Duration(seconds: 90));
    expect(tracks.first.album, "Show");
    expect(tracks.first.artist, "Host");
    // What the episode and the show are about, as plain text.
    expect(tracks.first.description, "Hello & world\nSecond.");
    expect(tracks.last.description, isNull);
    expect(tracks.first.showDescription, "About the show.");
  });

  test("something that is not a feed is refused", () {
    expect(
      () => RssClient.parse("<html/>"),
      throwsA(isA<PodcastException>()),
    );
    expect(RssClient.normalizeFeed("feed://a.b/x"), "http://a.b/x");
    expect(RssClient.normalizeFeed("a.b/x"), "https://a.b/x");
  });

  test("Audiobookshelf lists the episodes of podcast libraries", () async {
    final client = AudiobookshelfClient(
      server: address(),
      token: "abs-token",
    );
    await client.ping();
    final pages = <List<TrackTags>>[];
    await client.podcasts(onPage: pages.add, pathOf: (id) => "loc:$id");
    expect(pages.single, hasLength(1));
    final track = pages.single.single;
    expect(track.path, "loc:item1|99");
    expect(track.album, "ABS Show");
    expect(track.trackNumber, 4);
    expect(track.published, DateTime.utc(2023, 1, 1, 12));
    expect(track.progress, 0.25);
    expect(track.description, 'About "Ep"\nLine two');
    expect(track.showDescription, "The show.");
    expect(
      await client.resumePosition("item1|99"),
      const Duration(seconds: 754, milliseconds: 500),
    );
    expect(await client.resumePosition("item1|unknown"), isNull);
    expect(track.duration, const Duration(milliseconds: 12500));
    expect(track.imageUrl, contains("/api/items/item1/cover"));
    expect(client.streamUrl("item1|99"), contains("/api/items/item1/file/99"));
    client.close();
    final bad = AudiobookshelfClient(server: address(), token: "no");
    await expectLater(bad.ping(), throwsA(isA<RemoteAuthException>()));
    bad.close();
  });

  test("iTunes search keeps results that have a feed", () async {
    final search = ItunesSearch(base: address());
    final results = await search.search("found");
    search.close();
    expect(results.single.name, "Found");
    expect(results.single.feed, "http://x/feed");
    expect(results.single.image, "http://x/a.jpg");
  });

  test("the manager subscribes, lists and plays a podcast", () async {
    final manager = LibrarySourceManager(
      local: MediaLibrary(readTags: (files) async => const []),
      credentials: _MemoryStore(),
    );
    addTearDown(manager.dispose);
    final config = await manager.addPodcast(
      name: "",
      feed: "${address()}/feed.xml",
    );
    expect(config.name, "Show");
    await manager.open(config.id);
    expect(manager.errorOf(config.id), isNull);
    final section = manager.sections(localLabel: "Local").last;
    expect(section.kind, LibrarySourceKind.podcasts);
    expect(section.sources.single.library!.tracks, hasLength(2));
    final location = SourceLocation.build(config.id, "http://audio/one.mp3");
    expect(await manager.resolve(location), "http://audio/one.mp3");

    final abs = await manager.addAudiobookshelf(
      name: "Books",
      server: address(),
      token: "abs-token",
    );
    expect(abs.type, RemoteSourceType.audiobookshelf);
    await expectLater(
      manager.addAudiobookshelf(name: "x", server: address(), token: "no"),
      throwsA(isA<RemoteAuthException>()),
    );
    expect(manager.remotes, hasLength(2));
  });

  test("the client tells Audiobookshelf how far the user got", () async {
    final client = AudiobookshelfClient(
      server: address(),
      token: "abs-token",
    );
    await client.reportProgress(
      "item1|99",
      const Duration(seconds: 30),
      const Duration(seconds: 120),
      finished: false,
    );
    await client.reportProgress(
      "item1|99",
      const Duration(seconds: 120),
      const Duration(seconds: 120),
      finished: true,
    );
    client.close();
    expect(patches, hasLength(2));
    expect(patches.first["currentTime"], 30);
    expect(patches.first["duration"], 120);
    expect(patches.first["progress"], 0.25);
    expect(patches.first["isFinished"], isFalse);
    expect(patches.last["isFinished"], isTrue);
    expect(patches.last["progress"], 1);
  });

  group("playback progress", () {
    late MemoryTagCache store;
    late LibrarySourceManager manager;

    setUp(() {
      store = MemoryTagCache();
      manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: _MemoryStore(),
        progressStore: () => store,
      );
      addTearDown(manager.dispose);
    });

    test("is kept here for a feed, shown, and offered for resuming", () async {
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
      );
      await manager.open(config.id);
      final location = SourceLocation.build(config.id, "http://audio/two.mp3");
      expect(await manager.resumePosition(location), isNull);

      await manager.saveProgress(
        location,
        const Duration(minutes: 31),
        const Duration(seconds: 3723),
      );
      final library = manager
          .sections(localLabel: "L")
          .last
          .sources
          .single
          .library!;
      expect(library.tagsOf(location)!.progress, closeTo(0.5, 0.01));
      expect(
        await manager.resumePosition(location),
        const Duration(minutes: 31),
      );

      // The last seconds count as heard.
      await manager.saveProgress(
        location,
        const Duration(seconds: 3720),
        const Duration(seconds: 3723),
      );
      expect(library.tagsOf(location)!.progress, 1);
      expect(await manager.resumePosition(location), isNull);

      // Loaded again, the saved progress is on the tracks.
      await manager.reload(config.id);
      expect(
        manager
            .sections(localLabel: "L")
            .last
            .sources
            .single
            .library!
            .tagsOf(location)!
            .progress,
        1,
      );
    });

    test("episodes are marked played and unplayed", () async {
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
      );
      await manager.open(config.id);
      final one = SourceLocation.build(config.id, "http://audio/one.mp3");
      final two = SourceLocation.build(config.id, "http://audio/two.mp3");
      expect(manager.isPodcast(one), isTrue);
      expect(manager.isPodcast("/music/a.mp3"), isFalse);
      expect(LibrarySourceManager.sourcesOf([one, two, "x"]), {config.id});
      final library = manager
          .sections(localLabel: "L")
          .last
          .sources
          .single
          .library!;
      await manager.markPlayed([one, two], played: true);
      expect(library.tagsOf(one)!.progress, 1);
      expect(library.tagsOf(two)!.progress, 1);
      expect(await manager.resumePosition(one), isNull);
      await manager.markPlayed([two], played: false);
      expect(library.tagsOf(two)!.progress, 0);
      expect(library.tagsOf(one)!.progress, 1);
      expect(store.progress[two]!.finished, isFalse);
    });

    test("is sent to Audiobookshelf as well", () async {
      final abs = await manager.addAudiobookshelf(
        name: "Books",
        server: address(),
        token: "abs-token",
      );
      final location = SourceLocation.build(abs.id, "item1|99");
      await manager.saveProgress(
        location,
        const Duration(seconds: 5),
        const Duration(seconds: 100),
      );
      expect(patches.single["currentTime"], 5);
      expect(store.progress[location]!.position, const Duration(seconds: 5));
    });
  });

  test("the SQLite store keeps progress by location", () async {
    final dir = Directory.systemTemp.createTempSync("progress_db");
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = "${dir.path}/tags.sqlite";
    final first = await SqliteTagCache.open(path);
    await first.saveProgress(
      "amped-source://a/one",
      const PlaybackProgress(Duration(seconds: 5), Duration(seconds: 50)),
    );
    await first.saveProgress(
      "amped-source://a/one",
      const PlaybackProgress(
        Duration(seconds: 50),
        Duration(seconds: 50),
        finished: true,
      ),
    );
    await first.saveProgress(
      "amped-source://b/two",
      const PlaybackProgress(Duration(seconds: 1), Duration(seconds: 2)),
    );
    await first.close();
    final second = await SqliteTagCache.open(path);
    addTearDown(second.close);
    final rows = await second.progressWithPrefix("amped-source://a/");
    expect(rows.keys, ["amped-source://a/one"]);
    expect(rows.values.single.finished, isTrue);
    expect(rows.values.single.fraction, 1);
  });

  group("background refresh", () {
    late LibrarySourceManager manager;
    late List<String> announced;

    setUp(() {
      announced = [];
      manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: _MemoryStore(),
        onNewEpisodes: (source, episodes) => announced.add(
          "$source: ${episodes.map((e) => e.title).join(", ")}",
        ),
      );
      addTearDown(manager.dispose);
    });

    MediaLibrary shown() =>
        manager.sections(localLabel: "L").last.sources.single.library!;

    test("adds new episodes quietly and says so", () async {
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
      );
      await manager.open(config.id);
      var changes = 0;
      manager.addListener(() => changes++);
      // Nothing new: nothing said, nothing redrawn.
      await manager.refreshPodcasts();
      expect(announced, isEmpty);
      expect(changes, 0);
      expect(shown().tracks, hasLength(2));

      feedBody = _feed.replaceFirst(
        "<item>\n    <title>Two</title>",
        "<item><title>Three</title> "
            '<enclosure url="http://audio/three.mp3" type="audio/mpeg"/> '
            "</item>\n  <item>\n    <title>Two</title>",
      );
      await manager.refreshPodcasts();
      expect(shown().tracks, hasLength(3));
      expect(announced, ["Show: Three"]);
      expect(changes, 1);
      // The same feed again says nothing more.
      await manager.refreshPodcasts();
      expect(announced, hasLength(1));
    });

    test("loads a source nobody opened without calling it all new", () async {
      await manager.addPodcast(name: "", feed: "${address()}/feed.xml");
      expect(shown().tracks, isEmpty);
      await manager.refreshPodcasts();
      expect(shown().tracks, hasLength(2));
      expect(announced, isEmpty);
    });

    test("a feed that fails leaves the list as it was", () async {
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
      );
      await manager.open(config.id);
      feedBody = "not a feed";
      await manager.refreshPodcasts();
      expect(shown().tracks, hasLength(2));
      expect(announced, isEmpty);
    });

    test("keeps going on a timer until disposed", () async {
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
      );
      await manager.open(config.id);
      manager.startRefreshing(
        firstAfter: const Duration(milliseconds: 20),
        every: const Duration(milliseconds: 50),
      );
      feedBody = _feed.replaceFirst(
        "<item>\n    <title>Two</title>",
        "<item><title>Four</title> "
            '<enclosure url="http://audio/four.mp3" type="audio/mpeg"/> '
            "</item>\n  <item>\n    <title>Two</title>",
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(announced, ["Show: Four"]);
    });
  });

  test("plainText takes the markup out", () {
    expect(plainText(null), isNull);
    expect(plainText("  <p> </p> "), isNull);
    expect(plainText("a<br/>b&nbsp;c &lt;d&gt;"), "a\nb c <d>");
    expect(plainText("<p>one</p>\n\n\n<p>two   words</p>"), "one\n\ntwo words");
  });

  group("source settings", () {
    test("podcasts refresh by default and music sources do not", () {
      expect(SourceSettings.usualFor(podcast: true).refresh, isTrue);
      expect(SourceSettings.usualFor(podcast: false).refresh, isFalse);
      expect(const SourceSettings().completion.percent, 90);
      expect(
        RemoteSourceConfig(
          id: "a",
          type: RemoteSourceType.audiobookshelf,
          name: "n",
          server: "s",
          user: "u",
        ).settings.refresh,
        isTrue,
      );
      expect(
        RemoteSourceConfig(
          id: "a",
          type: RemoteSourceType.navidrome,
          name: "n",
          server: "s",
          user: "u",
        ).settings.refresh,
        isFalse,
      );
    });

    test("survive being saved, and bad ones are brought into range", () {
      const changed = SourceSettings(
        refresh: false,
        refreshEvery: Duration(hours: 2),
        refreshFirst: Duration(minutes: 5),
        completion: PodcastCompletion(
          mode: CompletionMode.remaining,
          percent: 95,
          remaining: Duration(minutes: 2),
        ),
      );
      final config = RemoteSourceConfig(
        id: "a",
        type: RemoteSourceType.podcast,
        name: "n",
        server: "s",
        user: "u",
        settings: changed,
      );
      expect(RemoteSourceConfig.fromJson(config.toJson()).settings, changed);
      // A source saved before there were settings has the usual ones.
      final old = config.toJson()..remove("settings");
      expect(
        RemoteSourceConfig.fromJson(old).settings,
        SourceSettings.usualFor(podcast: true),
      );
      // Less than the least share, or a zero interval, by hand.
      final bad = config.toJson();
      (bad["settings"] as Map<String, dynamic>)["refreshMinutes"] = 0;
      ((bad["settings"] as Map<String, dynamic>)["completion"]
              as Map<String, dynamic>)["percent"] =
          10;
      final loaded = RemoteSourceConfig.fromJson(bad).settings;
      expect(loaded.refreshEvery, const Duration(minutes: 15));
      expect(loaded.completion.percent, PodcastCompletion.minPercent);
      expect(PodcastCompletion.minPercent, 75);
    });

    test("an episode counts as played by percentage or by time left", () {
      const percent = PodcastCompletion();
      expect(percent.isCompletedAt(0.89, null), isFalse);
      expect(percent.isCompletedAt(0.9, null), isTrue);
      expect(
        percent.isCompleted(
          position: const Duration(minutes: 54),
          duration: const Duration(minutes: 60),
        ),
        isTrue,
      );
      expect(
        percent.isCompleted(
          position: const Duration(minutes: 53),
          duration: const Duration(minutes: 60),
        ),
        isFalse,
      );
      // Never under the least share, whatever was saved.
      expect(
        const PodcastCompletion(percent: 10).isCompletedAt(0.5, null),
        isFalse,
      );
      const left = PodcastCompletion(
        mode: CompletionMode.remaining,
        remaining: Duration(minutes: 2),
      );
      expect(
        left.isCompleted(
          position: const Duration(minutes: 58),
          duration: const Duration(minutes: 60),
        ),
        isTrue,
      );
      expect(
        left.isCompleted(
          position: const Duration(minutes: 57),
          duration: const Duration(minutes: 60),
        ),
        isFalse,
      );
      // 95% of an hour leaves three minutes; of 20 minutes, one.
      expect(left.isCompletedAt(0.95, const Duration(minutes: 60)), isFalse);
      expect(left.isCompletedAt(0.95, const Duration(minutes: 20)), isTrue);
      // Without a length, only the very end counts.
      expect(left.isCompletedAt(0.99, null), isFalse);
      expect(left.isCompletedAt(1, null), isTrue);
    });

    test("each source refreshes as its own settings say", () async {
      final announced = <String>[];
      final manager = LibrarySourceManager(
        local: MediaLibrary(readTags: (files) async => const []),
        credentials: _MemoryStore(),
        onNewEpisodes: (source, episodes) =>
            announced.add("$source: ${episodes.map((e) => e.title).join()}"),
      );
      addTearDown(manager.dispose);
      final config = await manager.addPodcast(
        name: "",
        feed: "${address()}/feed.xml",
        settings: const SourceSettings(refresh: false),
      );
      await manager.open(config.id);
      feedBody = _feed.replaceFirst(
        "<item>\n    <title>Two</title>",
        "<item><title>Five</title> "
            '<enclosure url="http://audio/five.mp3" type="audio/mpeg"/> '
            "</item>\n  <item>\n    <title>Two</title>",
      );
      manager.startRefreshing(firstAfter: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(announced, isEmpty);
      // Turned on in the source's settings: the next start looks at it.
      await manager.edit(config.id, settings: const SourceSettings());
      expect(manager.remotes.single.settings.refresh, isTrue);
      manager.startRefreshing(firstAfter: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(announced, ["Show: Five"]);
    });

    test(
      "an episode played as far as counts is not offered for resuming",
      () async {
        final store = MemoryTagCache();
        final manager = LibrarySourceManager(
          local: MediaLibrary(readTags: (files) async => const []),
          credentials: _MemoryStore(),
          progressStore: () => store,
        );
        addTearDown(manager.dispose);
        final config = await manager.addPodcast(
          name: "",
          feed: "${address()}/feed.xml",
        );
        await manager.open(config.id);
        final location = SourceLocation.build(
          config.id,
          "http://audio/two.mp3",
        );
        const length = Duration(seconds: 3723);
        Future<Duration?> resume(double fraction) async {
          await manager.saveProgress(
            location,
            length * fraction,
            length,
          );
          return manager.resumePosition(location);
        }

        // 90% is the usual: 80% is resumed, 95% is played.
        expect(await resume(0.8), isNotNull);
        expect(await resume(0.95), isNull);
        // Stricter, in the source's settings.
        await manager.edit(
          config.id,
          settings: const SourceSettings(
            completion: PodcastCompletion(percent: 100),
          ),
        );
        expect(await resume(0.95), isNotNull);
        // By time left instead: ten minutes of a 62-minute episode.
        await manager.edit(
          config.id,
          settings: const SourceSettings(
            completion: PodcastCompletion(
              mode: CompletionMode.remaining,
              remaining: Duration(minutes: 10),
            ),
          ),
        );
        expect(await resume(0.8), isNotNull);
        expect(await resume(0.9), isNull);
      },
    );
  });
}
