import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:ui" as ui;

import "package:amped_logging/amped_logging.dart";
import "package:amped_vis/amped_vis.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";

import "maki/maki_runtime.dart";
import "wasabi_config.dart";
import "wasabi_gamma.dart";
import "wasabi_host.dart";
import "wasabi_menu.dart";
import "wasabi_skin_data.dart";
import "wasabi_view.dart";

/// A [WasabiHost] for showing a skin without playing anything: a song
/// called [title] part-way through, a short made-up playlist, no
/// visualization, and controls that do nothing.
class WasabiPreviewHost extends ChangeNotifier implements WasabiHost {
  WasabiPreviewHost({required this.title, this.storage});

  final String title;

  /// Where the skin's settings are kept for real, such as the options it
  /// offers. Read through; written to only while [writeThrough] is set, so
  /// what the skin does by itself on starting does not change anything.
  final WasabiHost? storage;

  /// Whether settings the skin writes are kept in [storage] too.
  bool writeThrough = false;

  final Map<String, String> _private = {};
  final Map<WasabiCfgAttrib, int> _config = {};

  static const List<(String, int)> _playlist = [
    ("Amped - First Demo Track", 196000),
    ("Amped - Second Demo Track", 241000),
    ("Amped - Third Demo Track", 178000),
    ("Amped - Fourth Demo Track", 305000),
    ("Amped - Fifth Demo Track", 212000),
    ("Amped - Sixth Demo Track", 167000),
  ];

  @override
  String get songTitle => title;

  @override
  String get trackTitle => title;

  @override
  String get songInfoText => "";

  @override
  bool get videoPlaying => false;

  @override
  bool get videoFullscreen => false;

  /// The made-up song's artist and title: [title] cut at its first dash.
  @override
  String playItemMetadata(String name) {
    final cut = title.indexOf(" - ");
    if (cut < 0) return name.toLowerCase() == "title" ? title : "";
    return switch (name.toLowerCase()) {
      "artist" => title.substring(0, cut),
      "title" => title.substring(cut + 3),
      _ => "",
    };
  }

  @override
  ui.Rect get viewport => const ui.Rect.fromLTWH(0, 0, 640, 480);

  @override
  double layoutScale(String container) => 1;

  @override
  bool get appMinimized => false;

  @override
  void activateApplication() {}

  @override
  String get videoInfoText => "";

  @override
  int get lengthMs => 196000;

  @override
  int get positionMs => 61000;

  @override
  bool get timeRemaining => false;

  @override
  void toggleTimeRemaining() {}

  @override
  bool isActive(String action, String? param) => false;

  @override
  void runAction(WasabiAction action) {}

  @override
  int configValue(WasabiCfgAttrib attribute) => _config[attribute] ?? 0;

  @override
  void setConfigValue(WasabiCfgAttrib attribute, int value) {
    _config[attribute] = value;
    notifyListeners();
  }

  @override
  Future<void> openMenu(WasabiMenuRequest request) async {}

  @override
  double? sliderValue(String action, String? param) => 0.5;

  @override
  void setSliderValue(
    String action,
    String? param,
    double value, {
    required bool done,
  }) {}

  @override
  int get playbackStatus => 1;

  @override
  String get playItemLocation => "";

  @override
  ui.Image? get albumArt => null;

  @override
  ui.Offset get cursorPosition => ui.Offset.zero;

  @override
  ui.Offset? windowOrigin(String id) => null;

  @override
  ui.Image? get onlineAlbumArt => null;

  @override
  bool get albumArtLoading => false;

  @override
  void refreshAlbumArt() {}

  @override
  void pressAlbumArtMenu(PointerDownEvent event) {}

  @override
  void showAlbumArtMenu() {}

  @override
  void openAlbumArtFolder() {}

  @override
  void pressSecondaryAction(WasabiAction action, PointerDownEvent event) {}

  @override
  void seekTo(int ms) {}

  @override
  void showPopup(
    List<WasabiPopupItem> items,
    void Function(int id) chosen,
  ) {}

  @override
  void openPath(String path, {required bool play}) {}

  @override
  void revealPath(String path) {}

  @override
  void openFolder(String path) {}

