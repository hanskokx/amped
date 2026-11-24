import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/foundation.dart";

/// How a color theme changes the bitmaps and colors of one gamma group
/// (`<gammagroup id value="r,g,b" gray boost/>`): first to gray, then
/// brighter, then each channel scaled (gen_ff's `GammaFilter`).
@immutable
class WasabiGammaGroup {
  const WasabiGammaGroup({
    required this.id,
    this.red = 0,
    this.green = 0,
    this.blue = 0,
    this.gray = 0,
    this.boost = false,
  });

  /// A group that changes nothing.
  static const WasabiGammaGroup none = WasabiGammaGroup(id: "");

  final String id;

  /// What each channel is scaled by, from -4096 (to nothing) through 0
  /// (unchanged) to 4096 (doubled).
  final int red;
  final int green;
  final int blue;

  /// 1 turns each pixel into the gray of its brightest channel, 2 into the
  /// gray of the channels' average.
  final int gray;

  /// Halves each channel and adds half of white.
  final bool boost;

  /// Whether the group leaves everything as it is.
  bool get isIdentity =>
      red == 0 && green == 0 && blue == 0 && gray == 0 && !boost;

  /// The group as JSON, for saving a custom color theme.
  Map<String, Object> toJson() => {
    "id": id,
    "red": red,
    "green": green,
    "blue": blue,
    "gray": gray,
    "boost": boost,
  };

  /// A group from [toJson]'s output; missing values leave the group
  /// unchanged.
  factory WasabiGammaGroup.fromJson(Map<String, dynamic> json) =>
      WasabiGammaGroup(
        id: json["id"] is String ? json["id"] as String : "",
        red: json["red"] is int ? json["red"] as int : 0,
        green: json["green"] is int ? json["green"] as int : 0,
        blue: json["blue"] is int ? json["blue"] as int : 0,
        gray: json["gray"] is int ? json["gray"] as int : 0,
        boost: json["boost"] == true,
      );

  /// The same group with some values replaced.
  WasabiGammaGroup copyWith({
    int? red,
    int? green,
    int? blue,
    int? gray,
    bool? boost,
  }) => WasabiGammaGroup(
    id: id,
    red: red ?? this.red,
    green: green ?? this.green,
    blue: blue ?? this.blue,
    gray: gray ?? this.gray,
    boost: boost ?? this.boost,
  );

  /// The same change under another name: what tells filtered images apart.
  String get key => "$red,$green,$blue,$gray,${boost ? 1 : 0}";

  static int _scale(int channel, int multiplier) {
    final value = (channel * multiplier) >> 16;
    return value < 0 ? 0 : (value > 255 ? 255 : value);
  }

