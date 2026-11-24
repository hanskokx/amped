import "package:amped/src/player/playlist.dart";
import "package:amped_youtube/amped_youtube.dart";
import "package:flutter_test/flutter_test.dart";

class _FakeYouTube implements YouTubeResolver {
  _FakeYouTube(this.videos);

  final List<YouTubeVideo> videos;
  final List<String> asked = [];

  @override
  Future<List<YouTubeVideo>> playlist(String url) async {
    asked.add(url);
    return videos;
  }

  @override
  Future<String?> streamUrl(String url) async => null;

  @override
  Future<YouTubeStreams?> streams(String url) async => null;
}

YouTubeVideo _video(String id, [String? title]) =>
    YouTubeVideo(url: "https://www.youtube.com/watch?v=$id", title: title);

void main() {
  test("a playlist link adds its videos", () async {
    final youtube = _FakeYouTube([
      _video("aaaaaaaaaaa", "One"),
      _video("bbbbbbbbbbb", "Two"),
    ]);
    final playlist = Playlist(youtube: youtube);
    await playlist.add([
      "https://youtube.com/playlist?list=RDMbeku_nj0Nk&playnext=1",
    ]);
    expect(playlist.entries.map((e) => e.location), [
      "https://www.youtube.com/watch?v=aaaaaaaaaaa",
      "https://www.youtube.com/watch?v=bbbbbbbbbbb",
    ]);
    expect(playlist.entries.map((e) => e.title), ["One", "Two"]);
    expect(youtube.asked, [
      "https://www.youtube.com/playlist?list=RDMbeku_nj0Nk",
    ]);
  });

  test("a YouTube Music link adds its one video, titled", () async {
    final youtube = _FakeYouTube([_video("g_5EogA-Rzw", "Song")]);
    final playlist = Playlist(youtube: youtube);
    await playlist.add([
      "https://music.youtube.com/watch?v=g_5EogA-Rzw&list=RDAMVMg_5EogA-Rzw",
    ]);
    expect(
      playlist.entries.single.location,
      "https://www.youtube.com/watch?v=g_5EogA-Rzw",
    );
    expect(playlist.entries.single.title, "Song");
  });

  test("a video is still added when its title can't be read", () async {
    final playlist = Playlist(youtube: _FakeYouTube([]));
    await playlist.add(["https://youtu.be/ksS4pLsru60"]);
    expect(
      playlist.entries.single.location,
      "https://www.youtube.com/watch?v=ksS4pLsru60",
    );
  });

  test("an unreadable playlist adds nothing", () async {
    final playlist = Playlist(youtube: _FakeYouTube([]));
    await playlist.add(["https://youtube.com/playlist?list=PLabcdefgh"]);
    expect(playlist.entries, isEmpty);
  });
}
