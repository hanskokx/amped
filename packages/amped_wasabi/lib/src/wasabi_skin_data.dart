import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter/foundation.dart" show ValueNotifier;
import "package:flutter/services.dart";

import "maki/maki_binary.dart";
import "skin_region.dart";
import "wasabi_config.dart";
import "wasabi_files.dart";
import "wasabi_gamma.dart";
import "wasabi_gradient.dart";
import "wasabi_kabukicho.dart";
import "wasabi_playlist.dart" show wasabiComponentName;
import "xml.dart";

/// A bitmap element: a crop of a skin image (`<bitmap id file x y w h>`).
///
/// A color theme changes the picture ([image]) and leaves the element the
/// same, so what draws one compares the picture too.
class WasabiBitmap implements WasabiThemedImage {
  WasabiBitmap(this.source, this.src, {this.gammaGroup}) : image = source;

  /// The skin's image, as its file has it.
  @override
  final ui.Image source;

  /// [source] as the color theme that is on shows it.
  @override
  ui.Image image;

  /// The `gammagroup` that says how color themes change the bitmap.
  @override
  final String? gammaGroup;

  /// The crop of [image] this element names.
  final ui.Rect src;

  double get width => src.width;
  double get height => src.height;
  ui.Size get size => src.size;
}

/// A bitmap font (`<bitmapfont id file charwidth charheight hspacing
/// vspacing>`): a picture of fixed-size characters laid out the way
/// classic's `text.bmp` is, letters on the first row and digits and
/// punctuation on the second (`BitmapFont`).
class WasabiBitmapFont {
  WasabiBitmapFont({
    required this.table,
    required this.charWidth,
    required this.charHeight,
    required this.hSpacing,
    required this.vSpacing,
  });

  /// The character table.
  final WasabiBitmap table;

  final int charWidth;
  final int charHeight;

  /// Pixels added after each character (may be negative).
  final int hSpacing;
  final int vSpacing;

  /// How far each character moves the pen.
  int get advance => charWidth + hSpacing;

  /// The width [text] takes (`BitmapFont::getTextWidth`).
  int textWidth(String text) => text.length * advance;

  /// Where the character [code] is in [table], in table pixels
  /// (`BitmapFont::getXYfromChar`).
  ui.Offset glyph(int code) {
    final c = switch (code) {
      0xB0 => 0x30,
      0xC6 => 0x41,
      0xC7 => 0x43,
      0xC9 => 0x45,
      0xE0 || 0xE1 || 0xE2 || 0xE6 => 0x61,
      0xE7 => 0x63,
      0xE8 || 0xE9 || 0xEA || 0xEB => 0x65,
      0xEC || 0xED || 0xEE || 0xEF => 0x69,
      0xF2 || 0xF3 || 0xF4 => 0x6F,
      0xF9 || 0xFA || 0xFB || 0xFC => 0x75,
      0xFF => 0x79,
      0xDC => 0x55,
      0xD1 => 0x4E,
      0xF1 => 0x6E,
      0x192 => 0x66,
      _ => code,
    };
    var row = 0;
    int column;
    if (c >= 0x41 && c <= 0x5A) {
      column = c - 0x41;
    } else if (c >= 0x61 && c <= 0x7A) {
      column = c - 0x61;
    } else if (c == 0x20) {
      column = 30;
    } else if (_secondRow[c] case final second?) {
      row = 1;
      column = second;
    } else if (c >= 0x30 && c <= 0x39) {
      row = 1;
      column = c - 0x30;
    } else if (_thirdRow[c] case final third?) {
      row = 2;
      column = third;
    } else {
      column = switch (c) {
        0x22 => 26, // "
        0x40 => 27, // @
        _ => 30,
      };
    }
    return ui.Offset(
      (column * charWidth).toDouble(),
      (row * charHeight).toDouble(),
    );
  }

  static const Map<int, int> _secondRow = {
    0x01: 10,
    0x2E: 11, // .
    0x3A: 12, // :
    0x28: 13, // (
    0x29: 14, // )
    0x2D: 15, // -
    0x27: 16, // '
    0x60: 16, // `
    0x21: 17, // !
    0x5F: 18, // _
    0x2B: 19, // +
    0x5C: 20, // \
    0x2F: 21, // /
    0x5B: 22, // [
    0x7B: 22, // {
    0x3C: 22, // <
    0x5D: 23, // ]
    0x7D: 23, // }
    0x3E: 23, // >
    0x7E: 24, // ~
    0x5E: 24, // ^
    0x26: 25, // &
    0x25: 26, // %
    0x2C: 27, // ,
    0x3D: 28, // =
    0x24: 29, // $
    0x23: 30, // #
  };

  static const Map<int, int> _thirdRow = {
    0xC5: 0, // Å
    0xE5: 0,
    0xD6: 1, // Ö
    0xF6: 1,
    0xC4: 2, // Ä
    0xE4: 2,
    0x3F: 3, // ?
    0x2A: 4, // *
  };
}

/// A GUI object of a layout: a `<layer>`, `<button>`, `<slider>`, `<text>`,
/// `<group>`, ... with its XML attributes.
///
/// Groups carry the objects of their `<groupdef>` as [children], resolved at
/// load time, so a layout is a finished tree.
class WasabiObject {
  WasabiObject(this.tag, this.attributes, this.children, {this.background}) {
    for (final child in children) {
      child.parent = this;
    }
  }

  /// The group or layout this object is in; null for a layout.
  WasabiObject? parent;

  /// A deep copy, as it is now (scripts changed some of its attributes).
  WasabiObject copy() => WasabiObject(
    tag,
    Map.of(attributes),
    [for (final child in children) child.copy()],
    background: background,
  );

  /// The lower-cased XML element name.
  final String tag;

  /// The attributes, lower-cased keys; for groups, the `<groupdef>`'s
  /// attributes overlaid by the `<group>`'s.
  final Map<String, String> attributes;

  final List<WasabiObject> children;

  /// A group's or layout's `background` bitmap.
  final WasabiBitmap? background;

  String? operator [](String name) => attributes[name];

  String get id => attributes["id"] ?? "";

  /// Integer attribute [name], or [fallback].
  int intAttr(String name, [int fallback = 0]) =>
      int.tryParse(attributes[name]?.trim() ?? "") ?? fallback;

  /// Integer attribute [name], or null when missing or not a number.
  int? optInt(String name) => int.tryParse(attributes[name]?.trim() ?? "");

  /// Boolean attribute [name] ("1"/"true"/"yes").
  bool boolAttr(String name, {bool fallback = false}) {
    final value = attributes[name]?.trim().toLowerCase();
    if (value == null || value.isEmpty) return fallback;
    return value == "1" || value == "true" || value == "yes";
  }

  /// `alpha` (0..255, default opaque).
  int get alpha => intAttr("alpha", 255).clamp(0, 255);

  /// The alpha the object paints with while its window is [active] or not
  /// (`BaseWnd::getPaintingAlpha`): `activealpha` / `inactivealpha`, each
  /// falling back to [alpha].
  int paintingAlpha({required bool active}) =>
      intAttr(active ? "activealpha" : "inactivealpha", alpha).clamp(0, 255);

  /// Whether the object lets the mouse through (`ghost="1"`).
  bool get ghost => boolAttr("ghost");

  /// `visible="0"` hides the object.
  bool get visible => boolAttr("visible", fallback: true);

  /// Whether the object cuts its opaque pixels out of a region instead of
  /// adding to it: `sysregion` "sub"/-1 or "sub2"/-2 (REGIONOP_SUB/SUB2 in
  /// `BaseWnd::computeComposedRegion`). Wasabi 5's frames use such layers,
  /// black where the rounded corners are, so the region removes them.
  bool get subtractsRegion => isSubtractingRegionOp(attributes["sysregion"]);

  /// Whether the object cuts its opaque pixels out of the whole window
  /// (`sub2`/-2). Plain `sub`/-1 only cuts its own group's region.
  bool get subtractsFromWindow {
    final value = attributes["sysregion"]?.trim().toLowerCase();
    return value == "sub2" || int.tryParse(value ?? "") == -2;
  }

  /// Whether the `sysregion` value [sysregion] subtracts.
  static bool isSubtractingRegionOp(String? sysregion) {
    final value = sysregion?.trim().toLowerCase();
    if (value == null) return false;
    if (value == "sub" || value == "sub2") return true;
    final number = int.tryParse(value);
    return number == -1 || number == -2;
  }
}

/// Whether [object] is a layer that takes the mouse only over its image's
/// pixels: one with `rectrgn="0"` or a `sysregion` (Layer::setRegionOp).
/// Other layers take it over their whole rectangle (Layer's `setRectRgn(1)`).
bool wasabiShapedLayer(WasabiObject object) {
  if (object.tag != "layer" && object.tag != "animatedlayer") return false;
  final rectrgn = object["rectrgn"]?.trim();
  if (rectrgn != null && rectrgn.isNotEmpty) return rectrgn == "0";
  final sysregion = object["sysregion"]?.trim();
  return sysregion != null && sysregion.isNotEmpty && sysregion != "0";
}

/// A layout of a container: one look of a window (`normal`, `shade`, ...).
/// A key combination as Wasabi writes it, for comparing: lower case, with
/// the modifiers first in a fixed order (`Alt+F` and `alt+f` are the same;
/// `shift+ctrl+a` is `ctrl+shift+a`).
String wasabiKeyName(String key) {
  final parts = [
    for (final part in key.split("+"))
      if (part.trim().isNotEmpty) part.trim().toLowerCase(),
  ];
  const order = ["ctrl", "alt", "shift"];
  final modifiers = [
    for (final m in order)
      if (parts.contains(m)) m,
  ];
  final rest = [
    for (final p in parts)
      if (!order.contains(p)) p,
  ];
  return [...modifiers, ...rest].join("+");
}

/// A `<snappoint>` of a layout.
class WasabiSnapPoint {
  const WasabiSnapPoint({
    required this.id,
    required this.x,
    required this.y,
    this.fromRight = false,
    this.fromBottom = false,
  });

  final String id;
  final double x;
  final double y;
  final bool fromRight;
  final bool fromBottom;

  /// Where it is in a window of [size], from the window's top left.
  ui.Offset at(ui.Size size) => ui.Offset(
    fromRight ? size.width + x : x,
    fromBottom ? size.height + y : y,
  );
}

class WasabiLayout {
  WasabiLayout({
    required this.id,
    required this.root,
    required ui.Size size,
    required this.region,
  }) : _initialSize = size;

  final String id;

  /// The layout as a group: its background and objects.
  final WasabiObject root;

  final ui.Size _initialSize;

  /// The layout's `<snappoint id x y>`s: places on the window that dock to
  /// the point of the same id on another window (`SnapPoint`). A point is
  /// measured from the top left unless `relatx="0"` / `relaty="0"` measure it
  /// from the right / bottom edge.
  List<WasabiSnapPoint> get snapPoints => [
    for (final node in root.children)
      if (node.tag == "snappoint" && node.id.isNotEmpty)
        WasabiSnapPoint(
          id: node.id,
          x: node.intAttr("x").toDouble(),
          y: node.intAttr("y").toDouble(),
          fromRight: node["relatx"]?.trim() == "0",
          fromBottom: node["relaty"]?.trim() == "0",
        ),
  ];

  /// A deep copy of the layout, as it is now.
  WasabiLayout copy() => WasabiLayout(
    id: id,
    root: root.copy(),
    size: _initialSize,
    region: region,
  );