  /// Applies the group to [rgba], premultiplied RGBA pixels, in place
  /// (`GammaFilter::filterBitmap`).
  void filterPixels(Uint8List rgba) {
    if (isIdentity) return;
    // 65535, not 65536: the bitmap filter loses a little even at 0.
    final rm = 65535 + red * 16;
    final gm = 65535 + green * 16;
    final bm = 65535 + blue * 16;
    final gray = this.gray;
    final boost = this.boost;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      var r = rgba[i];
      var g = rgba[i + 1];
      var b = rgba[i + 2];
      if (gray == 1) {
        final c = r > g ? (r > b ? r : b) : (g > b ? g : b);
        r = g = b = c;
      }
      if (gray == 2) {
        final c = (r + g + b) ~/ 3;
        r = g = b = c;
      }
      if (boost) {
        final a = rgba[i + 3] >> 1;
        r = (r >> 1) + a;
        g = (g >> 1) + a;
        b = (b >> 1) + a;
      }
      rgba[i] = _scale(r, rm);
      rgba[i + 1] = _scale(g, gm);
      rgba[i + 2] = _scale(b, bm);
    }
  }

  /// [color] as the group shows it (`GammaFilter::filterColor`); its alpha
  /// stays.
  ui.Color filterColor(ui.Color color) {
    if (isIdentity) return color;
    var r = (color.r * 255).round();
    var g = (color.g * 255).round();
    var b = (color.b * 255).round();
    if (gray == 1) {
      final c = r > g ? (r > b ? r : b) : (g > b ? g : b);
      r = g = b = c;
    }
    if (gray == 2) {
      final c = (r + g + b) ~/ 3;
      r = g = b = c;
    }
    if (boost) {
      r = (r >> 1) + 0x80;
      g = (g >> 1) + 0x80;
      b = (b >> 1) + 0x80;
    }
    return ui.Color.fromARGB(
      (color.a * 255).round(),
      _scale(r, 65536 + red * 16),
      _scale(g, 65536 + green * 16),
      _scale(b, 65536 + blue * 16),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WasabiGammaGroup &&
      other.id == id &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.gray == gray &&
      other.boost == boost;

  @override
  int get hashCode => Object.hash(id, red, green, blue, gray, boost);

  @override
  String toString() =>
      "WasabiGammaGroup($id, $red,$green,$blue, gray $gray, boost $boost)";
}

/// A color theme (`<gammaset id="...">`): what each gamma group of the skin
/// looks like while the theme is on.
class WasabiGammaSet {
  WasabiGammaSet(this.name, {this.custom = false});

  /// The theme's name, as the Color Themes list shows it.
  final String name;

  /// Whether the user made the theme, rather than the skin defining it.
  final bool custom;

  /// A copy of this theme named [name], made by the user: the clone a
  /// custom theme starts from.
  WasabiGammaSet cloneAs(String name) {
    final clone = WasabiGammaSet(name, custom: true)..general = general;
    clone.groups.addAll(groups);
    return clone;
  }

  /// The theme as JSON, for saving a custom theme.
  Map<String, Object> toJson() => {
    "name": name,
    "general": general.toJson(),
    "groups": [for (final group in groups.values) group.toJson()],
  };

  /// A custom theme from [toJson]'s output, or null when it is not one.
  static WasabiGammaSet? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json["name"];
    if (name is! String || name.isEmpty) return null;
    final set = WasabiGammaSet(name, custom: true);
    final general = json["general"];
    if (general is Map<String, dynamic>) {
      set.add(WasabiGammaGroup.fromJson({...general, "id": "General"}));
    }
    final groups = json["groups"];
    if (groups is List) {
      for (final group in groups) {
        if (group is Map<String, dynamic>) {
          set.add(WasabiGammaGroup.fromJson(group));
        }
      }
    }
    return set;
  }

  /// The groups by lower-cased id.
  final Map<String, WasabiGammaGroup> groups = {};

  /// The `General` group, which adds to every other one and stands in for
  /// the groups the theme does not name.
  WasabiGammaGroup general = const WasabiGammaGroup(id: "General");

  /// Adds (or replaces) [group]; one named `General` becomes [general]
  /// (`GammaMgr::xmlReaderOnStartElementCallback`).
  void add(WasabiGammaGroup group) {
    final key = group.id.toLowerCase();
    if (key == "general") {
      general = group;
    } else {
      groups[key] = group;
    }
  }

  static int _clamp(int value) =>
      value < -4095 ? -4095 : (value > 4095 ? 4095 : value);

  /// What the theme does to gamma group [id] (case-insensitive): the group
  /// plus [general], or [general] alone when there is no such group
  /// (`GammaManagerAPI::getGammaForGroup`).
  WasabiGammaGroup resolve(String? id) {
    final group = id == null ? null : groups[id.toLowerCase()];
    final general = this.general;
    if (group == null) {
      return WasabiGammaGroup(
        id: id ?? "",
        red: _clamp(general.red),
        green: _clamp(general.green),
        blue: _clamp(general.blue),
        gray: general.gray,
        boost: general.boost,
      );
    }
    return WasabiGammaGroup(
      id: group.id,
      red: _clamp(group.red + general.red),
      green: _clamp(group.green + general.green),
      blue: _clamp(group.blue + general.blue),
      gray: group.gray | general.gray,
      boost: group.boost || general.boost,
    );
  }
}

