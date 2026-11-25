import "package:amped_update_checker/amped_update_checker.dart";
import "package:flutter_test/flutter_test.dart";

UpdateChecker checker(String json, {String version = "0.1.0", int? build}) =>
    UpdateChecker(
      releaseUrl: Uri.parse("https://example.test/release.json"),
      interval: const Duration(hours: 1),
      currentVersion: version,
      currentBuild: build,
      platform: "macos",
      fetch: (_) async => json,
    );

void main() {
  test("compares versions numerically", () {
    expect(UpdateInfo.compareVersions("1.10.0", "1.9.0"), greaterThan(0));
    expect(UpdateInfo.compareVersions("1.2.0-beta", "1.2.0"), lessThan(0));
    expect(UpdateInfo.compareVersions("1.2", "1.2.0"), 0);
  });

  test("announces a newer release once", () async {
    final c = checker('{"version":"0.2.0","notes":"Fixes."}');
    final seen = <UpdateInfo>[];
    c.updates.listen(seen.add);
    await c.check();
    await c.check();
    await pumpEventQueue();
    expect(seen, hasLength(1));
    expect(seen.single.version, "0.2.0");
    expect(seen.single.notes, "Fixes.");
    c.dispose();
  });

  test("ignores the placeholder and older releases", () async {
    for (final json in [
      '{"version":"0.0.0","assets":[]}',
      '{"version":"0.1.0"}',
      "not json",
      '{"items":[]}',
    ]) {
      final c = checker(json);
      final seen = <UpdateInfo>[];
      c.updates.listen(seen.add);
      await c.check();
      await pumpEventQueue();
      expect(seen, isEmpty, reason: json);
      c.dispose();
    }
  });

  test("compares build numbers first when both have one", () async {
    final c = checker('{"version":"0.1.0","buildNumber":5}', build: 1);
    final seen = <UpdateInfo>[];
    c.updates.listen(seen.add);
    await c.check();
    await pumpEventQueue();
    expect(seen, hasLength(1));
    c.dispose();
  });

  test("reads an app-archive.json for this platform", () {
    final info = UpdateInfo.parse(
      {
        "items": [
          {"version": "1.0.0", "platform": "macos", "channel": "stable"},
          {"version": "2.0.0", "platform": "windows", "channel": "stable"},
          {"version": "1.5.0", "platform": "macos", "channel": "stable"},
          {"version": "9.0.0", "platform": "macos", "channel": "beta"},
        ],
      },
      platform: "macos",
    );
    expect(info?.version, "1.5.0");
  });

  test("reads desktop_updater release notes", () {
    final info = UpdateInfo.parse({
      "version": "1.0.0+7",
      "data": [
        {"type": "feat", "message": "A"},
        {"type": "fix", "message": "B"},
      ],
    }, platform: "linux");
    expect(info?.buildNumber, 7);
    expect(info?.notes, "• A\n• B");
  });
}
