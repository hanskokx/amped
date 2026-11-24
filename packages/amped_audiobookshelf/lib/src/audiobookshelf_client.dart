import "dart:async";
import "dart:io";

import "package:amped_media_source/amped_media_source.dart";
import "package:amped_podcast/amped_podcast.dart";

/// An Audiobookshelf server's podcast libraries, signed in with an API
/// token: https://api.audiobookshelf.org/
class AudiobookshelfClient {
  AudiobookshelfClient({
    required String server,
    required String token,
    HttpClient? client,
  }) : server = normalizeServer(server),
       // ignore: prefer_initializing_formals
       _token = token,
       _client = client ?? HttpClient();

  static String normalizeServer(String server) {
    var text = server.trim();
    while (text.endsWith("/")) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isNotEmpty && !text.contains("://")) text = "http://$text";
    return text;
  }

  final String server;
  final String _token;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String> parameters = const {}]) =>
      Uri.parse("$server$path").replace(queryParameters: parameters);

  Future<Object?> _get(String path) async {
    try {
      final text = await fetchText(
        _client,
        _uri(path),
        headers: {"Authorization": "Bearer $_token"},
      );
      return await decodeJson(text);
    } on FormatException {
      throw const PodcastException("Not an Audiobookshelf server.");
    }
  }

  /// Throws when the server can't be reached or the token is refused.
  Future<void> ping() => _get("/api/libraries");

  /// The signed-in user's progress records (`/api/me`), or none when the
  /// server doesn't give them.
  Future<List<Map<String, dynamic>>> _mediaProgress() async {
    try {
      final me = await _get("/api/me");
      final all = me is Map<String, dynamic> ? me["mediaProgress"] : null;
      return [
        for (final entry in (all as List<dynamic>? ?? []))
          if (entry is Map<String, dynamic> && entry["libraryItemId"] is String)
            entry,
      ];
    } on PodcastException {
      // The listing is still good without the progress.
      return const [];
    }
  }

  /// How far the user got in each episode, as 0 to 1 (1 when finished), by
  /// `<item id>/<episode id>`.
  static Map<String, double> _episodeProgress(
    List<Map<String, dynamic>> records,
  ) => {
    for (final entry in records)
      if (entry["episodeId"] is String)
        "${entry["libraryItemId"]}/${entry["episodeId"]}":
            entry["isFinished"] == true
            ? 1.0
            : ((entry["progress"] as num?)?.toDouble() ?? 0).clamp(0, 1),
  };

  /// How far the user got in each book, by item id: the time played of the
  /// whole book, in seconds, and whether it is finished.
  static Map<String, ({double current, bool finished})> _bookProgress(
    List<Map<String, dynamic>> records,
  ) => {
    for (final entry in records)
      if (entry["episodeId"] is! String)
        "${entry["libraryItemId"]}": (
          current: (entry["currentTime"] as num?)?.toDouble() ?? 0,
          finished: entry["isFinished"] == true,
        ),
  };

  /// What is known of a library item: whether it is a book, the audio files
  /// of a book with their lengths, and the episodes of a podcast by audio
  /// file. Remembered, since the item (with all its files or episodes) is
  /// large.
  Future<_ItemInfo> _info(String itemId) async {
    final key = "$server $itemId";
    final known = _infos[key];
    if (known != null) return known;
    final item = await _get("/api/items/$itemId") as Map<String, dynamic>;
    final media = item["media"] as Map<String, dynamic>? ?? const {};
    final files = _audioFiles(media);
    return _infos[key] = _ItemInfo(
      book: item["mediaType"] == "book" || media["episodes"] == null,
      files: files,
      episodes: {
        for (final episode
            in (media["episodes"] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>())
          if ((episode["audioFile"] as Map<String, dynamic>?)?["ino"]
              case final String ino)
            if (episode["id"] case final String id) ino: id,
      },
    );
  }

  static final Map<String, _ItemInfo> _infos = {};

  /// The audio files of a book's [media], in order.
  static List<({String ino, Duration duration})> _audioFiles(
    Map<String, dynamic> media,
  ) {
    final files =
        (media["audioFiles"] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => ((a["index"] as num?) ?? 0).compareTo(
              (b["index"] as num?) ?? 0,
            ),
          );
    return [
      for (final file in files)
        if (file["ino"] case final String ino)
          (
            ino: ino,
            duration: Duration(
              milliseconds: (((file["duration"] as num?) ?? 0) * 1000).round(),
            ),
          ),
    ];
  }

  /// The id of the audio file [file] of the item [itemId]: `<item>|<ino>`,
  /// with the file's extension when only the video engine plays it.
  static String fileId(String itemId, Map<String, dynamic> file) {
    final metadata = file["metadata"] as Map<String, dynamic>? ?? const {};
    final ext = ((metadata["ext"] as String?) ?? "")
        .replaceFirst(".", "")
        .toLowerCase();
    return "$itemId|${file["ino"]}"
        "${SourceLocation.videoEngineExtensions.contains(ext) ? ".$ext" : ""}";
  }

  /// The audio file's `ino` in an id made by [fileId] (without the
  /// extension it may end with).
  static String inoOf(String id) {
    final split = id.split("|");
    return split.length == 2 ? split[1].split(".").first : "";
  }

  /// Where the user stopped the item [id] (`<item id>|<audio file ino>`),
  /// asked of the server now: in the episode, or in the audio file of a
  /// book (a book's progress is of the whole book, and the position in the
  /// file is what is left of it after the files before). Null when it was
  /// not started, is finished, or is in another file of the book.
  Future<Duration?> resumePosition(String id) async {
    final itemId = id.split("|").first;
    final ino = inoOf(id);
    try {
      final info = await _info(itemId);
      final episodeId = info.episodes[ino];
      if (!info.book && episodeId == null) return null;
      final progress = await _get(
        info.book
            ? "/api/me/progress/$itemId"
            : "/api/me/progress/$itemId/$episodeId",
      );
      if (progress is! Map<String, dynamic> || progress["isFinished"] == true) {
        return null;
      }
      final seconds = progress["currentTime"];
      if (seconds is! num || seconds <= 0) return null;
      var position = Duration(milliseconds: (seconds * 1000).round());
      if (info.book) {
        final within = info.positionIn(ino, position);
        if (within == null) return null;
        position = within;
      }
      return position;
    } on PodcastException {
      // Not started (404) or unreachable: play from the start.
      return null;
    } on RemoteAuthException {
      return null;
    }
  }

  /// Tells the server that the user got to [position] of the [duration]
  /// long item [id] (an episode, or an audio file of a book), or finished
  /// it. For a book it is told the position in the whole book; finishing
  /// one file of several is its end, and only the last finishes the book.
  /// Throws when it can't.
  Future<void> reportProgress(
    String id,
    Duration position,
    Duration duration, {
    required bool finished,
  }) async {
    final itemId = id.split("|").first;
    final ino = inoOf(id);
    final info = await _info(itemId);
    final headers = {"Authorization": "Bearer $_token"};
    if (info.book) {
      final offset = info.offsetOf(ino);
      if (offset == null) return;
      final total = info.total;
      final current = offset + (finished ? duration : position);
      final done = finished && info.isLast(ino);
      await sendJson(
        "PATCH",
        _uri("/api/me/progress/$itemId"),
        {
          "currentTime": current.inMilliseconds / 1000,
          "duration": total.inMilliseconds / 1000,
          "progress": done
              ? 1
              : total <= Duration.zero
              ? 0
              : current.inMilliseconds / total.inMilliseconds,
          "isFinished": done,
        },
        headers: headers,
      );
      return;
    }
    final episodeId = info.episodes[ino];
    if (episodeId == null) return;
    final seconds = position.inMilliseconds / 1000;
    final total = duration.inMilliseconds / 1000;
    await sendJson(
      "PATCH",
      _uri("/api/me/progress/$itemId/$episodeId"),
      {
        "currentTime": seconds,
        "duration": total,
        "progress": finished || total <= 0
            ? (finished ? 1 : 0)
            : seconds / total,
        "isFinished": finished,
      },
      headers: headers,
    );
  }

  /// Where the cover of the library item [itemId] is.
  String coverUrl(String itemId) =>
      _uri("/api/items/$itemId/cover", {"token": _token}).toString();

  /// Where the audio of an episode is streamed from; [id] is
  /// `<item id>|<audio file ino>`.
  String streamUrl(String id) {
    final split = id.split("|");
    if (split.length != 2) throw PodcastException("Unknown episode: $id");
    return _uri("/api/items/${split[0]}/file/${inoOf(id)}", {
      "token": _token,
    }).toString();
  }

  /// Every episode of every podcast library, one podcast at a time.
  Future<void> podcasts({
    required void Function(List<TrackTags> page) onPage,
    required String Function(String id) pathOf,
    bool Function()? isCancelled,
  }) async {
    final libraries = (await _get("/api/libraries")) as Map<String, dynamic>;
    final progress = _episodeProgress(await _mediaProgress());
    for (final library in (libraries["libraries"] as List<dynamic>? ?? [])) {
      if (library is! Map<String, dynamic> ||
          library["mediaType"] != "podcast") {
        continue;
      }
      final items =
          (await _get(
                "/api/libraries/${library["id"]}/items?limit=0",
              ))
              as Map<String, dynamic>;
      for (final entry in (items["results"] as List<dynamic>? ?? [])) {
        if (isCancelled?.call() ?? false) return;
        if (entry is! Map<String, dynamic>) continue;
        final item =
            (await _get("/api/items/${entry["id"]}")) as Map<String, dynamic>;
        final page = podcastTracks(item, pathOf, progress);
        if (page.isNotEmpty) onPage(page);
      }
    }
  }

  /// The episodes of the library item [item] (the `/api/items/<id>` body).
  List<TrackTags> podcastTracks(
    Map<String, dynamic> item,
    String Function(String id) pathOf, [
    Map<String, double> progress = const {},
  ]) {
    final metadata =
        (item["media"] as Map<String, dynamic>?)?["metadata"]
            as Map<String, dynamic>? ??
        const {};
    final episodes =
        (item["media"] as Map<String, dynamic>?)?["episodes"]
            as List<dynamic>? ??
        const [];
    final cover = coverUrl("${item["id"]}");
    final title = metadata["title"] as String?;
    final listed = [
      for (final episode in episodes.whereType<Map<String, dynamic>>())
        if ((episode["audioFile"] as Map<String, dynamic>?)?["ino"] is String)
          PodcastEpisode(
            id: fileId(
              "${item["id"]}",
              episode["audioFile"] as Map<String, dynamic>,
            ),
            title: (episode["title"] as String?) ?? "Episode",
            audioUrl: "",
            duration: switch (episode["duration"] ??
                (episode["audioFile"] as Map<String, dynamic>)["duration"]) {
              final num seconds => Duration(
                milliseconds: (seconds * 1000).round(),
              ),
              _ => null,
            },
            published: switch (episode["publishedAt"]) {
              final num millis when millis > 0 =>
                DateTime.fromMillisecondsSinceEpoch(
                  millis.round(),
                  isUtc: true,
                ),
              _ => null,
            },
            number: int.tryParse("${episode["episode"]}"),
            progress: progress["${item["id"]}/${episode["id"]}"],
            description: plainText(
              (episode["description"] ?? episode["subtitle"]) as String?,
            ),
          ),
    ];
    // Episodes without a number are numbered by when they came out.
    final byDate = [...listed]
      ..sort(
        (a, b) => (a.published ?? DateTime.utc(0)).compareTo(
          b.published ?? DateTime.utc(0),
        ),
      );
    final numbered = listed.any((episode) => episode.number != null);
    final podcast = Podcast(
      title: title ?? "Podcast",
      author: metadata["author"] as String?,
      image: cover,
      description: plainText(metadata["description"] as String?),
      episodes: [
        for (final episode in listed)
          numbered || episode.published == null
              ? episode
              : episode.numbered(byDate.indexOf(episode) + 1),
      ],
    );
    return podcast.tracks((episode) => pathOf(episode.id));
  }

  /// Every audiobook of every book library, one book at a time, each audio
  /// file of it a track.
  Future<void> books({
    required void Function(List<TrackTags> page) onPage,
    required String Function(String id) pathOf,
    bool Function()? isCancelled,
  }) async {
    final libraries = (await _get("/api/libraries")) as Map<String, dynamic>;
    final progress = _bookProgress(await _mediaProgress());
    for (final library in (libraries["libraries"] as List<dynamic>? ?? [])) {
      if (library is! Map<String, dynamic> || library["mediaType"] != "book") {
        continue;
      }
      final items =
          (await _get(
                "/api/libraries/${library["id"]}/items?limit=0",
              ))
              as Map<String, dynamic>;
      for (final entry in (items["results"] as List<dynamic>? ?? [])) {
        if (isCancelled?.call() ?? false) return;
        if (entry is! Map<String, dynamic>) continue;
        final item =
            (await _get("/api/items/${entry["id"]}")) as Map<String, dynamic>;
        final page = bookTracks(item, pathOf, progress);
        if (page.isNotEmpty) onPage(page);
      }
    }
  }

  /// The chapters that start between [from] and [to] seconds of the book, as
  /// lines `1:02:03  Title` with the time from the start of the part; null
  /// when there are none.
  static String? _chapterList(
    List<Map<String, dynamic>> chapters,
    double from,
    double to,
  ) {
    final lines = <String>[];
    for (final chapter in chapters) {
      final start = ((chapter["start"] as num?) ?? 0).toDouble();
      if (start < from || start >= to) continue;
      final at = Duration(milliseconds: ((start - from) * 1000).round());
      String two(int n) => n.toString().padLeft(2, "0");
      final time = at.inHours > 0
          ? "${at.inHours}:${two(at.inMinutes % 60)}:${two(at.inSeconds % 60)}"
          : "${at.inMinutes}:${two(at.inSeconds % 60)}";
      lines.add("$time  ${(chapter["title"] as String?) ?? "Chapter"}");
    }
    return lines.isEmpty ? null : "Chapters\n${lines.join("\n")}";
  }

  /// The audio files of the book [item] (the `/api/items/<id>` body) as
  /// tracks: the book is the album and its author the artist, and the
  /// files are numbered in order.
  List<TrackTags> bookTracks(
    Map<String, dynamic> item,
    String Function(String id) pathOf, [
    Map<String, ({double current, bool finished})> progress = const {},
  ]) {
    final media = item["media"] as Map<String, dynamic>? ?? const {};
    final metadata = media["metadata"] as Map<String, dynamic>? ?? const {};
    final files =
        (media["audioFiles"] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where((file) => file["ino"] is String)
            .toList()
          ..sort(
            (a, b) => ((a["index"] as num?) ?? 0).compareTo(
              (b["index"] as num?) ?? 0,
            ),
          );
    if (files.isEmpty) return const [];
    final title = (metadata["title"] as String?) ?? "Audiobook";
    final authors = [
      for (final author
          in (metadata["authors"] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        if (author["name"] case final String name) name,
    ];
    final author =
        (metadata["authorName"] as String?) ??
        (authors.isEmpty ? null : authors.join(", "));
    final narrator = metadata["narratorName"] as String?;
    final about = plainText(metadata["description"] as String?);
    final description = [
      if (narrator != null && narrator.isNotEmpty) "Narrated by $narrator",
      ?about,
    ].join("\n\n");
    final cover = coverUrl("${item["id"]}");
    final genres = [
      "Audiobook",
      for (final genre in (metadata["genres"] as List<dynamic>? ?? const []))
        if (genre is String) genre,
    ];
    // The series it is in: `seriesName` reads "Name #2" (the first of them).
    final seriesList = (metadata["series"] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((series) => series["name"])
        .whereType<String>()
        .toList();
    final seriesText = seriesList.isNotEmpty
        ? seriesList.first
        : (metadata["seriesName"] as String?)?.replaceFirst(
            RegExp(r"\s*#[\w.]+$"),
            "",
          );
    final series = seriesText?.trim();
    final chapters = (media["chapters"] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final played = progress["${item["id"]}"];
    var offset = 0.0;
    final tracks = <TrackTags>[];
    for (final (i, file) in files.indexed) {
      final length = ((file["duration"] as num?) ?? 0).toDouble();
      final tagTitle =
          (file["metaTags"] as Map<String, dynamic>?)?["tagTitle"] as String?;
      tracks.add(
        TrackTags(
          pathOf(fileId("${item["id"]}", file)),
          artist: author,
          album: title,
          title: files.length == 1
              ? title
              : (tagTitle != null && tagTitle.trim().isNotEmpty
                    ? tagTitle
                    : "Part ${i + 1}"),
          trackNumber: i + 1,
          year: int.tryParse("${metadata["publishedYear"] ?? ""}"),
          duration: Duration(milliseconds: (length * 1000).round()),
          genres: genres,
          imageUrl: cover,
          // How far the user is in this file of the book.
          progress: played == null
              ? null
              : played.finished || played.current >= offset + length
              ? 1.0
              : played.current <= offset || length <= 0
              ? 0.0
              : (played.current - offset) / length,
          description: _chapterList(chapters, offset, offset + length),
          series: series == null || series.isEmpty ? null : series,
          showDescription: description.isEmpty ? null : description,
        ),
      );
      offset += length;
    }
    return tracks;
  }

  void close() => _client.close(force: true);
}

/// What an Audiobookshelf library item is: a book (with its audio files and
/// their lengths) or a podcast (with its episodes by audio file).
class _ItemInfo {
  const _ItemInfo({
    required this.book,
    required this.files,
    required this.episodes,
  });

  final bool book;

  /// The audio files of a book, in order.
  final List<({String ino, Duration duration})> files;

  /// The id of each episode of a podcast, by its audio file's `ino`.
  final Map<String, String> episodes;

  /// How long the whole book is.
  Duration get total =>
      files.fold(Duration.zero, (sum, file) => sum + file.duration);

  /// Where the file [ino] starts in the book, or null for no such file.
  Duration? offsetOf(String ino) {
    var offset = Duration.zero;
    for (final file in files) {
      if (file.ino == ino) return offset;
      offset += file.duration;
    }
    return null;
  }

  bool isLast(String ino) => files.isNotEmpty && files.last.ino == ino;

  /// Where [bookPosition] of the whole book is in the file [ino], or null
  /// when it is in another file.
  Duration? positionIn(String ino, Duration bookPosition) {
    final offset = offsetOf(ino);
    if (offset == null) return null;
    final within = bookPosition - offset;
    final length = files.firstWhere((file) => file.ino == ino).duration;
    return within > Duration.zero && within < length ? within : null;
  }
}
