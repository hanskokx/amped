import "dart:async";
import "dart:convert";
import "dart:io" show Directory, File, Platform;
import "dart:math" as math;
import "dart:ui" show Color, Offset, Rect, Size;

import "package:amped_maki/amped_maki.dart" show makiClasses;
import "package:flutter/foundation.dart";
import "package:flutter/services.dart" show Clipboard, ClipboardData;

import "../skin_region.dart" show thresholdRects;
import "../wasabi_color_themes.dart";
import "../wasabi_config.dart";
import "../wasabi_files.dart";
import "../wasabi_gamma.dart";
import "../wasabi_host.dart";
import "../wasabi_image_size.dart";
import "../wasabi_path.dart";
import "../wasabi_playlist.dart"
    show
        formatPlaylistItemTime,
        wasabiComponentGuid,
        wasabiComponentName,
        wasabiComponentTitle;
import "../wasabi_skin_data.dart";
import "../wasabi_thinger.dart" show wasabiThingerExtent;
import "../wasabi_view.dart"
    show
        wasabiAnimationFrame,
        wasabiAnimationFrames,
        wasabiTimeText,
        wasabiBucketExtent,
        wasabiBucketIsVertical,
        wasabiObjectRect,
        wasabiTextAutoHeight,
        wasabiTextAutoWidth;
import "../xml.dart";
import "builtin_scripts.dart";
import "maki_binary.dart";
import "maki_vm.dart";

const List<String> _months = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/// Runs a modern skin's MAKI scripts against its layouts and the player.
///
/// Each `<script>` gets its own System object; scripts inside a group get
/// that group as their script group. GUI objects scripts change (visibility,
/// XML parameters, text, position) are changed in the skin's object tree,
/// and the runtime notifies so the layouts redraw.
class WasabiScriptRuntime extends ChangeNotifier {
  WasabiScriptRuntime({
    required this.skin,
    required this.host,
    void Function(String)? log,
  }) : _log = log ?? debugPrint;

  final WasabiSkinData skin;
  final WasabiHost host;
  final void Function(String) _log;

  late final MakiVm vm = MakiVm(instantiate: _instantiate, log: _log);

  final Map<WasabiObject, MakiGuiObject> _wrappers = Map.identity();

  /// The objects whose `onResize` is running.
  final Set<WasabiObject> _resizing = Set.identity();
  final Map<WasabiObject, (WasabiContainer, WasabiLayout)> _layouts =
      Map.identity();
  final Map<WasabiContainer, _MakiContainer> _containers = Map.identity();
  final List<_MakiSystem> _systems = [];
  final Set<_MakiTimer> _timers = {};
  final _MakiConfig _config = _MakiConfig();

  /// The regions scripts gave layers from maps (`Layer.setRegionFromMap`).
  final Map<WasabiObject, _MakiRegion> _mapRegions = Map.identity();
  bool _started = false;
  bool _disposed = false;

  // Player state last seen, to turn host changes into System events.
  int _status = 0;
  String _title = "";
  String _info = "";
  double? _volume;
  bool _eq = false;
  final List<double?> _bands = List.filled(10, null);
  double? _preamp;
  Object? _albumArt;

  /// Loads every script and fires `System.onScriptLoaded`, in load order.
  void start() {
    if (_started) return;
    _started = true;
    _config._runtime = this;
    for (final container in skin.containers) {
      for (final layout in container.layouts) {
        _layouts[layout.root] = (container, layout);
      }
    }
    for (final layout in _layouts.values) {
      _restoreFrames(layout.$2.root);
    }
    for (final script in skin.scripts) {
      _load(script, null);
    }
    for (final container in skin.containers) {
      for (final layout in container.layouts) {
        _loadIn(layout.root);
      }
    }
    _closeComponentsThatStartClosed();
    _lookForComponents();
    _status = host.playbackStatus;
    _title = host.trackTitle;
    _info = host.songInfoText;
    _volume = host.sliderValue("VOLUME", null);
    _eq = host.isActive("EQ_TOGGLE", null);
    _albumArt = host.albumArt;
    host.addListener(_onHostChanged);
    _startSystems(List.of(_systems));
    // A CfgGroup hears its option's value as it starts (`CfgGroup::onInit`).
    for (final MapEntry(key: node, value: wrapper) in _wrappers.entries) {
      if (node.tag == "group" && _cfgOf(node) != null) {
        vm.fire(wrapper, "oncfgchanged");
      }
    }
    // The skin's own switches (its windows' toggle buttons) are config
    // attributes too, unless a script made them: those are theirs.
    for (final toggle in skin.cfgToggles) {
      final item = _config._find(toggle.attribute.item);
      if (item != null &&
          item._attributes.containsKey(toggle.attribute.name.toLowerCase())) {
        continue;
      }
      _switches.add(
        WasabiSkinOption._(
          label: toggle.label,
          attribute: _config
              ._itemFor(toggle.attribute.item)
              ._attribute(toggle.attribute.name, ""),
        ),
      );
    }
    for (final container in skin.containers) {
      for (final layout in container.layouts) {
        _autoPlay(layout.root);
        _startBuckets(layout.root);
      }
    }

    // Every layout gets its size once the scripts run, as Wasabi resizes
    // each layout when it is created: Amped Modern's configtabs script
    // centers its drawer content in `onResize`.
    for (final container in skin.containers) {
      for (final layout in container.layouts) {
        layoutResized(layout);
      }
    }
    for (final container in skin.containers) {
      for (final layout in container.layouts) {
        _tabSheetsStart(layout.root);
      }
    }
    // The layouts on screen at start are shown: scripts that find their
    // window in `System.onShowLayout` (ClassicPro's song ticker) need it
    // before the first volume or track event.
    for (final container in skin.containers) {
      if (!container.defaultVisible || container.layouts.isEmpty) continue;
      final current = host.currentLayout(container.id)?.toLowerCase();
      final layout = container.layouts.firstWhere(
        (l) => l.id.toLowerCase() == current,
        orElse: () => container.layouts.first,
      );
      _broadcast("onshowlayout", [wrap(layout.root)]);
    }
  }

  /// Runs only the scripts in [layout], a group the app shows on its own
  /// as [container] (the skin's About panel), in place of [start]: the
  /// skin's other scripts belong to the runtime running its windows.
  void startGroup(WasabiContainer container, WasabiLayout layout) {
    if (_started) return;
    _started = true;
    _config._runtime = this;
    _layouts[layout.root] = (container, layout);
    _loadIn(layout.root);
    host.addListener(_onHostChanged);
    _startSystems(List.of(_systems));
    _autoPlay(layout.root);
    layoutResized(layout);
  }

  /// Tells the scripts the user dragged [layout]'s edge to its size now
  /// (`Layout.onUserResize`): a skin's frame then resizes the window it
  /// frames.
  void layoutUserResized(WasabiLayout layout) {
    if (!_started || _disposed) return;
    final size = layout.size;
    vm.fire(wrap(layout.root), "onuserresize", [
      0,
      0,
      size.width.round(),
      size.height.round(),
    ]);
  }

  /// The window of container [id] was opened or closed by the app (a menu,
  /// a button), not by a script: its layout's scripts hear
  /// `onSetVisible`, as do the objects in it.
  void containerVisibilityChanged(String id, bool visible) {
    if (_disposed) return;
    final container = skin.container(id);
    if (container == null || container.layouts.isEmpty) return;
    final current = host.currentLayout(container.id)?.toLowerCase();
    final layout = container.layouts.firstWhere(
      (l) => l.id.toLowerCase() == current,
      orElse: () => container.layouts.first,
    );
    vm.fire(wrap(layout.root), "onsetvisible", [visible]);
    _tellVisible(layout.root, visible);
  }

  /// Tells the scripts [layout] has its size now (`Layout.onResize`): at
  /// start and whenever the app resizes the layout. The window position
  /// arguments are 0, which no known skin reads.
  void layoutResized(WasabiLayout layout) {
    if (!_started || _disposed) return;
    final size = layout.size;
    vm.fire(wrap(layout.root), "onresize", [
      0,
      0,
      size.width.round(),
      size.height.round(),
    ]);
    _tellGroupsResized(layout.root);
  }

  /// The groups in [root] get theirs with the layout's size (`Group.onResize`):
  /// Amped Modern's title bars lay out their title and streaks then, and
  /// ClassicPro's tabs fit themselves to the room they have.
  void _tellGroupsResized(WasabiObject root) {
    void visit(WasabiObject node) {
      for (final child in List.of(node.children)) {
        if (child.tag != "group") continue;
        final wrapper = scriptObjectOf(child);
        if (wrapper != null) {
          final rect = rectOf(child);
          vm.fire(wrapper, "onresize", [
            rect.left.round(),
            rect.top.round(),
            rect.width.round(),
            rect.height.round(),
          ]);
        }
        visit(child);
      }
    }

    visit(root);
  }

  /// Tells the scripts the buckets in [node] have their items
  /// (`ComponentBucket.onStartup`).
  void _startBuckets(WasabiObject node) {
    for (final child in List.of(node.children)) {
      if (child.tag == "componentbucket" && child.children.isNotEmpty) {
        vm.fire(wrap(child), "onstartup");
      } else {
        _startBuckets(child);
      }
    }
  }

  /// Starts the `autoplay` animated layers in [node].
  void _autoPlay(WasabiObject node) {
    for (final child in node.children) {
      if (child.tag == "animatedlayer") {
        animationOf(child)?.autoPlay();
      } else {
        _autoPlay(child);
      }
    }
  }

  /// The warp layer [node] is drawn through while its effect is on
  /// (`fx_setEnabled`), or null.
  WasabiFxMesh? fxMeshOf(WasabiObject node) => _wrappers[node]?._fx?.mesh;

  /// The region a script gave layer [node] from a map
  /// (`Layer.setRegionFromMap`), as rectangles in layer pixels: the layer
  /// draws, and takes the mouse, only there. Null when it has none.
  List<Rect>? layerRegionOf(WasabiObject node) => _mapRegions[node]?.rects;

  /// Gives layer [node] the region of [map] at [threshold]
  /// (`Layer::setRegionFromMap`).
  void _setRegionFromMap(
    WasabiObject node,
    _MakiMap? map,
    int threshold,
    bool reversed,
  ) {
    if (map == null) {
      _setRegion(node, null);
      return;
    }
    _setRegion(node, _MakiRegion(this)..loadFromMap(map, threshold, reversed));
  }

  /// Gives layer [node] the shape of [region], or its whole box when null
  /// (`Layer::setRegion`).
  void _setRegion(WasabiObject node, _MakiRegion? region) {
    if (region == null) {
      if (_mapRegions.remove(node) != null) changed();
      return;
    }
    _mapRegions[node] = region;
    changed();
  }

  /// [map]'s pixels arrived: the regions made from it get their shape.
  void _mapLoaded(_MakiMap map) {
    if (_mapRegions.values.any((r) => r.usesMap(map))) changed();
  }

  /// The playback of animated layer [node]; null for other objects.
  WasabiLayerAnimation? animationOf(WasabiObject node) =>
      node.tag == "animatedlayer" ? wrap(node)._frames : null;

  /// Fires `onScriptLoaded` for newly loaded scripts, then gives the scripts
  /// of XUI groups the tag's attributes (`onSetXuiParam`).
  void _startSystems(List<_MakiSystem> systems) {
    // The scripts of groups start first, and the frames among them build
    // their content (below); the skin's own scripts, which find objects
    // all over the layouts, start after that (the classic player makes the layout, and
    // so its groups, when such a script asks for it).
    final topLevel = [
      for (final system in systems)
        if (system.group == null) system,
    ];
    for (final system in systems) {
      if (system.group != null) vm.fire(system, "onscriptloaded");
    }
    // `notify="command,parameter"` (and `notify1` ... `notify9`) on a group
    // sends its scripts `onNotify` with the whole value: a standard frame is
    // told its `content` group, or how far to pad its title bar.
    for (final system in systems) {
      final group = system.group;
      if (group == null) continue;
      for (final key in const [
        "notify",
        "notify1",
        "notify2",
        "notify3",
        "notify4",
        "notify5",
        "notify6",
        "notify7",
        "notify8",
        "notify9",
      ]) {
        final value = group[key];
        if (value == null || !value.contains(",")) continue;
        final wrapper = scriptObjectOf(group);
        if (wrapper != null) vm.fire(wrapper, "onnotify", [value, "", 0, 0]);
      }
    }
    for (final system in systems) {
      final group = system.group;
      final xui = group?["#xui"];
      if (group == null || xui == null || xui.isEmpty) continue;
      for (final key in xui.split(";")) {
        if (_positional.contains(key)) continue;
        vm.fire(system, "onsetxuiparam", [key, group[key] ?? ""]);
      }
    }
    for (final system in topLevel) {
      vm.fire(system, "onscriptloaded");
    }
    // The windows that are open from the start (the color changer's scripts
    // make their maps when their layout is shown; ClassicPro's player opens
    // its first tab when its group is) hear they are shown.
    for (final container in skin.containers) {
      if (host.isContainerVisible(container.id)) {
        containerVisibilityChanged(container.id, true);
      }
    }
    // The skin is in place: a `new ColorMgr` is told (`onLoaded`).
    for (final manager in List.of(_colorManagers)) {
      vm.fire(manager, "onloaded");
    }
  }

  /// The `ColorMgr` objects scripts made, to tell when the skin loaded.
  final List<_MakiColorMgr> _colorManagers = [];

  /// The playlist editors scripts made, which hear `onPleditModified`.
  final List<_MakiPlEdit> _plEdits = [];
  int _playlistSignature = 0;

  /// A number that changes with the playlist's entries and their order.
  int _playlistHash() {
    var hash = host.playlistLength;
    for (var i = 0; i < host.playlistLength; i++) {
      hash = Object.hash(hash, host.playlistLocation(i));
    }
    return hash;
  }

  /// Gives the scripts of XUI group [node] a parameter set on it later with
  /// `setXmlParam` (Amped Modern's frames pad their title bars this way).
  /// A parameter set on [node] reaches its script's `onSetXuiParam`: those
  /// its XUI declares, and, for a group, one nothing in the skin gave it (a
  /// list item's `widgetname`), which the group's script is there to take.
  void _setXuiParam(
    WasabiObject node,
    String name,
    String value, {
    bool unknown = false,
  }) {
    if (_positional.contains(name)) return;
    if (node["#xui"] == null && !(unknown && node.tag == "group")) return;
    for (final system in List.of(_systems)) {
      if (identical(system.group, node)) {
        vm.fire(system, "onsetxuiparam", [name, value]);
      }
    }
  }

  static const _positional = {
    "x",
    "y",
    "w",
    "h",
    "relatx",
    "relaty",
    "relatw",
    "relath",
    "id",
  };

  /// Attaches a group made with `newGroup` to [parent] (`Group.init`) and
  /// starts its scripts.
  void _attach(WasabiObject group, WasabiObject parent) {
    if (group.parent != null) return;
    group.parent = parent;
    parent.children.add(group);
    _restoreFrames(group);
    final before = _systems.length;
    _loadIn(group);
    changed();
    _startSystems(_systems.sublist(before));
  }

