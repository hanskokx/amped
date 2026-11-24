import "dart:ui";

import "package:amped_skin/amped_skin.dart";

import "wasabi_skin_data.dart";
import "wasabi_view.dart";

/// A Wasabi skin (`.wal` or a modern `.wsz`) with its containers, layouts
/// and the state the user changes in it.
final class ModernSkin extends Skin {
  /// [data] on top of [base], with the layouts it was switched to, the sizes
  /// it was dragged to and the windows it was left with brought back from
  /// [_storage].
  ModernSkin(super.info, this.data, this.base, this._storage) {
    _restoreExtraOpen();
    _restoreChoices();
  }

  final WasabiSkinData data;
  final SkinStorage _storage;

  @override
  final Skin base;

  @override
  void followShades(bool Function(SkinWindow window) isShaded) {
    super.followShades(isShaded);
    base.followShades(isShaded);
  }

  /// The layout the notifier's script showed (`Layout.show`), or null.
  String? notifierLayout;

  /// The layout each container was switched to, by container id
  /// (`Container.switchToLayout`, a `SWITCH` action).
  final Map<String, String> _choice = {};

  /// What was left open, by container id, and null for what was not touched
  /// yet.
  final Map<String, bool> _extraOpen = {};

  String get _extraOpenPrefix => "amped.extra_open.$name/";

  /// The containers that are no window of the player's own, each in a slot
  /// of its own ([SkinWindow.extras]).
  List<WasabiContainer> get _extraContainers =>
      data.extraContainers.take(SkinWindow.extras.length).toList();

  /// Panels that open with the skin when it says so, unless they are only
  /// its readme, tooltips or settings: those wait in the Skin Windows list.
  static final RegExp _quietPanel = RegExp(
    r"readme|tooltip|about|manual|pref|config|configure|colou?r|message|"
    r"browser|notifier|photo|pic|cthemes|theme|help|how|ad$|install|please|"
    r"mspp|credit|info|update|warn|note",
    caseSensitive: false,
  );

  bool _opensWithSkin(WasabiContainer container) =>
      container.defaultVisibleExplicit &&
      !_quietPanel.hasMatch(container.id) &&
      !_quietPanel.hasMatch(container.name);

  /// Whether the skin's own window for [container] is open: as it was left,
  /// else as the skin asks.
  bool isExtraOpen(WasabiContainer container) =>
      _extraOpen[container.id] ?? _opensWithSkin(container);

  /// Opens or closes the skin's own window for [container] and remembers
  /// it; true when that changed what was left.
  bool setExtraOpen(WasabiContainer container, bool open) {
    final changed = (_extraOpen[container.id] ?? false) != open;
    _extraOpen[container.id] = open;
    _storage.setBool("$_extraOpenPrefix${container.id}", value: open);
    return changed;
  }

  void _restoreExtraOpen() {
    for (final key in _storage.keys) {
      if (!key.startsWith(_extraOpenPrefix)) continue;
      final open = _storage.getBool(key);
      if (open != null) {
        _extraOpen[key.substring(_extraOpenPrefix.length)] = open;
      }
    }
  }

  /// The names that mark a skin's window as its settings.
  static final RegExp _settingsPanel = RegExp(
    r"config|prefer|setting|option|colou?r|theme|customi[sz]e",
    caseSensitive: false,
  );

  (SkinWindow, WasabiContainer)? get settingsWindow {
    for (final entry in windows) {
      final container = entry.$2;
      if (_settingsPanel.hasMatch(container.id) ||
          _settingsPanel.hasMatch(container.name)) {
        return entry;
      }
    }
    return null;
  }

  List<(SkinWindow, WasabiContainer)> get windows => [
    for (final window in SkinWindow.extras)
      if (container(window) case final container?) (window, container),
  ];

  WasabiContainer? container(SkinWindow window) {
    // The container ids Wasabi skins use for each window, in preference
    // order; older skins call them anything, which their component's guid
    // then tells (see [wasabiWindowContainers]).
    if (window == SkinWindow.notifier) return data.notifierContainer;
    final kind = switch (window) {
      SkinWindow.eq => "eq",
      SkinWindow.pl => "pl",
      SkinWindow.video => "video",
      SkinWindow.library => "library",
      SkinWindow.vis => "vis",
      _ => null,
    };
    if (kind != null) return data.windowContainer(kind);
    if (window.isExtra) {
      final extras = _extraContainers;
      final slot = window.index - SkinWindow.extra0.index;
      return slot < extras.length ? extras[slot] : null;
    }
    // Amped Modern's album art window (`xml/albumart.xml`), or the skin's
    // own "Album Art" container.
    if (window == SkinWindow.albumArt) return data.albumArtContainer;
    final id = window == SkinWindow.thinger ? "thinger" : "main";
    return data.container(id);
  }

