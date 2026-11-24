import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter/services.dart";

import "skin_cursors.dart";

/// Playlist editor text colors parsed from `pledit.txt`.
class PlEditConfig {
  const PlEditConfig({
    this.normal = const ui.Color(0xFF00FF00),
    this.current = const ui.Color(0xFFFFFFFF),
    this.normalBg = const ui.Color(0xFF000000),
    this.selectedBg = const ui.Color(0xFF0000C6),
    this.mbFg = const ui.Color(0xFF00FF00),
    this.mbBg = const ui.Color(0xFF000000),
    this.fontName = "",
    this.useGenNums = false,
  });

  final ui.Color normal;
  final ui.Color current;
  final ui.Color normalBg;
  final ui.Color selectedBg;
  final ui.Color mbFg;
  final ui.Color mbBg;
  final String fontName;
  final bool useGenNums;

  PlEditConfig copyWith({
    ui.Color? normal,
    ui.Color? current,
    ui.Color? normalBg,
    ui.Color? selectedBg,
    ui.Color? mbFg,
    ui.Color? mbBg,
    String? fontName,
    bool? useGenNums,
  }) {
    return PlEditConfig(
      normal: normal ?? this.normal,
      current: current ?? this.current,
      normalBg: normalBg ?? this.normalBg,
      selectedBg: selectedBg ?? this.selectedBg,
      mbFg: mbFg ?? this.mbFg,
      mbBg: mbBg ?? this.mbBg,
      fontName: fontName ?? this.fontName,
      useGenNums: useGenNums ?? this.useGenNums,
    );
  }
}

/// A window region parsed from `region.txt`, defined as one or more
/// polygons. Coordinates are in skin (single-size) pixels.
class SkinRegion {
  const SkinRegion(this.polygons);
  final List<List<ui.Offset>> polygons;

  ui.Path? toPath() {
    if (polygons.isEmpty) return null;
    final path = ui.Path();
    for (final polygon in polygons) {
      if (polygon.isEmpty) continue;
      path.moveTo(polygon.first.dx, polygon.first.dy);
      for (final p in polygon.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
    return path;
  }
}

/// The layout hints of an Audacious skin (`skin.hints`): `key=value` pairs
/// that move the main window's controls and give it its own size. Keys are
/// case-insensitive; a skin without the file, or without a key, gets the
/// classic layout. The parser lives in `amped_audacious_skin`.
class SkinHints {
  const SkinHints([this.values = const {}]);

  /// The hints by lower-cased key.
  final Map<String, int> values;

  /// Whether the skin has any hint at all.
  bool get isEmpty => values.isEmpty;

  /// The hint [key], or [fallback] when the skin gives none.
  int value(String key, int fallback) => values[key.toLowerCase()] ?? fallback;

  /// A boolean hint: anything but 0 is on.
  bool flag(String key, {required bool fallback}) =>
      values[key.toLowerCase()] == null
      ? fallback
      : values[key.toLowerCase()] != 0;

  /// The position of the element named [name], from its `<name>X` and
  /// `<name>Y` hints, or [fallback].
  ui.Offset point(String name, ui.Offset fallback) {
    final x = values["${name}x".toLowerCase()];
    final y = values["${name}y".toLowerCase()];
    return x == null || y == null
        ? fallback
        : ui.Offset(x.toDouble(), y.toDouble());
  }
}

/// Classic bitmap skin (the `.wsz` / base-skin format).
///
/// All drawing in the app blits crops from these images with
/// `Canvas.drawImageRect`, mirroring the original GDI `BitBlt` calls.
class ClassicSkinData {
  ClassicSkinData({
    required this.name,
    required this.images,
    this.cursors = const {},
    this.regions = const {},
    this.regionPaths = const {},
    this.pledit = const PlEditConfig(),
    this.visColors = _defaultVisColors,
    this.useGenNums = false,
    this.hasOwnGen = true,
    this.numbersExtended = false,
    this.overlay = false,
    this.hints = const SkinHints(),
  });

  final String name;

  /// Bitmaps keyed by lower-cased file name (e.g. `main.bmp`).
  final Map<String, ui.Image> images;

  /// The cursors this skin ships. Use [cursor] to resolve a slot.
  final Map<SkinCursor, CustomMouseCursor> cursors;

  /// The cursor for [slot]: the skin's own, or the OS cursor when the skin
  /// has no file for it.
  MouseCursor cursor(SkinCursor slot) =>
      cursors[slot] ?? SystemMouseCursors.basic;

  /// Raw polygon regions from `region.txt`.
  final Map<String, SkinRegion> regions;

  /// Pre-built [ui.Path]s from [regions], keyed the same way.
  final Map<String, ui.Path> regionPaths;

  final PlEditConfig pledit;

  /// The 24-color spectrum analyzer palette (ARGB ints).
  final List<int> visColors;

  /// Whether the skin's `pledit.txt` requests the `gen.bmp` titlebar numbers.
  final bool useGenNums;

  /// Whether the skin ships its own `gen.bmp`. When it doesn't, `gen.bmp` is a
  /// frame derived from the skin's playlist editor (or the base skin's).
  final bool hasOwnGen;

  /// Whether the time display uses `nums_ex.bmp` (the skin ships it but no
  /// `numbers.bmp`), which has its own full-size minus glyph (`draw_time`).
  final bool numbersExtended;

  /// Whether the skin is made to be drawn over video: its windows are the
  /// overlay color (`#100010`), which is transparent.
  final bool overlay;

  /// Layout hints from `skin.hints` (Audacious skins).
  final SkinHints hints;

  /// The size of the main window: 275×116 unless the skin's hints give one.
  ui.Size get mainSize {
    final width = hints.value("mainwinWidth", 0);
    final height = hints.value("mainwinHeight", 0);
    return width > 0 && height > 0
        ? ui.Size(width.toDouble(), height.toDouble())
        : const ui.Size(275, 116);
  }

  /// The time-display digits: `nums_ex.bmp` or `numbers.bmp`.
  ui.Image get timeDigits =>
      image(numbersExtended ? "nums_ex.bmp" : "numbers.bmp")!;

  ui.Image? image(String name) => images[name.toLowerCase()];

  /// Returns the window region for a key like `main`, `mainWs`, `eq`, `eqWs`,
  /// or null when the skin defines no region (the window is a rectangle).
  ui.Path? region(String key) => regionPaths[key];
}

/// Default the classic player spectrum palette (`draw.cpp:370-395`).
const List<int> _defaultVisColors = [
  0xFF000000, // 0 black
  0xFF181829, // 1 grey dots
  0xFFEF3110, // 2 top of spectrum
  0xFFCE2910, // 3
  0xFFD65A00, // 4
  0xFFD66600, // 5
  0xFFD67300, // 6
  0xFFC67B08, // 7
  0xFFDEA518, // 8
  0xFFD6B521, // 9
  0xFFBDDE29, // 10
  0xFF94DE21, // 11
  0xFF29CE10, // 12
  0xFF32BE10, // 13
  0xFF39B510, // 14
  0xFF319C08, // 15
  0xFF299400, // 16
  0xFF188408, // 17
  0xFFFFFFFF, // 18 oscilloscope 1
  0xFFD6D6DE, // 19
  0xFFB5BDBD, // 20
  0xFFA0AAAF, // 21
  0xFF949CA5, // 22
  0xFF969696, // 23 analyzer peak
];