  @override
  void dispose() {
    _artTimer?.cancel();
    _artTimer = null;
    if (_readingSamples) {
      _readingSamples = false;
      host.stopVisualization();
    }
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      host.removeListener(_onHostChanged);
      for (final system in List.of(_systems)) {
        vm.fire(system, "onscriptunloading");
      }
    }
    for (final timer in List.of(_timers)) {
      timer.dispose();
    }
    for (final timer in _redockTweens.values) {
      timer.cancel();
    }
    _redockTweens.clear();
    for (final wrapper in _wrappers.values) {
      wrapper._animation?.cancel();
      wrapper._animation = null;
      wrapper._animationOrNull?.dispose();
      wrapper._fx?.dispose();
    }
    for (final script in List.of(vm.scripts)) {
      vm.unload(script);
    }
    super.dispose();
  }

  void _loadIn(WasabiObject node) {
    for (final child in node.children) {
      if (child.tag == "script") {
        _load(child, node);
      } else {
        _loadIn(child);
      }
    }
  }

  void _load(WasabiObject script, WasabiObject? group) {
    final file = script["file"];
    if (file == null) return;
    final builtin = builtinScript(file);
    final path = builtin != null
        ? file
        : skin.resolveFile(file, dir: script["#dir"]);
    if (path == null) {
      _log("MAKI: script $file not found");
      return;
    }
    try {
      final binary = MakiBinary.parse(builtin ?? WasabiFiles.readBytes(path));
      final system = _MakiSystem(
        this,
        group,
        skin.expandPathVariables(script["param"] ?? ""),
      );
      _systems.add(system);
      vm.load(binary, system: system, name: file);
    } on Object catch (error) {
      _log("MAKI: could not load $file: $error");
    }
  }

  /// Something scripts changed; layouts redraw.
  void changed() {
    if (_disposed) return;
    _followCompanions();
    notifyListeners();
  }

  /// A window hidden under the frames drawn over it is as big as they are:
  /// the window shows only them.
  void _followCompanions() {
    for (final MapEntry(key: owner, value: list) in _companions.entries) {
      if (owner.root["#hidden"] != "1" || list.isEmpty) continue;
      final size = list.first.$2.size;
      owner.root.attributes
        ..["w"] = "${size.width.round()}"
        ..["h"] = "${size.height.round()}";
    }
  }

  /// Whether a script hid [layout] while frames drawn over it stay.
  bool isHiddenUnderCompanions(WasabiLayout layout) =>
      layout.root["#hidden"] == "1";

  // --- Skin options ---------------------------------------------------------

  /// The `ConfigAttribute` a script made with [name], in any config item;
  /// null when no script made one.
  _MakiConfigAttribute? _configAttribute(String name) {
    final key = name.toLowerCase();
    for (final item in _config._items.values) {
      final attribute = item._attributes[key];
      if (attribute != null) return attribute;
    }
    return null;
  }

  /// Whether desktop alpha is on (the classic player's "Enable desktop alpha"): windows
  /// draw their `alphabackground` and show what is behind them. A skin's own
  /// switch may turn it off (Resin's "Glass Mode").
  bool get desktopAlpha => configAttribute("Enable desktop alpha") != "0";

  /// Whether a script made the skin option [name] (such as Amped Modern's
  /// `Equalizer\tAlt+G`).
  bool hasConfigAttribute(String name) => _configAttribute(name) != null;

  /// The value of the skin option [name], or null when no script made it.
  String? configAttribute(String name) => _configAttribute(name)?.data;

  /// Sets the skin option [name], firing its `onDataChanged` like a menu
  /// click on it does in the classic player (`MenuActions::toggleOption`).
  void setConfigAttribute(String name, String value) =>
      _configAttribute(name)?.setData(vm, value);

  /// The `ConfigAttribute` a script made that [attribute] names, by its
  /// item's GUID or name; null when no script made it.
  _MakiConfigAttribute? _cfgAttribute(WasabiCfgAttrib attribute) =>
      _config._find(attribute.item)?._attributes[attribute.name.toLowerCase()];

  /// The value of the skin option a control's `cfgattrib` names
  /// (`getDataAsInt`), or null when no script made that option and the
  /// host keeps the value.
  int? cfgAttribValue(WasabiCfgAttrib attribute) =>
      _cfgAttribute(attribute)?.asInt;

  /// Sets the skin option a control's `cfgattrib` names, firing its
  /// `onDataChanged` (`guiobject_setCfgInt`); false when no script made
  /// that option and the host keeps the value.
  bool setCfgAttribValue(WasabiCfgAttrib attribute, int value) {
    final option = _cfgAttribute(attribute);
    option?.setData(vm, "$value");
    return option != null;
  }

  /// The config item gen_ff maps to the classic player's Options menu
  /// (`customOptionsMenuitemGuid`, `CUSTOM_OPTIONSMENU_ITEMS` in skins).
  static const _optionsMenuGuid = "1828d28f-78dd-4647-8532-eba504b8fc04";

  /// The options the skin's scripts put in the classic player's Options menu, such as
  /// Amped Modern's "Amped Modern > Drawers > Animate Config Drawer"
  /// (`MenuActions::installSkinOptions`); empty when they put none there.
  List<WasabiSkinOption> get skinOptions {
    final page = _config._byGuid[_optionsMenuGuid];
    return page == null ? const [] : _skinOptionsOf(page, {});
  }

  /// The switches the skin's own windows carry (its `cfgattrib` toggle
  /// buttons), as options: skins made before Amped Modern keep their
  /// settings there rather than in the Options menu.
  List<WasabiSkinOption> get skinSwitches => List.unmodifiable(_switches);

  final List<WasabiSkinOption> _switches = [];

  /// The entries of [page]: an attribute whose data is a config item's GUID
  /// opens that item as a submenu, one whose data is `-` is a separator,
  /// and any other is a check box (`makeSkinOptionsSubMenu`).
  List<WasabiSkinOption> _skinOptionsOf(
    _MakiConfigItem page,
    Set<_MakiConfigItem> open,
  ) {
    open.add(page);
    final options = [
      for (final attribute in page._attributes.values)
        if (attribute.name.isNotEmpty)
          if (attribute.data.trim() == "-")
            const WasabiSkinOption._separator()
          else if (_config._byGuidKey(attribute.data) case final submenu?)
            WasabiSkinOption._(
              label: attribute.name,
              children: open.contains(submenu)
                  ? const []
                  : _skinOptionsOf(submenu, open),
            )
          else
            WasabiSkinOption._(label: attribute.name, attribute: attribute),
    ];
    open.remove(page);
    return options;
  }

  /// Flips the check box [option] between 1 and 0, firing its
  /// `onDataChanged` (`MenuActions::toggleOption`).
  void toggleSkinOption(WasabiSkinOption option) {
    final attribute = option._attribute;
    if (attribute == null) return;
    attribute.setData(vm, attribute.asInt == 0 ? "1" : "0");
  }

  // --- Objects ----------------------------------------------------------------

  /// The script object for [node], creating it on first use.
  MakiGuiObject wrap(WasabiObject node) =>
      _wrappers[node] ??= MakiGuiObject._(this, node);

  /// The script object for [node] when scripts may be listening to it.
  MakiGuiObject? scriptObjectOf(WasabiObject node) {
    final wrapper = _wrappers[node];
    return wrapper == null || wrapper.bindings.isEmpty ? null : wrapper;
  }

  /// The layouts scripts asked for with `newDynamicContainer`, by the layout
  /// the asking script lives in. Wasabi 5 skins draw a window's frame as a
  /// second, transparent window that follows the first
  /// (`standardframeML.maki`); the app draws it over the layout it follows.
  final Map<WasabiLayout, List<(WasabiContainer, WasabiLayout)>> _companions =
      Map.identity();

  /// What `newDynamicContainer` makes: a container of its own each time (a
  /// frame is made for every window it frames), a copy of the skin's one of
  /// that id. A frame the script draws over its layout is a companion of it.
  MakiObject? _newDynamicContainer(_MakiSystem system, String id) {
    final container = skin.container(id);
    if (container == null) return null;
    final group = system.group;
    final owner = group == null ? null : layoutOf(group)?.$2;
    if (!container.dynamic || owner == null || container.layouts.isEmpty) {
      return _container(id);
    }
    // A window that starts hidden (`default_visible="0"`: ClassicPro's
    // playlist search results, a pop-up near the search box) is not a frame
    // to draw over the layout; it stays closed until a script opens it.
    if (!container.defaultVisible) {
      // Unless the script then sizes it to the window it asked from: a
      // frame GlassAMP shows when it is wanted ([_promoteFrame]).
      _frameAskers[container.id] = owner;
      return _container(id);
    }
    final copy = WasabiContainer(
      id: container.id,
      name: container.name,
      layouts: [for (final layout in container.layouts) layout.copy()],
      defaultPosition: container.defaultPosition,
      defaultVisible: container.defaultVisible,
      dynamic: true,
      component: container.component,
    );
    for (final layout in copy.layouts) {
      _layouts[layout.root] = (copy, layout);
    }
    final made = _containers[copy] = _MakiContainer(this, copy);
    final layout = copy.layout("normal") ?? copy.layouts.first;
    if (!identical(owner, layout)) {
      (_companions[owner] ??= []).add((copy, layout));
      notifyListeners();
    }
    // The copy's own scripts run for it, as for any other container (the
    // play button's, the volume bar's): the skin's are for the original.
    final before = _systems.length;
    for (final layout in copy.layouts) {
      _loadIn(layout.root);
    }
    _startSystems(_systems.sublist(before));
    for (final layout in copy.layouts) {
      _autoPlay(layout.root);
      _startBuckets(layout.root);
      layoutResized(layout);
      _tabSheetsStart(layout.root);
    }
    return made;
  }

  /// The layout whose script asked for each window that starts hidden.
  final Map<String, WasabiLayout> _frameAskers = {};

  /// A hidden window its script gives the size of the layout it asked from is
  /// that layout's frame (GlassAMP's `standardframeML.maki` shows and sizes
  /// its `cont.clear.ml` to the media library's window): drawn over it, as
  /// a frame made visible at once is.
  void _promoteFrame(WasabiObject node, int w, int h) {
    final entry = layoutOf(node);
    if (entry == null) return;
    final (container, layout) = entry;
    final owner = _frameAskers[container.id];
    if (owner == null || identical(owner, layout)) return;
    if (_companions[owner]?.any((e) => identical(e.$2, layout)) ?? false)
      return;
    if (w != owner.size.width.round() || h != owner.size.height.round()) return;
    (_companions[owner] ??= []).add((container, layout));
    notifyListeners();
  }

  /// Whether a script made the container [id] a companion of another window's
  /// layout (the Apple-styled skin draws its whole player as a frame over its playlist
  /// editor): then it shows there, not in a window of its own.
  bool isCompanionContainer(String id) {
    final key = id.toLowerCase();
    for (final list in _companions.values) {
      if (list.any((e) => e.$1.id == key)) return true;
    }
    return false;
  }

  /// The layouts drawn over [layout]: frames its scripts made.
  List<(WasabiContainer, WasabiLayout)> companionsOf(WasabiLayout layout) =>
      _companions[layout] ?? const [];

  MakiObject? _container(String id) {
    final container = skin.container(id);
    if (container == null) return null;
    // Once a script has made a window of its own of a dynamic container,
    // that is the container the skin's id names (the Apple-styled skin's scripts ask
    // for "main" after drawing it over the playlist editor).
    for (final list in _companions.values) {
      for (final (copy, _) in list) {
        if (copy.id == container.id) {
          return _containers[copy] ??= _MakiContainer(this, copy);
        }
      }
    }
    return _containers[container] ??= _MakiContainer(this, container);
  }

  MakiObject? _instantiate(String className) {
    switch (className) {
      case "timer":
        final timer = _MakiTimer(this);
        _timers.add(timer);
        return timer;
      case "list":
        return _MakiList();
      case "map":
        return _MakiMap(this);
      case "region":
        return _MakiRegion(this);
      case "colormgr":
        final manager = _MakiColorMgr(this);
        _colorManagers.add(manager);
        return manager;
      case "popupmenu":
        return _MakiPopupMenu(this);
      case "pledit":
        final editor = _MakiPlEdit(this);
        _plEdits.add(editor);
        return editor;
      case "bitlist":
        return _MakiBitList();
      case "pldir" || "application":
        return _MakiStub(className, this);
      case "classicprofile":
        return _MakiClassicProFile(this);
      case "winampconfig":
        return _MakiStub(className);
      case "config":
        return _config;
      case "file":
        return _MakiFile(this);
      case "xmldoc":
        return _MakiXmlDoc(this);
    }
    return null;
  }

  final Map<WasabiObject, Timer> _redockTweens = {};

  final Set<MakiGuiObject> _sliders = {};

  /// Notes that [object] slides (or stopped), and tells its layout: while a
  /// drawer slides the window keeps the whole layout, as the classic player's does
  /// (the room a closed drawer leaves out only matters for docking), or the
  /// drawer would be cut off by a window that only grows when it is done.
  void _noteSliding(MakiGuiObject object, bool sliding) {
    if (sliding) {
      _sliders.add(object);
    } else if (!_sliders.remove(object)) {
      return;
    }
    var root = object.node;
    while (root.parent != null) {
      root = root.parent!;
    }
    final any = _sliders.any((o) {
      var other = o.node;
      while (other.parent != null) {
        other = other.parent!;
      }
      return identical(other, root);
    });
    if (any) {
      root.attributes["#sliding"] = "1";
    } else {
      root.attributes.remove("#sliding");
    }
    changed();
  }

  void _stopRedockTween(WasabiObject root) {
    _redockTweens.remove(root)?.cancel();
    root.attributes
      ..remove("#tweenfrom")
      ..remove("#tweent");
  }

  /// A script's `redock`: the window takes the size its snap adjustments
  /// leave. After a drawer slid it takes that over the time the drawer took
  /// (a docked window follows instead of jumping), unless it already grew
  /// along with the drawer.
  void _redock(WasabiObject root) {
    final layout = _layouts[root]?.$2;
    final seconds = layout?.redockSeconds;
    final from = layout?.windowSize;
    root.attributes
      ..remove("#redocking")
      ..remove("#redockfrom")
      ..remove("#redockt");
    if (layout == null || from == null || seconds == null) return;
    final to = layout.settledWindowSize;
    if (from == to) return;
    root.attributes
      ..["#tweenfrom"] = "${from.width},${from.height}"
      ..["#tweent"] = "0";
    const tick = 20;
    final total = math.max(1, (seconds * 1000).round());
    _redockTweens[root] = Timer.periodic(const Duration(milliseconds: tick), (
      timer,
    ) {
      final n = math.min(1.0, timer.tick * tick / total);
      root.attributes["#tweent"] =
          "${math.sin(n * math.pi - math.pi / 2) / 2 + 0.5}";
      if (n >= 1) _stopRedockTween(root);
      changed();
    });
  }

  /// The layout (and its container) [node] is in.
  (WasabiContainer, WasabiLayout)? layoutOf(WasabiObject node) {
    var n = node;
    while (n.parent != null) {
      n = n.parent!;
    }
    return _layouts[n];
  }

  /// [node]'s rectangle inside its parent, in layout pixels.
  Rect rectOf(WasabiObject node) {
    final parent = node.parent;
    if (parent == null) {
      final size = _layouts[node]?.$2.size ?? Size.zero;
      return Offset.zero & size;
    }
    return wasabiObjectRect(node, rectOf(parent).size, skin);
  }

  double _frameDragStart = 0;

  /// A drag of a `Wasabi:Frame`'s divider starts.
  void frameDragStart(WasabiObject frame) {
    _frameDragStart = (int.tryParse(frame["#frame.size"] ?? "") ?? 0)
        .toDouble();
  }

  /// The divider has moved [delta] pixels along the frame since the drag
  /// started: the sized group follows, kept between `minwidth` and
  /// `maxwidth` (`FrameWnd::onMouseMove`; negative limits count from the
  /// frame's own size).
  void frameDragBy(WasabiObject frame, double delta) {
    final fromEnd = frame["#frame.fromend"] == "1";
    _setFrameSize(frame, _frameDragStart + (fromEnd ? -delta : delta));
  }

  /// The drag ended: the divider's place is kept for the skin
  /// (`FrameWnd/<id>,p`, as the original keeps it).
  void frameDragEnd(WasabiObject frame) {
    final id = frame.id;
    if (id.isEmpty) return;
    host.writePrivate(
      _frameSection,
      id.toLowerCase(),
      frame["#frame.size"] ?? "",
    );
  }

  static const String _frameSection = "amped.frames";

  void _setFrameSize(WasabiObject frame, double wanted) {
    final stacked = frame["#frame.stacked"] == "1";
    final bounds = rectOf(frame);
    final total = stacked ? bounds.height : bounds.width;
    final min = int.tryParse(frame["#frame.min"] ?? "") ?? 0;
    final max = int.tryParse(frame["#frame.max"] ?? "") ?? 0;
    final realMin = min < 0 ? total + min : min.toDouble();
    final realMax = max <= 0 ? total + max : max.toDouble();
    var size = math.min(wanted, realMax);
    size = math.max(size, realMin);
    size = math.max(0, size);
    layoutWasabiFrame(frame, size.round());
    changed();
  }

  /// Puts the `Wasabi:Frame`s under [node] where the skin's user left their
  /// dividers.
  void _restoreFrames(WasabiObject node) {
    if (node["#frame"] == "1" && node.id.isNotEmpty) {
      final saved = int.tryParse(
        host.readPrivate(_frameSection, node.id.toLowerCase()) ?? "",
      );
      if (saved != null) _setFrameSize(node, saved.toDouble());
    }
    for (final child in node.children) {
      _restoreFrames(child);
    }
  }

  /// The children of [group] that are objects: not the scripts and
  /// parameters it keeps with them (`Group.enumObject` counts only those).
  static List<WasabiObject> _guiChildren(WasabiObject group) => [
    for (final child in group.children)
      if (child.tag != "script" &&
          child.tag != "sendparams" &&
          child.tag != "hideobject")
        child,
  ];

  /// Whether the pointer is over [node]: the pointer is in the screen's
  /// pixels, the window's origin is asked of the host.
  bool _mouseOver(WasabiObject node) {
    final owner = layoutOf(node);
    if (owner == null) return false;
    final origin = host.windowOrigin(owner.$1.id);
    if (origin == null) return false;
    return _contains(node, host.cursorPosition - origin);
  }

  /// Whether [point], in the window's pixels, is inside [node].
  bool _contains(WasabiObject node, Offset point) {
    var left = 0.0;
    var top = 0.0;
    for (WasabiObject? n = node; n != null && n.parent != null; n = n.parent) {
      final rect = rectOf(n);
      left += rect.left;
      top += rect.top;
    }
    final box = (Offset.zero & rectOf(node).size).shift(Offset(left, top));
    return box.contains(point);
  }

  /// [node]'s position as Wasabi's `getGuiPosition` gives it (`getGuiX`
  /// and friends, `gotoTarget`): on an axis with `relatx`, `relaty`,
  /// `relatw` or `relath`, the value as the skin writes it (an offset from
  /// the parent's far edge, or a percentage), else [rectOf]'s. Keys are
  /// `x`, `y`, `w` and `h`.
  Map<String, double> guiPositionOf(WasabiObject node) {
    final rect = rectOf(node);
    final position = {
      "x": rect.left,
      "y": rect.top,
      "w": rect.width,
      "h": rect.height,
    };
    if (node.parent == null) {
      // A layout is a window: where scripts have put it on the screen
      // (`Layout.resize`, `setTargetX`), which the app follows.
      final origin = host.windowOrigin(layoutOf(node)?.$1.id ?? "");
      final view = host.viewport.topLeft;
      position["x"] = origin == null
          ? (node.optInt("x") ?? 0).toDouble()
          : (origin.dx - view.dx).roundToDouble();
      position["y"] = origin == null
          ? (node.optInt("y") ?? 0).toDouble()
          : (origin.dy - view.dy).roundToDouble();
      return position;
    }
    for (final key in position.keys.toList()) {
      final value = node.optInt(key);
      if (value != null && node.intAttr("relat$key") != 0) {
        position[key] = value.toDouble();
      }
    }
    return position;
  }

  /// Finds the object with [id] inside [node] (Group::findObject), ignoring
  /// case, depth first.
  WasabiObject? find(WasabiObject node, String id) {
    _giveTitleBarItsTrap(node);
    final key = id.toLowerCase();
    for (final child in node.children) {
      if (child.id.toLowerCase() == key) return child;
    }
    for (final child in node.children) {
      final found = find(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// A `Wasabi:TitleBar` holds a mouse trap layer of its own (`mousetrap`),
  /// which StandardFrame's script sets the double-click action of; the
  /// title bar here draws itself, so the trap is added when scripts look.
  /// What a `winamp:Browser` holds, by group, button and id: scripts that
  /// set its buttons' texts and icons (ClassicPro's CentroSUI) look them up.
  /// The browser here draws itself, so they are stand-ins that scripts can
  /// find and set parameters on.
  static const Map<String, List<String>> _browserParts = {
    "browser.navigate": [],
    "search.go": [],
    "browser.scraper": ["browser.dlds.settings"],
    "dlds.mode": ["scraper.switch", "dlds.switch"],
    "scraper.mode": ["scraper.switch", "dlds.switch"],
  };

  void _giveBrowserItsParts(WasabiObject node) {
    if (node.tag != "winamp:browser" || node.children.isNotEmpty) return;
    for (final MapEntry(key: id, value: inside) in _browserParts.entries) {
      final part = WasabiObject(
        inside.isEmpty ? "button" : "group",
        {"id": id, "visible": "0"},
        [
          for (final child in inside)
            WasabiObject("button", {"id": child, "visible": "0"}, []),
        ],
      )..parent = node;
      node.children.add(part);
    }
  }

  void _giveTitleBarItsTrap(WasabiObject node) {
    _giveBrowserItsParts(node);
    if (node.tag != "wasabi:titlebar" ||
        node.children.any((c) => c.id == "mousetrap")) {
      return;
    }
    node.children.add(
      WasabiObject("layer", {"id": "mousetrap", "ghost": "1"}, const [])
        ..parent = node,
    );
  }

  /// `GuiObject.findObject`: the object with [id] (ignoring case) nearest
  /// to [node], as Wasabi's `BaseWnd::findWindowChain` searches: [node]
  /// itself and inside it, then each parent and inside it, up to the
  /// layout. Amped Modern's scripts find the menu bar beside their own
  /// group this way.
  WasabiObject? findNear(WasabiObject node, String id) {
    final key = id.toLowerCase();
    WasabiObject? from;
    for (WasabiObject? at = node; at != null; from = at, at = at.parent) {
      _giveTitleBarItsTrap(at);
      if (at.id.toLowerCase() == key) return at;
      for (final child in at.children) {
        if (!identical(child, from) && child.id.toLowerCase() == key) {
          return child;
        }
      }
      for (final child in at.children) {
        if (identical(child, from)) continue;
        final found = find(child, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Whether a script asked how big the screen is, in skin pixels: it sized
  /// itself from the answer when it started, so it has to start again when
  /// the pixels are enlarged (double size).
  bool sizesDependOnScale = false;

  /// [w] by [h] for the layout [node] as a window may be: within its
  /// `minimum_w`/`maximum_w` and `minimum_h`/`maximum_h`, and no larger than
  /// the display in the layout's own pixels. Sizes of 0 or less (relative
  /// ones) are left alone.
  (int, int) _limitedWindowSize(WasabiObject node, int w, int h) {
    final owner = layoutOf(node)?.$1.id;
    final scale = owner == null ? 1.0 : host.layoutScale(owner);
    final area = host.viewport;
    int limit(int value, int? min, int? max, double screen) {
      if (value <= 0) return value;
      var limited = value;
      if (max != null && max > 0 && limited > max) limited = max;
      if (min != null && limited < min) limited = min;
      final fits = (screen / (scale <= 0 ? 1 : scale)).floor();
      if (fits > 0 && limited > fits) limited = fits;
      return limited;
    }

    return (
      limit(w, node.optInt("minimum_w"), node.optInt("maximum_w"), area.width),
      limit(h, node.optInt("minimum_h"), node.optInt("maximum_h"), area.height),
    );
  }

  /// How much the skin's pixels are enlarged on screen (double size).
  double _skinScale(_MakiSystem system) {
    final group = system.group;
    final owner = group == null ? null : layoutOf(group)?.$1.id;
    // Only the main window's scripts size themselves to the screen in its
    // pixels; the others place windows in screen pixels (a notifier in the
    // corner of the screen).
    if (owner != null && owner.toLowerCase() != "main") return 1;
    // A skin that reads the layout's scale divides the screen by it where it
    // needs to (ClassicPro's maximize): dividing here would do it twice.
    if (vm.scripts.any(
      (script) => script.binary.imports.any(
        (import) => import.name.toLowerCase() == "getscale",
      ),
    )) {
      return 1;
    }
    final scale = host.layoutScale("main");
    return scale < 1 ? 1 : scale;
  }

  // --- Events from the layouts -------------------------------------------------

  /// The objects the pointer is over (as `onEnterArea` and `onLeaveArea` said),
  /// for `isMouseOver`.
  final Set<WasabiObject> _hoveredObjects = {};

  /// A mouse event on [node]: `onLeftButtonDown`, `onLeftButtonUp`,
  /// `onRightButtonDown`, `onRightButtonUp`, `onLeftButtonDblClk`,
  /// `onMouseMove` (with [position] in object pixels), `onEnterArea`,
  /// `onLeaveArea`.
  void pointer(WasabiObject node, String event, [Offset? position]) {
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    switch (event.toLowerCase()) {
      case "onenterarea":
        _hoveredObjects.add(node);
      case "onleavearea":
        _hoveredObjects.remove(node);
    }
    if (node.tag == "layout") {
      final lower = event.toLowerCase();
      if (lower == "onenterarea") wrapper._hover(true);
      if (lower == "onleavearea") wrapper._hover(false);
    }
    final args = position == null
        ? const <Object?>[]
        : [position.dx.round(), position.dy.round()];
    vm.fire(wrapper, event.toLowerCase(), args);
  }

  /// The mouse wheel turned over [node]: `onMouseWheelUp` or `onMouseWheelDown`
  /// with `(clicked, lines)`, one line a notch.
  void mouseWheel(WasabiObject node, {required bool up}) {
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    vm.fire(wrapper, up ? "onmousewheelup" : "onmousewheeldown", [0, 1]);
  }

  /// The text of the `<edit>` [node] changed as its user typed.
  void editChanged(WasabiObject node, String text) {
    node.attributes["#text"] = text;
    skin.playlistFilter.value = text;
    changed();
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    vm.fire(wrapper, "ontextchanged", [text]);
    // `onEditUpdate` as it is typed, `onIdleEditUpdate` once typing pauses.
    vm.fire(wrapper, "oneditupdate", const []);
    if ((int.tryParse(node["#idle"] ?? "1") ?? 1) != 0) {
      _idleEdits.remove(node)?.cancel();
      _idleEdits[node] = Timer(const Duration(milliseconds: 350), () {
        _idleEdits.remove(node);
        if (!_disposed) vm.fire(wrapper, "onidleeditupdate", const []);
      });
    }
  }

  final Map<WasabiObject, Timer> _idleEdits = Map.identity();

  /// Enter in the `<edit>` [node].
  void editSubmitted(WasabiObject node) {
    final wrapper = scriptObjectOf(node);
    if (wrapper != null) vm.fire(wrapper, "onenter", const []);
  }

  /// A key went down or up in the focused object [node] (an `<edit>`): its
  /// scripts hear `onKeyDown(vk)` / `onKeyUp(vk)` with the Windows virtual-key
  /// code, and `onChar(c)` for the character a press typed.
  void objectKey(
    WasabiObject node,
    int vk, {
    required bool down,
    String? character,
  }) {
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    vm.fire(wrapper, down ? "onkeydown" : "onkeyup", [vk]);
    if (down && character != null && character.isNotEmpty) {
      vm.fire(wrapper, "onchar", [character]);
    }
  }

  /// Escape in the `<edit>` [node]: the clear button beside it, if any,
  /// is pressed (the playlist search box closes).
  void editCancelled(WasabiObject node) {
    final wrapper = scriptObjectOf(node);
    if (wrapper != null) vm.fire(wrapper, "onabort", const []);
    final clear = findNear(node, "pl.search.edit.clear");
    if (clear != null) buttonClicked(clear);
  }

  /// A click on a button: a toggle button flips, then `onLeftClick` (and
  /// `onToggle`) fire. An `<NStatesButton>` has already moved on to its
  /// next state, and toggles on in any but its first (NStatesTgButton).
  void buttonClicked(WasabiObject node) {
    if (_nStates(node) != null) {
      changed();
      final wrapper = scriptObjectOf(node);
      if (wrapper != null) {
        vm.fire(wrapper, "ontoggle", [node.intAttr("#state") != 0]);
      }
    } else if (node.tag == "togglebutton" ||
        node.tag == "nstatesbutton" ||
        node.tag == "checkbox") {
      final on = !_activated(node);
      node.attributes["#active"] = on ? "1" : "0";
      changed();
      final wrapper = scriptObjectOf(node);
      if (wrapper != null) {
        vm.fire(wrapper, "ontoggle", [on]);
        // The button is activated or not, as with `setActivated`: Catwoman's
        // and Batman Begins' scripts open their EQ drawer from it.
        vm.fire(wrapper, "onactivate", [on]);
      }
    }
    final wrapper = scriptObjectOf(node);
    if (wrapper != null) vm.fire(wrapper, "onleftclick");
  }

  /// Asks the scripts whether they take over showing ([goingVisible]) or
  /// hiding the component [guid] (`System.onGetCancelComponent`): the classic player
  /// Modern opens its drawer for the visualization instead of letting its
  /// window open. Whether one did, and so the window should be left alone.
  bool cancelsComponent(String guid, {required bool goingVisible}) {
    if (!_started || _disposed) return false;
    var cancelled = false;
    for (final system in List.of(_systems)) {
      final result = vm.fire(system, "ongetcancelcomponent", [
        guid,
        goingVisible,
      ]);
      if (result == true || (result is num && result != 0)) cancelled = true;
    }
    return cancelled;
  }

  /// Whether this runtime asked the host for audio samples, which the VU
  /// meters read; it gives them back when it is disposed.
  bool _readingSamples = false;

  /// The level of the playing audio's [left] or right channel, 0..255
  /// (`System.getLeftVuMeter`). The classic player's own comes from its output stage as
  /// a smoothed level, not the loudest single sample, which sits near full
  /// scale for most music: this is the root mean square of the latest
  /// window, scaled so a full-scale sine reads 255, that falls back
  /// gradually. Amped Modern's beat display and Ebonite's cube
  /// visualizer show it.
  int _vuMeter({required bool left}) {
    if (!_readingSamples) {
      _readingSamples = true;
      host.startVisualization();
    }
    final samples = host.visSamples;
    final held = left ? _vuLeft : _vuRight;
    if (samples == null || !host.visRunning) {
      final down = held * 0.8;
      left ? _vuLeft = down : _vuRight = down;
      return down.round().clamp(0, 255);
    }
    var sum = 0.0;
    final channel = left ? samples.$1 : samples.$2;
    for (final sample in channel) {
      sum += sample * sample;
    }
    final rms = channel.isEmpty ? 0.0 : math.sqrt(sum / channel.length);
    // A full-scale sine is 255 (its RMS is 1/sqrt(2)).
    final level = (rms * 255 * math.sqrt2).clamp(0.0, 255.0);
    final next = level > held ? level : held * 0.85 + level * 0.15;
    left ? _vuLeft = next : _vuRight = next;
    return next.round().clamp(0, 255);
  }

  double _vuLeft = 0;
  double _vuRight = 0;

  /// Runs a button's action when it is not the player's: one sent to
  /// another object (`action_target`, which gets `onAction`), or one that
  /// turns the pages of the layout's buckets (`cb_prevpage`,
  /// `cb_nextpage`). Whether it was one of those.
  bool buttonAction(WasabiObject node) {
    final action = node["action"] ?? "";
    switch (action.toLowerCase()) {
      case "cb_prevpage" || "cb_prev":
        _turnBucketPages(node, forward: false);
        return true;
      case "cb_nextpage" || "cb_next":
        _turnBucketPages(node, forward: true);
        return true;
    }
    final targetId = node["action_target"];
    if (targetId == null || targetId.isEmpty) return false;
    final target = findNear(node, targetId);
    if (target != null) {
      // A color themes list runs its actions itself; a script's
      // `onAction` still hears of them.
      wasabiColorThemeAction(skin, host, target, action);
      vm.fire(wrap(target), "onaction", [
        action,
        node["param"] ?? "",
        0,
        0,
        0,
        0,
        wrap(node),
      ]);
    }
    return true;
  }

  /// Scrolls the buckets of [node]'s layout a page on or back
  /// (`ComponentBucket2::next_page`, `prev_page`).
  void _turnBucketPages(WasabiObject node, {required bool forward}) {
    final layout = layoutOf(node);
    if (layout == null) return;
    void visit(WasabiObject at) {
      for (final child in at.children) {
        if (child.tag == "componentbucket") {
          final rect = rectOf(child);
          // The Thinger's own buttons (a bucket with no groups of the
          // skin's) run along it.
          final own = child.children.isEmpty;
          final vertical = !own && wasabiBucketIsVertical(child);
          final page = vertical ? rect.height : rect.width;
          final extent = own
              ? wasabiThingerExtent(child, rect.size, skin)
              : wasabiBucketExtent(child, skin);
          final last = math.max(0.0, extent - page);
          final scroll = child.intAttr("#scroll");
          final next = forward
              ? math.min(last, scroll + page)
              : math.max(0.0, scroll - page);
          child.attributes["#scroll"] = "${next.round()}";
        } else {
          visit(child);
        }
      }
    }

    visit(layout.$2.root);
    changed();
  }

  /// Shows the groupdef [id] in the `<GroupXFade>` [node], whose
  /// `groupid` changed: the group is made the first time and kept, hidden,
  /// when another takes its place.
  void _showXFadeGroup(WasabiObject node, String id) {
    final key = id.toLowerCase();
    WasabiObject? shown;
    for (final child in node.children) {
      final match = child.id.toLowerCase() == key;
      child.attributes["visible"] = match ? "1" : "0";
      if (match) shown = child;
    }
    if (shown != null || key.isEmpty) return;
    final group = skin.newGroup(id);
    if (group == null) return;
    group.attributes.addAll(const {
      "x": "0",
      "y": "0",
      "w": "0",
      "h": "0",
      "relatw": "1",
      "relath": "1",
    });
    _attach(group, node);
  }

  /// A slider without a player action moved to [value] (0..1).
  void sliderMoved(WasabiObject node, double value, {required bool done}) {
    final position = _sliderPosition(node, value);
    node.attributes["#pos"] = "$position";
    // A slider bound to a skin option (`cfgattrib`) writes it.
    final cfgAttrib = WasabiCfgAttrib.parse(node["cfgattrib"]);
    if (cfgAttrib != null) setCfgAttribValue(cfgAttrib, position);
    changed();
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    vm.fire(wrapper, "onsetposition", [position]);
    if (done) {
      vm.fire(wrapper, "onsetfinalposition", [position]);
      vm.fire(wrapper, "onpostedposition", [position]);
    }
  }

  /// A key went down (or up) with nothing in the app taking it: every
  /// script hears `System.onKeyDown(name)` (`onKeyUp`), where [name] lists the
  /// keys held, joined by `+` (`ctrl+a`). Returns whether a script took it
  /// (`complete`), as Wasabi's `Keyboard::onForwardOnKeyDown` does.
  bool keyEvent(String name, {required bool down}) {
    if (_disposed || _systems.isEmpty) return false;
    final event = down ? "onkeydown" : "onkeyup";
    for (final system in List.of(_systems).reversed) {
      vm.fire(system, event, [name]);
      if (vm.completed) return true;
    }
    return false;
  }

  /// The window of [layout] moved: `Layout.onMove`; [ended] when the move is
  /// over (`Layout.onEndMove`).
  void layoutMoved(WasabiLayout layout, {required bool ended}) {
    if (_disposed) return;
    vm.fire(wrap(layout.root), ended ? "onendmove" : "onmove", const []);
  }

  /// Container [id] changes to [to] from [from] (a window shade, a switch
  /// action): `Container.onBeforeSwitchToLayout` and `onSwitchToLayout` with
  /// the new layout, `System.onHideLayout` / `onShowLayout` with each.
  void layoutSwitched(String id, WasabiLayout from, WasabiLayout to) {
    if (_disposed) return;
    final container = skin.container(id);
    if (container == null) return;
    final wrapper = _containers[container] ??= _MakiContainer(this, container);
    final next = wrap(to.root);
    vm.fire(wrapper, "onbeforeswitchtolayout", [next]);
    _broadcast("onhidelayout", [wrap(from.root)]);
    vm.fire(wrapper, "onswitchtolayout", [next]);
    _broadcast("onshowlayout", [next]);
  }

  /// The answer a popup menu was given, while the handler that opened it
  /// runs again to read it.
  int? _popupAnswer;

  /// `PopupMenu.popAtMouse`: -1 and the menu opens, or, when the handler runs
  /// again after a pick, that pick.
  int _popUp(_MakiPopupMenu menu) {
    final answer = _popupAnswer;
    if (answer != null) {
      _popupAnswer = null;
      return answer;
    }
    final handler = vm.runningHandler;
    host.showPopup(menu.items(), (id) {
      if (_disposed || handler == null) return;
      _popupAnswer = id;
      try {
        vm.rerun(handler);
      } finally {
        _popupAnswer = null;
      }
      changed();
    });
    return -1;
  }

  /// A key the skin's `<accelerators>` bind: every script hears
  /// `System.onAccelerator(action, section, key)`; true when one took it
  /// (`complete`), as `SystemObject::onAccelerator` and `Keyboard` do.
  bool accelerator(String action, String section, String key) {
    if (_disposed || _systems.isEmpty) return false;
    for (final system in List.of(_systems).reversed) {
      vm.fire(system, "onaccelerator", [action, section, key]);
      if (vm.completed) return true;
    }
    return false;
  }

  /// The user sought to [ms]: `System.onSeek`.
  void seeked(int ms) => _broadcast("onseek", [ms]);

  /// A slider bound to a player action was moved by the user to [value]
  /// (0..1): its scripts hear `onPostedPosition` (`SSeeker`, `SVolbar`).
  void sliderPosted(WasabiObject node, double value) {
    final wrapper = scriptObjectOf(node);
    if (wrapper == null) return;
    vm.fire(wrapper, "onpostedposition", [_sliderPosition(node, value)]);
  }

  /// The value (0..1) of a script-driven slider, or null.
  double? sliderValueOf(WasabiObject node) {
    // A slider bound to a skin option (`cfgattrib`) shows its value.
    final cfgAttrib = WasabiCfgAttrib.parse(node["cfgattrib"]);
    final bound = cfgAttrib == null ? null : cfgAttribValue(cfgAttrib);
    final position = bound ?? int.tryParse(node["#pos"] ?? "");
    if (position == null) return null;
    final (low, high) = _limits(node);
    return high == low ? 0 : (position - low) / (high - low);
  }

  WasabiCfgAttrib? _cfgOf(WasabiObject node) =>
      WasabiCfgAttrib.parse(node["cfgattrib"]);

  /// A bound option's value as a number: the option a script made, else the
  /// host's.
  int _cfgInt(WasabiCfgAttrib attribute) =>
      cfgAttribValue(attribute) ?? host.configValue(attribute);

  String _cfgString(WasabiCfgAttrib attribute) {
    final option = _cfgAttribute(attribute);
    return option != null ? option.data : "${host.configValue(attribute)}";
  }

  void _cfgSetString(WasabiCfgAttrib attribute, String value) {
    final option = _cfgAttribute(attribute);
    if (option != null) {
      option.setData(vm, value);
    } else {
      host.setConfigValue(attribute, int.tryParse(value.trim()) ?? 0);
      _cfgFollow(attribute);
    }
  }

  /// Tells the CfgGroups bound to [attribute] that it changed
  /// (`CfgGroup::onCfgChanged`).
  void _cfgFollow(WasabiCfgAttrib attribute, [_MakiConfigAttribute? option]) {
    for (final MapEntry(key: node, value: wrapper) in _wrappers.entries) {
      final bound = _cfgOf(node);
      if (bound == null || node.tag != "group") continue;
      final same = option != null
          ? identical(_cfgAttribute(bound), option)
          : bound.item == attribute.item && bound.name == attribute.name;
      if (same) vm.fire(wrapper, "oncfgchanged");
    }
  }

  /// Tells the scripts of the sliders bound to [attribute] that its value
  /// changed (`onSetPosition`), so what they show next to it follows.
  void _slidersFollow(_MakiConfigAttribute attribute) {
    for (final MapEntry(key: node, value: wrapper) in _wrappers.entries) {
      if (node.tag != "slider") continue;
      final cfgAttrib = WasabiCfgAttrib.parse(node["cfgattrib"]);
      if (cfgAttrib == null ||
          !identical(_cfgAttribute(cfgAttrib), attribute)) {
        continue;
      }
      final position = _sliderPosition(node, sliderValueOf(node) ?? 0);
      vm.fire(wrapper, "onsetposition", [position]);
    }
  }

  /// Whether a button is activated (by its action or `setActivated`).
  bool isActivated(WasabiObject node) => _activated(node);

  /// An `<NStatesButton>`'s states, or null for other buttons.
  static WasabiNStates? _nStates(WasabiObject node) {
    if (node.tag != "nstatesbutton") return null;
    final states = WasabiNStates(node);
    return states.count > 1 ? states : null;
  }

  /// The config value a toggle button stands for (`getCurCfgVal`): an
  /// `<NStatesButton>`'s state's, or 1 for an activated toggle button.
  int _curCfgVal(WasabiObject node) {
    final states = _nStates(node);
    if (states == null) return isActivated(node) ? 1 : 0;
    final cfgAttrib = WasabiCfgAttrib.parse(node["cfgattrib"]);
    if (cfgAttrib != null) {
      final value = cfgAttribValue(cfgAttrib) ?? host.configValue(cfgAttrib);
      if (states.stateOf(value) != null) return value;
    }
    return states.cfgValue(node.intAttr("#state"));
  }

  static bool _activated(WasabiObject node) => node["#active"] == "1";

  static (int, int) _limits(WasabiObject node) => (
    int.tryParse(node["low"] ?? "") ?? 0,
    int.tryParse(node["high"] ?? "") ?? 255,
  );

  static int _sliderPosition(WasabiObject node, double value) {
    final (low, high) = _limits(node);
    return (low + (high - low) * value).round();
  }

  // --- Player events -----------------------------------------------------------

  /// The player is about to quit (`System.onQuit`).
  void quitting() {
    if (!_disposed) _broadcast("onquit");
  }

  /// Whether the skin's main window shows the component [name] (`pl`, `ml`,
  /// `vis`, `video`) inside it, and it is showing.
  bool isEmbeddedComponentShown(String name) =>
      skin.embeddedComponents(name).any((node) => node.visible);

  /// Shows or hides the component [name] the skin has inside its main
  /// window. Showing one of the components that share a place (ASNW's
  /// playlist, video and visualization, all over the same area) hides the
  /// others. Returns false when the skin has no such component.
  bool setEmbeddedComponent(String name, bool shown) {
    final nodes = skin.embeddedComponents(name);
    if (nodes.isEmpty) return false;
    for (final node in nodes) {
      if (shown && (node["dynamic"] ?? "") == "1") {
        // The others of the place give way.
        for (final other in _dynamicComponents()) {
          if (identical(other, node) || other["x"] != node["x"]) continue;
          if (other["y"] == node["y"] && other["w"] == node["w"]) {
            _setNodeVisible(other, false);
          }
        }
      }
      _setNodeVisible(node, shown);
    }
    changed();
    return true;
  }

  Iterable<WasabiObject> _dynamicComponents() sync* {
    for (final name in const ["pl", "ml", "vis", "video"]) {
      for (final node in skin.embeddedComponents(name)) {
        if ((node["dynamic"] ?? "") == "1") yield node;
      }
    }
  }

  void _setNodeVisible(WasabiObject node, bool visible) {
    if (node.visible == visible) return;
    node.attributes["visible"] = visible ? "1" : "0";
    final wrapper = _wrappers[node];
    if (wrapper != null) vm.fire(wrapper, "onsetvisible", [visible]);
  }

  /// A dynamic component that is not `autoopen` starts closed
  /// (`<component dynamic="1" autoopen="0">`): ASNW's video and
  /// visualization wait behind its playlist until their buttons are used.
  void _closeComponentsThatStartClosed() {
    for (final node in _dynamicComponents()) {
      if ((node["autoopen"] ?? "1") == "0") node.attributes["visible"] = "0";
    }
  }

  /// Asks the skin's scripts to show their notification now
  /// (`System.onShowNotification`, which the classic player sends for its "show
  /// notification" hotkey). Returns false when no script handles it.
  bool showNotification() {
    var handled = false;
    for (final system in List.of(_systems)) {
      if (!vm.handles(system, "onshownotification")) continue;
      handled = true;
      vm.fire(system, "onshownotification");
    }
    return handled;
  }

  void _broadcast(String event, [List<Object?> args = const []]) {
    for (final system in List.of(_systems)) {
      vm.fire(system, event, args);
    }
  }

  /// Whether each container holding a component showed at the last look.
  final Map<WasabiContainer, bool> _componentShown = {};

  /// `System.onLookForComponent(guid)`: a component's window is about to be
  /// shown, where it was not.
  void _lookForComponents() {
    for (final container in skin.containers) {
      final spec = container.component;
      if (spec == null) continue;
      final shown = host.isContainerVisible(container.id);
      final was = _componentShown[container];
      _componentShown[container] = shown;
      if (!shown || was != false) continue;
      // `guid:{...}`, or a name such as `guid:pl`.
      final text = spec.startsWith("guid:") ? spec.substring(5) : spec;
      final guid = text.startsWith("{")
          ? text.toUpperCase()
          : wasabiComponentGuid(text);
      if (guid != null) _broadcast("onlookforcomponent", [guid]);
    }
  }

  /// The time each `display="time"` text a script holds showed last, to tell
  /// its scripts when it changes (`onTextChanged`).
  final Map<WasabiObject, String> _timeTexts = {};

  void _followTimeDisplays() {
    for (final entry in _wrappers.entries) {
      final node = entry.key;
      if (node.tag != "text" ||
          (node["display"] ?? "").toLowerCase() != "time" ||
          node["#text"] != null ||
          entry.value.bindings.isEmpty) {
        continue;
      }
      final text = wasabiTimeText(host, node);
      if (_timeTexts[node] == text) continue;
      _timeTexts[node] = text;
      vm.fire(entry.value, "ontextchanged", [text]);
    }
  }

  void _onHostChanged() {
    _followTimeDisplays();
    _lookForComponents();
    if (_plEdits.isNotEmpty) {
      final signature = _playlistHash();
      if (signature != _playlistSignature) {
        _playlistSignature = signature;
        for (final editor in List.of(_plEdits)) {
          vm.fire(editor, "onpleditmodified");
        }
      }
    }
    final status = host.playbackStatus;
    if (status != _status) {
      final was = _status;
      _status = status;
      switch (status) {
        case 1:
          _broadcast(was == -1 ? "onresume" : "onplay");
        case -1:
          _broadcast("onpause");
        default:
          _broadcast("onstop");
      }
      // What the song is (its artist, its album) is known once it plays:
      // scripts showing it read it again.
      if (was == 0 && status != 0) {
        _broadcast("ontitlechange", [host.trackTitle]);
      }
    }
    final title = host.trackTitle;
    if (title != _title) {
      _title = title;
      // Nothing is playing while stopped: the player loading its playlist
      // or the user picking another song is no news (the notifier would
      // pop up at start-up).
      if (status != 0) _broadcast("ontitlechange", [title]);
    }
    final info = host.songInfoText;
    if (info != _info) {
      _info = info;
      _broadcast("oninfochange", [info]);
    }
    final volume = host.sliderValue("VOLUME", null);
    if (volume != _volume) {
      _volume = volume;
      _broadcast("onvolumechanged", [((volume ?? 0) * 255).round()]);
    }
    final eq = host.isActive("EQ_TOGGLE", null);
    if (eq != _eq) {
      _eq = eq;
      _broadcast("oneqchanged", [eq ? 1 : 0]);
    }
    for (var i = 0; i < 10; i++) {
      final band = host.sliderValue("EQ_BAND", "${i + 1}");
      if (band != _bands[i]) {
        final first = _bands[i] == null;
        _bands[i] = band;
        if (!first) _broadcast("oneqbandchanged", [i, _eqValue(band)]);
      }
    }
    final preamp = host.sliderValue("EQ_PREAMP", null);
    if (preamp != _preamp) {
      final first = _preamp == null;
      _preamp = preamp;
      if (!first) _broadcast("oneqpreampchanged", [_eqValue(preamp)]);
    }
    final art = host.albumArt;
    if (!identical(art, _albumArt)) {
      _albumArt = art;
      if (art != null)
        _artSizes[host.playItemLocation] = (art.width, art.height);
      // A picture found is announced to every album art object
      // (AlbumArt::ArtLoaded); one that asked for a refresh hears of a
      // miss too ([_awaitArt]).
      if (art != null) {
        _artRefreshes.clear();
        for (final wrapper in List.of(_wrappers.values)) {
          if (wrapper.node.tag != "albumart") continue;
          vm.fire(wrapper, "onalbumartloaded", [true]);
        }
      }
    }
  }

  /// The size of the cover each played item had, by its file: what
  /// `Map.loadMap` of an audio file's path knows of it (the classic player reads the
  /// file's cover then; SC-Cover sizes its pictures from it).
  final Map<String, (int, int)> _artSizes = {};

  /// The cover size known for the audio file [path], or null.
  (int, int)? artSizeOf(String path) {
    final art = host.albumArt;
    if (art != null && path == host.playItemLocation) {
      return (art.width, art.height);
    }
    return _artSizes[path];
  }

  /// The album art objects that asked for a refresh and have not heard of
  /// the result.
  final Set<MakiGuiObject> _artRefreshes = {};

  /// How long (in 50 ms ticks) a refresh waits for the cover: a podcast's or
  /// audiobook's is downloaded from its server first, which takes longer than
  /// reading a file's.
  static const _artWaitTicks = 400;
  Timer? _artTimer;

  /// Tells [object] how its refresh went once the cover is read:
  /// `onAlbumArtLoaded` with true for a picture, false for none (the
  /// notifier waits for it before it shows).
  void _awaitArt(MakiGuiObject object) {
    _artRefreshes.add(object);
    var ticks = 0;
    _artTimer ??= Timer.periodic(const Duration(milliseconds: 50), (timer) {
      ticks++;
      if (_disposed || _artRefreshes.isEmpty || ticks > _artWaitTicks) {
        timer.cancel();
        _artTimer = null;
        _artRefreshes.clear();
        return;
      }
      if (host.albumArtLoading) return;
      timer.cancel();
      _artTimer = null;
      final found = host.albumArt != null;
      for (final waiting in List.of(_artRefreshes)) {
        vm.fire(waiting, "onalbumartloaded", [found]);
      }
      _artRefreshes.clear();
    });
  }

  /// An EQ value in the script scale (-127..127).
  static int _eqValue(double? value) => (((value ?? 0.5) - 0.5) * 254).round();

  // --- System -------------------------------------------------------------------

  String? _private(String section, String item) =>
      host.readPrivate("${skin.name}/$section", item);

  Object? _system(_MakiSystem system, String member, List<Object?> a) {
    String s(int i) => a[i] as String? ?? "";
    int n(int i) => (a[i] as int?) ?? 0;
    double d(int i) => (a[i] as double?) ?? 0;
    switch (member) {
      // Script.
      case "getscriptgroup":
        final group = system.group;
        return group == null ? null : wrap(group);
      case "getparam":
        return system.param;
      case "getruntimeversion":
        return 5.666;
      case "getskinname":
        return skin.name;
      case "messagebox":
        _log("MAKI message: ${s(1)}: ${s(0)}");
        return 0;
      case "debugstring":
        _log("MAKI: ${s(0)}");
        return null;
      case "translate":
        return s(0);
      // Settings.
      case "getprivateint":
        return int.tryParse(_private(s(0), s(1)) ?? "") ?? n(2);
      case "setprivateint":
        host.writePrivate("${skin.name}/${s(0)}", s(1), "${n(2)}");
        return null;
      case "getprivatestring":
        return _private(s(0), s(1)) ?? s(2);
      case "setprivatestring":
        host.writePrivate("${skin.name}/${s(0)}", s(1), s(2));
        return null;
      case "getpublicint":
        return int.tryParse(host.readPrivate("public", s(0)) ?? "") ?? n(1);
      case "setpublicint":
        host.writePrivate("public", s(0), "${n(1)}");
        return null;
      case "getpublicstring":
        return host.readPrivate("public", s(0)) ?? s(1);
      case "setpublicstring":
        host.writePrivate("public", s(0), s(1));
        return null;
      // Strings and numbers.
      case "integertostring":
        return "${n(0)}";
      case "stringtointeger":
        return int.tryParse(
              RegExp(r"^\s*[+-]?\d+").stringMatch(s(0))?.trim() ?? "",
            ) ??
            0;
      case "floattostring":
        return d(0).toStringAsFixed(n(1).clamp(0, 20));
      case "stringtofloat":
        return double.tryParse(s(0).trim()) ?? 0.0;
      case "integertotime" || "integertolongtime":
        final total = n(0) ~/ 1000;
        final h = total ~/ 3600;
        final m = (total ~/ 60) % 60;
        final sec = (total % 60).toString().padLeft(2, "0");
        if (member == "integertolongtime" || h > 0) {
          return "$h:${m.toString().padLeft(2, "0")}:$sec";
        }
        return "$m:$sec";
      // File names: `getExtension` takes what follows the last dot (none
      // for a dotfile or no dot), `removePath` what follows the last slash.
      case "getextension":
        final name = s(0);
        final dot = name.lastIndexOf(".");
        return dot <= 0 || dot == name.length - 1
            ? ""
            : name.substring(dot + 1);
      case "removepath":
        final name = s(0);
        return name.substring(name.lastIndexOf(RegExp(r"[\\/]")) + 1);
      case "getpath":
        final name = s(0);
        final cut = name.lastIndexOf(RegExp(r"[\\/]"));
        return cut < 0 ? "" : name.substring(0, cut);
      case "chr":
        return String.fromCharCode(n(0));
      case "urlencode":
        return Uri.encodeComponent(s(0));
      case "urldecode":
        try {
          return Uri.decodeComponent(s(0));
        } on ArgumentError {
          return s(0);
        }
      case "frac":
        final value = d(0);
        return value - value.truncate();
      case "getdateyear" ||
          "getdatemonth" ||
          "getdateday" ||
          "getdatedow" ||
          "getdatedoy" ||
          "getdatehour" ||
          "getdatemin" ||
          "getdatesec" ||
          "getdatedst":
        final date = DateTime.fromMillisecondsSinceEpoch(n(0) * 1000);
        return switch (member) {
          "getdateyear" => date.year - 1900,
          "getdatemonth" => date.month - 1,
          "getdateday" => date.day,
          "getdatedow" => date.weekday % 7,
          "getdatedoy" => date.difference(DateTime(date.year)).inDays,
          "getdatehour" => date.hour,
          "getdatemin" => date.minute,
          "getdatesec" => date.second,
          _ => 0,
        };
      case "formatdate" || "formatlongdate":
        final date = DateTime.fromMillisecondsSinceEpoch(n(0) * 1000);
        return member == "formatdate"
            ? "${date.month}/${date.day}/${date.year}"
            : "${_months[date.month - 1]} ${date.day}, ${date.year}";
      case "datetotime" || "datetolongtime":
        final date = DateTime.fromMillisecondsSinceEpoch(n(0) * 1000);
        String two(int v) => v.toString().padLeft(2, "0");
        return member == "datetotime"
            ? "${date.hour}:${two(date.minute)}"
            : "${date.hour}:${two(date.minute)}:${two(date.second)}";
      case "playfile" || "enqueuefile":
        host.openPath(wasabiNativePath(s(0)), play: member == "playfile");
        return null;
      case "setclipboardtext":
        unawaited(Clipboard.setData(ClipboardData(text: s(0))));
        return null;
      case "switchskin":
        host.switchSkin(s(0));
        return null;
      // The application's window rectangle, -1 when there is none.
      case "getcurappleft" ||
          "getcurapptop" ||
          "getcurappwidth" ||
          "getcurappheight":
        final rect = host.appRect;
        if (rect == null) return -1;
        return switch (member) {
          "getcurappleft" => rect.left.round(),
          "getcurapptop" => rect.top.round(),
          "getcurappwidth" => rect.width.round(),
          _ => rect.height.round(),
        };
      // No components of Wasabi 3's kind exist (`getWac` answers null for
      // a GUID nothing registered), and the window and system menus are
      // Wasabi 3 compatibility calls that do nothing in Wasabi 5.
      case "getwac":
        return null;
      case "windowmenu" || "systemmenu":
        return null;
      // Whether the file has cover art: the current item's is the one known.
      case "getalbumart":
        return s(0) == host.playItemLocation && host.albumArt != null ? 1 : 0;
      case "minimizeapplication":
        host.runAction(const WasabiAction("MINIMIZE", null, container: ""));
        return null;
      case "strlen":
        return s(0).length;
      case "strupper":
        return s(0).toUpperCase();
      case "strlower":
        return s(0).toLowerCase();
      case "strleft":
        return s(0).substring(0, n(1).clamp(0, s(0).length));
      case "strright":
        final text = s(0);
        return text.substring(text.length - n(1).clamp(0, text.length));
      case "strmid":
        final text = s(0);
        final start = n(1).clamp(0, text.length);
        final length = n(2) < 0 ? text.length - start : n(2);
        return text.substring(
          start,
          (start + length).clamp(start, text.length),
        );
      case "strsearch":
        return s(0).indexOf(s(1));
      case "gettoken":
        final tokens = s(0).split(s(1));
        final index = n(2);
        return index >= 0 && index < tokens.length ? tokens[index] : "";
      case "random":
        return n(0) <= 0 ? 0 : math.Random().nextInt(n(0));
      case "sin":
        return math.sin(d(0));
      case "cos":
        return math.cos(d(0));
      case "tan":
        return math.tan(d(0));
      case "asin":
        return math.asin(d(0));
      case "acos":
        return math.acos(d(0));
      case "atan":
        return math.atan(d(0));
      case "atan2":
        return math.atan2(d(0), d(1));
      case "pow":
        return math.pow(d(0), d(1)).toDouble();
      case "sqr":
        return d(0) * d(0);
      case "sqrt":
        return math.sqrt(d(0));
      case "log10":
        return math.log(d(0)) / math.ln10;
      case "ln":
        return math.log(d(0));
      case "frand":
        return math.Random().nextDouble() * d(0);
      // Time.
      case "gettimeofday":
        final now = DateTime.now();
        return ((now.hour * 60 + now.minute) * 60 + now.second) * 1000 +
            now.millisecond;
      case "gettickcount" || "getmstime":
        return DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      case "getdate":
        return DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Playback.
      case "getstatus":
        return host.playbackStatus;
      case "play":
        host.runAction(const WasabiAction("PLAY", null, container: ""));
        return null;
      case "stop":
        host.runAction(const WasabiAction("STOP", null, container: ""));
        return null;
      case "pause":
        host.runAction(const WasabiAction("PAUSE", null, container: ""));
        return null;
      case "next":
        host.runAction(const WasabiAction("NEXT", null, container: ""));
        return null;
      case "previous":
        host.runAction(const WasabiAction("PREV", null, container: ""));
        return null;
      case "eject":
        host.runAction(const WasabiAction("EJECT", null, container: ""));
        return null;
      case "getposition":
        return math.max(0, host.positionMs);
      case "seekto":
        host.seekTo(n(0));
        return null;
      case "getplayitemlength":
        return host.lengthMs;
      // The plug-in that plays a file: not one the classic player would name.
      case "getdecodername":
        return "";
      case "getplayitemstring":
        return host.playItemLocation;
      case "getplayitemdisplaytitle":
        return host.trackTitle;
      case "getsonginfotext" || "getsonginfotexttranslated":
        return host.songInfoText;
      case "getplayitemmetadatastring":
        return host.playItemMetadata(s(0));
      case "getplaylistindex":
        return host.playlistCurrent;
      case "getplaylistlength":
        return host.playlistLength;
      case "getvolume":
        return ((host.sliderValue("VOLUME", null) ?? 0) * 255).round();
      case "setvolume":
        host.setSliderValue(
          "VOLUME",
          null,
          n(0).clamp(0, 255) / 255,
          done: true,
        );
        return null;
      case "getbalance":
        return (((host.sliderValue("PAN", null) ?? 0.5) - 0.5) * 254).round();
      case "setbalance":
        host.setSliderValue(
          "PAN",
          null,
          (n(0).clamp(-127, 127) + 127) / 254,
          done: true,
        );
        return null;
      case "geteq":
        return host.isActive("EQ_TOGGLE", null) ? 1 : 0;
      case "seteq":
        if ((n(0) != 0) != host.isActive("EQ_TOGGLE", null)) {
          host.runAction(const WasabiAction("EQ_TOGGLE", null, container: ""));
        }
        return null;
      case "geteqband":
        return _eqValue(host.sliderValue("EQ_BAND", "${n(0) + 1}"));
      case "seteqband":
        host.setSliderValue(
          "EQ_BAND",
          "${n(0) + 1}",
          (n(1).clamp(-127, 127) + 127) / 254,
          done: true,
        );
        return null;
      case "geteqpreamp":
        return _eqValue(host.sliderValue("EQ_PREAMP", null));
      case "seteqpreamp":
        host.setSliderValue(
          "EQ_PREAMP",
          null,
          (n(0).clamp(-127, 127) + 127) / 254,
          done: true,
        );
        return null;
      case "getleftvumeter" || "getrightvumeter":
        return _vuMeter(left: member == "getleftvumeter");
      case "getvisband":
        return 0;
      case "isvideo":
        return host.videoPlaying;
      case "isvideofullscreen":
        return host.videoFullscreen;
      case "isminimized":
        return host.appMinimized;
      case "iskeydown":
        return false;
      case "isdesktopalphaavailable" ||
          "istransparencyavailable" ||
          "isappactive":
        return true;
      case "isobjectvalid":
        return a[0] != null;
      // Windows.
      case "getcontainer":
        return _container(s(0));
      // Dynamic containers are the skin's own containers here; one the skin
      // does not define cannot be made.
      case "newdynamiccontainer":
        return _newDynamicContainer(system, s(0));
      case "newgroup" || "newgroupaslayout":
        final group = skin.newGroup(s(0));
        return group == null ? null : wrap(group);
      case "getnumcontainers":
        return skin.containers.length;
      case "enumcontainer":
        final i = n(0);
        return i >= 0 && i < skin.containers.length
            ? _container(skin.containers[i].id)
            : null;
      case "isnamedwindowvisible":
        return host.isContainerVisible(s(0));
      case "shownamedwindow" || "showwindow":
        host.setContainerVisible(s(0), true);
        return null;
      case "hidenamedwindow":
        host.setContainerVisible(s(0), false);
        return null;
      case "getviewportwidth" ||
          "getviewportwidthfromguiobject" ||
          "getviewportwidthfrompoint" ||
          "getmonitorwidth" ||
          "getmonitorwidthfromguiobject" ||
          "getmonitorwidthfrompoint":
        // In skin pixels: at double size a skin that stretches to the width of
        // the screen is told the screen is half as wide.
        sizesDependOnScale = true;
        return (host.viewport.width / _skinScale(system)).round();
      case "getviewportheight" ||
          "getviewportheightfromguiobject" ||
          "getviewportheightfrompoint" ||
          "getmonitorheight" ||
          "getmonitorheightfromguiobject" ||
          "getmonitorheightfrompoint":
        sizesDependOnScale = true;
        return (host.viewport.height / _skinScale(system)).round();
      case "getviewportleft" ||
          "getviewportleftfromguiobject" ||
          "getviewportleftfrompoint" ||
          "getmonitorleft" ||
          "getmonitorleftfromguiobject" ||
          "getmonitorleftfrompoint":
        return host.viewport.left.round();
      case "getviewporttop" ||
          "getviewporttopfromguiobject" ||
          "getviewporttopfrompoint" ||
          "getmonitortop" ||
          "getmonitortopfromguiobject" ||
          "getmonitortopfrompoint":
        return host.viewport.top.round();
      case "getmouseposx":
        // In the viewport's pixels, like a layout's position.
        return (host.cursorPosition.dx - host.viewport.left).round();
      case "getmouseposy":
        return (host.cursorPosition.dy - host.viewport.top).round();
      case "lockui" || "unlockui":
        return null;
      // A skin's link opens in the user's browser (there is no browser of
      // the original's own here); only web and mail links, not files or programs.
      case "navigateurl" || "navigateurlbrowser":
        final url = s(0).trim();
        final lower = url.toLowerCase();
        if (lower.startsWith("http://") ||
            lower.startsWith("https://") ||
            lower.startsWith("mailto:")) {
          host.openExternal(url);
        }
        return null;
      // The browser component is not built: no main browser to get or pop.
      case "getmainbrowser" || "popmainbrowser":
        return null;
      // The system's locale, as `en-US`.
      case "getlanguageid":
        return Platform.localeName.split(".").first.replaceAll("_", "-");
      case "getcurrenttrackrating":
        return 0;
      case "setcurrenttrackrating":
        return null;
      case "getwinampversion":
        return "5.666";
      case "getbuildnumber":
        return 3516;
      case "getfilesize":
        final path = skin.resolveFile(skin.expandPathVariables(s(0)));
        return path == null ? 0 : WasabiFiles.length(path);
      case "activateapplication" || "restoreapplication":
        host.activateApplication();
        return null;
      case "triggeraction":
        return null;
      case "integer":
        // A double loses its fraction (`GET_SCRIPT_INT`: a C cast).
        return ((a[0] as num?) ?? 0).truncate();
    }
    return makiUnhandled;
  }

  // --- GUI objects -------------------------------------------------------------

  Object? _gui(MakiGuiObject object, String member, List<Object?> a) {
    final node = object.node;
    // A tag whose group embeds a button (`embed_xui`: ClassicPro's tabs) is
    // that button for what a button does.
    if (node.tag == "group" &&
        node["embed_xui"] != null &&
        const {
          "setactivated",
          "setactivatednocallback",
          "setchecked",
          "getactivated",
          "ischecked",
        }.contains(member)) {
      final id = node["embed_xui"]!.trim().toLowerCase();
      WasabiObject? find(WasabiObject from) {
        for (final child in from.children) {
          if (child.id.toLowerCase() == id) return child;
          final found = find(child);
          if (found != null) return found;
        }
        return null;
      }

      final button = find(node);
      if (button != null) return _gui(wrap(button), member, a);
    }
    String s(int i) => a[i] as String? ?? "";
    int n(int i) => (a[i] as int?) ?? 0;
    double d(int i) => (a[i] as double?) ?? 0;
    switch (member) {
      case "getid":
        return node.id;
      case "show":
        _setVisible(object, true);
        return null;
      case "hide":
        _setVisible(object, false);
        return null;
      case "isvisible":
        return node.visible && (node.tag != "layout" || _layoutVisible(node));
      case "setxmlparam":
        final name = s(0).toLowerCase();
        // An object keeps the id it has: ClassicPro copies every attribute
        // of a style into its text, `id` among them, and other scripts
        // still look the text up by its own.
        if (name == "id") return null;
        final known = node.attributes.containsKey(name);
        node.attributes[name] = s(1);
        if (name == "visible") node.attributes["#visible"] = s(1);
        if (name == "groupid" && node["#xfade"] == "1") {
          _showXFadeGroup(node, s(1));
        }
        _setXuiParam(node, name, s(1), unknown: !known);
        changed();
        return null;
      case "getxmlparam":
        final key = s(0).toLowerCase();
        // A text's string is its `text` parameter, whether the skin or a
        // script (`setText`) put it there.
        if (key == "text" && node["#text"] != null) return node["#text"];
        return node[key] ?? "";
      case "getleft":
        // A layout is a window: its place on the screen.
        return (node.parent == null
                ? guiPositionOf(node)["x"]!
                : rectOf(node).left)
            .round();
      case "gettop":
        return (node.parent == null
                ? guiPositionOf(node)["y"]!
                : rectOf(node).top)
            .round();
      // A text is as wide as what it says (Amped Modern's title bars
      // center their titles by it).
      case "getautowidth" when node.tag == "text" || node.tag == "songticker":
        return wasabiTextAutoWidth(
          node,
          skin,
          componentName: layoutOf(node)?.$1.name,
        ).round();
      case "getautoheight" when node.tag == "text" || node.tag == "songticker":
        return wasabiTextAutoHeight(node, skin).round();
      case "getwidth" || "getautowidth":
        return rectOf(node).width.round();
      case "getheight" || "getautoheight":
        return rectOf(node).height.round();
      case "getguix":
        return guiPositionOf(node)["x"]!.round();
      case "getguiy":
        return guiPositionOf(node)["y"]!.round();
      case "getguiw":
        return guiPositionOf(node)["w"]!.round();
      case "getguih":
        return guiPositionOf(node)["h"]!.round();
      case "resize":
        // Two windows that keep each other the same size (a skin's frame and
        // the window it follows) answer each other's onResize with a resize
        // to the size already there: that one tells nobody, or it never ends.
        // A window never takes more than its layout allows (its maximum
        // size, which ClassicPro keeps at the screen's) or the display it is
        // on, whatever a script working from mouse positions asks for.
        var (w, h) = (n(2), n(3));
        if (node.tag == "layout") {
          (w, h) = _limitedWindowSize(node, w, h);
          _promoteFrame(node, w, h);
        }
        final unchanged =
            node.attributes["x"] == "${n(0)}" &&
            node.attributes["y"] == "${n(1)}" &&
            node.attributes["w"] == "$w" &&
            node.attributes["h"] == "$h";
        if (unchanged && _resizing.contains(node)) return null;
        node.attributes
          ..["x"] = "${n(0)}"
          ..["y"] = "${n(1)}"
          ..["w"] = "$w"
          ..["h"] = "$h";
        changed();
        if (node.tag == "layout" || node.tag == "group") {
          _resizing.add(node);
          try {
            vm.fire(object, "onresize", [n(0), n(1), w, h]);
            // A script resizing its layout (ClassicPro's maximize): what is
            // sized from the layout's size hears it, as with a drag.
            if (node.tag == "layout" && !unchanged) _tellGroupsResized(node);
          } finally {
            _resizing.remove(node);
          }
        }
        return null;
      case "getalpha":
        return node.alpha;
      case "getscale":
        // A script's own scale for the object, else the window's.
        final own = double.tryParse(node.attributes["#scale"] ?? "");
        final layout = layoutOf(node);
        return own ?? (layout == null ? 1.0 : host.layoutScale(layout.$1.id));
      case "setscale":
        node.attributes["#scale"] = "${d(0)}";
        if (node.tag == "layout") vm.fire(object, "onscale", [d(0)]);
        changed();
        return null;
      case "setalpha":
        // setAlpha sets both the active and the inactive alpha.
        node.attributes
          ..["alpha"] = "${n(0).clamp(0, 255)}"
          ..remove("activealpha")
          ..remove("inactivealpha");
        changed();
        return null;
      case "setenabled":
        node.attributes["#enabled"] = (a[0] == true) ? "1" : "0";
        return null;
      case "getenabled":
        return node["#enabled"] != "0";
      case "getparent":
        final parent = node.parent;
        return parent == null ? null : wrap(parent);
      case "getparentlayout":
        final layout = layoutOf(node);
        return layout == null ? null : wrap(layout.$2.root);
      case "findobject" || "getobject":
        final found = findNear(node, s(0));
        return found == null ? null : wrap(found);
      case "clienttoscreenx" ||
          "clienttoscreeny" ||
          "screentoclientx" ||
          "screentoclienty" ||
          "clienttoscreenw" ||
          "clienttoscreenh":
        return n(0);
      // `GuiObject.sendAction`: the object's scripts hear `onAction` and
      // answer (ClassicPro's tabs ask the CentroSUI group to show a tab).
      case "sendaction":
        final answer = vm.fire(object, "onaction", [
          s(0),
          s(1),
          n(2),
          n(3),
          n(4),
          n(5),
          null,
        ]);
        return answer is int ? answer : 0;
      case "settargetx":
        object._target["x"] = n(0).toDouble();
        return null;
      case "settargety":
        object._target["y"] = n(0).toDouble();
        return null;
      case "settargetw":
        object._target["w"] = n(0).toDouble();
        return null;
      case "settargeth":
        object._target["h"] = n(0).toDouble();
        return null;
      case "settargeta":
        object._target["alpha"] = n(0).toDouble();
        return null;
      case "settargetspeed":
        // Kept in whole quarter seconds (GuiObjectI::guiobject_setTargetSpeed).
        object._speed = (d(0) * 4).truncate() / 4;
        return null;
      case "reversetarget":
        object._reverse = a[0] == true || (a[0] is int && a[0] != 0);
        return null;
      case "gototarget":
        object._goToTarget();
        return null;
      case "isgoingtotarget":
        return object._animation != null;
      case "canceltarget":
        object._animation?.cancel();
        object._animation = null;
        return null;
      // Text.
      case "settext":
        node.attributes["#text"] = s(0);
        if (node.tag == "edit") skin.playlistFilter.value = s(0);
        changed();
        vm.fire(object, "ontextchanged", [s(0)]);
        return null;
      // The width of a Text's string in its font.
      case "gettextwidth":
        final text = node["#text"] ?? node["text"] ?? node["default"] ?? "";
        if (text.isEmpty) return 0;
        return math
            .max(
              0,
              wasabiTextAutoWidth(node, skin) -
                  4 -
                  node.intAttr("leftpadding") -
                  node.intAttr("rightpadding"),
            )
            .round();
      // A TabSheet's page.
      case "getcurpage":
        return int.tryParse(node["#page"] ?? "") ?? 0;
      case "setcurpage":
        final pages = node.children;
        if (pages.isEmpty) return null;
        final page = n(0).clamp(0, pages.length - 1);
        final current = int.tryParse(node["#page"] ?? "") ?? 0;
        if (page != current) {
          setNodeVisible(pages[current.clamp(0, pages.length - 1)], false);
          setNodeVisible(pages[page], true);
        }
        node.attributes["#page"] = "$page";
        changed();
        return null;
      // Centers a layout's window on its screen.
      case "center" when layoutOf(node)?.$2.root == node:
        host.centerWindow(layoutOf(node)!.$1.id);
        return null;
      // A WindowHolder's component.
      case "getcomponentname" when node.tag == "windowholder":
        final name = wasabiComponentName(node);
        return (name == null ? null : wasabiComponentTitle(name)) ?? "";
      case "getguid" when node.tag == "windowholder":
        final name = wasabiComponentName(node);
        return (name == null ? null : wasabiComponentGuid(name)) ??
            "{00000000-0000-0000-0000-000000000000}";
      case "getcontent" when node.tag == "windowholder":
        return wasabiComponentName(node) == null ? null : object;
      // A CfgGroup's (and any GuiObject's) config attribute.
      case "cfggetint" || "cfg_getint" when _cfgOf(node) != null:
        return _cfgInt(_cfgOf(node)!);
      case "cfgsetint" || "cfg_setint" when _cfgOf(node) != null:
        if (!setCfgAttribValue(_cfgOf(node)!, n(0))) {
          host.setConfigValue(_cfgOf(node)!, n(0));
          _cfgFollow(_cfgOf(node)!);
        }
        return null;
      case "cfggetfloat" || "cfg_getfloat" when _cfgOf(node) != null:
        return double.tryParse(_cfgString(_cfgOf(node)!).trim()) ?? 0.0;
      case "cfgsetfloat" || "cfg_setfloat" when _cfgOf(node) != null:
        _cfgSetString(_cfgOf(node)!, "${d(0)}");
        return null;
      case "cfggetstring" || "cfg_getstring" when _cfgOf(node) != null:
        return _cfgString(_cfgOf(node)!);
      case "cfgsetstring" || "cfg_setstring" when _cfgOf(node) != null:
        _cfgSetString(_cfgOf(node)!, s(0));
        return null;
      case "cfggetguid" || "cfg_getitemguid" when _cfgOf(node) != null:
        return _cfgOf(node)!.item;
      case "cfggetname" || "cfg_getattributename" when _cfgOf(node) != null:
        return _cfgOf(node)!.name;
      // Triggers `onRightClick` as a right click would.
      case "rightclick":
        vm.fire(object, "onrightclick");
        return null;
      // Stacking order among its siblings: later children draw on top.
      case "bringtofront" || "bringtoback" || "bringabove" || "bringbelow":
        final parent = node.parent;
        if (parent == null) return null;
        final other = a.isEmpty || a[0] is! MakiGuiObject
            ? null
            : (a[0] as MakiGuiObject).node;
        final siblings = parent.children;
        if (!siblings.remove(node)) return null;
        switch (member) {
          case "bringtofront":
            siblings.add(node);
          case "bringtoback":
            siblings.insert(0, node);
          default:
            final at = other == null ? -1 : siblings.indexOf(other);
            if (at < 0) {
              siblings.add(node);
            } else {
              siblings.insert(member == "bringabove" ? at + 1 : at, node);
            }
        }
        changed();
        return null;
      // Gives the keyboard focus: an Edit takes it for typing, anything else
      // has its window take it.
      case "setfocus":
        if (node.tag == "edit") {
          node.attributes["#focus"] = "${(node.intAttr("#focus")) + 1}";
          changed();
        }
        final owner = layoutOf(node);
        if (owner != null) host.focusWindow(owner.$1.id);
        return null;
      case "selectall" when node.tag == "edit":
        node.attributes["#selectall"] = "1";
        node.attributes["#focus"] = "${(node.intAttr("#focus")) + 1}";
        changed();
        return null;
      case "enter" when node.tag == "edit":
        editSubmitted(node);
        return null;
      case "setautoenter" when node.tag == "edit":
        node.attributes["autoenter"] = "${n(0)}";
        return null;
      case "getautoenter" when node.tag == "edit":
        return node.intAttr("autoenter");
      case "setidleenabled" when node.tag == "edit":
        node.attributes["#idle"] = "${n(0)}";
        return null;
      case "getidleenabled" when node.tag == "edit":
        return int.tryParse(node["#idle"] ?? "1") ?? 1;
      // A LayoutStatus: a push of the button named by the action string.
      case "callme" when node.tag == "layoutstatus":
        final parts = s(0).split(";");
        host.runAction(
          WasabiAction(
            parts.first.toUpperCase(),
            parts.length > 1 ? parts.sublist(1).join(";") : null,
            container: layoutOf(node)?.$1.id ?? "",
          ),
        );
        return null;
      case "gettext":
        // A time display is read as it shows (Avalon's timer script).
        if (node["#text"] == null &&
            node.tag == "text" &&
            (node["display"] ?? "").toLowerCase() == "time") {
          return wasabiTimeText(host, node);
        }
        final text = node["#text"] ?? node["text"] ?? node["default"] ?? "";
        // `:componentname` is the name of the window the text is in.
        if (text.toLowerCase() == ":componentname") {
          return layoutOf(node)?.$1.name ?? "";
        }
        return text;
      case "setalternatetext":
        node.attributes["#text"] = s(0);
        changed();
        return null;
      // Buttons.
      case "setactivated" || "setactivatednocallback" || "setchecked":
        final on = a[0] == true || (a[0] is num && a[0] != 0);
        node.attributes["#active"] = on ? "1" : "0";
        changed();
        if (member == "setactivated") vm.fire(object, "onactivate", [on]);
        return null;
      case "ischecked":
        return isActivated(node);
      case "getactivated":
        return _nStates(node) != null
            ? _curCfgVal(node) != 0
            : isActivated(node);
      case "leftclick":
        buttonClicked(node);
        // As a click on the button does: what its action says, unless the
        // scripts run it (Mercury's mode menu clicks buttons that switch
        // the layout).
        final action = node["action"]?.toUpperCase();
        if (!buttonAction(node) && action != null && action.isNotEmpty) {
          host.runAction(
            WasabiAction(
              action,
              node["param"],
              container: layoutOf(node)?.$1.id ?? "",
            ),
          );
        }
        return null;
      case "getcurcfgval":
        return _curCfgVal(node);
      // Sliders.
      case "getposition":
        final value =
            sliderValueOf(node) ??
            host.sliderValue(
              (node["action"] ?? "").toUpperCase(),
              node["param"],
            ) ??
            0;
        return _sliderPosition(node, value);
      case "setposition":
        // The position is kept within the slider's limits and `onSetPosition`
        // follows at once (`SliderWnd::setPosition` with `wantcb`), unless
        // that handler is what set it.
        final (low, high) = _limits(node);
        final position = math.max(
          math.min(low, high),
          math.min(math.max(low, high), n(0)),
        );
        node.attributes["#pos"] = "$position";
        final cfgAttrib = WasabiCfgAttrib.parse(node["cfgattrib"]);
        if (cfgAttrib != null) setCfgAttribValue(cfgAttrib, position);
        changed();
        if (node.attributes["#inpos"] != "1") {
          node.attributes["#inpos"] = "1";
          try {
            vm.fire(object, "onsetposition", [position]);
          } finally {
            node.attributes.remove("#inpos");
          }
        }
        return null;
      // Layouts and groups.
      case "getcontainer":
        final layout = layoutOf(node);
        return layout == null
            ? null
            : (_containers[layout.$1] ??= _MakiContainer(this, layout.$1));
      case "isactive":
        final layout = layoutOf(node);
        if (layout == null) return true;
        // A frame drawn over a window is active with it.
        var container = layout.$1;
        for (final MapEntry(key: owner, value: list) in _companions.entries) {
          if (list.any((e) => identical(e.$1, container))) {
            container = _layouts[owner.root]?.$1 ?? container;
            break;
          }
        }
        return host.isContainerActive(container.id);
      case "islayoutanimationsafe" || "istransparencysafe":
        return true;
      // A layout's snap adjustments: how much of each edge is not part
      // of the window (Amped Modern keeps 116 px under the player for its
      // config drawer). See [WasabiLayout.windowSize].
      case "getsnapadjustleft":
        return node.optInt("snapadjustleft") ?? 0;
      case "getsnapadjusttop":
        return node.optInt("snapadjusttop") ?? 0;
      case "getsnapadjustright":
        return node.optInt("snapadjustright") ?? 0;
      case "getsnapadjustbottom":
        return node.optInt("snapadjustbottom") ?? 0;
      case "snapadjust":
        // What a closed drawer leaves out, for the window to shrink
        // towards while the drawer slides back in.
        if (n(2) != 0 || n(3) != 0) {
          node.attributes["#closedadjust"] = "${n(2)},${n(3)}";
        }
        node.attributes
          ..["snapadjustleft"] = "${n(0)}"
          ..["snapadjusttop"] = "${n(1)}"
          ..["snapadjustright"] = "${n(2)}"
          ..["snapadjustbottom"] = "${n(3)}";
        changed();
        return null;
      // Between these, the window keeps the whole layout, so a drawer can
      // slide into the adjusted-away space before the new adjustment is
      // set.
      case "beforeredock":
        final layout = layoutOf(node)?.$2;
        if (layout != null && node.attributes["#redocking"] != "1") {
          _stopRedockTween(node);
          final from = layout.windowSize;
          node.attributes
            ..["#redockfrom"] = "${from.width},${from.height}"
            ..remove("#redockt")
            ..remove("#redockspeed");
        }
        node.attributes["#redocking"] = "1";
        changed();
        return null;
      case "redock":
        if (node.attributes["#redocking"] != "1") return null;
        _redock(node);
        changed();
        return null;
      case "init":
        final parent = a[0];
        if (parent is MakiGuiObject) _attach(node, parent.node);
        return null;
      case "refresh":
        if (node.tag == "albumart") {
          host.refreshAlbumArt();
          _awaitArt(object);
        }
        return null;
      // A region a script made from a map (Resin's equalizer bars).
      case "setregion" when node.tag.endsWith("layer"):
        final region = a[0];
        _setRegion(node, region is _MakiRegion ? region.copy() : null);
        return null;
      case "setregionfrommap" when node.tag.endsWith("layer"):
        final map = a[0];
        _setRegionFromMap(
          node,
          map is _MakiMap ? map : null,
          n(1),
          a[2] == true || (a[2] is int && a[2] != 0),
        );
        return null;
      // Layer effects: the image drawn through a warp the script computes.
      case final fx when fx.startsWith("fx_") && !fx.startsWith("fx_on"):
        return (object._fx ??= WasabiLayerFx._(object)).invoke(member, a);
      // Animated layers.
      case "gotoframe" ||
          "play" ||
          "stop" ||
          "pause" ||
          "togglepause" ||
          "setstartframe" ||
          "setendframe" ||
          "setspeed" ||
          "setautoreplay" ||
          "getlength" ||
          "getcurframe" ||
          "getstartframe" ||
          "getendframe" ||
          "getspeed" ||
          "getautoreplay" ||
          "isplaying" ||
          "ispaused" ||
          "isstopped":
        if (node.tag != "animatedlayer") {
          if (member.startsWith("get")) return 0;
          return member.startsWith("is") ? false : null;
        }
        return object._frames.invoke(member, a);
      // Vis: a script's mode (0 off, 1 analyzer, 2 oscilloscope) takes
      // the place of the player's on this object ([wasabiVisOptions]).
      case "setmode":
        node.attributes["#mode"] = "${n(0)}";
        changed();
        return null;
      case "nextmode":
        node.attributes["#mode"] = "${(node.intAttr("#mode", 1) + 1) % 3}";
        changed();
        return null;
      case "getmode":
        return node.intAttr("#mode", 1);
      // ComponentBucket: the skin's own groups it lists; no the classic player
      // components.
      case "getnumchildren":
        return node.tag == "componentbucket" ? node.children.length : 0;
      case "enumchildren":
        if (node.tag != "componentbucket") return null;
        final index = n(0);
        return index < 0 || index >= node.children.length
            ? null
            : wrap(node.children[index]);
      case "getscroll":
        return node.intAttr("#scroll");
      case "setscroll":
        node.attributes["#scroll"] = "${n(0)}";
        changed();
        return null;
      case "isloading" when node.tag == "albumart":
        return host.albumArtLoading;
      case "isinvalid" when node.tag == "albumart":
        return host.albumArt == null;
      // A layer or button whose picture is not in the skin is not there:
      // ClassicPro asks its optional `read.bg.*` layers (their pictures are
      // files only some skins carry) before it swaps in the artwork.
      case "isinvalid":
        final image = node["image"];
        return image != null &&
            image.isNotEmpty &&
            (node.tag == "layer" || node.tag == "button") &&
            skin.bitmap(image) == null;
      case "isloading":
        return false;
      // GuiObject.onNotify(cmd, param, a, b): a script's message to the
      // scripts that watch this object.
      case "onnotify":
        vm.fire(object, "onnotify", [s(0), s(1), a[2], a[3]]);
        return 0;
      // GuiList: the playlist search results Amped Modern sets up at load,
      // which amped does not draw.
      case "setfontsize":
        return null;
      // `Browser.navigateUrl` (no browser component here), `Edit`'s
      // auto-enter asked of another object and `MouseRedir` (clicks reach
      // the object they hit).
      case "navigateurl" || "setautoenter" || "setredirection":
        return null;
      case "getredirection":
        return null;
      // `Vis.setRealtime`: the analyzer here always runs on the live signal.
      // `isMouseOver(x, y)`: whether that point (in the window's pixels) is
      // inside the object; `isMouseOverRect()`: whether the pointer is.
      case "ismouseover":
        return _contains(node, Offset(n(0).toDouble(), n(1).toDouble()));
      case "ismouseoverrect":
        return _mouseOver(node);
      // List and browser options a skin sets that nothing here shows.
      case "seticonwidth" ||
          "seticonheight" ||
          "setshowicons" ||
          "setcancelieerrorpage":
        return null;
      case "setredraw" when node.tag == "grouplist":
        return null;
      // A GroupList: groups made from a groupdef, one under another.
      case "instantiate" when node.tag == "grouplist":
        WasabiObject? first;
        for (var i = 0; i < math.max(1, n(1)); i++) {
          final group = skin.newGroup(s(0));
          if (group == null) return null;
          var y = 0;
          for (final child in node.children) {
            y += child.intAttr("h");
          }
          group.attributes
            ..["x"] = "0"
            ..["y"] = "$y"
            ..["w"] = "0"
            ..["relatw"] = "1";
          _attach(group, node);
          first ??= group;
        }
        return first == null ? null : wrap(first);
      case "getnumitems" when node.tag == "grouplist":
        return node.children.length;
      case "enumitem" when node.tag == "grouplist":
        final i = n(0);
        return i >= 0 && i < node.children.length
            ? wrap(node.children[i])
            : null;
      case "removeall" when node.tag == "grouplist":
        node.children.clear();
        changed();
        return null;
      case "scrolltopercent" when node.tag == "grouplist":
        return null;
      // Group.getNumObjects / enumObject: its children.
      case "getnumobjects" when node.tag == "group":
        return _guiChildren(node).length;
      case "enumobject" when node.tag == "group":
        final i = n(0);
        final objects = _guiChildren(node);
        return i >= 0 && i < objects.length ? wrap(objects[i]) : null;
      case "setrealtime" when node.tag == "vis":
        return null;
      case "getrealtime" when node.tag == "vis":
        return 1;
      // A script calling an event of the object itself (`onActivate`,
      // `onAction`): the scripts that handle it hear it.
      case "onactivate" || "onaction":
        return vm.fire(object, member, a);
    }
    // An event of a class the object is not: a script holds a `ToggleButton`
    // in a variable and calls `onToggle` on an XML `<button>`; the handlers
    // of the scripts holding the object hear it all the same.
    if (member.startsWith("on") &&
        makiClasses.values.any(
          (c) =>
              c.members[member] != null && c.members[member]!.returns == null,
        )) {
      return vm.fire(object, member, a);
    }
    return makiUnhandled;
  }

  bool _layoutVisible(WasabiObject root) {
    final layout = _layouts[root];
    if (layout == null || root["#hidden"] == "1") return false;
    return host.isContainerVisible(layout.$1.id) &&
        (host.currentLayout(layout.$1.id)?.toLowerCase() ??
                layout.$2.id.toLowerCase()) ==
            layout.$2.id.toLowerCase();
  }

  /// Sets the text of [node] the way a script's `setText` does.
  void setNodeText(WasabiObject node, String text) {
    node.attributes["#text"] = text;
    changed();
    final wrapper = _wrappers[node];
    if (wrapper != null) vm.fire(wrapper, "ontextchanged", [text]);
  }

  /// Shows or hides [node] the way a tab sheet does, telling its scripts.
  void setNodeVisible(WasabiObject node, bool visible) {
    final wrapper = _wrappers[node];
    if (wrapper != null) {
      _setVisible(wrapper, visible);
    } else if (node.visible != visible) {
      node.attributes["visible"] = visible ? "1" : "0";
      changed();
    }
    _tellVisible(node, visible);
  }

  /// What is inside [parent] hears of it being shown or hidden too
  /// (`onSetVisible` goes down the tree).
  void _tellVisible(WasabiObject parent, bool visible) {
    for (final child in parent.children) {
      if (child.visible) {
        final inner = _wrappers[child];
        if (inner != null) vm.fire(inner, "onsetvisible", [visible]);
      }
      _tellVisible(child, visible);
    }
  }

  /// The first page of each tab sheet is shown from the start.
  void _tabSheetsStart(WasabiObject node) {
    if (node.tag == "tabsheet" && node.children.isNotEmpty) {
      final first = node.children.first;
      final wrapper = _wrappers[first];
      if (wrapper != null) vm.fire(wrapper, "onsetvisible", [true]);
      _tellVisible(first, true);
    }
    for (final child in node.children) {
      _tabSheetsStart(child);
    }
  }

  void _setVisible(MakiGuiObject object, bool visible) {
    final node = object.node;
    if (node.tag == "layout") {
      final layout = _layouts[node];
      if (layout == null) return;
      // Amped Modern lists the playlist search's results in a window of
      // their own (playlistpro.m); here the playlist itself shows them.
      if (layout.$1.id.toLowerCase() == "searchresults") return;
      final was = _layoutVisible(node);
      if (companionsOf(layout.$2).isNotEmpty) {
        // A window with frames drawn over it: hidden, it leaves them on
        // screen (the Apple-styled skin hides its playlist editor and keeps the player
        // for its mini mode and its big album art).
        if (visible) {
          node.attributes.remove("#hidden");
        } else {
          node.attributes["#hidden"] = "1";
        }
        _followCompanions();
        changed();
      }
      if (visible) {
        // A layout that comes up and is then faded in (`setTargetA`) fades
        // in from nothing (Amped Modern's notifier).
        if (!was) node.attributes["#justshown"] = "1";
        host.runAction(
          WasabiAction("SWITCH", layout.$2.id, container: layout.$1.id),
        );
        host.setContainerVisible(layout.$1.id, true);
      } else if (node["#hidden"] != "1") {
        node.attributes.remove("#justshown");
        host.setContainerVisible(layout.$1.id, false);
      }
      // As in Wasabi, only a change is news (`onSetVisible`).
      if (was != _layoutVisible(node)) {
        vm.fire(object, "onsetvisible", [visible]);
      }
      return;
    }
    if (node.visible == visible) return;
    node.attributes["visible"] = visible ? "1" : "0";
    changed();
    vm.fire(object, "onsetvisible", [visible]);
  }
}

/// A GUI object (layer, button, text, group, layout, ...) as scripts see it.
class MakiGuiObject extends MakiObject {
  MakiGuiObject._(this._runtime, this.node);

  final WasabiScriptRuntime _runtime;
  final WasabiObject node;

  final Map<String, double> _target = {};

  /// Seconds `gotoTarget` takes; one unless a script sets it.
  double _speed = 1;
  Timer? _animationTimer;

  Timer? get _animation => _animationTimer;

  set _animation(Timer? timer) {
    _animationTimer = timer;
    _runtime._noteSliding(this, timer != null && _slides);
  }

  /// Whether the animation running moves or resizes the object (a drawer
  /// sliding), not only fades it.
  bool _slides = false;

  /// Whether the pointer is over this layout. A layout under the pointer
  /// stays opaque, so a notification can be read for as long as wanted
  /// (Amped Modern's notifier, which fades out on a timer).
  bool _hovered = false;

  void _hover(bool over) {
    if (_hovered == over) return;
    _hovered = over;
    if (over) {
      // A fade running stops, at full opacity; one that has not started
      // is met when it does (see [_goToTarget]).
      if (_animation == null) return;
      _animation?.cancel();
      _target.clear();
      _holdWhileHovered();
    } else if (_held) {
      // Let go: the hold time starts over, then it fades.
      _held = false;
      _runtime.vm.fire(this, "ontargetreached");
    }
  }

  /// Whether the pointer kept a fade from going on.
  bool _held = false;

  /// Applies the targets of a move or fade at once, but for the fade out,
  /// which waits for the pointer to leave; then reports the target reached,
  /// as a fade in would, so the script's hold timer goes on.
  void _holdWhileHovered() {
    final end = Map.of(_target);
    _target.clear();
    node.attributes.remove("#justshown");
    end.remove("alpha");
    for (final MapEntry(key: key, value: to) in end.entries) {
      node.attributes[key] = "${to.round()}";
    }
    node.attributes["alpha"] = "255";
    _held = true;
    _animation = null;
    _runtime.changed();
    _runtime.vm.fire(this, "ontargetreached");
  }

  /// `reverseTarget`: the object grows up and to the left, keeping its
  /// bottom right corner, instead of moving to its target x/y.
  bool _reverse = false;

  /// An animated layer's frames and playback.
  WasabiLayerAnimation get _frames =>
      _animationOrNull ??= WasabiLayerAnimation._(this);
  WasabiLayerAnimation? _animationOrNull;

  /// A layer's effect, once a script set one up.
  WasabiLayerFx? _fx;

  @override
  String get makiClass => switch (node.tag) {
    "layer" => "layer",
    "animatedlayer" => "animatedlayer",
    "button" => "button",
    "togglebutton" || "nstatesbutton" || "checkbox" => "togglebutton",
    "wasabibutton" => "button",
    "text" || "songticker" => "text",
    "slider" => "slider",
    "group" => "group",
    "layout" => "layout",
    "vis" => "vis",
    "eqvis" => "eqvis",
    "albumart" => "albumartlayer",
    "edit" => "edit",
    "componentbucket" => "componentbucket",
    _ => "guiobject",
  };

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    final result = _runtime._gui(this, member, args);
    return identical(result, makiUnhandled)
        ? super.invoke(vm, member, args)
        : result;
  }

  /// Moves from its `getGuiPosition` toward the targets set with
  /// `setTarget*` over `setTargetSpeed` seconds, then fires `onTargetReached` (GuiObjectI::onTargetTimer).
  void _goToTarget() {
    _animation?.cancel();
    final fadeTo = _target["alpha"];
    if (_hovered && node.tag == "layout" && fadeTo != null && fadeTo < 255) {
      _holdWhileHovered();
      return;
    }
    final start = {
      ..._runtime.guiPositionOf(node),
      "alpha": node.alpha.toDouble(),
    };
    final end = Map.of(_target);
    _target.clear();
    // The first fade in of a layout just shown starts from nothing.
    if (node.tag == "layout" && node.attributes.remove("#justshown") != null) {
      final to = end["alpha"];
      if (to != null && to > 0) {
        node.attributes["alpha"] = "0";
        start["alpha"] = 0;
      }
    }
    // Reversed, x and y follow the size instead of their targets. A layout
    // keeps its window's place: moving windows is up to the host.
    final reverse = _reverse && node.tag != "layout";
    if (reverse) {
      end
        ..remove("x")
        ..remove("y");
    }
    const tick = 20;
    final total = math.max(0, (_speed * 1000).round());
    // A drawer sliding while the layout is redocking: the window follows
    // it (see [WasabiLayout.windowSize]).
    final redocking = _runtime.layoutOf(node)?.$2.root;
    if (redocking != null && redocking["#redocking"] == "1") {
      redocking.attributes["#redockspeed"] = "$_speed";
    } else {
      redocking?.attributes.remove("#redockt");
    }
    void step(Timer? timer) {
      // A periodic timer's tick counts the periods elapsed, even ones the
      // event loop was too busy to run, so it follows the clock. The move
      // eases in and out along a sine (`sintrans`).
      final elapsed = (timer?.tick ?? 0) * tick;
      final n = total == 0 ? 1.0 : math.min(1.0, elapsed / total);
      final t = math.sin(n * math.pi - math.pi / 2) / 2 + 0.5;
      for (final MapEntry(key: key, value: to) in end.entries) {
        final from = start[key]!;
        node.attributes[key] = "${(from + (to - from) * t).round()}";
      }
      if (reverse) {
        for (final (position, extent) in const [("x", "w"), ("y", "h")]) {
          final to = end[extent];
          if (to == null) continue;
          final grown = (to - start[extent]!) * t;
          node.attributes[position] = "${(start[position]! - grown).round()}";
        }
      }
      if (redocking != null && redocking["#redocking"] == "1") {
        redocking.attributes["#redockt"] = "$t";
      }
      _runtime.changed();
      if (n >= 1) {
        timer?.cancel();
        _animation = null;
        _runtime.vm.fire(this, "ontargetreached");
      }
    }

    _slides = end.keys.any(const {"x", "y", "w", "h"}.contains);
    _animation = Timer.periodic(const Duration(milliseconds: tick), step);
  }
}

/// An `<animatedlayer>`'s playback (Wasabi's AnimatedLayer): it shows frame
/// [frame] of its image ([wasabiAnimationFrames]) and, while playing, steps
/// from its start frame to its end frame every `speed` milliseconds, firing
/// `onFrame`; at the end it starts over (`autoreplay`, the default) or
/// stops.
class WasabiLayerAnimation {
  WasabiLayerAnimation._(this._object)
    : _speed = _object.node.optInt("speed") ?? 200,
      _autoReplay = _object.node.boolAttr("autoreplay", fallback: true),
      _start = _object.node.optInt("start") ?? -1,
      _end = _object.node.optInt("end") ?? -1;

  final MakiGuiObject _object;
  WasabiObject get _node => _object.node;
  WasabiScriptRuntime get _runtime => _object._runtime;

  int _speed;
  bool _autoReplay;
  int _start;
  int _end;
  Timer? _timer;

  static const int _stopped = 0;
  static const int _playing = 1;
  static const int _paused = 2;
  int _status = _stopped;

  /// The frame shown.
  int get frame => wasabiAnimationFrame(_node);

  /// How many frames the image holds.
  int get length {
    final bitmap = _runtime.skin.bitmap(_node["image"]);
    if (bitmap == null) return 0;
    return wasabiAnimationFrames(_node, bitmap)?.count ?? 1;
  }

  int get startFrame => _start == -1 ? 0 : _start;
  int get endFrame => _end == -1 ? length - 1 : _end;

  bool get isPlaying => _status == _playing;

  /// Starts playing if the XML says so (`autoplay`, AnimatedLayer::onInit).
  void autoPlay() {
    if (!_node.boolAttr("autoplay")) return;
    if (_start == -1) _start = 0;
    if (_end == -1) _end = length - 1;
    play();
  }

  /// Shows frame [n], firing `onFrame` when it changes.
  void gotoFrame(int n) {
    if (n == frame) return;
    _node.attributes["#frame"] = "$n";
    _runtime.changed();
    _runtime.vm.fire(_object, "onframe", [n]);
  }

  void play() {
    gotoFrame(startFrame);
    _startTimer();
    _status = _playing;
    _runtime.vm.fire(_object, "onplay");
  }

  void stop() {
    _stopTimer();
    _status = _stopped;
    _runtime.vm.fire(_object, "onstop");
  }

  void pause() {
    if (_status == _paused) {
      _startTimer();
      _status = _playing;
    } else if (_status == _playing) {
      _stopTimer();
      _status = _paused;
      _runtime.vm.fire(_object, "onpause");
    }
  }

  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(
      Duration(milliseconds: math.max(1, _speed)),
      (_) => step(),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// One tick of the timer (AnimatedLayer::timerCallback).
  @visibleForTesting
  void step() {
    final current = frame;
    if (current == endFrame) {
      if (!_autoReplay) {
        stop();
        return;
      }
      _node.attributes["#frame"] = "$startFrame";
      _runtime.changed();
      return;
    }
    gotoFrame(current + (startFrame < endFrame ? 1 : -1));
  }

  void dispose() => _stopTimer();

  Object? invoke(String member, List<Object?> a) {
    int n(int i) => (a[i] as int?) ?? 0;
    switch (member) {
      case "gotoframe":
        gotoFrame(n(0));
      case "play":
        play();
      case "stop":
        stop();
      case "pause" || "togglepause":
        pause();
      case "setstartframe":
        if (n(0) >= 0) _start = n(0);
      case "setendframe":
        if (n(0) >= 0) _end = n(0);
      case "setspeed":
        _speed = n(0);
        if (_status == _playing) {
          _stopTimer();
          _startTimer();
        }
      case "setautoreplay":
        _autoReplay = a[0] == true || (a[0] is int && a[0] != 0);
      case "getlength":
        return length;
      case "getcurframe":
        return frame;
      case "getstartframe":
        return startFrame;
      case "getendframe":
        return endFrame;
      case "getspeed":
        return _speed;
      case "getautoreplay":
        return _autoReplay;
      case "isplaying":
        return _status == _playing;
      case "ispaused":
        return _status == _paused;
      case "isstopped":
        return _status == _stopped;
    }
    return null;
  }
}

/// Where a layer with an effect takes its pixels from: a grid of
/// [columns] by [rows] points spread evenly over the layer, each with the
/// point of the image (in image pixels) drawn there; between the points
/// the image is stretched linearly (FxDynamicMove::render).
class WasabiFxMesh {
  const WasabiFxMesh({
    required this.columns,
    required this.rows,
    required this.source,
    required this.wrap,
    required this.bilinear,
    this.alphas,
  });

  final int columns;
  final int rows;

  /// The image point of each grid point, row by row.
  final List<Offset> source;

  /// Whether points off the image wrap around it instead of sticking to
  /// its edge (`fx_setWrap`).
  final bool wrap;

  /// Whether the image is smoothed (`fx_setBilinear`).
  final bool bilinear;

  /// How opaque (0 to 1) the layer is at each grid point, from the
  /// script's `fx_onGetPixelA` in alpha mode (`fx_setAlphaMode`); null
  /// when alpha mode is off.
  final List<double>? alphas;
}

/// A layer's effect (Layer's `fx_*`, Wasabi's FxDynamicMove): for each
/// point of a grid over the layer the script says, through
/// `fx_onGetPixelR` and `fx_onGetPixelD` (polar, the default) or
/// `fx_onGetPixelX` and `fx_onGetPixelY` (`fx_setRect`), which point of
/// the image to draw there. Skins rotate layers with it (clock hands,
/// knobs). With `fx_setAlphaMode` the script also gives, through
/// `fx_onGetPixelA`, how opaque each grid point is. It is worked out again on `fx_update`, and every `fx_setSpeed`
/// milliseconds after `fx_onFrame` with `fx_setRealtime`.
class WasabiLayerFx {
  WasabiLayerFx._(this._object);

  final MakiGuiObject _object;
  WasabiScriptRuntime get _runtime => _object._runtime;

  bool _enabled = false;
  bool _wrap = false;
  bool _rect = false;
  bool _bilinear = true;
  bool _realtime = false;
  bool _bgFx = false;
  bool _clear = true;
  bool _localized = true;
  bool _alphaMode = false;
  int _gridX = 16;
  int _gridY = 16;
  int _speed = 35;
  Timer? _timer;

  /// The warp now, or null while the effect is off.
  WasabiFxMesh? mesh;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Object? invoke(String member, List<Object?> a) {
    bool flag(int i) => a[i] == true || (a[i] is num && a[i] != 0);
    int n(int i) => (a[i] as int?) ?? 0;
    switch (member) {
      case "fx_setenabled":
        final on = flag(0);
        if (on == _enabled) return null;
        _enabled = on;
        if (on) _runtime.vm.fire(_object, "fx_oninit");
        _restartTimer();
        _update();
      case "fx_getenabled":
        return _enabled;
      case "fx_setwrap":
        _wrap = flag(0);
        _update();
      case "fx_getwrap":
        return _wrap;
      case "fx_setrect":
        _rect = flag(0);
        _update();
      case "fx_getrect":
        return _rect;
      case "fx_setbilinear":
        _bilinear = flag(0);
        _update();
      case "fx_getbilinear":
        return _bilinear;
      case "fx_setrealtime":
        _realtime = flag(0);
        _restartTimer();
      case "fx_getrealtime":
        return _realtime;
      case "fx_setspeed":
        _speed = n(0);
        _restartTimer();
      case "fx_getspeed":
        return _speed;
      case "fx_setgridsize":
        _gridX = n(0);
        _gridY = n(1);
        _update();
      case "fx_update" || "fx_restart":
        _update();
      case "fx_setalphamode":
        _alphaMode = flag(0);
        _update();
      case "fx_getalphamode":
        return _alphaMode;
      // Drawing options this renderer has no use for.
      case "fx_setbgfx":
        _bgFx = flag(0);
      case "fx_getbgfx":
        return _bgFx;
      case "fx_setclear":
        _clear = flag(0);
      case "fx_getclear":
        return _clear;
      case "fx_setlocalized":
        _localized = flag(0);
      case "fx_getlocalized":
        return _localized;
    }
    return null;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled || !_realtime) return;
    _timer = Timer.periodic(Duration(milliseconds: math.max(10, _speed)), (_) {
      _runtime.vm.fire(_object, "fx_onframe");
      _update();
    });
  }

  /// Asks the script for the image point of every grid point.
  void _update() {
    if (!_enabled) {
      if (mesh != null) {
        mesh = null;
        _runtime.changed();
      }
      return;
    }
    final node = _object.node;
    // An album art object warps the cover (or the picture for none).
    final art = node.tag == "albumart" ? _runtime.host.albumArt : null;
    final bitmap = art != null
        ? null
        : _runtime.skin.bitmap(
            node.tag == "albumart"
                ? node["notfoundimage"] ?? "winamp.cover.notfound"
                : node["image"],
          );
    if (art == null && bitmap == null) return;
    final width = art?.width.toDouble() ?? bitmap!.width;
    final height = art?.height.toDouble() ?? bitmap!.height;
    final columns = (_gridX + 1).clamp(2, 256);
    final rows = (_gridY + 1).clamp(2, 256);
    final halfDiagonal = math.sqrt(width * width + height * height) / 2;
    double ask(String event, double r, double d, double x, double y) {
      final value = _runtime.vm.fire(_object, event, [r, d, x, y]);
      return value is num ? value.toDouble() : double.nan;
    }

    final source = <Offset>[];
    final alphas = _alphaMode ? <double>[] : null;
    for (var row = 0; row < rows; row++) {
      final yd = row * height / (rows - 1) - height / 2;
      for (var column = 0; column < columns; column++) {
        final xd = column * width / (columns - 1) - width / 2;
        final x = xd * 2 / width;
        final y = yd * 2 / height;
        final d = halfDiagonal == 0
            ? 0.0
            : math.sqrt(xd * xd + yd * yd) / halfDiagonal;
        final r = math.atan2(yd, xd) + math.pi / 2;
        double sx;
        double sy;
        if (_rect) {
          var nx = ask("fx_ongetpixelx", r, d, x, y);
          var ny = ask("fx_ongetpixely", r, d, x, y);
          if (nx.isNaN) nx = x;
          if (ny.isNaN) ny = y;
          sx = (nx + 1) * width / 2;
          sy = (ny + 1) * height / 2;
        } else {
          var nr = ask("fx_ongetpixelr", r, d, x, y);
          var nd = ask("fx_ongetpixeld", r, d, x, y);
          if (nr.isNaN) nr = r;
          if (nd.isNaN) nd = d;
          final angle = nr - math.pi / 2;
          sx = width / 2 + math.cos(angle) * nd * halfDiagonal;
          sy = height / 2 + math.sin(angle) * nd * halfDiagonal;
        }
        if (!_wrap) {
          sx = sx.clamp(0, width);
          sy = sy.clamp(0, height);
        }
        source.add(Offset(sx, sy));
        if (alphas != null) {
          final a = ask("fx_ongetpixela", r, d, x, y);
          // A script without the handler leaves the layer opaque.
          alphas.add(a.isNaN ? 1.0 : a.clamp(0.0, 1.0));
        }
      }
    }
    mesh = WasabiFxMesh(
      columns: columns,
      rows: rows,
      source: source,
      wrap: _wrap,
      bilinear: _bilinear,
      alphas: alphas,
    );
    _runtime.changed();
  }
}

class _MakiSystem extends MakiObject {
  _MakiSystem(this._runtime, this.group, this.param);

  final WasabiScriptRuntime _runtime;
  final WasabiObject? group;
  final String param;

  @override
  String get makiClass => "system";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    final result = _runtime._system(this, member, args);
    return identical(result, makiUnhandled)
        ? super.invoke(vm, member, args)
        : result;
  }
}

class _MakiContainer extends MakiObject {
  _MakiContainer(this._runtime, this.container);

  final WasabiScriptRuntime _runtime;
  final WasabiContainer container;

  @override
  String get makiClass => "container";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    final host = _runtime.host;
    switch (member) {
      case "getid":
        return container.id;
      case "getname":
        return container.name;
      case "getlayout":
        final layout = container.layout(args[0] as String? ?? "");
        return layout == null ? null : _runtime.wrap(layout.root);
      case "getcurlayout":
        final id = host.currentLayout(container.id);
        final layout = id == null ? null : container.layout(id);
        return _runtime.wrap((layout ?? container.layouts.first).root);
      case "getnumlayouts":
        return container.layouts.length;
      case "enumlayout":
        final i = (args[0] as int?) ?? 0;
        return i >= 0 && i < container.layouts.length
            ? _runtime.wrap(container.layouts[i].root)
            : null;
      case "switchtolayout":
        host.runAction(
          WasabiAction("SWITCH", args[0] as String?, container: container.id),
        );
        return null;
      case "show":
        host.setContainerVisible(container.id, true);
        return null;
      case "hide" || "close":
        host.setContainerVisible(container.id, false);
        return null;
      case "toggle":
        host.setContainerVisible(
          container.id,
          !host.isContainerVisible(container.id),
        );
        return null;
      case "isdynamic":
        return container.dynamic;
    }
    return super.invoke(vm, member, args);
  }
}

class _MakiTimer extends MakiObject {
  _MakiTimer(this._runtime);

  final WasabiScriptRuntime _runtime;
  int _delay = 5000;
  Timer? _timer;

  @override
  String get makiClass => "timer";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "setdelay":
        _delay = math.max(1, (args[0] as int?) ?? 0);
        if (_timer != null) _start();
        return null;
      case "getdelay":
        return _delay;
      case "start":
        _start();
        return null;
      case "stop":
        _timer?.cancel();
        _timer = null;
        return null;
      case "isrunning":
        return _timer != null;
      case "getskipped":
        return 0;
    }
    return super.invoke(vm, member, args);
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: _delay),
      (_) => _runtime.vm.fire(this, "ontimer"),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _runtime._timers.remove(this);
  }
}