  /// The window size of this layout; scripts may change it (`resize`,
  /// `setTargetH`).
  ui.Size get size => ui.Size(
    (root.optInt("w") ?? _initialSize.width).toDouble(),
    (root.optInt("h") ?? _initialSize.height).toDouble(),
  );

  /// The size of the window showing this layout: [size] less its right and
  /// bottom snap adjustments (`snapadjustright`/`snapadjustbottom`, or a
  /// script's `snapAdjust`), the transparent room a skin keeps for a drawer
  /// that is closed. The classic player keeps that room in the window and only leaves
  /// it out when docking; leaving it out of the window does the same for
  /// screen edges and other windows. Between a script's `beforeRedock` and
  /// `redock` the window keeps the whole layout, so a drawer can slide in.
  ui.Size get windowSize {
    final settled = _settledWindowSize;
    if (root["#redocking"] == "1") {
      // The room is open for the drawer; the window grows into it along
      // with the drawer instead of jumping when it has slid in, and
      // shrinks back along with the drawer as it slides out.
      final from = _sizeOf(root["#redockfrom"]);
      if (from == null) return size;
      final closed = _sizeOf(root["#closedadjust"]);
      final to = from == size && closed != null
          ? ui.Size(size.width - closed.width, size.height - closed.height)
          : size;
      return ui.Size.lerp(from, to, _fraction("#redockt"))!;
    }
    // A drawer sliding needs the room a closed one leaves out.
    if (root["#sliding"] == "1") return size;
    final from = _sizeOf(root["#tweenfrom"]);
    if (from == null) return settled;
    return ui.Size.lerp(from, settled, _fraction("#tweent"))!;
  }

  /// The window size once any redocking is over: [size] less the snap
  /// adjustments.
  ui.Size get _settledWindowSize {
    final size = this.size;
    final right = root.optInt("snapadjustright") ?? 0;
    final bottom = root.optInt("snapadjustbottom") ?? 0;
    return ui.Size(
      math.max(1, size.width - math.max(0, right)).toDouble(),
      math.max(1, size.height - math.max(0, bottom)).toDouble(),
    );
  }

  /// The settled window size, ignoring a redock in progress.
  ui.Size get settledWindowSize => _settledWindowSize;

  double _fraction(String key) =>
      (double.tryParse(root[key] ?? "") ?? 0).clamp(0.0, 1.0);

  static ui.Size? _sizeOf(String? text) {
    final parts = text?.split(",");
    if (parts == null || parts.length != 2) return null;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    return w == null || h == null ? null : ui.Size(w, h);
  }

  /// Seconds a drawer slid for between the script's `beforeRedock` and
  /// `redock`, or null when it did not animate.
  double? get redockSeconds => double.tryParse(root["#redockspeed"] ?? "");

  /// The window's shape: where the base texture is not fully transparent,
  /// as a list of polygons in layout pixels; null for a rectangular window.
  /// Everything the layout draws is clipped to it, as the original clips
  /// the window to its region.
  final List<List<ui.Offset>>? region;
}

/// A container: one skinned window and its layouts.
class WasabiContainer {
  WasabiContainer({
    required this.id,
    required this.name,
    required this.layouts,
    required this.defaultPosition,
    required this.defaultVisible,
    required this.dynamic,
    this.component,
    this.defaultVisibleExplicit = false,
  });

  /// The component the container holds (`guid:{...}`), lower-cased, when it
  /// names one: how Wasabi tells the media library, the playlist editor, the
  /// video and visualization windows from containers called anything.
  final String? component;

  /// The lower-cased container id (`main`, `eq`, `pl`, `thinger`, ...).
  final String id;
  final String name;
  final List<WasabiLayout> layouts;
  final ui.Offset? defaultPosition;
  final bool defaultVisible;

  /// Whether the skin says `default_visible="1"` itself, rather than leaving
  /// the default.
  final bool defaultVisibleExplicit;

  /// A container created on demand for components (not shown at load).
  final bool dynamic;

  /// The layout named [id] (case-insensitive), or null.
  WasabiLayout? layout(String id) {
    final key = id.toLowerCase();
    for (final layout in layouts) {
      if (layout.id.toLowerCase() == key) return layout;
    }
    return null;
  }
}

/// A switch a skin's window carries: a toggle button bound to [attribute],
/// named by its tooltip.
class WasabiCfgToggle {
  const WasabiCfgToggle(this.attribute, this.tooltip);

  final WasabiCfgAttrib attribute;
  final String? tooltip;

  /// What the switch is called in a list of options.
  String get label =>
      tooltip != null && tooltip!.isNotEmpty ? tooltip! : attribute.name;
}

/// The container ids and component guids by which skins mark the container
/// of one of the player's windows, in preference order. Amped Modern says
/// `pledit`, `mlibrary` and `avs`; older skins call them anything
/// (`medlib`, `equalizer`, `playlist`), which only their component's guid
/// tells (the equalizer has none).
const Map<String, (List<String>, List<String>)> wasabiWindowContainers = {
  "eq": (["eq", "equalizer", "eqmain", "eqth"], []),
  "pl": (
    ["pl", "pledit", "playlist"],
    ["guid:{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}", "guid:pl"],
  ),
  "video": (
    ["video", "videowindow", "videocon"],
    ["guid:{f0816d7b-fffc-4343-80f2-e8199aa15cc3}", "guid:video"],
  ),
  "library": (
    ["library", "mlibrary", "medlib", "mllibrary"],
    ["guid:{6b0edf80-c9a5-11d3-9f26-00c04f39ffc6}", "guid:ml"],
  ),
  "vis": (
    ["vis", "avs", "avs_window", "viscon"],
    ["guid:{0000000a-000c-0010-ff7b-01014263450c}", "guid:avs"],
  ),
};

/// A Wasabi 3 / Wasabi 5 modern skin (the `.wal` format), loaded from its
/// extracted directory.
class WasabiSkinData {
  WasabiSkinData._({
    required this.name,
    required this.directory,
    required this.info,
    required this.bitmaps,
    required this.regionMasks,
    required this.cfgToggles,
    required this.fonts,
    required this.bitmapFonts,
    required this.colors,
    required this.colorGroups,
    required this.aliases,
    required this.cursors,
    required this.accelerators,
    required this.colorThemes,
    required this.containers,
    required this.scripts,
    required this._builder,
    required this._bitmapRegions,
    required this._pixels,
  });

  /// The RGBA bytes of the images scripts read as maps (`Map.loadMap`), by
  /// image: read at load for the bitmaps the scripts name, so the
  /// synchronous map calls can look at their pixels.
  final Map<ui.Image, ByteData> _pixels;

  /// The RGBA bytes (premultiplied) of [bitmap]'s whole image, when they
  /// have been read ([readPixels]); null otherwise.
  ///
  /// They are the skin's own pixels ([WasabiBitmap.source]), whatever the
  /// color theme.
  ByteData? pixelsOf(WasabiBitmap bitmap) => _pixels[bitmap.source];

  /// Reads the RGBA bytes of [bitmap]'s whole image, once.
  Future<ByteData?> readPixels(WasabiBitmap bitmap) =>
      _readPixels(_pixels, bitmap.source);

  static Future<ByteData?> _readPixels(
    Map<ui.Image, ByteData> pixels,
    ui.Image image,
  ) async {
    final known = pixels[image];
    if (known != null) return known;
    final data = await image.toByteData();
    if (data != null) pixels[image] = data;
    return data;
  }

  final Map<WasabiBitmap, List<ui.Rect>?> _bitmapRegions;

  /// The pixels of [bitmap] with any alpha, in bitmap pixels, for the
  /// group backgrounds and `sysregion` layers of shaped layouts (read at
  /// load). Null when the bitmap is fully opaque or was not read: its
  /// region is its whole rectangle.
  List<ui.Rect>? bitmapRegion(WasabiBitmap bitmap) => _bitmapRegions[bitmap];

  final _TreeBuilder _builder;

  /// A new, unattached instance of the groupdef [id] (`System.newGroup`),
  /// or null when the skin has no such group.
  WasabiObject? newGroup(String id) => _builder.newGroup(id);

  /// The display name (`<skininfo><name>` or the folder name).
  final String name;

  final Directory directory;

  /// `<skininfo>` fields (`name`, `author`, `comment`, `version`, ...).
  final Map<String, String> info;

  /// The bitmap elements by lower-cased id.
  final Map<String, WasabiBitmap> bitmaps;

  /// The opaque pixels, as rectangles in bitmap pixels, of the bitmaps that
  /// layers cut out of the window region ([WasabiObject.subtractsRegion]),
  /// by lower-cased bitmap id (`RegionI(bitmap)` in `Layer::makeRegion`).
  final Map<String, List<ui.Rect>> regionMasks;

  /// The switches the skin's windows carry (a toggle button bound to a
  /// config attribute of the skin's own, such as Resin's "Glass" button):
  /// the skin's options even when no script lists them in the Options menu.
  final List<WasabiCfgToggle> cfgToggles;

  /// Registered font families by lower-cased font id.
  final Map<String, String> fonts;

  /// The bitmap fonts by lower-cased font id.
  final Map<String, WasabiBitmapFont> bitmapFonts;

  /// `<color>` elements by lower-cased id, as the skin defines them: the
  /// color theme is not applied ([color] does that).
  final Map<String, ui.Color> colors;

  /// The skin's accent in the color theme that is on: the most vivid color
  /// of its bitmaps, else of its colors; null for a skin of grays.
  ui.Color? get accentColor {
    // The bitmaps, which every theme changes, then the colors, which some
    // themes leave as they are.
    if (colorThemes.accent case final accent?) return accent;
    ui.Color? best;
    var bestScore = 0.1;
    for (final id in colors.keys) {
      final color = this.color(id);
      if (color == null) continue;
      final high = math.max(color.r, math.max(color.g, color.b));
      final low = math.min(color.r, math.min(color.g, color.b));
      // Chroma, discounted for colors near black or white.
      final score = (high - low) * (1 - (high + low - 1).abs());
      if (score > bestScore) {
        best = color;
        bestScore = score;
      }
    }
    return best;
  }

  /// The gamma group of the `<color>` elements that have one, by
  /// lower-cased id.
  final Map<String, String> colorGroups;

  /// `<elementalias id target>`: an element id that stands for another
  /// (both lower-cased). The skin's definitions of the alias are kept under
  /// the target, and a lookup of the alias finds the target
  /// (`PaletteManager::getElementAlias`).
  final Map<String, String> aliases;

  String _aliased(String id) => aliases[id] ?? id;

  /// The skin's `<accelerators section="...">`: for each section (a layout's
  /// id, or `general`), the action each key combination (as
  /// [wasabiKeyName] writes it) stands for.
  final Map<String, Map<String, String>> accelerators;

  /// The action [key] is bound to in [section], or null.
  String? accelerator(String section, String key) =>
      accelerators[section.toLowerCase()]?[wasabiKeyName(key)];

  /// The skin's `<cursor>` elements by lower-cased id.
  final Map<String, MouseCursor> cursors;

  /// The cursor element [id] (an object's `cursor` attribute), or null.
  MouseCursor? cursor(String? id) {
    final key = id?.trim().toLowerCase();
    return key == null || key.isEmpty ? null : cursors[_aliased(key)];
  }

  /// The skin's color themes (`<gammaset>`s) and the one that is on.
  final WasabiColorThemes colorThemes;

  final List<WasabiContainer> containers;

