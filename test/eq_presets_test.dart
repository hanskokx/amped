import "dart:math";

import "package:amped/src/player/eq_presets.dart";
import "package:amped/src/player/eqf.dart";
import "package:amped/src/player/equalizer.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test("first load seeds the 18 classic and 6 room presets", () async {
    final presets = await EqPresets.load();
    expect(presets.length, 24);
    expect(presets["Classical"], isNotNull);
    // Anexa's Arena button: setEqBand(44) -> slider 63 - (44 + 127) / 4.
    expect(presets["Arena"]!.bands, [21, 21, 32, 32, 32, 32, 32, 32, 21, 21]);
    expect(presets["Stadium"]!.preamp, Equalizer.neutral);
    expect(presets["Flat"]!.bands, everyElement(31));
    // "Full Bass" boosts the low bands by 5.8 dB, as in the original.
    expect(presets["Full Bass"]!.bands.first, 16);
    expect(
      Equalizer.bandDb(presets["Full Bass"]!.bands.first),
      closeTo(5.8, 0.1),
    );
  });

  test("built-ins seeded by earlier versions are corrected", () async {
    SharedPreferences.setMockInitialValues({
      "amped.eq_presets":
          '{"Club":{"preamp":31,"bands":[31,31,38,50,56,63,50,44,38,31]},'
          '"Mine":{"preamp":40,"bands":[1,2,3,4,5,6,7,8,9,10]}}',
    });
    final presets = await EqPresets.load();
    expect(presets["Club"]!.bands, [31, 31, 26, 22, 22, 22, 26, 31, 31, 31]);
    expect(presets["Mine"]!.bands, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test("stores seeded before the room presets get them once", () async {
    SharedPreferences.setMockInitialValues({
      "amped.eq_presets":
          '{"Rock":{"preamp":31,"bands":[19,24,41,45,38,25,17,14,14,14]},'
          '"hall":{"preamp":40,"bands":[1,2,3,4,5,6,7,8,9,10]}}',
    });
    final presets = await EqPresets.load();
    expect(presets.keys, containsAll(["Room", "Arena", "Space"]));
    // A user's own preset of the same name is kept.
    expect(presets.containsKey("Hall"), isFalse);
    expect(presets["hall"]!.preamp, 40);
    // Deleting a room preset afterwards sticks.
    await EqPresets.remove("Room");
    expect((await EqPresets.load()).containsKey("Room"), isFalse);
  });

  test("slider values map to dB as the original's (0 = top = +12 dB)", () {
    expect(Equalizer.bandDb(0), 12);
    expect(Equalizer.bandDb(31), 0);
    expect(Equalizer.bandDb(63), -12);
    expect(Equalizer.preampGain(31), 1);
    expect(Equalizer.preampGain(0), 4);
    expect(Equalizer.preampGain(63), 0.25);
    expect(
      Equalizer.isActive(enabled: true, preamp: 31, bands: List.filled(10, 31)),
      isFalse,
    );
    expect(
      Equalizer.isActive(enabled: false, preamp: 0, bands: List.filled(10, 31)),
      isFalse,
    );
    expect(
      Equalizer.isActive(
        enabled: true,
        preamp: 31,
        bands: [30, ...List.filled(9, 31)],
      ),
      isTrue,
    );
  });

  test("save adds a new preset", () async {
    await EqPresets.save(
      const EqPreset(
        name: "My mix",
        preamp: 40,
        bands: [35, 36, 37, 38, 39, 40, 41, 42, 43, 44],
      ),
    );
    final presets = await EqPresets.load();
    expect(presets.length, 25);
    expect(presets["My mix"]!.preamp, 40);
    expect(presets["My mix"]!.bands, [35, 36, 37, 38, 39, 40, 41, 42, 43, 44]);
  });

  test("save overwrites an existing preset case-insensitively", () async {
    await EqPresets.save(
      const EqPreset(
        name: "rock",
        preamp: 50,
        bands: [50, 50, 50, 50, 50, 50, 50, 50, 50, 50],
      ),
    );
    final presets = await EqPresets.load();
    expect(presets.length, 24);
    expect(presets["Rock"]!.preamp, 50);
  });

  test("remove deletes by name case-insensitively", () async {
    await EqPresets.remove("flat");
    final presets = await EqPresets.load();
    expect(presets.containsKey("Flat"), isFalse);
    expect(presets.length, 23);
  });

  test(
    "byName matches case-insensitively and misses missing presets",
    () async {
      final found = await EqPresets.byName("POP");
      expect(found, isNotNull);
      expect(found!.name, "Pop");
      expect(await EqPresets.byName("Nope"), isNull);
    },
  );

  test("last preset round-trips", () async {
    expect(await EqPresets.lastPreset(), isNull);
    await EqPresets.setLastPreset("Classical");
    expect(await EqPresets.lastPreset(), "Classical");
  });

  test("malformed stored data falls back to the built-ins", () async {
    SharedPreferences.setMockInitialValues({"amped.eq_presets": "{oops"});
    final presets = await EqPresets.load();
    expect(presets.length, 24);
  });

  test("defaultPreset is the neutral reset", () {
    expect(EqPresets.defaultPreset.preamp, 31);
    expect(EqPresets.defaultPreset.bands, everyElement(31));
    expect(EqPresets.defaultPreset.name, "Default");
  });

  test("auto-load presets are kept apart and found by file name", () async {
    await EqPresets.save(
      const EqPreset(
        name: "song.mp3",
        preamp: 40,
        bands: [40, 40, 40, 40, 40, 40, 40, 40, 40, 40],
      ),
      autoLoad: true,
    );
    expect((await EqPresets.load()).containsKey("song.mp3"), isFalse);
    expect((await EqPresets.forFile("/music/SONG.mp3"))!.preamp, 40);
    expect(await EqPresets.forFile("/music/other.mp3"), isNull);
  });

  group("genre presets", () {
    late Map<String, EqPreset> presets;

    setUp(() async {
      presets = await EqPresets.load();
    });

    String? match(List<String> genres) =>
        EqPresets.matchGenre(genres, presets)?.name;

    test("a genre picks the preset of that name, case-insensitively", () {
      expect(match(["Rock"]), "Rock");
      expect(match(["classical"]), "Classical");
      expect(match(["SOFT ROCK"]), "Soft Rock");
    });

    test("combined genres, last words and aliases find a preset", () {
      expect(match(["Pop/Rock"]), "Pop");
      expect(match(["Jazz; Reggae"]), "Reggae");
      expect(match(["Hard Rock"]), "Rock");
      expect(match(["Synth-pop"]), "Pop");
      expect(match(["Heavy Metal"]), "Rock");
      expect(match(["Electronic"]), "Techno");
      expect(match(["Disco"]), "Dance");
    });

    test("the first genre with a preset wins", () {
      expect(match(["Jazz", "Ska", "Rock"]), "Ska");
    });

    test("unknown genres and non-genre presets give none", () {
      expect(match([]), isNull);
      expect(match(["Jazz"]), isNull);
      expect(match(["Hip-Hop"]), isNull);
      expect(match(["Live"]), isNull);
      expect(match(["Flat"]), isNull);
      expect(match(["Music Hall"]), isNull);
      expect(match(["Space"]), isNull);
    });

    test("a user's own preset matches its genre", () {
      presets["Jazz"] = const EqPreset(
        name: "Jazz",
        preamp: 31,
        bands: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      expect(match(["Smooth Jazz"]), "Jazz");
    });

    test("a deleted genre preset is not matched", () {
      presets.remove("Rock");
      expect(match(["Rock"]), isNull);
    });
  });

  group("forTrack", () {
    test("prefers the per-file preset and leaves the tags alone", () async {
      await EqPresets.save(
        const EqPreset(
          name: "song.mp3",
          preamp: 40,
          bands: [40, 40, 40, 40, 40, 40, 40, 40, 40, 40],
        ),
        autoLoad: true,
      );
      var asked = false;
      final preset = await EqPresets.forTrack(
        "/music/song.mp3",
        genres: () async {
          asked = true;
          return ["Rock"];
        },
      );
      expect(preset!.name, "song.mp3");
      expect(asked, isFalse);
    });

    test("falls back to the genre preset", () async {
      final preset = await EqPresets.forTrack(
        "/music/song.mp3",
        genres: () async => ["Classical"],
      );
      expect(preset!.name, "Classical");
    });

    test("gives none without a per-file or genre preset", () async {
      // Not even a saved "Default" preset applies.
      await EqPresets.save(
        const EqPreset(
          name: "Default",
          preamp: 20,
          bands: [32, 32, 32, 32, 32, 32, 32, 32, 32, 32],
        ),
      );
      expect(
        await EqPresets.forTrack("/music/a.mp3", genres: () async => []),
        isNull,
      );
      expect(
        await EqPresets.forTrack("/music/a.mp3", genres: () async => ["Jazz"]),
        isNull,
      );
    });
  });

  test("EQF files round-trip in the original's format", () {
    final bytes = Eqf.write(
      preamp: 0,
      bands: [31, 63, 0, 31, 31, 31, 31, 31, 31, 16],
    );
    expect(bytes.length, 31 + 268);
    expect(bytes.sublist(31, 37), "Entry1".codeUnits);
    expect(bytes.sublist(31 + 257), [31, 63, 0, 31, 31, 31, 31, 31, 31, 16, 0]);
    final preset = Eqf.read(bytes)!;
    expect(preset.preamp, 0);
    expect(preset.bands, [31, 63, 0, 31, 31, 31, 31, 31, 31, 16]);
    expect(Eqf.read(bytes, name: "Other"), isNull);
  });

  test("the fitted filter reproduces the original 4Front EQ curve", () {
    for (final bands in [
      [19, 24, 41, 45, 38, 25, 17, 14, 14, 14], // Rock
      [16, 16, 16, 22, 29, 39, 46, 49, 50, 50], // Full Bass
      [0, 0, 0, 31, 31, 31, 63, 63, 63, 63],
    ]) {
      final gains = Equalizer.fittedGains(bands);
      for (var i = 0; i <= 100; i++) {
        final f = 30 * pow(16000 / 30, i / 100);
        var actual = 1.0;
        for (final (j, c) in Equalizer.fitFrequencies.indexed) {
          final w = exp(
            -pow(log(f / c), 2) * 4.16277 * Equalizer.fitQ * Equalizer.fitQ,
          );
          actual *= 1 + (gains[j] - 1) * w;
        }
        final error =
            20 * log(actual / Equalizer.response(bands, f.toDouble())) / ln10;
        expect(error.abs(), lessThan(1.1), reason: "$bands at ${f.round()} Hz");
      }
    }
    // A +12 dB band peaks near +12 dB, as in the original.
    final boost = [0, ...List.filled(9, 31)];
    expect(20 * log(Equalizer.response(boost, 70)) / ln10, closeTo(12, 1));
  });
}