/// An image a color theme can change: [source] as the skin has it, [image]
/// as the theme on now shows it.
abstract class WasabiThemedImage {
  ui.Image get source;

  /// The gamma group that says how themes change the image, or null.
  String? get gammaGroup;

  ui.Image get image;
  set image(ui.Image value);
}

/// The color themes of a skin and the one that is on.
///
/// Choosing a theme ([select]) filters the skin's bitmaps again, as
/// The classic player does (`imageLoader::applySkinFilters`); that takes a moment, so
/// [current] changes at once and [applied] when the bitmaps are ready. It
/// notifies on both.
class WasabiColorThemes extends ChangeNotifier {
  WasabiColorThemes({
    required this.sets,
    required List<WasabiThemedImage> images,
    required Future<ByteData?> Function(ui.Image source) readPixels,
  }) : _themed = images,
       // ignore: prefer_initializing_formals
       _readPixels = readPixels;

  /// The themes, in the order the skin defines them, then the user's.
  final List<WasabiGammaSet> sets;

  final List<WasabiThemedImage> _themed;
  final Future<ByteData?> Function(ui.Image source) _readPixels;

  WasabiGammaSet? _current;
  WasabiGammaSet? _applied;
  Future<void> _settled = Future.value();
  bool _disposed = false;

  /// The filtered images in use, and the ones before them: those are
  /// disposed a theme later, once nothing can still be drawing them.
  List<ui.Image> _images = const [];
  List<ui.Image> _previous = const [];

  /// The theme that was chosen last, or null when the skin has none.
  WasabiGammaSet? get current => _current;

  /// The theme the bitmaps and colors show.
  WasabiGammaSet? get applied => _applied;

  /// The most vivid color of the bitmaps as [applied] shows them, or null
  /// for bitmaps of grays: the theme's accent, when its `<color>`s do not
  /// carry it.
  ui.Color? get accent => _accent;
  ui.Color? _accent;

  /// Completes when the theme chosen last is [applied].
  Future<void> get settled => _settled;

  /// The theme names as the list shows them: sorted, ignoring case.
  List<String> get names =>
      [for (final set in sets) set.name]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Adds the custom theme [set], replacing a custom one of that name.
  void add(WasabiGammaSet set) {
    sets.removeWhere((s) => s.custom && s.name == set.name);
    sets.add(set);
    notifyListeners();
  }

  /// Removes the custom theme named [name]. When it is on, the first
  /// theme takes over.
  Future<void> remove(String name) async {
    final set = named(name);
    if (set == null || !set.custom) return;
    final wasOn = identical(set, _current);
    sets.remove(set);
    if (wasOn) {
      _current = null;
      _applied = null;
      await select(sets.isEmpty ? null : sets.first.name);
    }
    notifyListeners();
  }

  /// Filters the bitmaps again, after the theme that is on was edited.
  Future<void> reapply() {
    if (_disposed) return _settled;
    _applied = null;
    return _settled = _settled.then((_) => _apply());
  }

  /// The theme named [name] (case-insensitive), or null.
  WasabiGammaSet? named(String? name) {
    if (name == null) return null;
    final key = name.toLowerCase();
    for (final set in sets) {
      if (set.name.toLowerCase() == key) return set;
    }
    return null;
  }

  /// Turns on the theme named [name], or the first one when there is none
  /// of that name (`GammaManagerAPI::setGammaSet`). Completes when the
  /// bitmaps show it.
  Future<void> select(String? name) {
    final set = named(name) ?? (sets.isEmpty ? null : sets.first);
    if (set == null || _disposed) return _settled;
    if (!identical(set, _current)) {
      _current = set;
      notifyListeners();
    }
    return _settled = _settled.then((_) => _apply());
  }

