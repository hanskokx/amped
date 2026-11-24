import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "equalizer.dart";

const String _kPresetsKey = "amped.eq_presets";
const String _kAutoPresetsKey = "amped.eq_autoload_presets";
const String _kLastPresetKey = "amped.eq_last_preset";
const String _kSeedVersionKey = "amped.eq_presets_seed_version";

/// Bumped whenever presets are added to [EqPresets.builtins]; stores seeded
/// by an older version get the new ones added once (see [EqPresets.load]).
const int _kSeedVersion = 2;

/// A single saved Equalizer preset: the preamp gain plus the 10 band gains.
///
/// Values are the original's slider values (see [Equalizer]): 0..63, 0 at
/// the top (+12 dB), 31 at 0 dB.
class EqPreset {
  const EqPreset({
    required this.name,
    required this.preamp,
    required this.bands,
  });

  final String name;
  final int preamp;
  final List<int> bands;

  @override
  bool operator ==(Object other) {
    return other is EqPreset &&
        other.name == name &&
        other.preamp == preamp &&
        _sameBands(other.bands);
  }

  bool _sameBands(List<int> other) {
    if (other.length != bands.length) return false;
    for (var i = 0; i < bands.length; i++) {
      if (other[i] != bands[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, preamp, Object.hashAll(bands));

  /// Decodes a single preset map value (from the JSON store), or `null` when
  /// the payload is malformed.
  static EqPreset? fromJson(String name, Object? json) {
    final map = json is Map ? json : null;
    if (map == null) return null;
    final preamp = map["preamp"];
    final bands = map["bands"];
    if (preamp is! num || bands is! List) return null;
    return EqPreset(
      name: name,
      preamp: preamp.toInt().clamp(0, 63),
      bands: bands
          .whereType<num>()
          .take(10)
          .map((v) => v.toInt().clamp(0, 63))
          .toList(),
    );
  }
}

/// The Equalizer preset store, persisted as a JSON map in `SharedPreferences`.
///
/// Mirrors the original `Winamp EQ library file` (`eqpresets/eqm.preset`,
/// Eq.cpp): a flat set of named presets seeded with the built-in set on first
/// use (main.cpp `CreateEQPresets`). Load/Delete/Save operate case-insensitively
/// on preset names, and the last applied preset is remembered so the presets
/// window can preselect it.
class EqPresets {
  /// The built-in presets with their 10 band values, seeded on first run:
  /// the original's 18 (`CreateEQPresets` in main.cpp) followed by
  /// [roomPresets].
  static const List<(String, List<int>)> builtins = [
    ...classicPresets,
    ...roomPresets,
  ];

  /// The original's 18 built-in presets (`CreateEQPresets` in main.cpp).
  static const List<(String, List<int>)> classicPresets = [
    ("Classical", [31, 31, 31, 31, 31, 31, 44, 44, 44, 48]),
    ("Club", [31, 31, 26, 22, 22, 22, 26, 31, 31, 31]),
    ("Dance", [16, 20, 28, 32, 32, 42, 44, 44, 32, 32]),
    ("Flat", [31, 31, 31, 31, 31, 31, 31, 31, 31, 31]),
    ("Laptop speakers/headphones", [24, 14, 23, 38, 36, 29, 24, 16, 11, 8]),
    ("Large hall", [15, 15, 22, 22, 31, 40, 40, 40, 31, 31]),
    ("Party", [20, 20, 31, 31, 31, 31, 31, 31, 20, 20]),
    ("Pop", [35, 24, 20, 19, 23, 34, 36, 36, 35, 35]),
    ("Reggae", [31, 31, 33, 42, 31, 21, 21, 31, 31, 31]),
    ("Rock", [19, 24, 41, 45, 38, 25, 17, 14, 14, 14]),
    ("Soft", [24, 29, 34, 36, 34, 25, 18, 16, 14, 12]),
    ("Ska", [36, 40, 39, 33, 25, 22, 17, 16, 14, 16]),
    ("Full Bass", [16, 16, 16, 22, 29, 39, 46, 49, 50, 50]),
    ("Soft Rock", [25, 25, 28, 33, 39, 41, 38, 33, 27, 17]),
    ("Full Treble", [48, 48, 48, 39, 27, 14, 6, 6, 6, 4]),
    ("Full Bass & Treble", [20, 22, 31, 44, 40, 29, 18, 14, 12, 12]),
    ("Live", [40, 31, 25, 23, 22, 22, 25, 27, 27, 28]),
    ("Techno", [19, 22, 31, 41, 40, 31, 19, 16, 16, 17]),
  ];

  /// The room presets that skins such as Anexa have buttons for
  /// (`maki/eq.m`, which passes -127..127 values to `setEqBand`), converted
  /// to slider values the way the original does (`Core::setEqBand` in
  /// gen_ff/wa2core.cpp: `63 - (val + 127) / 4`).
  static const List<(String, List<int>)> roomPresets = [
    ("Hall", [32, 32, 27, 23, 23, 23, 27, 32, 32, 32]),
    ("Room", [41, 32, 26, 24, 23, 23, 24, 28, 28, 29]),
    ("Arena", [21, 21, 32, 32, 32, 32, 32, 32, 21, 21]),
    ("Studio", [26, 26, 29, 34, 40, 42, 39, 34, 28, 18]),
    ("Stadium", [19, 22, 32, 42, 41, 32, 19, 16, 16, 17]),
    ("Space", [21, 23, 32, 45, 41, 30, 17, 10, 15, 24]),
  ];

  /// The built-ins as earlier versions seeded them, which did not match the
  /// original; [load] replaces any still stored unchanged.
  static const List<(String, List<int>)> _legacyBuiltins = [
    ("Classical", [31, 31, 31, 31, 31, 31, 44, 44, 44, 48]),
    ("Club", [31, 31, 38, 50, 56, 63, 50, 44, 38, 31]),
    ("Dance", [44, 38, 44, 50, 38, 31, 25, 31, 31, 31]),
    ("Flat", [31, 31, 31, 31, 31, 31, 31, 31, 31, 31]),
    ("Laptop speakers/headphones", [31, 38, 44, 50, 56, 63, 56, 44, 38, 31]),
    ("Large hall", [50, 50, 38, 38, 38, 38, 38, 38, 38, 50]),
    ("Party", [38, 38, 31, 31, 31, 31, 50, 56, 50, 38]),
    ("Pop", [38, 31, 31, 31, 38, 56, 56, 44, 31, 31]),
    ("Reggae", [31, 44, 31, 38, 56, 38, 31, 31, 31, 31]),
    ("Rock", [50, 38, 31, 38, 44, 50, 56, 56, 56, 50]),
    ("Soft", [44, 38, 31, 31, 31, 31, 25, 25, 31, 44]),
    ("Ska", [31, 31, 25, 38, 56, 63, 56, 38, 31, 31]),
    ("Full Bass", [56, 56, 56, 38, 31, 31, 31, 31, 31, 31]),
    ("Soft Rock", [50, 44, 38, 31, 31, 31, 31, 31, 31, 44]),
    ("Full Treble", [31, 31, 31, 31, 31, 38, 56, 56, 56, 56]),
    ("Full Bass & Treble", [56, 56, 56, 31, 31, 31, 56, 56, 56, 56]),
    ("Live", [31, 31, 31, 38, 38, 38, 31, 31, 31, 31]),
    ("Techno", [56, 50, 38, 31, 25, 25, 31, 38, 50, 56]),
  ];

  /// The neutral reset applied by the Default action when no "Default" preset
  /// has been saved yet (the original `eq_tab` initialization: 0 dB).
  static const EqPreset defaultPreset = EqPreset(
    name: "Default",
    preamp: 31,
    bands: [31, 31, 31, 31, 31, 31, 31, 31, 31, 31],
  );

  /// Loads all presets, seeding the built-ins on first run. With
  /// [autoLoad], the auto-load library instead (`EQDIR2`: presets named
  /// after the files they load for, which starts empty).
  static Future<Map<String, EqPreset>> load({bool autoLoad = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, autoLoad: autoLoad);
  }

  /// Saves or overwrites [preset] (matched case-insensitively by name), in
  /// the auto-load library with [autoLoad].
  static Future<void> save(EqPreset preset, {bool autoLoad = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = await _read(prefs, autoLoad: autoLoad);
    final key = _findKey(presets, preset.name) ?? preset.name;
    presets[key] = preset;
    await _write(prefs, presets, autoLoad: autoLoad);
  }

  /// Deletes the preset named [name] (matched case-insensitively), if present.
  static Future<void> remove(String name, {bool autoLoad = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = await _read(prefs, autoLoad: autoLoad);
    final key = _findKey(presets, name);
    if (key == null) return;
    presets.remove(key);
    await _write(prefs, presets, autoLoad: autoLoad);
  }

  /// The preset named [name] (matched case-insensitively), or `null`.
  static Future<EqPreset?> byName(String name, {bool autoLoad = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final presets = await _read(prefs, autoLoad: autoLoad);
    final key = _findKey(presets, name);
    return key == null ? null : presets[key];
  }

  /// The auto-load preset for [path]: the one named after its file
  /// (`eq_autoload`), or `null`.
  static Future<EqPreset?> forFile(String path) =>
      byName(path.split(RegExp(r"[/\\]")).last, autoLoad: true);

  /// The preset AUTO applies when [path] becomes the current track: its
  /// auto-load preset ([forFile]), else the preset for one of its [genres]
  /// ([matchGenre]), else none. [genres] is only asked for when there is no
  /// auto-load preset, as reading the tags may take a moment.
  static Future<EqPreset?> forTrack(
    String path, {
    required Future<List<String>> Function() genres,
  }) async {
    final perFile = await forFile(path);
    if (perFile != null) return perFile;
    final trackGenres = await genres();
    if (trackGenres.isEmpty) return null;
    return matchGenre(trackGenres, await load());
  }

  /// The built-in presets that are not named after a genre, so that a track
  /// tagged "Live" or "Music Hall" doesn't pick them.
  static final Set<String> _notGenres = {
    "flat",
    "laptop speakers/headphones",
    "large hall",
    "party",
    "soft",
    "full bass",
    "full treble",
    "full bass & treble",
    "live",
    for (final (name, _) in roomPresets) name.toLowerCase(),
  };

  /// Genres that have no preset of their own, and the built-in genre preset
  /// closest to them.
  static const Map<String, String> genreAliases = {
    "disco": "Dance",
    "edm": "Dance",
    "electronic": "Techno",
    "electronica": "Techno",
    "house": "Techno",
    "trance": "Techno",
    "dub": "Reggae",
    "dancehall": "Reggae",
    "metal": "Rock",
    "punk": "Rock",
    "grunge": "Rock",
    "opera": "Classical",
    "baroque": "Classical",
    "orchestral": "Classical",
    "symphony": "Classical",
  };

  /// The preset in [presets] for the first of [genres] that has one, or
  /// `null`. Each genre is tried whole, then each part of a combined genre
  /// ("Pop/Rock", "Rock; Pop"), then its last word ("Hard Rock", "Synth-pop"),
  /// each as a preset name (case-insensitively) or through [genreAliases].
  /// Presets that are not named after a genre ("Flat", "Live", the room set)
  /// never match; a user's own presets do ("Jazz").
  static EqPreset? matchGenre(
    List<String> genres,
    Map<String, EqPreset> presets,
  ) {
    EqPreset? named(String name) {
      final lower = name.trim().toLowerCase();
      if (lower.isEmpty) return null;
      for (final candidate in [lower, genreAliases[lower]?.toLowerCase()]) {
        if (candidate == null || _notGenres.contains(candidate)) continue;
        final key = _findKey(presets, candidate);
        if (key != null) return presets[key];
      }
      return null;
    }

    for (final genre in genres) {
      final parts = [genre, ...genre.split(RegExp(r"[/;,|]"))];
      for (final part in parts) {
        final match = named(part);
        if (match != null) return match;
      }
      for (final part in parts) {
        final words = part.trim().split(RegExp(r"[\s-]+"));
        if (words.length < 2) continue;
        final match = named(words.last);
        if (match != null) return match;
      }
    }
    return null;
  }

  static Future<Map<String, EqPreset>> _read(
    SharedPreferences prefs, {
    required bool autoLoad,
  }) async => autoLoad
      ? _decode(prefs.getString(_kAutoPresetsKey) ?? "{}")
      : _readOrSeed(prefs);

  static Future<void> _write(
    SharedPreferences prefs,
    Map<String, EqPreset> presets, {
    required bool autoLoad,
  }) => prefs.setString(
    autoLoad ? _kAutoPresetsKey : _kPresetsKey,
    jsonEncode(_encode(presets)),
  );

  /// The name of the last applied preset, or `null`.
  static Future<String?> lastPreset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastPresetKey);
  }

  /// Remembers [name] as the last applied preset.
  static Future<void> setLastPreset(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastPresetKey, name);
  }

  static Map<String, EqPreset> _builtinPresets() {
    return {
      for (final (name, bands) in builtins)
        name: EqPreset(name: name, preamp: Equalizer.neutral, bands: bands),
    };
  }

  /// Replaces the stored built-ins that are still as earlier versions
  /// seeded them. Returns whether anything changed.
  static bool _migrateLegacy(Map<String, EqPreset> presets) {
    final fixed = _builtinPresets();
    var changed = false;
    for (final (name, bands) in _legacyBuiltins) {
      final legacy = EqPreset(name: name, preamp: 31, bands: bands);
      if (presets[name] == legacy) {
        presets[name] = fixed[name]!;
        changed = true;
      }
    }
    return changed;
  }

  static Future<Map<String, EqPreset>> _readOrSeed(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_kPresetsKey);
    if (raw == null) {
      final seeded = _builtinPresets();
      await prefs.setString(_kPresetsKey, jsonEncode(_encode(seeded)));
      await prefs.setInt(_kSeedVersionKey, _kSeedVersion);
      return seeded;
    }
    final decoded = _decode(raw);
    if (decoded.isEmpty) return _builtinPresets();
    final legacy = _migrateLegacy(decoded);
    final added = (prefs.getInt(_kSeedVersionKey) ?? 1) < _kSeedVersion;
    if (added) _addMissing(decoded, roomPresets);
    if (legacy || added) {
      await prefs.setString(_kPresetsKey, jsonEncode(_encode(decoded)));
    }
    if (added) await prefs.setInt(_kSeedVersionKey, _kSeedVersion);
    return decoded;
  }

  /// Adds the [presets] not already stored under the same name (matched
  /// case-insensitively), so a user's own preset of that name is kept.
  static void _addMissing(
    Map<String, EqPreset> stored,
    List<(String, List<int>)> presets,
  ) {
    for (final (name, bands) in presets) {
      if (_findKey(stored, name) != null) continue;
      stored[name] = EqPreset(
        name: name,
        preamp: Equalizer.neutral,
        bands: bands,
      );
    }
  }

  static String? _findKey(Map<String, EqPreset> presets, String name) {
    for (final key in presets.keys) {
      if (key.toLowerCase() == name.toLowerCase()) return key;
    }
    return null;
  }

  static Map<String, Object?> _encode(Map<String, EqPreset> presets) {
    return {
      for (final entry in presets.entries)
        entry.key: {
          "preamp": entry.value.preamp,
          "bands": entry.value.bands,
        },
    };
  }

  static Map<String, EqPreset> _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (decoded is! Map) return {};
    final result = <String, EqPreset>{};
    for (final entry in decoded.entries) {
      final preset = EqPreset.fromJson(entry.key as String, entry.value);
      if (preset != null) result[entry.key as String] = preset;
    }
    return result;
  }
}