  /// The components (`pl`, `ml`, `vis`, `video`, as [wasabiComponentName]
  /// names them) the skin shows inside its main window with `<component>`
  /// objects, as the nodes that hold them. A skin that does has no use for
  /// the player's own window of that component.
  List<WasabiObject> embeddedComponents(String name) {
    final nodes = <WasabiObject>[];
    void visit(WasabiObject group) {
      for (final child in group.children) {
        // `<component>` is the Wasabi 3 way to put a window inside another;
        // a `<windowholder>` is placed by the skin's scripts or frames.
        if (child.tag == "component" && wasabiComponentName(child) == name) {
          nodes.add(child);
        }
        visit(child);
      }
    }

    for (final layout in container("main")?.layouts ?? const <WasabiLayout>[]) {
      visit(layout.root);
    }
    return nodes;
  }

  /// Whether the main window has an equalizer of its own: sliders for the
  /// bands (`action="EQ_BAND"`) or an `<eqvis>`.
  bool get hasBuiltInEq {
    bool visit(WasabiObject group) {
      for (final child in group.children) {
        final action = (child["action"] ?? "").toLowerCase();
        if (child.tag == "eqvis" ||
            action == "eq_band" ||
            action == "eq_preamp") {
          return true;
        }
        if (visit(child)) return true;
      }
      return false;
    }

    for (final layout in container("main")?.layouts ?? const <WasabiLayout>[]) {
      if (visit(layout.root)) return true;
    }
    return false;
  }

  /// What the playlist search box holds: the playlist shows only the
  /// entries that match it while it is not empty.
  final ValueNotifier<String> playlistFilter = ValueNotifier("");

  /// Counts the scripts' requests to scroll the playlist to the track that
  /// is playing (`PlEdit.showCurrentlyPlayingTrack`).
  final ValueNotifier<int> playlistReveal = ValueNotifier(0);

  /// The `<script>`s outside any group: they run with no script group.
  final List<WasabiObject> scripts;

  /// The container of the player window [kind] (a key of
  /// [wasabiWindowContainers]), by its id or else its component.
  WasabiContainer? windowContainer(String kind) {
    final (ids, guids) =
        wasabiWindowContainers[kind] ?? (const <String>[], const <String>[]);
    for (final id in ids) {
      final found = container(id);
      if (found != null) return found;
    }
    for (final candidate in containers) {
      if (candidate.component case final guid? when guids.contains(guid)) {
        return candidate;
      }
    }
    return null;
  }

  /// The skin's Album Art window: Amped Modern's `amped.albumart` (or `winamp.albumart`, as
  /// skins made from the original Wasabi skins name it), an
  /// `albumart` container, or one a skin names "Album Art" itself (Ebonite's
  /// `covermain`).
  late final WasabiContainer? albumArtContainer =
      container("amped.albumart") ??
      container("winamp.albumart") ??
      container("albumart") ??
      containers
          .where(
            (c) =>
                !c.dynamic &&
                c.layouts.isNotEmpty &&
                const {"album art", "albumart"}.contains(
                  c.name.trim().toLowerCase(),
                ),
          )
          .firstOrNull;

  /// The containers that are no window of the player's own: panels the skin
  /// brings (Resin's "Color and Opacity", HARMONIA's control and song
  /// display panels, AudioRack's VU meters), in the order it lists them.
  /// Dynamic containers are left out: they are the skin's own machinery
  /// (component frames, the frames scripts draw over other windows).
  late final List<WasabiContainer> extraContainers = () {
    final taken = <String>{
      for (final id in const ["main", "thinger"]) ?container(id)?.id,
      ?albumArtContainer?.id,
      for (final kind in wasabiWindowContainers.keys)
        ?windowContainer(kind)?.id,
      ?notifierContainer?.id,
    };
    return [
      for (final candidate in containers)
        if (!candidate.dynamic &&
            !_isBrowser(candidate) &&
            !taken.contains(candidate.id) &&
            candidate.layouts.isNotEmpty &&
            candidate.layouts.first.size.longestSide > 1)
          candidate,
    ];
  }();

  /// The skin's notifier (the pop-up for track changes): `notifier`, or a
  /// skin's own name for it that ends so (Graviton's `opensource_notifier`;
  /// not its `..._prefs` settings window).
  late final WasabiContainer? notifierContainer =
      container("notifier") ??
      containers
          .where((c) => c.id.endsWith("notifier") && c.layouts.isNotEmpty)
          .firstOrNull;

  /// Whether [container] is a web browser window (the classic player's minibrowser, "Warp
  /// Browser", ...): they show pages of sites that are mostly gone and are
  /// not something amped has a component for, so they are never opened.
  static bool _isBrowser(WasabiContainer container) =>
      _browserName.hasMatch(container.id) ||
      _browserName.hasMatch(container.name);

  static final RegExp _browserName = RegExp(
    r"browser|^mb$|minibrowser|^warp|^web",
    caseSensitive: false,
  );

  /// The container [id] (case-insensitive), or null.
  WasabiContainer? container(String id) {
    final key = id.toLowerCase();
    for (final container in containers) {
      if (container.id == key) return container;
    }
    return null;
  }

  /// The bitmap element [id], or null.
  WasabiBitmap? bitmap(String? id) =>
      id == null ? null : bitmaps[_aliased(id.toLowerCase())];

  /// The font family registered for font element [id], or null.
  /// The family of the TrueType font [id] names. A text that names none the
  /// skin defines (ClassicPro's tabs, whose skins leave the font out "if you
  /// use arial") gets Arial, Wasabi's default, not the system's own font
  /// which is wider.
  String fontFamily(String? id) =>
      (id == null ? null : fonts[id.toLowerCase()]) ?? "Arial";

  /// The bitmap font element [id], or null.
  WasabiBitmapFont? bitmapFont(String? id) =>
      id == null ? null : bitmapFonts[id.toLowerCase()];

  /// The color an attribute names, as the color theme that is on shows
  /// it: `r,g,b`, `#rrggbb`, `white`, `black` or a `<color>` element id
  /// (`SkinParser::parseColor`, `SkinColor::v`).
  ///
  /// The theme changes it by the gamma group [group], else the element's
  /// own, else [defaultGroup]: `Text`, as for every `SkinColor`.
  ui.Color? color(
    String? value, {
    String? group,
    String defaultGroup = "Text",
  }) {
    final color = sourceColor(value);
    final theme = colorThemes.applied;
    if (color == null || theme == null) return color;
    final own = value == null
        ? null
        : colorGroups[_aliased(value.trim().toLowerCase())];
    return theme
        .resolve(_named(group) ?? _named(own) ?? defaultGroup)
        .filterColor(color);
  }

  static final RegExp _imageFile = RegExp(
    r"\.(png|jpe?g|bmp|gif)\s*$",
    caseSensitive: false,
  );

  static String? _named(String? group) =>
      group == null || group.trim().isEmpty ? null : group.trim();