class _MakiList extends MakiObject {
  final List<Object?> _items = [];

  @override
  String get makiClass => "list";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "additem":
        _items.add(args[0]);
        return null;
      case "removeitem":
        final i = (args[0] as int?) ?? -1;
        if (i >= 0 && i < _items.length) _items.removeAt(i);
        return null;
      case "enumitem":
        final i = (args[0] as int?) ?? -1;
        return i >= 0 && i < _items.length ? _items[i] : null;
      case "finditem":
        return _items.indexOf(args[0]);
      case "getnumitems":
        return _items.length;
      case "removeall":
        _items.clear();
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// A `Map`: a bitmap scripts read values from (`SMap`), such as Anexa's
/// gradient that shapes its volume and seek bars by level.
/// A `Region` a script builds. Only what it takes from a map is kept
/// (`loadFromMap`): the shape of a layer that follows a value.
/// A `Region` a script builds: rectangles in pixels, from a map or a bitmap,
/// then added to, subtracted from, moved and scaled (`RegionI`). It is read
/// when a layer uses it, since a map's pixels can arrive after the script
/// made it.
class _MakiRegion extends MakiObject {
  _MakiRegion(this._runtime);

  final WasabiScriptRuntime _runtime;

  /// What the region starts as: a map's pixels at a threshold, or nothing.
  _MakiMap? _map;
  int _threshold = 0;
  bool _reversed = false;
  List<Rect>? _mapRects;
  WasabiBitmap? _mapBitmap;

