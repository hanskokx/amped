/// The kinds of network share amped can browse and play from.
enum RemoteScheme {
  /// Samba / Windows file sharing: `smb://host/share/folder/file.mp3`.
  smb,

  /// WebDAV over HTTP or HTTPS: `webdav://host/folder/file.mp3`.
  webdav;

  /// The scheme a URL's scheme names, or null for anything else (`http`
  /// stays a plain stream).
  static RemoteScheme? of(String scheme) => switch (scheme.toLowerCase()) {
    "smb" => smb,
    "webdav" || "webdavs" || "dav" || "davs" => webdav,
    _ => null,
  };
}

/// A location on a network share, taken apart from its URL:
/// `smb://user:password@host/share/folder/file.mp3`.
///
/// A name and password in the URL are used to sign in; without them the
/// share is entered as a guest.
class RemoteLocation {
  const RemoteLocation._(this.uri, this.scheme);

  /// Parses [location]; null when it isn't a URL of a supported share type.
  static RemoteLocation? tryParse(String location) {
    final Uri uri;
    try {
      uri = Uri.parse(location.trim());
    } on FormatException {
      return null;
    }
    final scheme = RemoteScheme.of(uri.scheme);
    if (scheme == null || uri.host.isEmpty) return null;
    return RemoteLocation._(uri, scheme);
  }

  /// Whether [location] is a URL of a supported share type.
  static bool isRemote(String location) => tryParse(location) != null;

  final Uri uri;
  final RemoteScheme scheme;

  String get host => uri.host;

  /// The port in the URL, or null for the protocol's own.
  int? get port => uri.hasPort ? uri.port : null;

  /// Whether the connection is encrypted (`webdavs`, `davs`).
  bool get secure {
    final name = uri.scheme.toLowerCase();
    return name == "webdavs" || name == "davs";
  }

  /// The name to sign in with, or null for a guest. A Windows domain can
  /// be put in front: `DOMAIN;name`.
  String? get user => _credentials.$1;

  String? get password => _credentials.$2;

  /// The domain of a `DOMAIN;name` user, or an empty string.
  String get domain {
    final name = user ?? "";
    final semicolon = name.indexOf(";");
    return semicolon < 0 ? "" : name.substring(0, semicolon);
  }

  /// [user] without its domain.
  String? get userName {
    final name = user;
    if (name == null) return null;
    final semicolon = name.indexOf(";");
    return semicolon < 0 ? name : name.substring(semicolon + 1);
  }

  (String?, String?) get _credentials {
    final info = uri.userInfo;
    if (info.isEmpty) return (null, null);
    final colon = info.indexOf(":");
    final name = colon < 0 ? info : info.substring(0, colon);
    final password = colon < 0 ? null : info.substring(colon + 1);
    return (
      name.isEmpty ? null : Uri.decodeComponent(name),
      password == null ? null : Uri.decodeComponent(password),
    );
  }

  /// The decoded names between the slashes of the path.
  List<String> get segments => [
    for (final segment in uri.pathSegments)
      if (segment.isNotEmpty) segment,
  ];

  /// The path from the root, decoded: `/share/folder/file.mp3`. The root
  /// is `/`.
  String get path => "/${segments.join("/")}";

  /// The last name of the path, or an empty string for the root.
  String get name => segments.isEmpty ? "" : segments.last;

  /// Whether the URL ends in a slash or has no path: a folder, by the way
  /// it's written.
  bool get looksLikeFolder => uri.path.isEmpty || uri.path.endsWith("/");

  /// The URL of [name] inside this folder.
  String child(String name) {
    return uri.replace(pathSegments: [...segments, name]).toString();
  }

  /// The URL [relative] names from the folder this location is in: how a
  /// playlist file on a share refers to its neighbours. A path with a
  /// leading slash starts at the server's root.
  String sibling(String relative) {
    final reference = Uri(
      pathSegments: relative.replaceAll(r"\", "/").split("/"),
    );
    return uri
        .replace(query: "", fragment: "")
        .resolveUri(reference)
        .toString();
  }

  /// The server this is on, as credentials are saved by it: `smb://nas`.
  String get server =>
      "${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}"
      "${uri.hasPort ? ":${uri.port}" : ""}";

  /// This location, signed in as [user] with [password].
  RemoteLocation withLogin(String user, String password) => RemoteLocation._(
    uri.replace(
      userInfo: "${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}",
    ),
    scheme,
  );

  /// This URL with credentials taken out, for showing.
  String get display => uri.replace(userInfo: "").toString();

  @override
  String toString() => uri.toString();
}