  /// The color an attribute names as the skin defines it, whatever the
  /// color theme.
  ui.Color? sourceColor(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == "white") return const ui.Color(0xFFFFFFFF);
    if (lower == "black") return const ui.Color(0xFF000000);
    if (text.contains(",")) {
      final parts = text.split(",").map((p) => int.tryParse(p.trim())).toList();
      if (parts.length < 3 || parts.take(3).contains(null)) return null;
      final alpha = parts.length > 3 ? parts[3] ?? 255 : 255;
      return ui.Color.fromARGB(alpha, parts[0]!, parts[1]!, parts[2]!);
    }
    if (text.startsWith("#") && text.length >= 7) {
      final rgb = int.tryParse(text.substring(1, 7), radix: 16);
      if (rgb != null) return ui.Color(0xFF000000 | rgb);
    }
    return colors[_aliased(lower)];
  }

  /// The folder `@WINAMPPATH@` stands for: one holding `Plugins/` with
  /// the plugins skins need (`Plugins/ClassicPro/engine/load.xml`), as in
  /// an original install. Null when there is none, and the files named
  /// through it are not found.
  static Directory? playerPath;

  /// The folder `@WINAMPPATH@` stands for: [playerPath], or the folder the
  /// bundled plugins are mounted in.
  static String? get _playerRoot =>
      playerPath?.path.replaceAll("\\", "/") ??
      (WasabiFiles.mounted ? WasabiFiles.virtualRoot : null);

  /// Mounts the zip [bytes] (a `Plugins/` folder, as in an original install)
  /// in memory as the folder `@WINAMPPATH@` stands for, when [playerPath]
  /// is not set: nothing is written to disk.
  static void mountPlugins(Uint8List bytes) => WasabiFiles.mountZip(bytes);

  /// [text] with the classic player's path variables filled in (`@SKINPATH@` and the
  /// others end in a separator, as in the classic player), for script parameters.
  String expandPathVariables(String text) {
    if (!text.contains("@")) return text;
    final root = _playerRoot ?? "";
    return text
        .replaceAll("@SKINPATH@", "${directory.path}/")
        .replaceAll("@WINAMPPATH@", "$root/")
        .replaceAll("@COLORTHEMESPATH@", "$root/Skins/");
  }

  /// Finds a skin file named by an attribute (like `<script file>`),
  /// relative to the skin root or to [dir], ignoring case.
  String? resolveFile(String file, {String? dir}) =>
      _resolve(directory.path, dir ?? directory.path, file);

  static int _fontSerial = 0;

  /// Tells this run's font families from an earlier run's: the engine keeps
  /// the families a hot restart registered, and a new font under an old
  /// family's name would draw with the old one's glyphs.
  static final int _fontRun = DateTime.now().microsecondsSinceEpoch;

  /// A `<color value>`: `r,g,b`, `#rrggbb`, `white` or `black`. (the classic player
  /// Modern's notifier writes its colors as `white` and `black`.)
  static ui.Color? _colorLiteral(String value) {
    final text = value.trim().toLowerCase();
    if (text == "white") return const ui.Color(0xFFFFFFFF);
    if (text == "black") return const ui.Color(0xFF000000);
    if (text.startsWith("#") && text.length >= 7) {
      final rgb = int.tryParse(text.substring(1, 7), radix: 16);
      return rgb == null ? null : ui.Color(0xFF000000 | rgb);
    }
    final parts = text.split(",").map((p) => int.tryParse(p.trim())).toList();
    if (parts.length < 3 || parts.take(3).contains(null)) return null;
    return ui.Color.fromARGB(255, parts[0]!, parts[1]!, parts[2]!);
  }

  /// The color theme a skin has until another is chosen.
  static const String defaultColorTheme = "Default";

  /// Loads the skin extracted in [directory] (the folder holding
  /// `skin.xml`), in the color theme named [colorTheme]:
  /// [defaultColorTheme] when null, the skin's first when it has none of
  /// that name. [customThemes] are the user's own color themes, listed
  /// with the skin's.
  static Future<WasabiSkinData> load(
    Directory directory, {
    String? name,
    String? colorTheme,
    List<WasabiGammaSet> customThemes = const [],
  }) async {
    final root = directory.path;
    final skinXml = _findFile(root, "skin.xml");
    if (skinXml == null) {
      throw FileSystemException("No skin.xml in the skin", root);
    }
    final nodes = await _readXml(skinXml, root, {});

    final bitmapNodes = <(XmlNode, String)>[];
    final fileBitmaps = <(String, String)>{};
    // The skin's own switches: toggle buttons bound to a config attribute.
    final cfgToggles = <WasabiCfgToggle>[];
    final fontNodes = <(XmlNode, String)>[];
    final bitmapFontNodes = <(XmlNode, String)>[];
    final colors = <String, ui.Color>{};
    final colorGroups = <String, String>{};
    final aliases = <String, String>{};
    final cursorNodes = <(XmlNode, String)>[];
    final accelerators = <String, Map<String, String>>{};
    final gammaSets = <WasabiGammaSet>[];
    final groupDefs = <String, XmlNode>{};
    // Every definition of a groupdef id, with where it came in the files: a
    // skin may define the same id again for another layout (Ebonite's mini
    // and vertical mini bars), and a layout takes the definition before it.
    final groupDefHistory = <String, List<(int, XmlNode)>>{};
    final layoutOrder = Map<XmlNode, int>.identity();
    var order = 0;
    // Each container, and whether it is nested in another container.
    final containerNodes = <(XmlNode, bool)>[];
    final scripts = <WasabiObject>[];
    // Every `<script>`, wherever it is: (file, folder).
    final scriptFiles = <(String, String)>[];
    final info = <String, String>{};

    // [topLevel]: not inside a groupdef or container. [inContainer]:
    // directly in a container (Amped Modern defines its playlist search
    // results container inside the main container, and its scripts open
    // it with `newDynamicContainer`).
    void walk(
      List<XmlNode> list, {
      required bool topLevel,
      bool inContainer = false,
    }) {
      for (final node in list) {
        if (node.tag == "layout") layoutOrder[node] = ++order;
        if (node.tag == "togglebutton") {
          final attribute = WasabiCfgAttrib.parse(node["cfgattrib"]);
          if (attribute != null &&
              attribute.setting == null &&
              !cfgToggles.any((t) => t.attribute == attribute)) {
            cfgToggles.add(
              WasabiCfgToggle(attribute, node["tooltip"]?.trim()),
            );
          }
        }
        // An image attribute may name a file instead of a bitmap element
        // (`background="img/bg.png"`).
        if (node.tag != "bitmap" &&
            node.tag != "bitmapfont" &&
            node.tag != "script") {
          for (final MapEntry(:key, :value) in node.attributes.entries) {
            if (!key.startsWith("#") && _imageFile.hasMatch(value)) {
              fileBitmaps.add((value, node["#dir"] ?? root));
            }
          }
        }
        switch (node.tag) {
          case "bitmap":
            bitmapNodes.add((node, node["#dir"] ?? root));
          case "truetypefont":
            fontNodes.add((node, node["#dir"] ?? root));
          case "bitmapfont":
            bitmapFontNodes.add((node, node["#dir"] ?? root));
          case "accelerators":
            // `<accelerators section="x"><accelerator bind="Alt+F"
            // action="MENUHOTKEY_FILE"/></accelerators>`; a table without a
            // section is the general one.
            final section = (node["section"] ?? "general").trim().toLowerCase();
            final table = accelerators.putIfAbsent(section, () => {});
            for (final child in node.children) {
              if (child.tag != "accelerator") continue;
              final bind = child["bind"];
              final action = child["action"];
              if (bind == null || action == null) continue;
              table[wasabiKeyName(bind)] = action.trim();
            }
          case "cursor":
            cursorNodes.add((node, node["#dir"] ?? root));
          case "elementalias":
            final alias = node["id"]?.trim().toLowerCase();
            final target = node["target"]?.trim().toLowerCase();
            if (alias != null &&
                target != null &&
                alias.isNotEmpty &&
                target.isNotEmpty &&
                alias != target) {
              aliases[alias] = target;
            }
          case "color":
            final id = node["id"];
            final value = node["value"];
            if (id != null && value != null) {
              // A color may be another color's id (the Apple-styled skin's
              // `wasabi.list.background` is `color.display.bg`).
              final color =
                  _colorLiteral(value) ??
                  colors[aliases[value.trim().toLowerCase()] ??
                      value.trim().toLowerCase()];
              if (color != null) {
                final key = id.toLowerCase();
                final target = aliases[key] ?? key;
                colors[target] = color;
                // `colorgroup`, else `gammagroup` (skinelem.cpp).
                final group =
                    _named(node["colorgroup"]) ?? _named(node["gammagroup"]);
                if (group == null) {
                  colorGroups.remove(target);
                } else {
                  colorGroups[target] = group;
                }
              }
            }
          case "gammaset":
            // A set defined again starts over, keeping its place
            // (GammaMgr: resetGammaSet, newGammaSet).
            final name = node["id"];
            if (name == null) continue;
            final at = gammaSets.indexWhere(
              (set) => set.name.toLowerCase() == name.toLowerCase(),
            );
            final set = WasabiGammaSet(name);
            if (at < 0) {
              gammaSets.add(set);
            } else {
              gammaSets[at] = set;
            }
            for (final child in node.children) {
              if (child.tag != "gammagroup") continue;
              final id = child["id"];
              final value = child["value"];
              if (id == null || value == null) continue;
              final parts = value.split(",");
              int part(int i) =>
                  i < parts.length ? int.tryParse(parts[i].trim()) ?? 0 : 0;
              set.add(
                WasabiGammaGroup(
                  id: id,
                  red: part(0),
                  green: part(1),
                  blue: part(2),
                  gray: int.tryParse(child["gray"]?.trim() ?? "") ?? 0,
                  boost: (int.tryParse(child["boost"]?.trim() ?? "") ?? 0) != 0,
                ),
              );
            }
          case "groupdef":
            final id = node["id"];
            // Later definitions replace earlier ones, as in the original.
            if (id != null) {
              groupDefs[id.toLowerCase()] = node;
              (groupDefHistory[id.toLowerCase()] ??= []).add((++order, node));
            }
            walk(node.children, topLevel: false);
          case "container":
            if (topLevel || inContainer) {
              containerNodes.add((node, inContainer));
            }
            walk(node.children, topLevel: false, inContainer: true);
          case "script":
            if (node["file"] case final file?) {
              scriptFiles.add((file, node["#dir"] ?? root));
            }
            if (topLevel) {
              scripts.add(
                WasabiObject("script", Map.of(node.attributes), const []),
              );
            }
          case "skininfo":
            for (final child in node.children) {
              final text = child["#text"];
              if (text != null) info[child.tag] = text;
            }
          default:
            walk(
              node.children,
              topLevel: topLevel,
              inContainer: inContainer && node.tag != "layout",
            );
        }
      }
    }

    walk(nodes, topLevel: true);

    // Bitmaps: load each file once. The first definition of an id that
    // loads wins: Wasabi 3 skins such as Lapis Lazuli reuse ids in their
    // standard-frame elements (`glass`), and Wasabi 3 drew the player with
    // the first. Wasabi 5's PaletteManager would pick the last one
    // (findLastItem), which puts the frame's titlebar glass on the player.
    final images = <String, ui.Image?>{};
    final bitmaps = <String, WasabiBitmap>{};
    for (final (node, dir) in bitmapNodes) {
      final id = node["id"];
      final file = node["file"];
      if (id == null || file == null) continue;
      final bitmapKey = aliases[id.toLowerCase()] ?? id.toLowerCase();
      if (bitmaps.containsKey(bitmapKey)) continue;
      if (file.trim().toLowerCase() == r"$gradient") {
        final width = int.tryParse(node["w"] ?? "") ?? 1;
        final height = int.tryParse(node["h"] ?? "") ?? 1;
        final image = await wasabiGradientImage(
          width,
          height,
          renderWasabiGradient(
            width: width,
            height: height,
            mode: node["mode"] ?? "linear",
            x1: double.tryParse(node["gradient_x1"] ?? "") ?? 0,
            y1: double.tryParse(node["gradient_y1"] ?? "") ?? 0,
            x2: double.tryParse(node["gradient_x2"] ?? "") ?? 0,
            y2: double.tryParse(node["gradient_y2"] ?? "") ?? 0,
            points: node["points"] ?? "",
            antialias: (int.tryParse(node["antialias"] ?? "") ?? 0) != 0,
          ),
        );
        if (image != null) {
          bitmaps[bitmapKey] = WasabiBitmap(
            image,
            ui.Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            gammaGroup: _named(node["gammagroup"]),
          );
        }
        continue;
      }
      final path = _resolve(root, dir, file);
      if (path == null) continue;
      final image = images.containsKey(path)
          ? images[path]
          : images[path] = await _decode(path);
      if (image == null) continue;
      // Any of x, y, w and h may be left out: the corner is 0,0 and the
      // size runs to the image's far edge (miniplayer gives `h` alone, for a
      // strip of button states).
      final given = ["x", "y", "w", "h"].any(
        (name) => int.tryParse(node[name] ?? "") != null,
      );
      final x = int.tryParse(node["x"] ?? "") ?? 0;
      final y = int.tryParse(node["y"] ?? "") ?? 0;
      final w = int.tryParse(node["w"] ?? "") ?? image.width - x;
      final h = int.tryParse(node["h"] ?? "") ?? image.height - y;
      // A size of 0 is an empty picture (XENERGY1 keeps its centre and right
      // pieces empty), not the whole image.
      final empty =
          (node["w"]?.trim() == "0" || node["h"]?.trim() == "0") && x >= 0;
      final src = empty
          ? ui.Rect.fromLTWH(x.toDouble(), math.max(y, 0).toDouble(), 0, 0)
          : !given || x < 0 || y < 0 || w <= 0 || h <= 0
          ? ui.Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            )
          : ui.Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              w.toDouble(),
              h.toDouble(),
            );
      bitmaps[bitmapKey] = WasabiBitmap(
        image,
        src,
        gammaGroup: _named(node["gammagroup"]),
      );
    }

    // Image files named where a bitmap element is expected.
    for (final (file, dir) in fileBitmaps) {
      final key = file.toLowerCase();
      if (bitmaps.containsKey(key)) continue;
      final path = _resolve(root, dir, file.trim());
      if (path == null) continue;
      final image = images.containsKey(path)
          ? images[path]
          : images[path] = await _decode(path);
      if (image == null) continue;
      bitmaps[key] = WasabiBitmap(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
    }

    // Cursors: a `.cur`/`.ani` file, or a bitmap element with a hotspot.
    final cursors = <String, MouseCursor>{};
    for (final (node, dir) in cursorNodes) {
      final id = node["id"]?.trim().toLowerCase();
      if (id == null || id.isEmpty) continue;
      final key = aliases[id] ?? id;
      final hotspot = ui.Offset(
        (int.tryParse(node["hotspot_x"] ?? "") ?? 0).toDouble(),
        (int.tryParse(node["hotspot_y"] ?? "") ?? 0).toDouble(),
      );
      final bitmap = node["bitmap"] == null
          ? null
          : bitmaps[aliases[node["bitmap"]!.toLowerCase()] ??
                node["bitmap"]!.toLowerCase()];
      if (bitmap != null) {
        cursors[key] = CustomMouseCursor.fromImage(
          bitmap.source,
          hotspot: hotspot,
        );
        continue;
      }
      final file = node["file"];
      final path = file == null ? null : _resolve(root, dir, file);
      if (path == null) continue;
      try {
        cursors[key] = CustomMouseCursor.memory(WasabiFiles.readBytes(path));
      } on Object {
        // A cursor that cannot be read leaves the default one.
      }
    }

    // The pixels of the bitmaps scripts may load as maps.
    final pixels = Map<ui.Image, ByteData>.identity();
    for (final id in _mapBitmapIds(root, scriptFiles)) {
      final bitmap = bitmaps[id];
      if (bitmap != null) await _readPixels(pixels, bitmap.source);
    }

    final fonts = <String, String>{};
    final loadedFonts = <String, String>{};
    for (final (node, dir) in fontNodes) {
      final id = node["id"];
      final file = node["file"];
      if (id == null || file == null) continue;
      final path = _resolve(root, dir, file);
      if (path == null) continue;
      var family = loadedFonts[path];
      if (family == null) {
        family = "wasabi_font_${_fontRun}_${_fontSerial++}";
        try {
          final bytes = await WasabiFiles.readBytesAsync(path);
          final loader = FontLoader(family)
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
          loadedFonts[path] = family;
        } on Object {
          continue;
        }
      }
      fonts[id.toLowerCase()] = family;
    }

    // Bitmap fonts: `file` names a bitmap element or an image file
    // (BitmapFont::setFontBitmap).
    final bitmapFonts = <String, WasabiBitmapFont>{};
    // The font pictures that are no bitmap element.
    final fontTables = <WasabiBitmap>[];
    for (final (node, dir) in bitmapFontNodes) {
      final id = node["id"];
      final file = node["file"];
      if (id == null || file == null) continue;
      var table = bitmaps[file.toLowerCase()];
      if (table == null) {
        final path = _resolve(root, dir, file);
        if (path == null) continue;
        final image = images.containsKey(path)
            ? images[path]
            : images[path] = await _decode(path);
        if (image == null) continue;
        table = WasabiBitmap(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          gammaGroup: _named(node["gammagroup"]),
        );
        fontTables.add(table);
      }
      final charWidth = int.tryParse(node["charwidth"] ?? "") ?? 0;
      final charHeight = int.tryParse(node["charheight"] ?? "") ?? 0;
      if (charWidth <= 0 || charHeight <= 0) continue;
      bitmapFonts[id.toLowerCase()] = WasabiBitmapFont(
        table: table,
        charWidth: charWidth,
        charHeight: charHeight,
        hSpacing: int.tryParse(node["hspacing"] ?? "") ?? 0,
        vSpacing: int.tryParse(node["vspacing"] ?? "") ?? 0,
      );
    }

    final builder = _TreeBuilder(
      groupDefs,
      bitmaps,
      aliases,
      history: groupDefHistory,
      layoutOrder: layoutOrder,
    );
    final bitmapRegions = Map<WasabiBitmap, List<ui.Rect>?>.identity();
    final containers = <WasabiContainer>[];

    /// The container [node] makes: its layouts with their regions. [id],
    /// [component] and [size] stand in for what the node says (a copy of the
    /// skin's component frame made for one of the player's windows).
    Future<WasabiContainer?> buildContainer(
      XmlNode node,
      bool nested, {
      String? id,
      String? component,
      String? name,
      ui.Size? defaultSize,
    }) async {
      id ??= node["id"];
      if (id == null) return null;
      final layouts = <WasabiLayout>[];
      for (final child in node.children) {
        if (child.tag != "layout") continue;
        final root = builder.buildLayout(child);
        if (defaultSize != null &&
            root.optInt("w") == null &&
            root.optInt("default_w") == null) {
          root.attributes["w"] = "${defaultSize.width.round()}";
          root.attributes["h"] = "${defaultSize.height.round()}";
        }
        final size = _layoutSize(root);
        // A nested container is a script's helper window, sized when the
        // script shows it.
        if (size.isEmpty && !nested) continue;
        // The window region is the pixels with any alpha of the picture the
        // window draws with desktop alpha on, which is always: its
        // `alphabackground` when it has one (its soft glow is part of the
        // window), else the base texture (Layout::desktopAlpha_autoTurnOn).
        final background =
            builder.bitmapOf(child["alphabackground"]) ??
            builder.bitmapOf(child["background"]) ??
            root.background;
        if (background != null) {
          // Objects with `sysregion` add to (or cut from) the shape.
          for (final bitmap in _regionBitmaps(root, bitmaps)) {
            if (bitmapRegions.containsKey(bitmap)) continue;
            bitmapRegions[bitmap] = await alphaRects(bitmap);
          }
        }
        // Layers and buttons that only take the mouse over their pixels.
        for (final bitmap in _shapedLayerBitmaps(root, bitmaps)) {
          if (bitmapRegions.containsKey(bitmap)) continue;
          bitmapRegions[bitmap] = await alphaRects(bitmap);
        }
        layouts.add(
          WasabiLayout(
            id: child["id"] ?? "normal",
            root: root,
            size: size,
            region: background == null ? null : await alphaRegion(background),
          ),
        );
      }
      if (layouts.isEmpty) return null;
      final x = int.tryParse(node["default_x"] ?? "");
      final y = int.tryParse(node["default_y"] ?? "");
      return WasabiContainer(
        id: id.toLowerCase(),
        name: name ?? node["name"] ?? id,
        layouts: layouts,
        defaultPosition: x == null || y == null
            ? null
            : ui.Offset(x.toDouble(), y.toDouble()),
        defaultVisible: (node["default_visible"] ?? "1").trim() != "0",
        dynamic: component == null && (node["dynamic"] ?? "0").trim() == "1",
        component: component ?? node["component"]?.trim().toLowerCase(),
        defaultVisibleExplicit: (node["default_visible"] ?? "").trim() == "1",
      );
    }

    XmlNode? frameNode;
    for (final (node, nested) in containerNodes) {
      final hold = (node["hold"] ?? "").toLowerCase();
      if ((node["dynamic"] ?? "0").trim() == "1" && hold.contains("@all@")) {
        frameNode ??= node;
      }
      final built = await buildContainer(node, nested);
      if (built != null) containers.add(built);
    }

    // The classic player's own default frame (freeform's `components.xml`) when the skin
    // gives none but does draw standard frames.
    if (frameNode == null &&
        groupDefs.containsKey("wasabi.standardframe.statusbar")) {
      if (!groupDefs.containsKey("component.content.group")) {
        for (final node in parseXmlFragment('''
<groupdef id="component.content.group">
  <windowholder x="0" y="0" w="0" relatw="1" h="0" relath="1" hold="@ALL@"/>
</groupdef>''')) {
          groupDefs["component.content.group"] = node;
        }
      }
      frameNode = parseXmlFragment('''
<container id="resizable_status" name=":componenttitle" dynamic="1" hold="@all@">
  <layout id="normal" minimum_h="116" minimum_w="275">
    <Wasabi:StandardFrame:Status id="wasabi.standardframe" x="0" y="0" w="0"
      h="0" relatw="1" relath="1" content="component.content.group"/>
  </layout>
</container>''').first;
    }

    // A window the skin has no container for (the media library, in many
    // skins) goes in a copy of its component frame, as the classic player makes one for
    // each component it holds (`hold="@all@"`, `guid:default`).
    if (frameNode != null) {
      bool has(List<String> ids, List<String> guids) => containers.any(
        (c) =>
            ids.contains(c.id) ||
            (c.component != null && guids.contains(c.component)),
      );
      const frames = {
        "pl": ("guid:pl", Size(275, 232), "Playlist Editor"),
        "library": ("guid:ml", Size(500, 348), "Media Library"),
        "video": ("guid:video", Size(275, 232), "Video"),
        "vis": ("guid:avs", Size(275, 232), "Visualizer"),
      };
      for (final MapEntry(key: kind, value: (guid, size, title))
          in frames.entries) {
        final (ids, guids) = wasabiWindowContainers[kind]!;
        if (has(ids, guids)) continue;
        final copy = await buildContainer(
          frameNode,
          false,
          id: "component.$kind",
          component: guid,
          name: title,
          defaultSize: ui.Size(size.width, size.height),
        );
        if (copy != null) containers.add(copy);
      }
    }

    // Region masks: what the subtracting layers cut out of their window.
    // From the XML rather than the layout trees: scripts build much of a
    // window from groupdefs at run time (Wasabi 5's frame content and its
    // config drawer).
    final regionMasks = <String, List<ui.Rect>>{};
    Future<void> collectMasks(XmlNode node) async {
      for (final child in node.children) {
        final id = child["image"]?.toLowerCase();
        final bitmap = id == null ? null : bitmaps[id];
        if (bitmap != null &&
            (child.tag == "layer" || child.tag == "animatedlayer") &&
            WasabiObject.isSubtractingRegionOp(child["sysregion"]) &&
            !regionMasks.containsKey(id)) {
          final polygons = await alphaRegion(bitmap);
          regionMasks[id!] = polygons == null
              ? [ui.Offset.zero & bitmap.size]
              : [for (final p in polygons) ui.Rect.fromPoints(p[0], p[2])];
        }
        await collectMasks(child);
      }
    }

    for (final node in [
      ...groupDefs.values,
      for (final (node, _) in containerNodes) node,
    ]) {
      await collectMasks(node);
    }

    gammaSets.addAll(customThemes);
    // Kabukichō joins the skin's own themes, unless it has one by that name.
    if (gammaSets.isNotEmpty &&
        !gammaSets.any(
          (set) => set.name.toLowerCase() == wasabiKabukichoTheme.toLowerCase(),
        )) {
      gammaSets.add(wasabiKabukichoGammaSet());
    }

    // The images' pixels are read again for each theme and not kept.
    final colorThemes = WasabiColorThemes(
      sets: gammaSets,
      images: [...bitmaps.values, ...fontTables],
      readPixels: (image) => image.toByteData(),
    );
    // The theme the skin starts with (`GammaMgr::loadDefault`).
    await colorThemes.select(colorTheme ?? defaultColorTheme);

    return WasabiSkinData._(
      name:
          name ??
          info["name"] ??
          directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
      directory: directory,
      info: info,
      bitmaps: bitmaps,
      regionMasks: regionMasks,
      cfgToggles: cfgToggles,
      fonts: fonts,
      bitmapFonts: bitmapFonts,
      colors: colors,
      aliases: aliases,
      cursors: cursors,
      accelerators: accelerators,
      colorGroups: colorGroups,
      colorThemes: colorThemes,
      containers: containers,
      scripts: scripts,
      builder: builder,
      bitmapRegions: bitmapRegions,
      pixels: pixels,
    );
  }

  /// The lower-cased strings of the scripts in [files] that call
  /// `Map.loadMap`: the bitmap ids they may load as maps.
  static Set<String> _mapBitmapIds(String root, List<(String, String)> files) {
    final ids = <String>{};
    final seen = <String>{};
    for (final (file, dir) in files) {
      final path = _resolve(root, dir, file);
      if (path == null || !seen.add(path)) continue;
      try {
        final binary = MakiBinary.parse(WasabiFiles.readBytes(path));
        if (!binary.imports.any(
          (i) =>
              (i.className == "map" && i.name == "loadmap") ||
              (i.className == "region" && i.name == "loadfrombitmap"),
        )) {
          continue;
        }
        for (final variable in binary.variables) {
          final value = variable.initial;
          if (value is String && value.isNotEmpty) {
            ids.add(value.toLowerCase());
          }
        }
      } on Object {
        // The runtime reports scripts it cannot load.
      }
    }
    return ids;
  }

  /// The bitmaps whose shape counts for [layout]'s window region: the
  /// backgrounds of its groups and the images of its `sysregion` layers.
  /// None when nothing in the layout has a `sysregion`.
  static Iterable<WasabiBitmap> _regionBitmaps(
    WasabiObject layout,
    Map<String, WasabiBitmap> bitmaps,
  ) sync* {
    var any = false;
    void find(WasabiObject node) {
      for (final child in node.children) {
        if (child["sysregion"] != null) any = true;
        find(child);
      }
    }

    find(layout);
    if (!any) return;
    Iterable<WasabiBitmap> visit(WasabiObject node) sync* {
      for (final child in node.children) {
        if (child.tag == "group") {
          if (child.background case final background?) yield background;
          yield* visit(child);
        } else if (child["sysregion"] != null &&
            (child.tag == "layer" || child.tag == "animatedlayer")) {
          final image = bitmaps[child["image"]?.toLowerCase()];
          if (image != null) yield image;
        }
      }
    }

    yield* visit(layout);
  }

  /// The images of [layout]'s layers that take the mouse only where they
  /// have pixels ([wasabiShapedLayer]).
  static Iterable<WasabiBitmap> _shapedLayerBitmaps(
    WasabiObject layout,
    Map<String, WasabiBitmap> bitmaps,
  ) sync* {
    for (final child in layout.children) {
      // A button takes the mouse over its picture's pixels unless it says
      // `rectrgn="1"` (the Wasabi 3 convention: Act3scene2's E, P and M).
      final shapedButton =
          (child.tag == "button" ||
              child.tag == "togglebutton" ||
              child.tag == "nstatesbutton") &&
          child["rectrgn"]?.trim() != "1";
      if (wasabiShapedLayer(child) || shapedButton) {
        final image = bitmaps[child["image"]?.toLowerCase()];
        if (image != null) yield image;
      }
      // A group whose background is only its shape clips what it holds to it.
      if (child.tag == "group") {
        final shape = bitmaps[child["background"]?.toLowerCase()];
        if (shape != null &&
            (child["drawbackground"]?.trim() == "0" ||
                child.children.any(
                  (c) => c["sysregion"]?.trim().toLowerCase() == "and",
                ))) {
          yield shape;
        }
      }
      yield* _shapedLayerBitmaps(child, bitmaps);
    }
  }

  static ui.Size _layoutSize(WasabiObject layout) {
    final w = layout.optInt("w") ?? layout.optInt("default_w");
    final h = layout.optInt("h") ?? layout.optInt("default_h");
    final background = layout.background;
    // A layout that says nothing else opens at its background's size, but
    // never below its minimum (Vista's playlist: `w` and `minimum_h`; Cannes'
    // gives only a 21x21 texture and `minimum_w`/`minimum_h`).
    double side(int? explicit, int? fallback, int? minimum) {
      if (explicit != null) return explicit.toDouble();
      final natural = fallback ?? 0;
      return (minimum != null && minimum > natural ? minimum : natural)
          .toDouble();
    }

    return ui.Size(
      side(w, background?.width.round(), layout.optInt("minimum_w")),
      side(h, background?.height.round(), layout.optInt("minimum_h")),
    );
  }

  /// Reads [path] and expands its `<include>`s (paths relative to the
  /// including file). Each node remembers its file's folder in `#dir`.
  static Future<List<XmlNode>> _readXml(
    String path,
    String root,
    Set<String> seen,
  ) async {
    if (!seen.add(path)) return const [];
    final String source;
    try {
      final bytes = await WasabiFiles.readBytesAsync(path);
      source = _decodeText(bytes);
    } on Object {
      return const [];
    }
    final dir = File(path).parent.path;
    final nodes = parseXmlFragment(source);
    _readSkinInfoText(nodes, source);
    return _expand(nodes, dir, root, seen);
  }

  static Future<List<XmlNode>> _expand(
    List<XmlNode> nodes,
    String dir,
    String root,
    Set<String> seen,
  ) async {
    final result = <XmlNode>[];
    for (final node in nodes) {
      if (node.tag == "include") {
        final file = node["file"];
        if (file == null) continue;
        final paths = file.contains("*")
            ? _resolveWildcard(root, dir, file)
            : [?_resolve(root, dir, file, preferDir: true)];
        for (final path in paths) {
          result.addAll(await _readXml(path, root, seen));
        }
        continue;
      }
      node.attributes["#dir"] = dir;
      final children = await _expand(node.children, dir, root, seen);
      node.children
        ..clear()
        ..addAll(children);
      result.add(node);
    }
    return result;
  }

  /// `<skininfo>` children hold text, which the element reader skips; pick
  /// it up separately.
  static void _readSkinInfoText(List<XmlNode> nodes, String source) {
    for (final node in nodes) {
      if (node.tag != "skininfo") {
        _readSkinInfoText(node.children, source);
        continue;
      }
      final match = RegExp(
        r"<skininfo[^>]*>([\s\S]*?)</skininfo>",
        caseSensitive: false,
      ).firstMatch(source);
      if (match == null) return;
      for (final field in RegExp(
        r"<(\w+)[^>]*>([^<]*)</\1>",
      ).allMatches(match[1]!)) {
        final tag = field[1]!.toLowerCase();
        for (final child in node.children) {
          if (child.tag == tag) child.attributes["#text"] = field[2]!.trim();
        }
      }
    }
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static Future<ui.Image?> _decode(String path) async {
    try {
      final bytes = await WasabiFiles.readBytesAsync(path);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } on Object {
      return null;
    }
  }

  /// The files an include with a `*` in its last segment names
  /// (`widgets\load\*.xml`), in name order.
  static List<String> _resolveWildcard(String root, String dir, String file) {
    final relative = file.replaceAll("\\", "/");
    final slash = relative.lastIndexOf("/");
    final folder = slash < 0 ? "" : relative.substring(0, slash);
    final pattern = RegExp(
      "^${RegExp.escape(relative.substring(slash + 1)).replaceAll(r"\*", ".*")}\$",
      caseSensitive: false,
    );
    for (final base in [dir, root]) {
      final found = folder.isEmpty ? base : _findDirectory(base, folder);
      if (found == null) continue;
      final candidates = WasabiFiles.isVirtual(found)
          ? WasabiFiles.filesIn(found)
          : [
              for (final f in Directory(found).listSync().whereType<File>())
                f.path,
            ];
      final files =
          candidates.where((f) => pattern.hasMatch(f.split("/").last)).toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (files.isNotEmpty) return files;
    }
    return const [];
  }

  /// Resolves the folder [relative] under [base], ignoring case.
  static String? _findDirectory(String base, String relative) {
    if (WasabiFiles.isVirtual(base)) {
      return WasabiFiles.findDirectory("$base/$relative");
    }
    var current = base;
    for (final segment in relative.split("/")) {
      if (segment.isEmpty || segment == ".") continue;
      if (segment == "..") {
        current = Directory(current).parent.path;
        continue;
      }
      final dir = Directory(current);
      if (!dir.existsSync()) return null;
      String? match;
      for (final entity in dir.listSync().whereType<Directory>()) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.toLowerCase() == segment.toLowerCase()) {
          match = entity.path;
          break;
        }
      }
      if (match == null) return null;
      current = match;
    }
    return current;
  }

  /// Finds [file] (Windows-style, case-insensitive) relative to the skin
  /// root or [dir]. Element files are relative to the skin root; includes to
  /// the including file ([preferDir]).
  static String? _resolve(
    String root,
    String dir,
    String file, {
    bool preferDir = false,
  }) {
    var relative = file.replaceAll("\\", "/");
    if (relative.contains("@")) {
      // The classic player's path variables: skins that lean on a plugin (the ClassicPro
      // ones) name its files by them. `@COLORTHEMESPATH@` is the classic player's `Skins`
      // folder, with its separator: the skins reach the plugins from it with
      // `\..\..\Plugins`, one `..` for the empty name after the separator.
      final playerRoot = _playerRoot;
      if (playerRoot == null && !relative.contains("@SKINPATH@")) return null;
      relative = relative
          .replaceAll("@WINAMPPATH@", playerRoot ?? "")
          .replaceAll("@COLORTHEMESPATH@", "${playerRoot ?? ""}/Skins/")
          .replaceAll("@SKINPATH@", root.replaceAll("\\", "/"));
    }
    // An absolute path: `/dir/file` or `C:/dir/file`.
    final drive = RegExp(r"^[A-Za-z]:/").hasMatch(relative);
    if (relative.startsWith("/") || drive) {
      // The folders `..` steps out of need not exist. As on Windows, an
      // empty segment (`Skins//..`) is a level that `..` removes.
      final parts = <String>[];
      final segments = relative.substring(drive ? 3 : 0).split("/");
      for (var i = 0; i < segments.length; i++) {
        final part = segments[i];
        if (part == "..") {
          if (parts.isNotEmpty) parts.removeLast();
        } else if (part == ".") {
          continue;
        } else if (part.isNotEmpty || (i > 0 && i < segments.length - 1)) {
          parts.add(part);
        }
      }
      parts.removeWhere((p) => p.isEmpty);
      final base = drive ? relative.substring(0, 3) : "/";
      if (WasabiFiles.isVirtual(base + parts.join("/")) && !drive) {
        return WasabiFiles.findFile("/${parts.join("/")}");
      }
      return _findFile(base, parts.join("/"));
    }
    final bases = preferDir ? [dir, root] : [root, dir];
    for (final base in bases) {
      final found = _findFile(base, relative);
      if (found != null) return found;
    }
    return null;
  }

  /// Resolves [relative] under [base], matching each path segment
  /// case-insensitively like the Windows file system the skins were made on.
  static String? _findFile(String base, String relative) {
    if (WasabiFiles.isVirtual(base)) {
      return WasabiFiles.findFile("$base/$relative");
    }
    final direct = File("$base/$relative");
    if (direct.existsSync()) return direct.path;
    var current = base;
    for (final segment in relative.split("/")) {
      if (segment.isEmpty || segment == ".") continue;
      if (segment == "..") {
        current = Directory(current).parent.path;
        continue;
      }
      final dir = Directory(current);
      if (!dir.existsSync()) return null;
      String? match;
      for (final entity in dir.listSync()) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.toLowerCase() == segment.toLowerCase()) {
          match = entity.path;
          break;
        }
      }
      if (match == null) return null;
      current = match;
    }
    return File(current).existsSync() ? current : null;
  }
}

