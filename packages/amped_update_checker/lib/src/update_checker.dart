import "dart:async";
import "dart:convert";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart" show visibleForTesting;
import "package:package_info_plus/package_info_plus.dart";

import "update_info.dart";

/// Reads a release.json at [start] and every [interval] after, and reports
/// each release newer than the running app once, through [updates].
class UpdateChecker {
  UpdateChecker({
    required this.releaseUrl,
    required this.interval,
    @visibleForTesting this.currentVersion,
    @visibleForTesting this.currentBuild,
    @visibleForTesting this.fetch,
    @visibleForTesting this.platform,
  });

  /// Where the release.json is.
  final Uri releaseUrl;

  /// How long to wait between checks.
  final Duration interval;

  /// The running app's version; read from the app itself when null.
  final String? currentVersion;
  final int? currentBuild;

  /// Gets the text at a URL; a plain HTTP GET when null.
  final Future<String> Function(Uri url)? fetch;

  /// `macos`, `windows` or `linux`; this machine's when null.
  final String? platform;

  final StreamController<UpdateInfo> _updates = StreamController.broadcast();
  Timer? _timer;
  String? _announced;

  /// The releases newer than the running app, each once.
  Stream<UpdateInfo> get updates => _updates.stream;

  /// Checks now, and again every [interval].
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
    unawaited(check());
  }

  /// Checks once. A failure (offline, a file that isn't a release) is
  /// logged and left for the next check.
  Future<void> check() async {
    try {
      final text = await (fetch ?? _get)(releaseUrl);
      final info = UpdateInfo.parse(
        jsonDecode(text),
        platform: platform ?? _platform,
      );
      if (info == null) return;
      final version =
          currentVersion ?? (await PackageInfo.fromPlatform()).version;
      final build =
          currentBuild ??
          (currentVersion == null
              ? int.tryParse((await PackageInfo.fromPlatform()).buildNumber)
              : null);
      if (!info.isNewerThan(version, build: build)) return;
      // The same release is not announced again on the next hour's check.
      final key = "${info.version}+${info.buildNumber}";
      if (_announced == key || _updates.isClosed) return;
      _announced = key;
      _updates.add(info);
    } on Object catch (error) {
      Arcane.log(
        "Could not check for an update",
        level: Level.warning,
        module: "UpdateChecker",
        metadata: {"location": "$releaseUrl", "error": "$error"},
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_updates.close());
  }

  static String get _platform => Platform.isMacOS
      ? "macos"
      : Platform.isWindows
      ? "windows"
      : "linux";

  static Future<String> _get(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = "Amped";
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException("HTTP ${response.statusCode}", uri: url);
      }
      return await utf8.decodeStream(response);
    } finally {
      client.close(force: true);
    }
  }
}
