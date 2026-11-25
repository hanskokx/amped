import "dart:async";

import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/vis/vis_host.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisHost host;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    host = VisHost(PlayerState(engine: AudioEngine()));
  });

  test("Random is off by default and toggles with notification", () {
    var notified = 0;
    host.addListener(() => notified++);
    expect(host.random, isFalse);
    host.setRandom(true);
    expect(host.random, isTrue);
    expect(notified, 1);
    host.setRandom(true);
    expect(notified, 1);
  });

  test("every module keeps drawing through a one-pixel view", () async {
    // The size a skin's placeholder window would report must not reach it.
    for (var m = 0; m < host.plugin.modules.length; m++) {
      host.select(host.plugin, m);
      host.start();
      host.resize(320, 200, fullscreen: false);
      host.resize(1, 1, fullscreen: false);
      final drawn = Completer<void>();
      void listen() {
        if (host.picture.value != null && !drawn.isCompleted) drawn.complete();
      }

      host.picture.addListener(listen);
      await drawn.future.timeout(const Duration(seconds: 10));
      host.picture.removeListener(listen);
      expect(host.picture.value!.width, 320);
      expect(host.picture.value!.height, 200);
      host.stop();
    }
  });

  test("with Random on, next and previous always change the module", () {
    host.setRandom(true);
    for (var i = 0; i < 50; i++) {
      final before = (host.plugin, host.moduleIndex);
      i.isEven ? host.next() : host.previous();
      expect((host.plugin, host.moduleIndex), isNot(before));
    }
  });
}