/// Resolves `<group>` references (and XUI tags such as
/// `<Wasabi:MainFrame:NoStatus>`) into the objects of their `<groupdef>`,
/// and applies `<sendparams>` / `<hideobject>`.
class _TreeBuilder {
  _TreeBuilder(
    this.groupDefs,
    this.bitmaps,
    this.aliases, {
    this.history = const {},
    this.layoutOrder,
  }) : xuiTags = {
         for (final def in groupDefs.values)
           if (def["xuitag"] case final tag?) tag.toLowerCase(): def,
       };

  final Map<String, XmlNode> groupDefs;

  /// Every definition of a groupdef id with its place in the files, and the
  /// place of each layout.
  final Map<String, List<(int, XmlNode)>> history;
  final Map<XmlNode, int>? layoutOrder;

  /// The place of the layout being built.
  int? _asOf;

  /// The groupdef [key] means in the layout being built: the last definition
  /// before the layout when the id is defined more than once.
  XmlNode? _def(String key) {
    final definitions = history[key];
    final at = _asOf;
    if (definitions == null || definitions.length < 2 || at == null) {
      return groupDefs[key];
    }
    XmlNode? found;
    for (final (place, node) in definitions) {
      if (place < at) found = node;
    }
    return found ?? groupDefs[key];
  }