  @override
  void openExternal(String path) {}

  @override
  String? readPrivate(String section, String item) =>
      _private["$section/$item"] ?? storage?.readPrivate(section, item);

  @override
  void writePrivate(String section, String item, String value) {
    _private["$section/$item"] = value;
    if (writeThrough) storage?.writePrivate(section, item, value);
  }

  @override
  bool isContainerVisible(String id) => false;

  /// A preview shows its windows as they look in front.
  @override
  bool isContainerActive(String id) => true;

  @override
  void setContainerVisible(String id, bool visible) {}

  @override
  String? currentLayout(String id) => null;

  @override
  void resizeLayout(String container, WasabiLayout layout, Size size) {
    layout.root.attributes
      ..["w"] = "${size.width.round()}"
      ..["h"] = "${size.height.round()}";
  }

  @override
  int get playlistLength => _playlist.length;

  @override
  String playlistTitle(int index) => _playlist[index].$1;

  @override
  int playlistItemLengthMs(int index) => _playlist[index].$2;

  @override
  int get playlistCurrent => 0;

  @override
  String playlistLocation(int index) => "";

  @override
  String playlistMetadata(int index, String name) => "";

  @override
  void removePlaylistItem(int index) {}

  @override
  void clearPlaylist() {}

  @override
  void movePlaylistItem(int from, int to) {}

  @override
  void switchSkin(String name) {}

  @override
  ui.Rect? get appRect => null;

  @override
  void centerWindow(String container) {}

  @override
  void focusWindow(String container) {}

  @override
  bool isPlaylistSelected(int index) => false;

  @override
  void selectPlaylistItem(
    int index, {
    required bool extend,
    required bool toggle,
  }) {}

  @override
  void playPlaylistItem(int index) {}

  @override
  List<int> searchPlaylist(String query) => const [];

  @override
  void pressPlaylistMenu(int? index, PointerDownEvent event) {}

  @override
  void showPlaylistMenu() {}

  @override
  ClassicVisOptions get visOptions => const ClassicVisOptions();

  @override
  void clickVis() {}

  @override
  bool get visRunning => false;

  @override
  void startVisualization() {}

  @override
  void stopVisualization() {}

  @override
  (Float32List, Float32List)? get visSamples => null;
}

/// A modern skin loaded and run on its own, to look at and to change the
/// settings of without putting it on: its color themes and the options its
/// scripts offer. Nothing here touches the skin that is on.
///
/// The skin runs against a [WasabiPreviewHost] showing a made-up song called
/// [title]. Its options are read from [storage]; changes to them are held
/// ([toggleOption]) until [commitOptions] writes them there. Color themes are
/// not saved by the controller.
class WasabiSkinPreviewController extends ChangeNotifier {
  WasabiSkinPreviewController({
    required this.directory,
    required this.name,
    required this.title,
    required this.settings,
    this.storage,
  }) {
    _load();
  }

  /// Amped Modern's option that shows its equalizer in the main window.
  static const String _equalizerOption = "Equalizer\tAlt+G";

  final Directory directory;
  final String name;
  final String title;
  final WasabiHost? storage;

  /// The color theme the skin is saved in (null: its default) and the
  /// user's own themes for it.
  final Future<(String?, List<WasabiGammaSet>)> Function() settings;

  WasabiSkinData? _skin;
  WasabiScriptRuntime? _scripts;
  WasabiPreviewHost? _host;
  bool _failed = false;
  bool _disposed = false;
  String? _savedTheme;
  String _savedCustom = "";

  /// The loaded skin, or null while it loads or when it cannot be loaded.
  WasabiSkinData? get skin => _skin;

  WasabiScriptRuntime? get scripts => _scripts;

  WasabiPreviewHost? get host => _host;

  bool get failed => _failed;

  bool get loaded => _skin != null;

  /// The options the skin's scripts offer.
  List<WasabiSkinOption> get options =>
      _scripts?.skinOptions ?? const <WasabiSkinOption>[];

  /// The switches the skin's own windows carry.
  List<WasabiSkinOption> get switches =>
      _scripts?.skinSwitches ?? const <WasabiSkinOption>[];