  /// What was done to it since, in order.
  final List<List<Rect> Function(List<Rect>)> _ops = [];

  @override
  String get makiClass => "region";

  bool usesMap(_MakiMap map) => identical(_map, map);

  void loadFromMap(_MakiMap map, int threshold, bool reversed) {
    _map = map;
    _threshold = threshold & 0xFF;
    _reversed = reversed;
    _mapRects = null;
    _ops.clear();
  }

  /// The region's rectangles, or null while its map's pixels are not read.
  List<Rect>? get rects {
    var base = const <Rect>[];
    final map = _map;
    if (map != null) {
      final bitmap = map.bitmap;
      final pixels = map.pixels;
      if (bitmap == null || pixels == null) return null;
      if (!identical(_mapBitmap, bitmap)) _mapRects = null;
      _mapBitmap = bitmap;
      base = _mapRects ??= thresholdRects(
        bitmap,
        pixels,
        _threshold,
        reversed: _reversed,
      );
    }
    var result = base;
    for (final op in _ops) {
      result = op(result);
    }
    return result;
  }

  /// A region of its own with the same shape (`Region.copy`).
  _MakiRegion copy() {
    final copy = _MakiRegion(_runtime)
      .._map = _map
      .._threshold = _threshold
      .._reversed = _reversed;
    copy._ops.addAll(_ops);
    return copy;
  }