  final Map<String, WasabiBitmap> bitmaps;
  final Map<String, String> aliases;

  /// Groupdefs that define an XUI tag, by lower-cased tag.
  final Map<String, XmlNode> xuiTags;

  /// The groupdefs the classic player's own skin binds to the standard frame tags. A
  /// skin that redefines one (BLAKK's `wasabi.standardframe.nostatusbar`)
  /// without saying `xuitag` again keeps the tag.
  static const Map<String, String> _defaultXuiIds = {
    "wasabi:standardframe:nostatus": "wasabi.standardframe.nostatusbar",
    "wasabi:standardframe:status": "wasabi.standardframe.statusbar",
    "wasabi:standardframe:static": "wasabi.standardframe.static",
    "wasabi:standardframe:modal": "wasabi.standardframe.modal",
  };

  /// The `param` of the default standard frame script: where the frame
  /// puts its content group (x, y, w, h, relatx, relaty, relatw, relath).
  static const Map<String, String> _defaultFrameParams = {
    "wasabi.standardframe.statusbar": "5,15,-10,-34,0,0,1,1",
    "wasabi.standardframe.nostatusbar": "5,15,-10,-20,0,0,1,1",
    "wasabi.standardframe.static": "5,15,-10,-20,0,0,1,1",
    "wasabi.standardframe.modal": "5,15,-10,-20,0,0,1,1",
  };

