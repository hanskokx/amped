import "package:amped_logging/amped_logging.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late MemoryInterface memory;

  setUp(() async {
    memory = MemoryInterface(maxCharacters: 400);
    Arcane.logger.reset();
    Arcane.logger.interceptors.add(redactingInterceptor);
    await Arcane.logger.registerInterface(memory);
  });

  tearDown(Arcane.logger.reset);

  test("keeps events with their level, module and metadata", () {
    Arcane.log(
      "Could not open the stream",
      level: Level.warning,
      module: "AudioEngine",
      metadata: {"path": "/music/a.mp3"},
    );
    expect(memory.text, contains("WARNING"));
    expect(memory.text, contains("[AudioEngine]"));
    expect(memory.text, contains("Could not open the stream"));
    expect(memory.text, contains("/music/a.mp3"));
  });

  test("keeps events masked", () {
    Arcane.log("Opening http://nas:32400/p/1?X-Plex-Token=abc123");
    expect(memory.text, contains("X-Plex-Token=***"));
    expect(memory.text, isNot(contains("abc123")));
  });

  test("drops the oldest events past its size", () {
    for (var i = 0; i < 50; i++) {
      Arcane.log("event number $i", skipAutodetection: true);
    }
    expect(memory.text, contains("event number 49"));
    expect(memory.text, isNot(contains("event number 0\n")));
    expect(memory.text.length, lessThan(800));
  });
}