  static List<Rect> _subtract(List<Rect> from, List<Rect> cut) {
    var result = from;
    for (final hole in cut) {
      final next = <Rect>[];
      for (final r in result) {
        final inner = r.intersect(hole);
        if (inner.isEmpty) {
          next.add(r);
          continue;
        }
        if (inner.top > r.top) {
          next.add(Rect.fromLTRB(r.left, r.top, r.right, inner.top));
        }
        if (inner.bottom < r.bottom) {
          next.add(Rect.fromLTRB(r.left, inner.bottom, r.right, r.bottom));
        }
        if (inner.left > r.left) {
          next.add(Rect.fromLTRB(r.left, inner.top, inner.left, inner.bottom));
        }
        if (inner.right < r.right) {
          next.add(
            Rect.fromLTRB(inner.right, inner.top, r.right, inner.bottom),
          );
        }
      }
      result = next;
    }
    return result;
  }

  Rect? get _bounds {
    final all = rects;
    if (all == null || all.isEmpty) return null;
    var bounds = all.first;
    for (final r in all.skip(1)) {
      bounds = bounds.expandToInclude(r);
    }
    return bounds;
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "loadfrommap":
        final source = args.isEmpty ? null : args[0];
        final inverse = args.length > 2 ? args[2] : 0;
        if (source is _MakiMap) {
          loadFromMap(
            source,
            args.length > 1 ? (args[1] as int? ?? 0) : 0,
            inverse == true || (inverse is int && inverse != 0),
          );
        } else {
          _map = null;
          _mapRects = null;
          _ops.clear();
        }
        return null;
      case "loadfrombitmap":
        // The pixels of the bitmap that have any alpha.
        final map = _MakiMap(_runtime)
          ..invoke(vm, "loadmap", [args.isEmpty ? "" : args[0]]);
        loadFromMap(map, 0, false);
        return null;
      case "add":
        final other = args.isEmpty ? null : args[0];
        if (other is _MakiRegion) {
          final snapshot = other.copy();
          _ops.add((r) => [...r, ...?snapshot.rects]);
        }
        return null;
      case "sub":
        final other = args.isEmpty ? null : args[0];
        if (other is _MakiRegion) {
          final snapshot = other.copy();
          _ops.add((r) => _subtract(r, snapshot.rects ?? const []));
        }
        return null;
      case "offset":
        final dx = ((args.isNotEmpty ? args[0] : 0) as num? ?? 0).toDouble();
        final dy = ((args.length > 1 ? args[1] : 0) as num? ?? 0).toDouble();
        _ops.add((r) => [for (final e in r) e.shift(Offset(dx, dy))]);
        return null;
      case "stretch":
        final f = ((args.isNotEmpty ? args[0] : 1) as num? ?? 1).toDouble();
        _ops.add(
          (r) => [
            for (final e in r)
              Rect.fromLTRB(e.left * f, e.top * f, e.right * f, e.bottom * f),
          ],
        );
        return null;
      case "copy":
        final other = args.isEmpty ? null : args[0];
        if (other is _MakiRegion) {
          _map = other._map;
          _threshold = other._threshold;
          _reversed = other._reversed;
          _mapRects = null;
          _ops
            ..clear()
            ..addAll(other._ops);
        }
        return null;
      case "isinvalid":
        return _map == null && _ops.isEmpty;
      case "getboundingboxx":
        return _bounds?.left.floor() ?? 0;
      case "getboundingboxy":
        return _bounds?.top.floor() ?? 0;
      case "getboundingboxw":
        return _bounds?.width.ceil() ?? 0;
      case "getboundingboxh":
        return _bounds?.height.ceil() ?? 0;
    }
    return super.invoke(vm, member, args);
  }
}