  XmlNode? _defaultXui(String tag) {
    final id = _defaultXuiIds[tag];
    return id == null ? null : groupDefs[id];
  }

  WasabiBitmap? bitmapOf(String? id) => id == null
      ? null
      : bitmaps[aliases[id.toLowerCase()] ?? id.toLowerCase()];

  WasabiObject buildLayout(XmlNode layout) {
    // With desktop alpha the original draws `alphabackground` when given.
    final background =
        bitmapOf(layout["alphabackground"]) ?? bitmapOf(layout["background"]);
    _asOf = layoutOrder?[layout];
    final root = WasabiObject(
      "layout",
      Map.of(layout.attributes),
      _children(layout.children, const {}),
      background: background,
    );
    _applyParams(root);
    _asOf = null;
    return root;
  }

  /// A new instance of groupdef [id] (`System.newGroup`), or null.
  WasabiObject? newGroup(String id) {
    final key = id.toLowerCase();
    final def = groupDefs[key];
    if (def == null) return null;
    return _group(def, {"id": def["id"] ?? id}, {key});
  }

  List<WasabiObject> _children(List<XmlNode> nodes, Set<String> stack) {
    final result = <WasabiObject>[];
    for (final node in nodes) {
      final object = _build(node, stack);
      if (object != null) result.add(object);
    }
    return result;
  }

  WasabiObject? _build(XmlNode node, Set<String> stack) {
    switch (node.tag) {
      case "script" || "sendparams" || "hideobject":
        // Kept (not drawn): scripts run per group instance, and parameters
        // are applied once the group is complete.
        return WasabiObject(node.tag, Map.of(node.attributes), const []);
      case "groupdef" || "elements" || "layout" || "container":
        return null;
      case "group" || "cfggroup":
        final id = node["id"]?.toLowerCase();
        final def = id == null ? null : _def(id);
        if (def == null || stack.contains(id)) {
          return WasabiObject("group", Map.of(node.attributes), []);
        }
        return _group(def, node.attributes, {...stack, id!});
      default:
        if (node.tag == "wasabi:titlebox" && xuiTags[node.tag] == null) {
          return _titleBox(node, stack);
        }
        if (node.tag == "wasabi:frame" && xuiTags[node.tag] == null) {
          return _frame(node, stack);
        }
        if (xuiTags[node.tag] == null) {
          final builtin = _builtinControl(node, stack);
          if (builtin != null) return builtin;
        }
        final xui = xuiTags[node.tag] ?? _defaultXui(node.tag);
        final xuiId = xui?["id"]?.toLowerCase();
        if (xui != null && xuiId != null && !stack.contains(xuiId)) {
          final group = _group(xui, node.attributes, {...stack, xuiId});
          // The tag's own attributes reach the group's scripts through
          // System.onSetXuiParam.
          group.attributes["#xui"] = [
            for (final key in node.attributes.keys)
              if (!key.startsWith("#")) key,
          ].join(";");
          return group;
        }
        if (node.tag == "componentbucket") {
          final items = _bucketItems(node, stack);
          if (items.isNotEmpty) {
            return WasabiObject(node.tag, Map.of(node.attributes), items);
          }
        }
        if (node.tag == "groupxfade" || node.tag == "customobject") {
          // A group that shows whichever groupdef its `groupid` names (a
          // `<CustomObject>` is the same: ClassicPro's widget holder).
          return WasabiObject("group", {
            ...node.attributes,
            "#xfade": "1",
          }, []);
        }
        return WasabiObject(
          node.tag,
          Map.of(node.attributes),
          _children(node.children, stack),
        );
    }
  }

  /// `<Wasabi:Frame left right orientation from width>` (xuiframe.cpp): two
  /// groups side by side (`orientation="v"`, the default, a vertical divider)
  /// or stacked (`"h"`), the one named by `from` (`l`/`t` by default) is
  /// `width` pixels and the other takes the rest. `top`/`bottom` are other
  /// names for `left`/`right`. `minwidth` and `maxwidth` (negative: from the
  /// frame's size) limit how far the divider is dragged (framewnd.cpp);
  /// `resizable="0"` fixes it. `jump` is not a parameter of the original's
  /// frame.
  WasabiObject _frame(XmlNode node, Set<String> stack) {
    final attributes = Map.of(node.attributes);
    final orientation = (attributes["orientation"] ?? "v").toLowerCase();
    final stacked = orientation == "h" || orientation == "horizontal";
    final from = (attributes["from"] ?? "l").toLowerCase();
    final fromEnd =
        from == "r" || from == "right" || from == "b" || from == "bottom";
    final size =
        int.tryParse(attributes["width"] ?? attributes["height"] ?? "") ?? 128;
    final dividerImage =
        attributes["vbitmap"] ??
        "wasabi.framewnd.${stacked ? "horizontal" : "vertical"}divider";
    final divider = dividerImage.toLowerCase() == "empty"
        ? null
        : bitmaps[dividerImage.toLowerCase()];
    final gap = divider == null
        ? 0
        : (stacked ? divider.height : divider.width).round();

    WasabiObject? pane(String? id, String role) {
      final key = id?.toLowerCase();
      final def = key == null ? null : groupDefs[key];
      if (def == null || stack.contains(key)) return null;
      return _group(def, {"id": id!, "#frame.role": role}, {...stack, key!});
    }

    final sized = fromEnd
        ? (attributes["right"] ?? attributes["bottom"])
        : (attributes["left"] ?? attributes["top"]);
    final rest = fromEnd
        ? (attributes["left"] ?? attributes["top"])
        : (attributes["right"] ?? attributes["bottom"]);
    final resizable = (int.tryParse(attributes["resizable"] ?? "") ?? 1) != 0;
    final children = <WasabiObject>[
      ?pane(sized, "sized"),
      ?pane(rest, "rest"),
      // The divider: its picture, and the strip a drag takes hold of.
      WasabiObject("framedivider", {
        "id": "frame.divider",
        "#frame.role": "divider",
        if (divider != null) "image": dividerImage,
        if (!resizable) "#fixed": "1",
      }, const []),
    ];
    final frame = WasabiObject("group", {
      ...attributes,
      "#frame": "1",
      "#frame.stacked": stacked ? "1" : "0",
      "#frame.fromend": fromEnd ? "1" : "0",
      "#frame.gap": "$gap",
      "#frame.min":
          "${int.tryParse(attributes["minwidth"] ?? attributes["minheight"] ?? "") ?? 0}",
      "#frame.max":
          "${int.tryParse(attributes["maxwidth"] ?? attributes["maxheight"] ?? "") ?? 0}",
    }, children);
    for (final child in children) {
      child.parent = frame;
    }
    layoutWasabiFrame(frame, size);
    return frame;
  }

  /// The controls Wasabi draws itself (`<Wasabi:Text>`, `Button`,
  /// `CheckBox`, `RadioGroup`, `TabSheet`) for a skin that does not define
  /// them, or null for any other tag.
  WasabiObject? _builtinControl(XmlNode node, Set<String> stack) {
    final attributes = Map.of(node.attributes);
    switch (node.tag) {
      case "wasabi:text":
        // Wasabi's text sits at the top of its box.
        attributes.putIfAbsent("valign", () => "top");
        return WasabiObject("text", attributes, const []);
      case "wasabi:button":
        return WasabiObject("wasabibutton", attributes, const []);
      case "wasabi:checkbox":
        final text = attributes["text"] ?? "";
        attributes.putIfAbsent("w", () => "${24 + text.length * 7}");
        attributes.putIfAbsent("h", () => "14");
        return WasabiObject("checkbox", attributes, const []);
      case "wasabi:radiogroup":
        return WasabiObject("radiogroup", attributes, const []);
      case "wasabi:hslider" || "wasabi:vslider":
        attributes["orientation"] = node.tag == "wasabi:vslider"
            ? "vertical"
            : "horizontal";
        attributes["#builtin"] = "1";
        return WasabiObject("slider", attributes, const []);
      case "wasabi:dropdownlist":
        // Scripts read and set the text inside it (`dropdownlist.text`).
        final text = WasabiObject("text", {
          "id": "dropdownlist.text",
          "visible": "0",
        }, const []);
        return WasabiObject("dropdownlist", attributes, [text]);
      case "wasabi:tabsheet":
        final pages = <WasabiObject>[];
        for (final id in (attributes["children"] ?? "").split(";")) {
          final key = id.trim().toLowerCase();
          final def = groupDefs[key];
          if (def == null || stack.contains(key)) continue;
          final page = _group(
            def,
            {"id": id.trim(), "name": def["name"] ?? id.trim()},
            {...stack, key},
          );
          if (pages.isNotEmpty) page.attributes["visible"] = "0";
          pages.add(page);
        }
        return WasabiObject("tabsheet", attributes, pages);
    }
    return null;
  }

  /// `<Wasabi:TitleBox title content>` (xuititlebox.cpp, titlebox.xml in
  /// the original's own skin data): a frame drawn from the skin's
  /// `wasabi.groupbox.*` pieces with the title in its top edge and the group
  /// [content] names inside it.
  WasabiObject _titleBox(XmlNode node, Set<String> stack) {
    WasabiObject layer(String id, String image, Map<String, String> place) =>
        WasabiObject("layer", {"id": id, "image": image, ...place}, const []);
    final title = node["title"] ?? "";
    // The title's width isn't known before the text is laid out; this keeps
    // the frame's top edge from running through it.
    final labelWidth = title.isEmpty ? 0 : 8 + title.length * 7;
    // The classic player draws its own frame for a skin with no `wasabi.groupbox.*`
    // pieces (Ebonite's titleboxes show nothing of one in its data).
    final plain = !bitmaps.containsKey("wasabi.groupbox.top");
    final children = <WasabiObject>[
      if (plain)
        WasabiObject("boxframe", {
          "id": "groupbox.frame",
          "x": "0",
          "y": "6",
          "w": "0",
          "h": "-6",
          "relatw": "1",
          "relath": "1",
          "color": node["color"] ?? "wasabi.text.color",
          "#gap": "$labelWidth",
        }, const [])
      else ...[
        layer("groupbox.bottom", "wasabi.groupbox.bottom", {
          "x": "3",
          "y": "-3",
          "w": "-6",
          "relaty": "1",
          "relatw": "1",
        }),
        layer("groupbox.left", "wasabi.groupbox.left", {
          "x": "0",
          "y": "9",
          "h": "-12",
          "relath": "1",
        }),
        layer("groupbox.right", "wasabi.groupbox.right", {
          "x": "-3",
          "y": "9",
          "h": "-12",
          "relatx": "1",
          "relath": "1",
        }),
        layer("groupbox.bottom.left", "wasabi.groupbox.bottom.left", {
          "x": "0",
          "y": "-3",
          "relaty": "1",
        }),
        layer("groupbox.bottom.right", "wasabi.groupbox.bottom.right", {
          "x": "-3",
          "y": "-3",
          "relatx": "1",
          "relaty": "1",
        }),
        layer("groupbox.top.left", "wasabi.groupbox.top.left", {
          "x": "0",
          "y": "6",
        }),
        layer("groupbox.top.start", "wasabi.groupbox.top", {
          "x": "3",
          "y": "6",
          "w": "3",
        }),
        layer("groupbox.top", "wasabi.groupbox.top", {
          "x": "${6 + labelWidth}",
          "y": "6",
          "w": "${-9 - labelWidth}",
          "relatw": "1",
        }),
        layer("groupbox.top.right", "wasabi.groupbox.top.right", {
          "x": "-3",
          "y": "6",
          "relatx": "1",
        }),
      ],
      if (title.isNotEmpty)
        WasabiObject("text", {
          "id": "titlebox.text",
          "default": title,
          "x": "6",
          "y": "-1",
          "w": "$labelWidth",
          "h": "13",
          "font": "tahoma",
          "fontsize": "14",
          "color": node["color"] ?? "wasabi.text.color",
        }, const []),
    ];
    final content = node["content"]?.toLowerCase();
    final def = content == null ? null : groupDefs[content];
    if (def != null && !stack.contains(content)) {
      children.add(
        _group(
          def,
          {
            "id": "titlebox.content",
            "x": "8",
            "y": "16",
            "w": "-16",
            "h": "-23",
            "relatw": "1",
            "relath": "1",
          },
          {...stack, content!},
        ),
      );
    }
    return WasabiObject(
      "group",
      {
        for (final MapEntry(:key, :value) in node.attributes.entries)
          if (key != "content" && key != "title") key: value,
      },
      children,
    );
  }

