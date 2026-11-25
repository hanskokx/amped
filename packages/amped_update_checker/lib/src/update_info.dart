/// A release published in a release.json.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    this.buildNumber,
    this.notes = "",
    this.downloadUrl,
  });

  /// `1.2.3`, without any `+build` part.
  final String version;

  /// The build number (`45` of `1.2.3+45`), when the release has one.
  final int? buildNumber;

  /// The release notes as plain text; empty when the release has none.
  final String notes;

  /// Where the release can be downloaded, when the file says.
  final Uri? downloadUrl;

  /// The release in [json] for [platform] (`macos`, `windows` or `linux`).
  ///
  /// [json] is either one release (`version`, `buildNumber`, and notes as
  /// `notes`, `releaseNotes`, a `data` list of `{type, message}` or
  /// `summary` with `sections`) or desktop_updater's app-archive.json, a
  /// list of `items` of which the newest stable one for [platform] counts.
  /// Null when there is no release in it.
  static UpdateInfo? parse(Object? json, {required String platform}) {
    if (json is! Map) return null;
    final items = json["items"];
    if (items is List) {
      UpdateInfo? best;
      for (final item in items) {
        if (item is! Map) continue;
        if (item["platform"] != platform) continue;
        final channel = item["channel"];
        if (channel != null && channel != "stable") continue;
        final info = _release(item);
        if (info != null && (best == null || info.isNewerThanInfo(best))) {
          best = info;
        }
      }
      return best;
    }
    return _release(json);
  }

  static UpdateInfo? _release(Map json) {
    final raw = json["version"];
    if (raw is! String) return null;
    final plus = raw.indexOf("+");
    final version = (plus < 0 ? raw : raw.substring(0, plus)).trim();
    if (version.isEmpty) return null;
    final build =
        json["buildNumber"] ?? (plus < 0 ? null : raw.substring(plus + 1));
    final url = json["url"] ?? json["downloadUrl"];
    return UpdateInfo(
      version: version,
      buildNumber: build is int ? build : int.tryParse("${build ?? ""}"),
      notes: _notes(json),
      downloadUrl: url is String ? Uri.tryParse(url) : null,
    );
  }

  static String _notes(Map json) {
    for (final key in const ["notes", "releaseNotes", "changes"]) {
      final value = json[key];
      if (value is String) return value.trim();
      if (value is List) return _lines(value);
    }
    final data = json["data"];
    if (data is List) return _lines(data);
    final buffer = StringBuffer();
    final summary = json["summary"];
    if (summary is String) buffer.writeln(summary.trim());
    final sections = json["sections"];
    if (sections is List) {
      for (final section in sections) {
        if (section is! Map) continue;
        final title = section["title"];
        if (title is String) buffer.writeln("\n$title");
        final items = section["items"];
        if (items is List) buffer.writeln(_lines(items));
      }
    }
    return buffer.toString().trim();
  }

  /// A list of strings, `{message}` or `{body}` maps as bullet lines.
  static String _lines(List items) => [
    for (final item in items)
      if (item is String)
        "• $item"
      else if (item is Map && (item["message"] ?? item["body"]) is String)
        "• ${item["message"] ?? item["body"]}",
  ].join("\n");

  /// Whether this release is newer than the one running: by build number
  /// when both have one, else by version.
  bool isNewerThan(String version, {int? build}) {
    final mine = buildNumber;
    if (mine != null && build != null && mine != build) return mine > build;
    return compareVersions(this.version, version) > 0;
  }

  /// Whether this release is newer than [other].
  bool isNewerThanInfo(UpdateInfo other) =>
      isNewerThan(other.version, build: other.buildNumber);

  /// Orders versions by their numeric parts (`1.10.0` after `1.9.0`); a
  /// part that is not a number counts as 0, and a pre-release suffix
  /// (`1.2.0-beta`) as before its release.
  static int compareVersions(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    for (var i = 0; i < 3; i++) {
      final c = left.numbers[i].compareTo(right.numbers[i]);
      if (c != 0) return c;
    }
    if (left.pre == right.pre) return 0;
    if (left.pre) return -1;
    return 1;
  }

  static ({List<int> numbers, bool pre}) _parts(String version) {
    final core = version.split("+").first;
    final dash = core.indexOf("-");
    final numbers = (dash < 0 ? core : core.substring(0, dash))
        .split(".")
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return (numbers: numbers, pre: dash >= 0);
  }
}