  /// The user's custom color themes now in the skin.
  List<WasabiGammaSet> get customThemes => [
    for (final set in _skin?.colorThemes.sets ?? const <WasabiGammaSet>[])
      if (set.custom) set,
  ];

  static String _signature(List<WasabiGammaSet> sets) =>
      sets.map((set) => jsonEncode(set.toJson())).join("\n");

  /// Whether the color theme chosen or the custom themes differ from what
  /// was saved.
  bool get themeDirty {
    final themes = _skin?.colorThemes;
    if (themes == null) return false;
    return themes.current?.name != _savedTheme ||
        _signature(customThemes) != _savedCustom;
  }

  /// Takes the themes as they are for what is saved.
  void markThemesSaved() {
    _savedTheme = _skin?.colorThemes.current?.name;
    _savedCustom = _signature(customThemes);
    notifyListeners();
  }

  Future<void> _load() async {
    try {
      final (theme, customs) = await settings();
      final skin = await WasabiSkinData.load(
        directory,
        name: name,
        colorTheme: theme,
        customThemes: customs,
      );
      if (_disposed) return;
      final host = WasabiPreviewHost(title: title, storage: storage);
      final scripts = WasabiScriptRuntime(
        skin: skin,
        host: host,
        log: (_) {},
      )..start();
      // The equalizer, not the visualization.
      if (scripts.hasConfigAttribute(_equalizerOption)) {
        scripts.setConfigAttribute(_equalizerOption, "1");
      }
      _matchPlaylistWidth(skin, scripts);
      _openDrawerSoon(skin, scripts);
      _skin = skin;
      _host = host;
      _scripts = scripts;
      _savedTheme = skin.colorThemes.current?.name;
      _savedCustom = _signature(customThemes);
      skin.colorThemes.addListener(notifyListeners);
      scripts.addListener(notifyListeners);
      notifyListeners();
    } on Object catch (error) {
      Arcane.log(
        "Could not load a preview",
        level: Level.warning,
        module: "WasabiPreview",
        metadata: {"name": name, "error": "$error"},
      );
      if (_disposed) return;
      _failed = true;
      notifyListeners();
    }
  }

  /// Whether [node] is the button a skin opens a drawer with: Anexa's `>>`
  /// is a button named `colour.sets.toggle`, the iPhone skin's equalizer
  /// button a toggle button named `eqbt`.
  static bool _opensDrawer(WasabiObject node) {
    final id = node.id.toLowerCase();
    return switch (node.tag) {
      "button" => id.contains("toggle"),
      "togglebutton" => id == "eqbt",
      _ => false,
    };
  }

  /// Presses the button a skin opens its drawer with, a moment after the
  /// preview shows, so the skin's own script slides it open.
  void _openDrawerSoon(WasabiSkinData skin, WasabiScriptRuntime scripts) {
    final layout = skin.container("main")?.layout("normal");
    if (layout == null) return;
    WasabiObject? toggle;
    void find(WasabiObject node) {
      if (toggle != null) return;
      if (_opensDrawer(node) && scripts.scriptObjectOf(node) != null) {
        toggle = node;
        return;
      }
      node.children.forEach(find);
    }

    find(layout.root);
    final button = toggle;
    if (button == null) return;
    _drawerTimer = Timer(const Duration(milliseconds: 700), () {
      if (_disposed) return;
      if (button.tag == "togglebutton") {
        scripts.buttonClicked(button);
        return;
      }
      // As a click on it: scripts read the pointer's position.
      scripts
        ..pointer(button, "onLeftButtonDown", Offset.zero)
        ..pointer(button, "onLeftButtonUp", Offset.zero);
    });
  }

  Timer? _drawerTimer;

