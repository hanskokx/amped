import "dart:io";

import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";

/// A bug report for the issue tracker: a new issue with the environment and
/// the tail of the log filled in. The page is only opened; the report is
/// posted when the user submits it there.
abstract final class BugReport {
  static const String website = "https://www.amped-player.com/";
  static const String issues = "https://github.com/hanskokx/amped/issues";

  /// The longest address the issue form takes (GitHub refuses about 8,000
  /// characters).
  static const int maxUrlLength = 7000;

  /// What the report says about the machine and the build.
  static String environment({
    required String version,
    required String buildNumber,
    String commit = "",
    String? operatingSystem,
    String? locale,
  }) {
    final os =
        operatingSystem ??
        "${Platform.operatingSystem} ${Platform.operatingSystemVersion}";
    return [
      "- Amped: $version ($buildNumber)${commit.isEmpty ? "" : " $commit"}",
      "- System: $os",
      if (locale != null) "- Language: $locale",
    ].join("\n");
  }

  /// The address of a new issue for [environment] and [logs]. [logs] is cut
  /// from the start to fit the address, keeping the latest lines.
  static Uri newIssue({required String environment, required String logs}) {
    const cut = "[earlier lines cut; the full log is on the clipboard]\n";
    Uri build(String log) => Uri.parse(issues).replace(
      path: "/hanskokx/amped/issues/new",
      queryParameters: {
        "labels": "bug",
        "title": "Bug: ",
        "body":
            "**What happened?**\n\n"
            "<!-- Describe the problem and how to reproduce it. -->\n\n"
            "**Environment**\n$environment\n\n"
            "<details>\n<summary>Log</summary>\n\n"
            "```\n$log```\n\n</details>\n",
      },
    );

    var log = logs.isEmpty
        ? "(empty)\n"
        : (logs.endsWith("\n") ? logs : "$logs\n");
    var uri = build(log);
    var trimmed = false;
    while (uri.toString().length > maxUrlLength && log.length > 1) {
      // Drop the oldest lines, a fifth at a time.
      final from = (log.length * 0.2).ceil();
      final next = log.indexOf("\n", from);
      log = next < 0 || next + 1 >= log.length
          ? log.substring(from)
          : log.substring(next + 1);
      trimmed = true;
      uri = build("$cut$log");
    }
    return trimmed ? uri : build(log);
  }

  /// Puts the environment and the whole log on the clipboard and opens the issue page.
  /// Returns whether the page opened.
  static Future<bool> open({
    required String environment,
    required String logs,
  }) async {
    await Clipboard.setData(
      ClipboardData(text: "Environment\n$environment\n\nLog\n$logs"),
    );
    return launchUrl(
      newIssue(environment: environment, logs: logs),
      mode: LaunchMode.externalApplication,
    );
  }
}