  /// The theme [step] places after [current] in [names], wrapping around
  /// (`ColorThemesList::colorthemes_advance`), or null.
  String? advance(int step) {
    final current = _current;
    if (current == null || names.isEmpty) return null;
    final at = names.indexOf(current.name);
    if (at < 0) return null;
    return names[(at + step) % names.length];
  }

  Future<void> _apply() async {
    final set = _current;
    if (set == null || identical(set, _applied) || _disposed) return;
    final made = <(ui.Image, String), ui.Image>{};
    final next = <ui.Image>[];
    final tally = _AccentTally();
    final tallied = Set<ui.Image>.identity();
    for (final themed in _themed) {
      final group = set.resolve(themed.gammaGroup);
      if (group.isIdentity) {
        next.add(themed.source);
        if (tallied.add(themed.source)) {
          final data = await _readPixels(themed.source);
          if (data != null) {
            tally.add(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          }
        }
        continue;
      }
      final key = (themed.source, group.key);
      var image = made[key];
      if (image == null) {
        image = await _filter(themed.source, group, tally);
        if (image != null) made[key] = image;
      }
      next.add(image ?? themed.source);
    }
    if (_disposed) {
      for (final image in made.values) {
        image.dispose();
      }
      return;
    }
    for (var i = 0; i < _themed.length; i++) {
      _themed[i].image = next[i];
    }
    for (final image in _previous) {
      image.dispose();
    }
    _previous = _images;
    _images = made.values.toList();
    _applied = set;
    _accent = tally.result;
    notifyListeners();
  }

  Future<ui.Image?> _filter(
    ui.Image source,
    WasabiGammaGroup group,
    _AccentTally tally,
  ) async {
    final data = await _readPixels(source);
    if (data == null) return null;
    final pixels = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    group.filterPixels(pixels);
    tally.add(pixels);
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      source.width,
      source.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in [..._images, ..._previous]) {
      image.dispose();
    }
    _images = const [];
    _previous = const [];
    super.dispose();
  }
}

/// Finds the most vivid color of some RGBA pixels: the hue (of 24) with the
/// most chroma in its mid-tones, averaged.
class _AccentTally {
  static const int _hues = 24;
  final List<double> _weight = List.filled(_hues, 0);
  final List<double> _red = List.filled(_hues, 0);
  final List<double> _green = List.filled(_hues, 0);
  final List<double> _blue = List.filled(_hues, 0);

  void add(Uint8List rgba) {
    // Every few pixels: the picture of a skin is a few hundred thousand.
    for (var i = 0; i + 3 < rgba.length; i += 4 * 5) {
      if (rgba[i + 3] < 200) continue;
      final r = rgba[i] / 255;
      final g = rgba[i + 1] / 255;
      final b = rgba[i + 2] / 255;
      final high = math.max(r, math.max(g, b));
      final low = math.min(r, math.min(g, b));
      final chroma = high - low;
      // Chroma, discounted for colors near black or white.
      final weight = chroma * (1 - (high + low - 1).abs());
      if (weight < 0.05) continue;
      final hue = chroma == 0
          ? 0.0
          : high == r
          ? ((g - b) / chroma) % 6
          : high == g
          ? (b - r) / chroma + 2
          : (r - g) / chroma + 4;
      final bucket = (hue / 6 * _hues).floor() % _hues;
      _weight[bucket] += weight;
      _red[bucket] += r * weight;
      _green[bucket] += g * weight;
      _blue[bucket] += b * weight;
    }
  }

  ui.Color? get result {
    var best = 0;
    for (var i = 1; i < _hues; i++) {
      if (_weight[i] > _weight[best]) best = i;
    }
    final weight = _weight[best];
    if (weight < 1) return null;
    return ui.Color.from(
      alpha: 1,
      red: _red[best] / weight,
      green: _green[best] / weight,
      blue: _blue[best] / weight,
    );
  }
}
