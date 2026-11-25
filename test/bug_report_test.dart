import "package:amped/src/dialogs/bug_report.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  const environment = "- Amped: 0.1.1 (1) abc1234\n- System: Test OS";

  test("a new issue carries the environment and the log", () {
    final uri = BugReport.newIssue(
      environment: environment,
      logs: "line one\nline two\n",
    );
    expect(uri.host, "github.com");
    expect(uri.path, "/hanskokx/amped/issues/new");
    expect(uri.queryParameters["labels"], "bug");
    final body = uri.queryParameters["body"]!;
    expect(body, contains("Amped: 0.1.1 (1) abc1234"));
    expect(body, contains("line one\nline two\n"));
  });

  test("a long log is cut from the start to fit the address", () {
    final logs = [
      for (var i = 0; i < 2000; i++) "2026-11-25 line number $i of the log",
    ].join("\n");
    final uri = BugReport.newIssue(environment: environment, logs: logs);
    expect(uri.toString().length, lessThanOrEqualTo(BugReport.maxUrlLength));
    final body = uri.queryParameters["body"]!;
    expect(body, contains("line number 1999 of the log"));
    expect(body, isNot(contains("line number 0 of the log")));
    expect(body, contains("the full log is on the clipboard"));
  });

  test("an empty log is still a report", () {
    final uri = BugReport.newIssue(environment: environment, logs: "");
    expect(uri.queryParameters["body"], contains("(empty)"));
  });

  test("the environment names the version, build and commit", () {
    final text = BugReport.environment(
      version: "0.1.1",
      buildNumber: "1",
      commit: "abc1234",
      operatingSystem: "Linux 6.8",
      locale: "en-US",
    );
    expect(text, contains("0.1.1 (1) abc1234"));
    expect(text, contains("Linux 6.8"));
    expect(text, contains("en-US"));
  });
}