  WasabiLayout? layout(SkinWindow window) {
    final container = this.container(window);
    if (container == null) return null;
    // The notifier has the layout its script showed.
    if (window == SkinWindow.notifier) {
      return container.layout(notifierLayout ?? "desktopalpha") ??
          container.layout("normal") ??
          container.layouts.first;
    }
    // The layout a script switched the container to (a skin's own window
    // modes: Ebonite's compact, mini and stick layouts).
    final chosen = _choice[container.id];
    if (chosen != null) {
      final layout = container.layout(chosen);
      if (layout != null) return layout;
    }
    if (isShaded(window)) {
      final shade =
          container.layout("shade") ??
          container.layout("winshade") ??
          container.layouts
              .where((l) => l.id.toLowerCase().contains("shade"))
              .firstOrNull;
      if (shade != null) return shade;
    }
    return container.layout("normal") ?? container.layouts.first;
  }

  @override
  bool hasModernLook(SkinWindow window) => layout(window) != null;

  /// The polygons that cut [window] to its shape, with the layouts of the
  /// windows the skin draws over it as [companions].
  @override
  List<List<Offset>>? shape(
    SkinWindow window, {
    List<WasabiLayout> companions = const [],
  }) {
    final layout = this.layout(window);
    if (layout == null) return base.shape(window);
    return wasabiWindowShape(data, layout, companions: companions);
  }

  @override
  Size? get mainSize => layout(SkinWindow.main) == null ? base.mainSize : null;

  SkinWindow? windowForContainer(String id) {
    for (final window in SkinWindow.values) {
      if (container(window)?.id.toLowerCase() == id.toLowerCase()) {
        return window;
      }
    }
    return null;
  }

  @override
  bool get ownsNotifier =>
      container(SkinWindow.notifier) == null || data.scripts.isEmpty;

  String _sizeKey(WasabiContainer container, WasabiLayout layout) =>
      "wasabi.size.$name.${container.id}.${layout.id}";

  /// Gives the layouts the sizes the user dragged them to.
  void restoreSizes() {
    for (final container in data.containers) {
      for (final layout in container.layouts) {
        final saved = _storage.getStringList(_sizeKey(container, layout));
        if (saved == null || saved.length != 2) continue;
        layout.root.attributes
          ..["w"] = saved[0]
          ..["h"] = saved[1];
      }
    }
  }

  /// [size] (layout pixels) kept within [layout]'s minimum and maximum
  /// size.
  Size clampSize(WasabiLayout layout, Size size) {
    final root = layout.root;
    double clampTo(double v, String min, String max) => v.roundToDouble().clamp(
      (root.optInt(min) ?? 16).toDouble(),
      (root.optInt(max) ?? 8000).toDouble(),
    );
    return Size(
      clampTo(size.width, "minimum_w", "maximum_w"),
      clampTo(size.height, "minimum_h", "maximum_h"),
    );
  }

  /// Gives [layout] of [container] the [size] the user dragged it to, with
  /// the layouts linked to it, and remembers both.
  void resizeLayout(WasabiContainer container, WasabiLayout layout, Size size) {
    layout.root.attributes
      ..["w"] = "${size.width.round()}"
      ..["h"] = "${size.height.round()}";
    _linkLayouts(container, layout, size);
    _storage.setStringList(_sizeKey(container, layout), [
      "${size.width.round()}",
      "${size.height.round()}",
    ]);
  }

  /// A layout resized: the layouts of its container it is linked to
  /// (`linkwidth="shade"`, `linkheight`) take its width or height, unless
  /// either is `unlinked` (`Layout::onResize`).
  void _linkLayouts(WasabiContainer container, WasabiLayout layout, Size size) {
    bool unlinked(WasabiLayout l) => l.root["unlinked"]?.trim() == "1";
    for (final (attribute, width) in const [
      ("linkwidth", true),
      ("linkheight", false),
    ]) {
      final name = layout.root[attribute]?.trim();
      if (name == null || name.isEmpty) continue;
      final other = container.layout(name);
      if (other == null || identical(other, layout)) continue;
      if (unlinked(other) || unlinked(layout)) continue;
      final key = width ? "w" : "h";
      final value = (width ? size.width : size.height).round();
      if (other.root[key] == "$value") continue;
      other.root.attributes[key] = "$value";
      final area = other.size;
      _storage.setStringList(_sizeKey(container, other), [
        "${area.width.round()}",
        "${area.height.round()}",
      ]);
    }
  }

  String _choiceKey(String containerId) =>
      "amped.modern_layout.$name/$containerId";

  void choose(WasabiContainer container, WasabiLayout layout) {
    _choice[container.id] = layout.id;
    _storage.setString(_choiceKey(container.id), layout.id);
  }

  /// Forgets the layout [container] was switched to, in memory and saved;
  /// true when there was one.
  bool unchoose(WasabiContainer container) {
    if (_choice.remove(container.id) == null) return false;
    _storage.remove(_choiceKey(container.id));
    return true;
  }

  void _restoreChoices() {
    for (final container in data.containers) {
      final name = _storage.getString(_choiceKey(container.id));
      final layout = name == null ? null : container.layout(name);
      if (layout != null) _choice[container.id] = layout.id;
    }
  }
}