class _MakiMap extends MakiObject {
  _MakiMap(this._runtime);

  final WasabiScriptRuntime _runtime;

  /// The bitmap loaded with `loadMap`, and its image's pixels once read.
  WasabiBitmap? bitmap;
  ByteData? pixels;

  /// The size of an image file loaded by its path (`loadMap` takes a path
  /// as well as a bitmap id; the ClassicPro skins look for the plugin's
  /// `installed.png` that way), or null. Its pixels are not read.
  (int, int)? fileSize;

  @override
  String get makiClass => "map";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    int n(int i) => (args[i] as int?) ?? 0;
    switch (member) {
      case "loadmap":
        _load(args[0] as String? ?? "");
        return null;
      case "getwidth":
        return bitmap?.width.toInt() ?? fileSize?.$1 ?? 0;
      case "getheight":
        return bitmap?.height.toInt() ?? fileSize?.$2 ?? 0;
      case "getvalue":
        // The brightest of red, green and blue (`SMap::getValue`).
        final p = _pixel(n(0), n(1));
        if (p == null) return 0;
        return math.max(math.max(p.$1, p.$2), p.$3);
      case "getargbvalue":
        // Channel 0 is blue, 1 green, 2 red, 3 alpha; colors come back
        // without the alpha premultiplied in (`SMap::getARGBValue`).
        final p = _pixel(n(0), n(1));
        if (p == null) return 0;
        final (r, g, b, alpha) = p;
        final channel = n(2) % 4;
        if (channel == 3) return alpha;
        final value = [b, g, r][channel];
        if (alpha == 0 || alpha == 255) return value;
        return value * 255 ~/ alpha;
      case "inregion":
        // Whether the pixel has any alpha (the map's `RegionI(bitmap)`).
        final p = _pixel(n(0), n(1));
        return p != null && p.$4 != 0;
    }
    return super.invoke(vm, member, args);
  }

  void _load(String id) {
    final skin = _runtime.skin;
    final bitmap = this.bitmap = skin.bitmap(id);
    fileSize = null;
    if (bitmap == null) fileSize = _sizeOfFile(id);
    pixels = bitmap == null ? null : skin.pixelsOf(bitmap);
    if (bitmap == null || pixels != null) return;
    // A bitmap the skin did not read at load: its values come once read.
    unawaited(
      skin.readPixels(bitmap).then((data) {
        if (!identical(this.bitmap, bitmap) || _runtime._disposed) return;
        pixels = data;
        _runtime._mapLoaded(this);
      }),
    );
  }

  /// The size of the image file [path] names, or null when it names none
  /// (a bitmap id that is not one either, a missing file, an unknown format).
  (int, int)? _sizeOfFile(String path) {
    if (!path.contains("/") && !path.contains("\\") && !path.contains("@")) {
      return null;
    }
    // An audio file: its cover.
    final art = _runtime.artSizeOf(path);
    if (art != null) return art;
    try {
      final found = _runtime.skin.resolveFile(path);
      if (found == null) return null;
      final bytes = WasabiFiles.isVirtual(found)
          ? WasabiFiles.readBytes(found)
          : File(found).readAsBytesSync();
      return wasabiImageSize(bytes);
    } on Object {
      return null;
    }
  }

  /// The premultiplied (red, green, blue, alpha) of pixel ([x], [y]) of the
  /// map; null outside it or before its pixels are read.
  (int, int, int, int)? _pixel(int x, int y) {
    final bitmap = this.bitmap;
    final pixels = this.pixels;
    if (bitmap == null || pixels == null) return null;
    if (x < 0 || y < 0 || x >= bitmap.width || y >= bitmap.height) {
      return null;
    }
    final ix = bitmap.src.left.toInt() + x;
    final iy = bitmap.src.top.toInt() + y;
    final image = bitmap.source;
    if (ix >= image.width || iy >= image.height) return null;
    final p = (iy * image.width + ix) * 4;
    return (
      pixels.getUint8(p),
      pixels.getUint8(p + 1),
      pixels.getUint8(p + 2),
      pixels.getUint8(p + 3),
    );
  }
}

