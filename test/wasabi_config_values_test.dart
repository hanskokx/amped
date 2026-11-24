import "package:amped/src/app/modern_host.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  late PlayerState player;
  late Map<String, String> stored;
  late WasabiConfigValues config;
  late int changes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    player = PlayerState(engine: AudioEngine());
    stored = {};
    changes = 0;
    config = WasabiConfigValues(
      player,
      read: (key) => stored[key],
      write: (key, value) => stored[key] = value,
    )..addListener(() => changes++);
  });

  WasabiCfgAttrib attrib(String value) => WasabiCfgAttrib.parse(value)!;

  test("Shuffle is the player's shuffle", () {
    final shuffle = attrib("{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Shuffle");
    expect(config.value(shuffle), 0);
    config.setValue(shuffle, 1);
    expect(player.shuffle, isTrue);
    expect(config.value(shuffle), 1);
    config.setValue(shuffle, 0);
    expect(player.shuffle, isFalse);
    expect(stored, isEmpty);
  });

  test("Repeat is off, the playlist or the track", () {
    final repeat = attrib("{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D};Repeat");
    // Anexa's button stores its cfgval, 2.
    config.setValue(repeat, 2);
    expect(player.repeat, isTrue);
    expect(player.manualAdvance, isFalse);
    expect(config.value(repeat), 1);
    // Amped Modern's NStatesButton stores -1 for the track.
    config.setValue(repeat, -1);
    expect(player.repeat && player.manualAdvance, isTrue);
    expect(config.value(repeat), -1);
    config.setValue(repeat, 0);
    expect(player.repeat || player.manualAdvance, isFalse);
    expect(config.value(repeat), 0);
  });

  test("Enable crossfading is the player's crossfading", () {
    final crossfade = attrib(
      "{FC3EAF78-C66E-4ED2-A0AA-1494DFCC13FF};Enable crossfading",
    );
    expect(config.value(crossfade), 0);
    config.setValue(crossfade, 1);
    expect(player.crossfade, isTrue);
    expect(config.value(crossfade), 1);
    config.setValue(crossfade, 0);
    expect(player.crossfade, isFalse);
    expect(stored, isEmpty);
  });

  test("a skin's own options are only remembered", () {
    final own = attrib("{F1036C9C-3919-47ac-8494-366778CF10F9};Show Tab");
    config.setValue(own, 3);
    expect(config.value(own), 3);
    expect(changes, 1);
    expect(player.shuffle || player.repeat || player.crossfade, isFalse);
  });
}
