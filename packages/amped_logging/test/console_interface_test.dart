import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late List<String> lines;

  setUp(() async {
    lines = [];
    Arcane.logger.reset();
    Arcane.logger.interceptors.add(redactingInterceptor);
    await Arcane.logger.registerInterface(
      ConsoleInterface(output: lines.add),
    );
  });

  tearDown(Arcane.logger.reset);

  test("masks a token in the message", () {
    Arcane.log("Opening http://nas:32400/p/1?X-Plex-Token=abc123");
    final text = lines.join("\n");
    expect(text, contains("X-Plex-Token=***"));
    expect(text, isNot(contains("abc123")));
  });

  test("masks a token in the metadata", () {
    Arcane.log(
      "Could not open the stream",
      level: Level.warning,
      module: "AudioEngine",
      metadata: {
        "location": "http://j/Audio/1/stream?api_key=xyz",
        "error": "HttpException: uri = http://h/a?token=qrs",
      },
    );
    final text = lines.join("\n");
    expect(text, contains("AudioEngine"));
    expect(text, contains("api_key=***"));
    expect(text, isNot(contains("xyz")));
    expect(text, isNot(contains("qrs")));
  });

  test("masks tokens nested in metadata", () {
    Arcane.log(
      "Nested",
      metadata: {
        "urls": ["http://h/a?api_key=deep1"],
        "inner": {"auth": "Authorization: Bearer deep2value"},
      },
    );
    final text = lines.join("\n");
    expect(text, isNot(contains("deep1")));
    expect(text, isNot(contains("deep2value")));
  });

  test("masks a token in an error", () {
    Arcane.log(
      "Failed",
      level: Level.error,
      extra: Exception("uri = http://h/a?api_key=secret"),
    );
    expect(lines.join("\n"), isNot(contains("secret")));
  });

  test("debugPrint goes through the console, masked", () async {
    await AppLogging.init();
    Arcane.logger.reset();
    Arcane.logger.interceptors.add(redactingInterceptor);
    await Arcane.logger.registerInterface(ConsoleInterface(output: lines.add));
    debugPrint("Could not open http://s/rest/stream?u=bob&t=abc&s=salt");
    final text = lines.join("\n");
    expect(text, isNot(contains("abc")));
    expect(text, isNot(contains("salt")));
  });
}