/// A layer's region from a map: [map]'s pixels at [threshold], taken when
/// the script set it, as `Layer::setRegionFromMap` builds it then.
/// Classes scripts can create but that do nothing here yet (menus).
/// The `ColorMgr` object: the skin's color themes (gamma sets).
class _MakiColorMgr extends MakiObject {
  _MakiColorMgr(this._runtime);

  final WasabiScriptRuntime _runtime;

  @override
  String get makiClass => "colormgr";

  WasabiColorThemes get _themes => _runtime.skin.colorThemes;

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "getgammaset":
        final set = _themes.named(args[0] as String?);
        return set == null ? null : _MakiGammaSet(_runtime, set);
      case "enumgammaset":
        final n = (args[0] as int?) ?? -1;
        final sets = _themes.sets;
        return n < 0 || n >= sets.length
            ? null
            : _MakiGammaSet(_runtime, sets[n]);
      case "getcurrentgammaset":
        final set = _themes.current;
        return set == null ? null : _MakiGammaSet(_runtime, set);
      case "newgammaset":
        final name = args[0] as String? ?? "";
        final set = _themes.named(name) ?? WasabiGammaSet(name, custom: true);
        if (!_themes.sets.contains(set)) _themes.add(set);
        return _MakiGammaSet(_runtime, set);
      case "getnumgammasets":
        return _themes.sets.length;
      case "getnumcolors":
        return 0;
      // A color of the skin, as the color theme on shows it.
      case "getcolor":
        final color = _runtime.skin.color(args[0] as String?);
        return color == null ? null : _MakiColor(color);
      case "enumcolor":
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// A `Color` ([_MakiColorMgr.getColor]): the parts of one color.
class _MakiColor extends MakiObject {
  _MakiColor(this.color);

  final Color color;

  @override
  String get makiClass => "color";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "getred":
        return (color.r * 255).round();
      case "getgreen":
        return (color.g * 255).round();
      case "getblue":
        return (color.b * 255).round();
      case "getalpha":
        return (color.a * 255).round();
    }
    return super.invoke(vm, member, args);
  }
}

/// A `GammaSet`: one color theme.
class _MakiGammaSet extends MakiObject {
  _MakiGammaSet(this._runtime, this.set);

  final WasabiScriptRuntime _runtime;
  final WasabiGammaSet set;

