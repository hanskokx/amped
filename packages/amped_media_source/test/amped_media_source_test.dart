import "package:amped_media_source/amped_media_source.dart";
import "package:test/test.dart";

class _FakeRemote extends RemoteLibrarySource {
  _FakeRemote(this.connection);

  final SourceConnection connection;

  @override
  Future<void> check() async {}

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) async => add([
    TrackTags(SourceLocation.build(connection.id, "item-1"), title: "One"),
  ]);

  @override
  String streamUrl(String id) => "${connection.server}/stream/$id";

  @override
  void close() {}
}

void main() {
  group("RemoteLibrarySource", () {
    test(
      "a source implements the contract with only the required members",
      () async {
        final remote = _FakeRemote(
          const SourceConnection(id: "s1", server: "http://x", user: "me"),
        );
        final pages = <List<TrackTags>>[];

        await remote.load(pages.add, () => false);
        await remote.loadVideos((_) => fail("no videos"), () => false);

        expect(pages.single.single.path, "amped-source://s1/item-1");
        expect(await remote.coverUrl("item-1"), isNull);
        expect(remote.streamUrl("item-1"), "http://x/stream/item-1");
      },
    );
  });

  group("SourceLocation", () {
    test("builds and parses a location", () {
      final location = SourceLocation.build("s1", "a b");

      expect(SourceLocation.isSource(location), isTrue);
      expect(SourceLocation.parse(location), (sourceId: "s1", itemId: "a b"));
      expect(SourceLocation.parse("/music/a.mp3"), isNull);
    });
  });

  group("TrackTags", () {
    test("equal tags compare equal, including genres", () {
      const a = TrackTags("p", title: "t", genres: ["x"]);
      const b = TrackTags("p", title: "t", genres: ["x"]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const TrackTags("p", title: "t", genres: ["y"])));
    });
  });
}
