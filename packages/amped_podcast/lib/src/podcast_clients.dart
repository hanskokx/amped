import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_media_source/amped_media_source.dart";

import "package:xml/xml.dart";

/// A podcast server or feed answered with an error, or with something that
/// isn't a podcast.
class PodcastException implements Exception {
  const PodcastException(this.message);

  final String message;

  @override
  String toString() => "PodcastException: $message";
}

/// One episode of a podcast: where its audio is and what to show of it.
class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.audioUrl,
    this.published,
    this.duration,
    this.image,
    this.number,
    this.progress,
    this.description,
  });

  /// Names the episode within its source.
  final String id;
  final String title;
  final String audioUrl;
  final DateTime? published;
  final Duration? duration;
  final String? image;
  final int? number;

  /// How much was played, 0 to 1, when the server knows.
  final double? progress;

  /// What the episode is about, as plain text.
  final String? description;

  /// A copy with a different [number].
  PodcastEpisode numbered(int number) => PodcastEpisode(
    id: id,
    title: title,
    audioUrl: audioUrl,
    published: published,
    duration: duration,
    image: image,
    number: number,
    progress: progress,
    description: description,
  );
}

/// [html] as plain text: the tags gone, the usual entities decoded, runs of
/// blanks folded, paragraph breaks kept. Null when nothing is left.
String? plainText(String? html) {
  if (html == null) return null;
  var text = html
      .replaceAll(
        RegExp(r"<\s*(br|/p|/div|/li|/h\d)\s*/?>", caseSensitive: false),
        "\n",
      )
      .replaceAll(RegExp(r"<[^>]*>"), "")
      .replaceAll("&nbsp;", " ")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", '"')
      .replaceAll("&#39;", "'")
      .replaceAll("&apos;", "'")
      .replaceAll("&amp;", "&");
  text = text
      .replaceAll(RegExp(r"[ \t]+"), " ")
      .replaceAll(RegExp(r" ?\n ?"), "\n")
      .replaceAll(RegExp(r"\n{3,}"), "\n\n")
      .trim();
  return text.isEmpty ? null : text;
}

/// A podcast and its episodes, newest first.
class Podcast {
  const Podcast({
    required this.title,
    required this.episodes,
    this.author,
    this.image,
    this.description,
  });

  final String title;
  final String? author;

  /// What the podcast is about, as plain text.
  final String? description;
  final String? image;
  final List<PodcastEpisode> episodes;

  /// The episodes as tracks: the podcast is the album, its author the
  /// artist, and the episodes are numbered oldest first.
  List<TrackTags> tracks(String Function(PodcastEpisode episode) pathOf) => [
    for (final episode in episodes)
      TrackTags(
        pathOf(episode),
        artist: author ?? title,
        album: title,
        title: episode.title,
        trackNumber: episode.number,
        duration: episode.duration,
        genres: const ["Podcast"],
        imageUrl: episode.image ?? image,
        published: episode.published,
        progress: episode.progress,
        description: episode.description,
        showDescription: description,
      ),
  ];
}

/// Fetches [uri] as text; shared by the podcast clients and the sources built
/// on them (Audiobookshelf).
Future<String> fetchText(
  HttpClient client,
  Uri uri, {
  Map<String, String> headers = const {},
}) async {
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.headers.set("User-Agent", "Amped");
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode == 401 || response.statusCode == 403) {
      await response.drain<void>();
      throw const RemoteAuthException("The server refused the sign-in.");
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw PodcastException("HTTP ${response.statusCode}");
    }
    return await response.transform(utf8.decoder).join();
  } on SocketException catch (error) {
    throw PodcastException(error.message);
  } on TimeoutException {
    throw const PodcastException("The server did not answer.");
  } on HandshakeException catch (error) {
    throw PodcastException(error.message);
  }
}

/// Sends [body] as JSON with [method] to [uri], and returns what the server
/// answers with.
Future<String> sendJson(
  String method,
  Uri uri,
  Map<String, Object?> body, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 20));
    request.headers
      ..set("User-Agent", "Amped")
      ..contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final answer = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RemoteAuthException("The server refused the sign-in.");
    }
    if (response.statusCode >= 300) {
      throw PodcastException("HTTP ${response.statusCode}");
    }
    return answer;
  } on SocketException catch (error) {
    throw PodcastException(error.message);
  } on TimeoutException {
    throw const PodcastException("The server did not answer.");
  } on HandshakeException catch (error) {
    throw PodcastException(error.message);
  } finally {
    client.close(force: true);
  }
}

/// Reads an RSS podcast feed.
class RssClient {
  RssClient({required String feed, HttpClient? client})
    : feed = normalizeFeed(feed),
      _client = client ?? HttpClient();