  /// What fills a `<componentbucket wndtype="...">`: an instance of every
  /// groupdef of that `windowtype`, in the order the skin defines them,
  /// one after the other along the bucket (`ComponentBucket2::load`,
  /// `onResize`). Amped Modern lists its options pages this way. Empty
  /// for the Thinger's bucket, whose items are the classic player's own.
  List<WasabiObject> _bucketItems(XmlNode bucket, Set<String> stack) {
    final type = bucket["wndtype"]?.toLowerCase();
    if (type == null) return const [];
    int number(String name) => int.tryParse(bucket[name] ?? "") ?? 2;
    final vertical = (bucket["vertical"] ?? "0").trim() == "1";
    final spacing = number("spacing");
    var at = number("leftmargin");
    final items = <WasabiObject>[];
    for (final MapEntry(key: id, value: def) in groupDefs.entries) {
      if (def["windowtype"]?.toLowerCase() != type || stack.contains(id)) {
        continue;
      }
      final extent = int.tryParse(def[vertical ? "h" : "w"] ?? "") ?? 0;
      items.add(
        _group(
          def,
          {
            "id": def["id"] ?? id,
            "x": vertical ? "0" : "$at",
            "y": vertical ? "$at" : "0",
          },
          {...stack, id},
        ),
      );
      at += extent + spacing;
    }
    return items;
  }

  WasabiObject _group(XmlNode def, Map<String, String> use, Set<String> stack) {
    final children = <WasabiObject>[];
    // `inherit_group` pulls in another groupdef's objects first.
    final inherited = def["inherit_group"]?.toLowerCase();
    final parent = inherited == null ? null : groupDefs[inherited];
    if (parent != null && !stack.contains(inherited)) {
      children.addAll(_children(parent.children, {...stack, inherited!}));
    }
    children.addAll(_children(def.children, stack));
    // `inherit_content="scripts"` keeps the scripts of the default definition
    // of the same group: the standard frames' script, which the classic player's own
    // default skin supplies.
    final id = def["id"]?.toLowerCase();
    if ((def["inherit_content"]?.toLowerCase().contains("scripts") ?? false) &&
        id != null &&
        _defaultFrameParams.containsKey(id) &&
        !children.any((c) => c.tag == "script")) {
      children.add(
        WasabiObject("script", {
          "id": "standardframe.script",
          "file": "builtin:standardframe.maki",
          "param": _defaultFrameParams[id]!,
        }, const []),
      );
    }
    // The inheriting groupdef also takes the parent's own attributes, its
    // background among them (Resin's static frame has the base frame's).
    final attributes = {
      if (parent != null && !stack.contains(inherited))
        for (final MapEntry(:key, :value) in parent.attributes.entries)
          if (key != "id" &&
              key != "xuitag" &&
              key != "inherit_group" &&
              !key.startsWith("#"))
            key: value,
      ...def.attributes,
      ...use,
    };
    // The groupdef's id names the group unless the use gives it another;
    // an `instanceid` names this one instance (Amped Modern's title bars
    // tell their two streaks apart by it).
    attributes["id"] = use["instanceid"] ?? use["id"] ?? def["id"] ?? "";
    final group = WasabiObject(
      "group",
      attributes,
      children,
      background:
          bitmapOf(def["background"]) ??
          (parent == null ? null : bitmapOf(parent["background"])),
    );
    _embedXui(group, def["embed_xui"], use);
    _applyParams(group);
    return group;
  }

  /// The parameters a group (and any GuiObject) knows itself: the XML
  /// attributes of an XUI tag that are not these go to the object its
  /// groupdef embeds (`EmbeddedXuiObject::onUnknownXuiParam`).
  static const Set<String> _groupParams = {
    "activealpha",
    "alpha",
    "anchor",
    "appbar",
    "autoheightsource",
    "autowidthsource",
    "background",
    "default_h",
    "default_w",
    "design_h",
    "design_w",
    "drawbackground",
    "droptarget",
    "embed_xui",
    "enabled",
    "fitparent",
    "focusonclick",
    "ghost",
    "h",
    "id",
    "inactivealpha",
    "inherit_content",
    "inherit_group",
    "instanceid",
    "lockminmax",
    "maximum_h",
    "maximum_w",
    "minimum_h",
    "minimum_w",
    "move",
    "name",
    "nocontextmenu",
    "nodblclick",
    "noleftclick",
    "nomousemove",
    "norightclick",
    "notify",
    "notify0",
    "notify1",
    "notify2",
    "notify3",
    "notify4",
    "notify5",
    "notify6",
    "notify7",
    "notify8",
    "notify9",
    "propagatesize",
    "rectrgn",
    "regionop",
    "relath",
    "relatw",
    "relatx",
    "relaty",
    "renderbasetexture",
    "sysmetricsh",
    "sysmetricsw",
    "sysmetricsx",
    "sysmetricsy",
    "sysregion",
    "taborder",
    "tooltip",
    "translate",
    "userdata",
    "visible",
    "w",
    "wantfocus",
    "x",
    "x1",
    "x2",
    "xuitag",
    "y",
    "y1",
    "y2",
  };

  /// `embed_xui="id"` on a groupdef: the tag that uses it is, for its
  /// parameters, the object [embedded] names inside it (Bento's
  /// `<Bento:TabButton text="...">` is the button in its group). What the
  /// group does not know, and its `cfgattrib`, go to that object.
  static void _embedXui(
    WasabiObject group,
    String? embedded,
    Map<String, String> use,
  ) {
    final id = embedded?.trim().toLowerCase();
    if (id == null || id.isEmpty) return;
    WasabiObject? find(WasabiObject node) {
      for (final child in node.children) {
        if (child.id.toLowerCase() == id) return child;
      }
      for (final child in node.children) {
        final found = find(child);
        if (found != null) return found;
      }
      return null;
    }

    final target = find(group);
    if (target == null || identical(target, group)) return;
    for (final MapEntry(:key, :value) in use.entries) {
      final name = key.toLowerCase();
      if (name.startsWith("#")) continue;
      if (_groupParams.contains(name) && name != "cfgattrib") continue;
      target.attributes[name] = value;
    }
  }

  /// Applies a group's `<sendparams target="a;b" attr="..."/>` and
  /// `<hideobject target="a;b"/>` to the named objects inside it.
  static void _applyParams(WasabiObject group) {
    // A static or modal standard frame has no way to resize its window,
    // whatever ids its `sendparams` name (Flo's are not its own layers').
    final tag = (group["xuitag"] ?? "").toLowerCase();
    if (tag == "wasabi:standardframe:static" ||
        tag == "wasabi:standardframe:modal") {
      void fix(WasabiObject node) {
        for (final c in node.children) {
          if (c.attributes.containsKey("resize")) c.attributes["resize"] = "0";
          fix(c);
        }
      }

      fix(group);
    }
    for (final child in group.children) {
      if (child.tag != "sendparams" && child.tag != "hideobject") continue;
      final targets = (child["target"] ?? "")
          .split(";")
          .map((t) => t.trim().toLowerCase())
          .where((t) => t.isNotEmpty)
          .toSet();
      // A `<hideobject>` hides the first object of each name, as the
      // original finds one object per target: Amped Modern's player hides
      // the frame's `close` and then adds a `Close` button of its own.
      final toHide = child.tag == "hideobject" ? {...targets} : null;
      void visit(WasabiObject node) {
        for (final c in node.children) {
          if (targets.contains(c.id.toLowerCase())) {
            if (toHide != null) {
              if (toHide.remove(c.id.toLowerCase())) {
                c.attributes["visible"] = "0";
              }
            } else {
              for (final MapEntry(key: key, value: value)
                  in child.attributes.entries) {
                if (key != "target" && key != "group" && !key.startsWith("#"))
                  c.attributes[key] = value;
              }
            }
          }
          visit(c);
        }
      }

      // `group="..."` sends them to the objects of that group only.
      final within = child["group"]?.trim().toLowerCase();
      if (within == null || within.isEmpty) {
        visit(group);
      } else {
        void seek(WasabiObject node) {
          for (final c in node.children) {
            if (c.id.toLowerCase() == within) {
              visit(c);
            } else {
              seek(c);
            }
          }
        }

        seek(group);
      }
    }
  }
}

/// Places a `Wasabi:Frame`'s two groups and its divider for a divider
/// [size] pixels from the `from` edge: the sized group is [size] wide (or
/// high), the divider follows it, and the other group has the rest.
void layoutWasabiFrame(WasabiObject frame, int size) {
  final stacked = frame["#frame.stacked"] == "1";
  final fromEnd = frame["#frame.fromend"] == "1";
  final gap = int.tryParse(frame["#frame.gap"] ?? "") ?? 0;
  frame.attributes["#frame.size"] = "$size";
  // The axis along the frame, and the one across.
  final along = stacked ? "y" : "x";
  final length = stacked ? "h" : "w";
  final across = stacked ? ("x", "w") : ("y", "h");
  void place(WasabiObject o, int at, int extent, {required bool end}) {
    o.attributes
      ..[across.$1] = "0"
      ..[across.$2] = "0"
      ..["relat${across.$2}"] = "1"
      ..[along] = "$at"
      ..[length] = "$extent"
      ..["relat$along"] = end ? "1" : "0"
      ..["relat$length"] = extent <= 0 && !end ? "1" : "0";
  }

  for (final child in frame.children) {
    switch (child.attributes["#frame.role"]) {
      case "sized":
        if (fromEnd) {
          place(child, -size, size, end: true);
        } else {
          place(child, 0, size, end: false);
        }
      case "rest":
        // The sized group and the divider are taken off the rest.
        if (fromEnd) {
          place(child, 0, -(size + gap), end: false);
        } else {
          place(child, size + gap, -(size + gap), end: false);
        }
        child.attributes["relat$length"] = "1";
      case "divider":
        // A strip over the edge, a few pixels wide when the skin draws
        // none, so there is something to take hold of.
        final thick = gap > 0 ? gap : 4;
        if (fromEnd) {
          place(child, -(size + gap) - (gap > 0 ? 0 : 2), thick, end: true);
        } else {
          place(child, size - (gap > 0 ? 0 : 2), thick, end: false);
        }
    }
  }
}
