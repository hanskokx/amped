import "dart:convert";
import "dart:io";
import "dart:typed_data";

/// One skin in the Webamp skin library (skins.webamp.org).
class WebampSkin {
  const WebampSkin({
    required this.md5,
    required this.fileName,
    required this.downloadUrl,
    this.screenshotUrl,
    this.nsfw = false,
  });

  factory WebampSkin.fromJson(Map<String, dynamic> json) => WebampSkin(
    md5: json["md5"] as String,
    fileName: json["filename"] as String? ?? json["md5"] as String,
    screenshotUrl: json["screenshot_url"] as String?,
    downloadUrl: json["download_url"] as String,
    nsfw: json["nsfw"] as bool? ?? false,
  );

  final String md5;

  /// The name the skin was uploaded under, like `Dark4.zip`.
  final String fileName;

  /// The preview image, or null: the library has none for modern (`.wal`)
  /// skins.
  final String? screenshotUrl;
  final String downloadUrl;
  final bool nsfw;

  /// [fileName] without its extension, for display and as the installed name.
  String get title => fileName.replaceAll(
    RegExp(r"\.(wsz|zip|wal)$", caseSensitive: false),
    "",
  );

  /// Whether this is a modern (Wasabi, `.wal`) skin rather than a classic one.
  bool get modern => downloadUrl.toLowerCase().endsWith(".wal");

  /// [title] with the extension of the skin's kind, so a classic `.zip`
  /// upload installs as the `.wsz` it is.
  String get installFileName => "$title${modern ? ".wal" : ".wsz"}";
}

/// A page of skins and how many the whole listing holds.
class WebampSkinPage {
  const WebampSkinPage(this.skins, this.total);

  final List<WebampSkin> skins;
  final int total;
}

/// Thrown when the library can't be reached or answers badly.
class WebampLibraryException implements Exception {
  const WebampLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A client for the Webamp skin library's GraphQL endpoint (MIT-licensed,
/// see the `skin-database` package of captbaritone/webamp).
class WebampSkinLibrary {
  WebampSkinLibrary({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  static final Uri endpoint = Uri.parse("https://api.webamp.org/graphql");

  /// The skins shown per page.
  static const int pageSize = 24;

  final HttpClient Function() _clientFactory;

  /// Skins matching [query], or the museum's default listing when blank.
  /// [offset] is the index of the first skin wanted.
  Future<WebampSkinPage> browse({String query = "", int offset = 0}) async {
    final text = query.trim();
    const fields = "md5 filename screenshot_url download_url nsfw";
    if (text.isEmpty) {
      final data = await _post(
        "query(\$first: Int!, \$offset: Int!) { skins(first: \$first, "
        "offset: \$offset, sort: MUSEUM) { count nodes { $fields } } }",
        {"first": pageSize, "offset": offset},
      );
      final skins = data["skins"] as Map<String, dynamic>;
      return WebampSkinPage(
        _parse(skins["nodes"]),
        skins["count"] as int? ?? 0,
      );
    }
    final data = await _post(
      "query(\$q: String!, \$first: Int!, \$offset: Int!) { "
      "search_skins(query: \$q, first: \$first, offset: \$offset) "
      "{ $fields } }",
      {"q": text, "first": pageSize, "offset": offset},
    );
    final found = _parse(data["search_skins"]);
    // The search has no total; an unfilled page means it ran out.
    return WebampSkinPage(
      found,
      found.length < pageSize
          ? offset + found.length
          : offset + found.length + 1,
    );
  }

  List<WebampSkin> _parse(Object? nodes) => [
    for (final node in nodes as List<dynamic>? ?? const [])
      if (node is Map<String, dynamic> && !(node["nsfw"] as bool? ?? false))
        WebampSkin.fromJson(node),
  ];

  /// The archive bytes of [skin].
  Future<Uint8List> download(WebampSkin skin) =>
      _get(Uri.parse(skin.downloadUrl));

  /// The preview image bytes of [skin].
  Future<Uint8List> screenshot(WebampSkin skin) {
    final url = skin.screenshotUrl;
    if (url == null) throw const WebampLibraryException("No preview");
    return _get(Uri.parse(url));
  }

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, Object?> variables,
  ) async {
    final client = _clientFactory()..userAgent = "amped";
    try {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode({
            "query": query,
            "variables": variables,
          }),
        ),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw WebampLibraryException("HTTP ${response.statusCode}");
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json["data"];
      if (data is! Map<String, dynamic>) {
        final errors = json["errors"];
        throw WebampLibraryException(
          errors is List && errors.isNotEmpty
              ? "${(errors.first as Map)["message"]}"
              : "Unexpected reply",
        );
      }
      return data;
    } on WebampLibraryException {
      rethrow;
    } on Object catch (error) {
      throw WebampLibraryException("$error");
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _get(Uri url) async {
    final client = _clientFactory()..userAgent = "amped";
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw WebampLibraryException("HTTP ${response.statusCode}");
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on WebampLibraryException {
      rethrow;
    } on Object catch (error) {
      throw WebampLibraryException("$error");
    } finally {
      client.close();
    }
  }
}