  /// [feed] with `https://` when it names no scheme (`feed://` is `http://`).
  static String normalizeFeed(String feed) {
    final text = feed.trim();
    if (text.startsWith("feed://")) return "http://${text.substring(7)}";
    if (text.isNotEmpty && !text.contains("://")) return "https://$text";
    return text;
  }

  final String feed;
  final HttpClient _client;

  /// Throws when the feed can't be read.
  Future<Podcast> podcast() async =>
      parse(await fetchText(_client, Uri.parse(feed)));

  /// The podcast of the feed [xml].
  static Podcast parse(String xml) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      throw const PodcastException("Not an RSS feed.");
    }
    final channel = document.findAllElements("channel").firstOrNull;
    if (channel == null) throw const PodcastException("Not an RSS feed.");
    String? text(XmlElement parent, String name) {
      final value = parent.childElements
          .where((element) => element.name.qualified == name)
          .firstOrNull
          ?.innerText
          .trim();
      return value == null || value.isEmpty ? null : value;
    }

    String? image(XmlElement parent) {
      final itunes = parent.childElements
          .where((element) => element.name.qualified == "itunes:image")
          .firstOrNull
          ?.getAttribute("href");
      if (itunes != null && itunes.isNotEmpty) return itunes;
      final plain = parent.childElements
          .where((element) => element.name.local == "image")
          .firstOrNull;
      return plain == null ? null : text(plain, "url");
    }

    final items = channel.childElements
        .where((element) => element.name.local == "item")
        .toList();
    final episodes = <PodcastEpisode>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final enclosure = item.childElements
          .where((element) => element.name.local == "enclosure")
          .firstOrNull;
      final url = enclosure?.getAttribute("url");
      if (url == null || url.isEmpty) continue;
      episodes.add(
        PodcastEpisode(
          id: url,
          title: text(item, "title") ?? url,
          audioUrl: url,
          published: _date(text(item, "pubDate")),
          duration: parseDuration(text(item, "itunes:duration")),
          image: image(item),
          number: items.length - i,
          description: plainText(
            text(item, "content:encoded") ??
                text(item, "description") ??
                text(item, "itunes:summary"),
          ),
        ),
      );
    }
    return Podcast(
      title: text(channel, "title") ?? "Podcast",
      author: text(channel, "itunes:author"),
      image: image(channel),
      description: plainText(
        text(channel, "description") ?? text(channel, "itunes:summary"),
      ),
      episodes: episodes,
    );
  }

  /// `1:02:03`, `12:30` or a number of seconds.
  static Duration? parseDuration(String? text) {
    if (text == null) return null;
    final parts = text.split(":").map(int.tryParse).toList();
    if (parts.isEmpty || parts.length > 3 || parts.contains(null)) return null;
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part!;
    }
    return Duration(seconds: seconds);
  }

  static const _months = [
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec", //
  ];

  /// An RFC 822 date: `Mon, 02 Jan 2006 15:04:05 +0000`.
  static DateTime? _date(String? text) {
    if (text == null) return null;
    final match = RegExp(
      r"(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})(?::(\d{2}))?",
    ).firstMatch(text);
    if (match == null) return null;
    final month = _months.indexOf(match.group(2)!.toLowerCase());
    if (month < 0) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month + 1,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.tryParse(match.group(6) ?? "") ?? 0,
    );
  }

  void close() => _client.close(force: true);
}

/// One result of searching the iTunes podcast directory.
class PodcastSearchResult {
  const PodcastSearchResult({
    required this.name,
    required this.feed,
    this.image,
  });

  final String name;

  /// The RSS feed to subscribe to.
  final String feed;
  final String? image;
}

/// Searches the iTunes podcast directory (the public iTunes Search API).
class ItunesSearch {
  ItunesSearch({this.base = "https://itunes.apple.com", HttpClient? client})
    : _client = client ?? HttpClient();

  final String base;
  final HttpClient _client;

  Future<List<PodcastSearchResult>> search(String term) async {
    if (term.trim().isEmpty) return const [];
    final body = await fetchText(
      _client,
      Uri.parse("$base/search").replace(
        queryParameters: {
          "term": term.trim(),
          "media": "podcast",
          "entity": "podcast",
          "limit": "25",
        },
      ),
    );
    try {
      final results = (jsonDecode(body) as Map<String, dynamic>)["results"];
      return [
        for (final result in (results as List<dynamic>? ?? []))
          if (result is Map<String, dynamic> &&
              result["feedUrl"] is String &&
              result["collectionName"] is String)
            PodcastSearchResult(
              name: result["collectionName"] as String,
              feed: result["feedUrl"] as String,
              image: result["artworkUrl600"] as String?,
            ),
      ];
    } on Object {
      throw const PodcastException("Not an iTunes answer.");
    }
  }

  void close() => _client.close(force: true);
}