  /// Makes the playlist editor as wide as the main window, as far as the
  /// skin lets it be resized.
  static void _matchPlaylistWidth(
    WasabiSkinData skin,
    WasabiScriptRuntime scripts,
  ) {
    final mainContainer = skin.container("main");
    final main =
        mainContainer?.layout("normal") ?? mainContainer?.layouts.firstOrNull;
    final container = skin.windowContainer("pl");
    final layout = container?.layout("normal") ?? container?.layouts.first;
    if (main == null || layout == null) return;
    final width = main.size.width.round();
    final root = layout.root;
    // A skin drawing its main window over the playlist editor (the Apple-styled skin)
    // has that window as big as the one drawn over it.
    final over = scripts.companionsOf(layout);
    if (over.isNotEmpty) {
      final size = over.first.$2.size;
      root.attributes
        ..["w"] = "${size.width.round()}"
        ..["h"] = "${size.height.round()}";
      scripts
        ..layoutResized(layout)
        ..changed();
      return;
    }
    if (layout.size.width.round() == width) return;
    final min = root.optInt("minimum_w");
    final max = root.optInt("maximum_w");
    if ((min != null && width < min) || (max != null && width > max)) return;
    root.attributes["w"] = "$width";
    scripts
      ..layoutResized(layout)
      ..changed();
  }

  /// The options changed since they were last kept, by name and new value
  /// ("1" or "0").
  final Map<String, String> _pendingOptions = {};

  /// What each changed option was before the first change.
  final Map<String, String> _originalOptions = {};

  Map<String, String> get pendingOptions => Map.unmodifiable(_pendingOptions);

  bool get optionsDirty => _pendingOptions.isNotEmpty;

  /// Whether anything was changed that [commitOptions] or the saving of the
  /// color themes would keep.
  bool get changed => themeDirty || optionsDirty;

  /// Flips the check box [option] on the preview only; [commitOptions] keeps
  /// the change.
  void toggleOption(WasabiSkinOption option) {
    final scripts = _scripts;
    if (scripts == null) return;
    final before = option.checked ? "1" : "0";
    scripts.toggleSkinOption(option);
    final after = option.checked ? "1" : "0";
    final original = _originalOptions.putIfAbsent(option.key, () => before);
    if (after == original) {
      _pendingOptions.remove(option.key);
      _originalOptions.remove(option.key);
    } else {
      _pendingOptions[option.key] = after;
    }
    notifyListeners();
  }

  /// Keeps the changed options, where the skin keeps its settings.
  void commitOptions() {
    final scripts = _scripts;
    final host = _host;
    if (scripts == null || host == null || _pendingOptions.isEmpty) return;
    host.writeThrough = true;
    try {
      for (final MapEntry(:key, :value) in _pendingOptions.entries) {
        scripts.setConfigAttribute(key, value);
      }
    } finally {
      host.writeThrough = false;
    }
    _pendingOptions.clear();
    _originalOptions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _drawerTimer?.cancel();
    _scripts?.removeListener(notifyListeners);
    _skin?.colorThemes.removeListener(notifyListeners);
    _scripts?.dispose();
    _scripts = null;
    super.dispose();
  }
}

/// The skin of [controller] as it looks: its main window with its equalizer
/// (Amped Modern keeps that in the main window's drawer) and its playlist
/// editor beneath. Not interactive.
class WasabiSkinPreview extends StatelessWidget {
  const WasabiSkinPreview({
    required this.controller,
    this.placeholder,
    super.key,
  });

  final WasabiSkinPreviewController controller;

  /// What shows while the skin loads, or when it cannot be loaded.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final skin = controller.skin;
        final host = controller.host;
        final scripts = controller.scripts;
        if (skin == null || host == null || scripts == null) {
          return placeholder ?? const SizedBox.shrink();
        }
        final windows = <Widget>[];
        // A skin whose scripts draw the main window over its playlist
        // editor (the Apple-styled skin) shows that one window, not both.
        final mainIsCompanion = scripts.isCompanionContainer("main");
        for (final container in [
          if (!mainIsCompanion) skin.container("main"),
          if (mainIsCompanion) skin.windowContainer("pl"),
          skin.windowContainer("eq"),
          if (!mainIsCompanion) skin.windowContainer("pl"),
        ]) {
          final layout =
              container?.layout("normal") ?? container?.layouts.first;
          if (container == null || layout == null) continue;
          windows.add(
            WasabiLayoutView(
              skin: skin,
              layout: layout,
              host: host,
              container: container.id,
              scripts: scripts,
            ),
          );
        }
        return IgnorePointer(
          child: ExcludeFocus(
            child: FittedBox(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: windows,
              ),
            ),
          ),
        );
      },
    );
  }
}