  @override
  String get makiClass => "gammaset";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    final themes = _runtime.skin.colorThemes;
    switch (member) {
      case "getid":
        return set.name;
      case "apply":
        // Turns the theme on (`colortheme_setColorSet`); the one that is on
        // is filtered again, for what the script changed in it.
        if (identical(themes.current, set)) {
          unawaited(themes.reapply());
        } else {
          unawaited(themes.select(set.name));
        }
        return null;
      case "getgeneralgroup":
        return _MakiGammaGroup(set, null);
      case "getnumgammagroups":
        return set.groups.length;
      case "enumgammagroup":
        // Out of range, and -1, is the general group
        // (`GammaManagerAPI::enumColorThemeGroup`).
        final n = (args[0] as int?) ?? -1;
        if (n < 0 || n >= set.groups.length) {
          return _MakiGammaGroup(set, null);
        }
        return _MakiGammaGroup(set, set.groups.keys.elementAt(n));
      case "getgammagroup":
        final name = (args[0] as String? ?? "").toLowerCase();
        if (name == "general") return _MakiGammaGroup(set, null);
        return set.groups.containsKey(name) ? _MakiGammaGroup(set, name) : null;
      case "remove" || "delete":
        if (set.custom) unawaited(themes.remove(set.name));
        return null;
      case "update" || "rename":
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// A `GammaGroup` of a theme: what the theme does to one group of colors.
class _MakiGammaGroup extends MakiObject {
  _MakiGammaGroup(this.set, this.key);

  final WasabiGammaSet set;

  /// The group's lower-case id in the set, or null for the general group.
  final String? key;

  @override
  String get makiClass => "gammagroup";

  WasabiGammaGroup get _group =>
      key == null ? set.general : set.groups[key] ?? WasabiGammaGroup.none;

  void _replace(WasabiGammaGroup group) {
    if (key == null) {
      set.general = group;
    } else {
      set.groups[key!] = group;
    }
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    int n() => (args[0] as int?) ?? 0;
    switch (member) {
      case "getid":
        return _group.id;
      case "getred":
        return _group.red;
      case "getgreen":
        return _group.green;
      case "getblue":
        return _group.blue;
      case "getgray":
        return _group.gray;
      case "getboost":
        return _group.boost ? 1 : 0;
      case "setred":
        _replace(_group.copyWith(red: n()));
        return null;
      case "setgreen":
        _replace(_group.copyWith(green: n()));
        return null;
      case "setblue":
        _replace(_group.copyWith(blue: n()));
        return null;
      case "setgray":
        _replace(_group.copyWith(gray: n()));
        return null;
      case "setboost":
        _replace(_group.copyWith(boost: n() != 0));
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// A script's `PopupMenu`. The classic player holds the script until the user picks an
/// entry and answers `popAtMouse` with its id; the menu here opens when the
/// handler returns, and the handler that opened it runs again to be given
/// the id (the menu is built the same way each time), so `popAtMouse`
/// answers -1 the first time, and the pick the second.
class _MakiPopupMenu extends MakiObject {
  _MakiPopupMenu(this._runtime);

  final WasabiScriptRuntime _runtime;

  final List<_PopupEntry> _entries = [];

  @override
  String get makiClass => "popupmenu";

  _PopupEntry? _command(int id) {
    for (final entry in _entries) {
      if (!entry.separator && entry.submenu == null && entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  List<WasabiPopupItem> items() => [
    for (final entry in _entries)
      if (entry.separator)
        const WasabiPopupItem.separator()
      else if (entry.submenu case final sub?)
        WasabiPopupItem(label: entry.text, children: sub.items())
      else
        WasabiPopupItem(
          label: entry.text,
          id: entry.id,
          checked: entry.checked,
          disabled: entry.disabled,
        ),
  ];

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "addcommand":
        _entries.add(
          _PopupEntry(
            text: args[0] as String? ?? "",
            id: (args[1] as int?) ?? 0,
            checked: _truthy(args[2]),
            disabled: _truthy(args[3]),
          ),
        );
        return null;
      case "addseparator":
        _entries.add(_PopupEntry.separator());
        return null;
      case "addsubmenu":
        final sub = args[0];
        if (sub is _MakiPopupMenu) {
          _entries.add(
            _PopupEntry(text: args[1] as String? ?? "", submenu: sub),
          );
        }
        return null;
      case "checkcommand":
        _command((args[0] as int?) ?? 0)?.checked = _truthy(args[1]);
        return null;
      case "disablecommand":
        _command((args[0] as int?) ?? 0)?.disabled = _truthy(args[1]);
        return null;
      case "getnumcommands":
        return _entries.length;
      case "popatmouse" || "popatxy":
        return _runtime._popUp(this);
    }
    return super.invoke(vm, member, args);
  }

  static bool _truthy(Object? value) =>
      value == true || (value is num && value != 0);
}

class _PopupEntry {
  _PopupEntry({
    this.text = "",
    this.id = 0,
    this.checked = false,
    this.disabled = false,
    this.submenu,
  }) : separator = false;

  _PopupEntry.separator()
    : text = "",
      id = 0,
      checked = false,
      disabled = false,
      submenu = null,
      separator = true;

  final String text;
  final int id;
  bool checked;
  bool disabled;
  final _MakiPopupMenu? submenu;
  final bool separator;
}

/// The classic player's playlist editor (`PlEdit`, `pldir.mi`): the playlist's tracks by
/// index.
class _MakiPlEdit extends MakiObject {
  _MakiPlEdit(this._runtime);

  final WasabiScriptRuntime _runtime;

  WasabiHost get _host => _runtime.host;

  @override
  String get makiClass => "pledit";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    int n(int i) => (args[i] as num?)?.toInt() ?? 0;
    bool valid(int i) => i >= 0 && i < _host.playlistLength;
    switch (member) {
      case "getnumtracks":
        return _host.playlistLength;
      case "getcurrentindex":
        return _host.playlistCurrent;
      case "getnumselectedtracks":
        return [
          for (var i = 0; i < _host.playlistLength; i++)
            if (_host.isPlaylistSelected(i)) i,
        ].length;
      // The next selected track after [i] (-1 starts from the top), or -1.
      case "getnextselectedtrack":
        for (var i = n(0) + 1; i < _host.playlistLength; i++) {
          if (_host.isPlaylistSelected(i)) return i;
        }
        return -1;
      case "enqueuefile":
        _host.openPath(
          wasabiNativePath(args[0] as String? ?? ""),
          play: false,
        );
        return null;
      case "clear":
        _host.clearPlaylist();
        return null;
      case "removetrack":
        if (valid(n(0))) _host.removePlaylistItem(n(0));
        return null;
      case "swaptracks":
        final a = n(0);
        final b = n(1);
        if (valid(a) && valid(b) && a != b) {
          // Two moves leave the others where they were.
          final low = a < b ? a : b;
          final high = a < b ? b : a;
          _host.movePlaylistItem(high, low);
          if (high - low > 1) _host.movePlaylistItem(low + 1, high);
        }
        return null;
      case "moveup":
        if (n(0) > 0 && valid(n(0))) _host.movePlaylistItem(n(0), n(0) - 1);
        return null;
      case "movedown":
        if (valid(n(0)) && valid(n(0) + 1)) {
          _host.movePlaylistItem(n(0), n(0) + 1);
        }
        return null;
      case "moveto":
        if (valid(n(0)) && valid(n(1))) _host.movePlaylistItem(n(0), n(1));
        return null;
      case "playtrack":
        if (valid(n(0))) _host.playPlaylistItem(n(0));
        return null;
      // Ratings are not kept.
      case "getrating":
        return 0;
      case "setrating":
        return null;
      case "gettitle":
        return valid(n(0)) ? _host.playlistTitle(n(0)) : "";
      case "getlength":
        return valid(n(0))
            ? formatPlaylistItemTime(_host.playlistItemLengthMs(n(0)))
            : "";
      case "getmetadata":
        return valid(n(0))
            ? _host.playlistMetadata(n(0), args[1] as String? ?? "")
            : "";
      case "getfilename":
        return valid(n(0)) ? _host.playlistLocation(n(0)) : "";
      // Scrolls the list to the playing track.
      case "showcurrentlyplayingtrack":
        _runtime.skin.playlistReveal.value++;
        return null;
      case "showtrack":
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// A `BitList`: booleans by index, grown as they are set.
class _MakiBitList extends MakiObject {
  final List<bool> _bits = [];

  @override
  String get makiClass => "bitlist";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "setsize":
        final size = ((args[0] as int?) ?? 0).clamp(0, 1 << 20);
        if (size < _bits.length) {
          _bits.length = size;
        } else {
          _bits.addAll(List.filled(size - _bits.length, false));
        }
        return null;
      case "getsize":
        return _bits.length;
      case "setitem":
        final i = (args[0] as int?) ?? -1;
        if (i >= 0 && i < (1 << 20)) {
          if (i >= _bits.length) {
            _bits.addAll(List.filled(i + 1 - _bits.length, false));
          }
          final v = args[1];
          _bits[i] = v == true || (v is num && v != 0);
        }
        return null;
      case "getitem":
        final i = (args[0] as int?) ?? -1;
        return i >= 0 && i < _bits.length && _bits[i];
    }
    return super.invoke(vm, member, args);
  }
}

/// A `File`: a path a script loads, then asks about (`FileReaderI`).
class _MakiFile extends MakiObject {
  _MakiFile(this._runtime);

  final WasabiScriptRuntime _runtime;
  String? _path;

  @override
  String get makiClass => "file";

  /// The loaded file's text, or null when it does not exist.
  String? get text {
    final path = _path;
    return path == null
        ? null
        : utf8.decode(WasabiFiles.readBytes(path), allowMalformed: true);
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "load":
        _path = _runtime.skin.resolveFile(
          _runtime.skin.expandPathVariables("${args[0]}"),
        );
        return null;
      case "exists":
        return _path != null;
      case "getsize":
        final path = _path;
        return path == null ? 0 : WasabiFiles.length(path);
    }
    return super.invoke(vm, member, args);
  }
}

/// An `XmlDoc`: a file a script reads tag by tag. `parser_addCallback`
/// names the tag paths (`main/cfg/*`) to report; `parser_start` calls
/// `parser_onCallback(path, tag, paramNames, paramValues)` for each one, and
/// `parser_onCloseCallback(path, tag)` after its children.
class _MakiXmlDoc extends _MakiFile {
  _MakiXmlDoc(super.runtime);

  final List<RegExp> _callbacks = [];

  @override
  String get makiClass => "xmldoc";

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "parser_addcallback":
        _callbacks.add(
          RegExp(
            "^${RegExp.escape("${args[0]}").replaceAll(r"\*", ".*")}\$",
            caseSensitive: false,
          ),
        );
        return null;
      case "parser_start":
        final source = text;
        if (source == null) {
          vm.fire(this, "parser_onerror", ["", 0, "file not found"]);
          return null;
        }
        _walk(vm, parseXmlFragment(source), "");
        return null;
      case "parser_destroy":
        _callbacks.clear();
        return null;
    }
    return super.invoke(vm, member, args);
  }

  void _walk(MakiVm vm, List<XmlNode> nodes, String parent) {
    for (final node in nodes) {
      final path = parent.isEmpty ? node.tag : "$parent/${node.tag}";
      final reported = _callbacks.any((r) => r.hasMatch(path));
      if (reported) {
        final names = _MakiList();
        final values = _MakiList();
        for (final entry in node.attributes.entries) {
          if (entry.key.startsWith("#")) continue;
          names._items.add(entry.key);
          values._items.add(entry.value);
        }
        vm.fire(this, "parser_oncallback", [parent, node.tag, names, values]);
      }
      _walk(vm, node.children, path);
      if (reported) vm.fire(this, "parser_onclosecallback", [parent, node.tag]);
    }
  }
}

/// `ClassicProFile`: the file calls the ClassicPro plugin gives its skins
/// (`ClassicProFile.mi`, written from its scripts and plugin).
class _MakiClassicProFile extends MakiObject {
  _MakiClassicProFile(this._runtime);

  final WasabiScriptRuntime _runtime;

  @override
  String get makiClass => "classicprofile";

  /// What a skin's script may not start with `openFile`: programs and
  /// scripts (a skin is downloaded, and this is not Windows' `ShellExecute`
  /// for anything it names).
  static const _programs = {
    "app",
    "apk",
    "bat",
    "cmd",
    "com",
    "command",
    "cpl",
    "dll",
    "dmg",
    "exe",
    "jar",
    "js",
    "jse",
    "lnk",
    "msi",
    "pif",
    "pkg",
    "ps1",
    "reg",
    "scr",
    "sh",
    "vbe",
    "vbs",
    "wsf",
  };

  /// [path] with the separators of this system: the scripts write Windows
  /// paths.
  static String _native(String path) => wasabiNativePath(path);

  /// A Windows wildcard (`*.mp3`, `*.*`, `a?.txt`) as a regular expression;
  /// `*.*` matches every name, even one without a dot.
  static RegExp _wildcard(String pattern) {
    if (pattern == "*.*") return RegExp(".*");
    final body = pattern
        .split("")
        .map(
          (c) => switch (c) {
            "*" => ".*",
            "?" => ".",
            _ => RegExp.escape(c),
          },
        )
        .join();
    return RegExp("^$body\$", caseSensitive: false);
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    String s(int i) => i < args.length ? args[i] as String? ?? "" : "";
    switch (member) {
      case "explorefile":
        _runtime.host.revealPath(_native(s(0)));
        return null;
      case "explorefolder":
        _runtime.host.openFolder(_native(s(0)));
        return null;
      case "openfile":
        final path = _native(s(0));
        final name = path.split(Platform.pathSeparator).last;
        final extension = name.contains(".")
            ? name.split(".").last.toLowerCase()
            : "";
        if (_programs.contains(extension)) {
          _runtime._log("ClassicProFile.openFile: will not start $name");
          return null;
        }
        _runtime.host.openExternal(path);
        return null;
      // The names in a folder that match, "." and ".." first as Windows
      // lists them (the scripts count on the first two); -1 when the folder
      // cannot be read.
      case "findfiles":
        final list = args.length > 2 ? args[2] : null;
        if (list is! _MakiList) return -1;
        final folder = Directory(_native(s(0)));
        final List<String> names;
        try {
          names = [
            for (final entity in folder.listSync())
              entity.uri.pathSegments.lastWhere((e) => e.isNotEmpty),
          ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        } on Object {
          return -1;
        }
        final wanted = _wildcard(s(1));
        for (final name in [".", "..", ...names]) {
          if (wanted.hasMatch(name)) list._items.add(name);
        }
        return 0;
    }
    return super.invoke(vm, member, args);
  }
}

class _MakiStub extends MakiObject {
  _MakiStub(this.makiClass, [this._runtime]);

  final WasabiScriptRuntime? _runtime;

  @override
  final String makiClass;

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "popatmouse" || "popatxy":
        return -1;
      // `PlDir.showCurrentlyPlayingEntry` is the old name of
      // `PlEdit.showCurrentlyPlayingTrack`: the playlist scrolls to the
      // playing track.
      case "showcurrentlyplayingentry":
        _runtime?.skin.playlistReveal.value++;
        return null;
      // Application: quits the player.
      case "shutdown" when makiClass == "application":
        _runtime?.host.runAction(
          const WasabiAction("EXIT", null, container: ""),
        );
        return null;
      case "cancelshutdown" when makiClass == "application":
        return null;
      // Where "the classic player" is: the folder skins find the plug-ins they carry in
      // (ClassicPro's BrowserPro reads its provider list there).
      case "getapplicationpath" when makiClass == "application":
        return WasabiFiles.virtualRoot;
      case "getgroup":
        return _MakiStub("winampconfiggroup");
      case "getint":
        return 0;
      case "getbool":
        return false;
      case "getstring":
        return "";
      case "setint" || "setbool" || "setstring":
        return null;
      case "getnumcommands" || "getnumitems":
        return 0;
      case "addcommand" ||
          "addseparator" ||
          "addsubmenu" ||
          "checkcommand" ||
          "disablecommand":
        return null;
    }
    return super.invoke(vm, member, args);
  }
}

/// The `Config` object: skin options as items of attributes, stored with
/// the private settings.
class _MakiConfig extends MakiObject {
  late WasabiScriptRuntime _runtime;
  final Map<String, _MakiConfigItem> _items = {};

  /// The items by GUID, lowercase and without braces.
  final Map<String, _MakiConfigItem> _byGuid = {};

  @override
  String get makiClass => "config";

  static final _guidPattern = RegExp(
    r"^\{?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\}?$",
    caseSensitive: false,
  );

  /// [text] as a key of [_byGuid], or null when it is not a GUID
  /// (`nsGUID::fromCharW`).
  static String? _guidOf(String text) =>
      _guidPattern.firstMatch(text.trim())?.group(1)!.toLowerCase();

  /// The item whose GUID [text] is, if any.
  _MakiConfigItem? _byGuidKey(String text) {
    final guid = _guidOf(text);
    return guid == null ? null : _byGuid[guid];
  }

  /// The item named [nameOrGuid] or with that GUID
  /// (`ConfigObject::getItem`).
  _MakiConfigItem? _find(String nameOrGuid) =>
      _byGuidKey(nameOrGuid) ?? _items[nameOrGuid.toLowerCase()];

  /// The item a skin's `cfgattrib` names, made when no script did.
  _MakiConfigItem _itemFor(String nameOrGuid) =>
      _find(nameOrGuid) ?? _create(nameOrGuid, nameOrGuid);

  _MakiConfigItem _create(String name, String guid) {
    final item = _items[name.toLowerCase()] = _MakiConfigItem(this, name);
    final key = _guidOf(guid);
    if (key != null) _byGuid[key] = item;
    return item;
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "getitem" || "getitembyguid":
        // The classic player's own items (such as the Options menu's) exist before any
        // script asks for them.
        final name = args[0] as String? ?? "";
        return _find(name) ?? _create(name, name);
      case "newitem":
        final name = args[0] as String? ?? "";
        final guid = args.length > 1 ? args[1] as String? ?? "" : "";
        return _find(name) ?? _find(guid) ?? _create(name, guid);
    }
    return super.invoke(vm, member, args);
  }
}

class _MakiConfigItem extends MakiObject {
  _MakiConfigItem(this._config, this.name);

  final _MakiConfig _config;
  final String name;
  final Map<String, _MakiConfigAttribute> _attributes = {};

  @override
  String get makiClass => "configitem";

  _MakiConfigAttribute _attribute(String attribute, String fallback) =>
      _attributes[attribute.toLowerCase()] ??= _MakiConfigAttribute(
        this,
        attribute,
        fallback,
      );

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "getname" || "getguid":
        return name;
      case "getattribute":
        return _attribute(args[0] as String? ?? "", "");
      case "newattribute":
        return _attribute(args[0] as String? ?? "", args[1] as String? ?? "");
    }
    return super.invoke(vm, member, args);
  }
}

class _MakiConfigAttribute extends MakiObject {
  _MakiConfigAttribute(this._item, this.name, this._fallback);

  final _MakiConfigItem _item;
  final String name;
  final String _fallback;

  WasabiScriptRuntime get _runtime => _item._config._runtime;

  String get _section => "config/${_item.name}";

  @override
  String get makiClass => "configattribute";

  /// What the classic player's own options are before anyone sets them. Skins read the
  /// desktop alpha one to choose between artwork for windows that can be
  /// see-through and a baked-in fallback (OrbFace's "if you see this, disable
  /// desktop alpha" message), and this runtime always can be.
  static final Map<String, String> _coreDefaults = {
    for (final section in const [
      "config/skins and ui tweaks",
      // The same item by its GUID, as classic.x-era skins name it.
      "config/{9149c445-3c30-4e04-8433-5a518ed0fdde}",
    ])
      for (final entry in _uiOptions.entries)
        "$section/${entry.key}": entry.value,
  };

  /// The attributes of the classic player's "Skins and UI Tweaks" item
  /// (`{9149C445-3C30-4E04-8433-5A518ED0FDDE}`) and what gen_ff gives them
  /// before anyone sets them (`wasabicfg.h`, `uioptions.cpp`): a skin's
  /// ticker script divides by `Text Ticker Speed`.
  static const Map<String, String> _uiOptions = {
    "enable desktop alpha": "1",
    "link layouts scale": "1",
    "link layouts alpha": "0",
    "link all layouts alpha": "1",
    "link all layouts scale": "0",
    "linked layouts alpha": "255",
    "auto opacity hold time": "2000",
    "auto opacity fade in time": "250",
    "auto opacity fade out time": "1000",
    "use auto opacity": "0",
    "auto opacity extend by": "25",
    "use layout scale locks": "0",
    "multiplexed timers resolution": "33",
    "enable tooltips": "1",
    "text ticker speed": "0.333333",
    "text ticker increment": "1",
    "appbar hide time": "500",
    "appbar show time": "500",
    "timer refresh rate": "30",
    "popup menu alpha": "240",
    "spectrum analyzer mode": "1",
  };

  String get data =>
      _runtime._private(_section, name) ??
      (_fallback.isNotEmpty
          ? _fallback
          : _coreDefaults["$_section/$name".toLowerCase()] ?? "");

  /// [data] as a number, 0 when it is not one (`getDataAsInt`).
  int get asInt => int.tryParse(data.trim()) ?? 0;

  void setData(MakiVm vm, String value) {
    if (value == data) return;
    _runtime.host.writePrivate("${_runtime.skin.name}/$_section", name, value);
    vm.fire(this, "ondatachanged");
    _runtime._slidersFollow(this);
    _runtime._cfgFollow(WasabiCfgAttrib(_item.name, name), this);
    _runtime.changed();
  }

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    switch (member) {
      case "getdata":
        return data;
      case "setdata":
        setData(vm, args[0] as String? ?? "");
        return null;
      case "getattributename":
        return name;
      case "getparentitem":
        return _item;
    }
    return super.invoke(vm, member, args);
  }
}

/// An entry a skin's scripts put in the classic player's Options menu
/// ([WasabiScriptRuntime.skinOptions]): a check box, a submenu of
/// [children], or a separator.
class WasabiSkinOption {
  const WasabiSkinOption._({
    required this.label,
    this.children,
    this._attribute,
  }) : separator = false;

  const WasabiSkinOption._separator()
    : label = "",
      children = null,
      _attribute = null,
      separator = true;

  /// The entry's text, with any shortcut after a tab (`Equalizer\tAlt+G`).
  final String label;

  /// The submenu's entries, or null when the entry is not a submenu.
  final List<WasabiSkinOption>? children;

  /// Whether the entry is a separator line.
  final bool separator;

  final _MakiConfigAttribute? _attribute;

  /// What identifies the option's attribute ([WasabiScriptRuntime.
  /// setConfigAttribute]): its name.
  String get key => _attribute?.name ?? label;

  /// Whether the entry is a check box.
  bool get checkable => _attribute != null;

  /// Whether the check box is checked: its value is not 0.
  bool get checked => (_attribute?.asInt ?? 0) != 0;
}
