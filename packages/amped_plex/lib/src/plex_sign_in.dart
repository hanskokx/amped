import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:amped_media_source/amped_media_source.dart";

import "plex_client.dart";

/// Signs in at plex.tv with the PIN flow (the polling is [pollSignIn]): the user approves Amped on the Plex
/// website, and the token comes back here.
/// https://forums.plex.tv/t/authenticating-with-plex/609370
class PlexSignIn {
  PlexSignIn({
    this.api = "https://plex.tv",
    this.web = "https://app.plex.tv",
    String? clientId,
    HttpClient? client,
  }) : clientId = clientId ?? _newClientId(),
       _client = client ?? HttpClient();

  static String _newClientId() {
    final random = Random.secure();
    return "amped-${[for (var i = 0; i < 16; i++) random.nextInt(16).toRadixString(16)].join()}";
  }

  /// Where the PIN API is.
  final String api;

  /// Where the user approves the sign-in.
  final String web;

  /// Names this install to Plex.
  final String clientId;
  final HttpClient _client;

  Future<Map<String, dynamic>> _json(
    String method,
    String url, {
    String? token,
    bool wrap = false,
  }) async {
    try {
      final request = await _client
          .openUrl(method, Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set("Accept", "application/json")
        ..set("X-Plex-Client-Identifier", clientId)
        ..set("X-Plex-Product", "Amped");
      if (token != null) request.headers.set("X-Plex-Token", token);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (wrap) throw const PlexException("Wrong PIN for that user.");
      }
      if (response.statusCode >= 400) {
        throw PlexException("plex.tv answered HTTP ${response.statusCode}");
      }
      final decoded = jsonDecode(text);
      if (decoded is List && wrap) return {"users": decoded};
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      throw const PlexException("Not plex.tv.");
    } on SocketException catch (error) {
      throw PlexException(error.message);
    } on TimeoutException {
      throw const PlexException("plex.tv did not answer.");
    }
  }

  /// Asks plex.tv for a PIN to approve.
  Future<PlexPin> start() async {
    final body = await _json("POST", "$api/api/v2/pins?strong=true");
    final id = body["id"];
    final code = body["code"];
    if (id is! int || code is! String) {
      throw const PlexException("plex.tv gave no sign-in code.");
    }
    final url = Uri.parse(web).replace(
      path: "/auth",
      fragment: Uri(
        path: "",
        queryParameters: {
          "clientID": clientId,
          "code": code,
          "context[device][product]": "Amped",
        },
      ).toString(),
    );
    return PlexPin(id: id, code: code, url: url.toString());
  }

  /// Opens plex.tv with [opener] and waits for the user to approve there;
  /// the token. Throws a [BrowserSignInException] when that takes longer
  /// than [timeout].
  Future<String> signIn(
    BrowserOpener opener, {
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final pin = await start();
    await opener(Uri.parse(pin.url));
    return pollSignIn<String>(
      () async {
        final body = await _json(
          "GET",
          "$api/api/v2/pins/${pin.id}?code=${pin.code}",
        );
        final token = body["authToken"];
        return token is String && token.isNotEmpty ? token : null;
      },
      interval: interval,
      timeout: timeout,
    );
  }

  /// The addresses of the Plex Media Servers [token]'s account can use, the
  /// ones it owns first.
  Future<List<String>> servers(String token) async {
    final text = await _list("$api/api/v2/resources?includeHttps=1", token);
    final owned = <String>[];
    final shared = <String>[];
    for (final device in text) {
      final provides = "${device["provides"]}".split(",");
      final connections = device["connections"];
      if (!provides.contains("server") || connections is! List) continue;
      final uris = [
        for (final connection in connections.whereType<Map<String, dynamic>>())
          if (connection["relay"] != true && connection["uri"] is String)
            connection["uri"] as String,
      ];
      (device["owned"] == true ? owned : shared).addAll(uris);
    }
    return [...owned, ...shared];
  }

  /// The users of the Plex Home [token]'s account belongs to; empty when it
  /// has no home (a lone account has nobody else to be).
  Future<List<PlexUser>> homeUsers(String token) async {
    final Map<String, dynamic> body;
    try {
      body = await _json(
        "GET",
        "$api/api/v2/home/users",
        token: token,
        wrap: true,
      );
    } on PlexException {
      return const [];
    }
    final users = body["users"];
    if (users is! List) return const [];
    return [
      for (final user in users.whereType<Map<String, dynamic>>())
        if (user["uuid"] is String)
          PlexUser(
            uuid: user["uuid"] as String,
            name: "${user["title"] ?? user["username"] ?? user["uuid"]}",
            protected: user["protected"] == true,
          ),
    ];
  }

  /// The token to present as [user], which [token]'s account switches to
  /// with the user's [pin] when they have one. Throws when plex.tv refuses.
  Future<String> switchUser(String token, PlexUser user, {String? pin}) async {
    final query = pin == null || pin.isEmpty
        ? ""
        : "?pin=${Uri.encodeQueryComponent(pin)}";
    final body = await _json(
      "POST",
      "$api/api/v2/home/users/${Uri.encodeComponent(user.uuid)}/switch$query",
      token: token,
      wrap: true,
    );
    final switched = body["authToken"];
    if (switched is! String || switched.isEmpty) {
      throw const PlexException("plex.tv gave no token for that user.");
    }
    return switched;
  }

  Future<List<Map<String, dynamic>>> _list(String url, String token) async {
    try {
      final request = await _client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      request.headers
        ..set("Accept", "application/json")
        ..set("X-Plex-Client-Identifier", clientId)
        ..set("X-Plex-Token", token);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(text);
      return decoded is List
          ? decoded.whereType<Map<String, dynamic>>().toList()
          : const [];
    } on Object {
      return const [];
    }
  }

  void close() => _client.close(force: true);
}

/// A sign-in the user has to approve at [url].
class PlexPin {
  const PlexPin({required this.id, required this.code, required this.url});

  final int id;
  final String code;

  /// The page on plex.tv to open in the browser.
  final String url;
}

/// A user of a Plex Home, who the library can be presented as.
class PlexUser {
  const PlexUser({
    required this.uuid,
    required this.name,
    this.protected = false,
  });

  final String uuid;
  final String name;

  /// Whether switching to this user asks for their PIN.
  final bool protected;
}
