import "dart:async";
import "dart:convert";
import "dart:math";
import "dart:ui" as ui;

import "package:amped_logging/amped_logging.dart";
import "package:amped_vis/amped_vis.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../player/player_state.dart";
import "vis_plugins.dart";

/// Runs the selected visualization plug-in module (`vis_start`/`vis_stop`
/// and the plug-in thread in VIS.cpp): each frame it hands the module what
/// is playing and turns the picture it draws into an [image].
class VisHost extends ChangeNotifier implements VisContext {
  VisHost(this.player);

  final PlayerState player;

  /// The available plug-ins.
  final List<VisPlugin> plugins = createVisPlugins();

  VisPlugin? _plugin;
  int _module = 0;

  VisModule? _running;
  Timer? _timer;

  /// The isolate drawing the running module's frames, once it is up.
  VisWorker? _worker;

  /// Whether a frame is being drawn or decoded.
  bool _busy = false;

  /// The size of the pictures being drawn, and the title line drawn over
  /// the latest.
  (int, int)? _size;
  String? _title;
  bool _titleOpaque = false;

  /// Counts starts, so that a late worker or frame of an earlier run is
  /// dropped.
  int _run = 0;

  /// The picture before the current one, disposed once the next arrives
  /// (the screen may still be showing it).
  ui.Image? _previous;

  /// The latest picture. Only the visualization window listens to it, so
  /// frames do not rebuild anything else.
  final ValueNotifier<ui.Image?> picture = ValueNotifier(null);

  /// The selected plug-in (the first until one is chosen).
  VisPlugin get plugin => _plugin ?? plugins.first;

  /// The selected module of [plugin].
  int get moduleIndex => _module.clamp(0, plugin.modules.length - 1);

  VisModule get module => plugin.modules[moduleIndex];

  /// The running module, if any.
  VisModule? get running => _running;

  bool get isRunning => _running != null;

  /// Whether the visualization fills the screen instead of its skinned
  /// window (the original's default is the window).
  bool get fullscreen => _fullscreen;
  bool _fullscreen = false;

  void setFullscreen(bool value) {
    if (_fullscreen == value) return;
    _fullscreen = value;
    _applySize();
    notifyListeners();
  }

  void toggleFullscreen() => setFullscreen(!_fullscreen);

  /// The strip at the top of the window that can't be seen (under a
  /// camera housing), which the picture stays below.
  double topInset = 0;

  /// The title line drawn over the picture.
  String? get overlayTitle => _title;
  bool get overlayOpaque => _titleOpaque;

  /// The main window's title as the plug-ins read it ("3. Title"), without
  /// the length the song ticker adds.
  @override
  String get title {
    final entry = player.playlist.currentEntry;
    return entry == null
        ? ""
        : "${player.playlist.current + 1}. ${entry.playingTitle}";
  }

  @override
  int get positionSeconds => player.playing ? player.elapsedSec : 0;

  @override
  int get lengthSeconds =>
      player.playlist.currentEntry?.duration?.inSeconds ?? 0;

  /// Restores the saved plug-in, module and plug-in configurations.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final plugin in plugins) {
      final saved = prefs.getString("amped.vis_config.${plugin.id}");
      if (saved == null) continue;
      try {
        plugin.loadConfig(jsonDecode(saved));
      } on FormatException {
        // Keep the defaults.
      }
    }
    final saved = prefs.getString("amped.vis_plugin")?.split(":");
    if (saved == null || saved.length != 2) return;
    for (final candidate in plugins) {
      if (candidate.id == saved[0]) _plugin = candidate;
    }
    _module = int.tryParse(saved[1]) ?? 0;
  }

  /// Selects [module] of [plugin] (restarting it when one is running).
  void select(VisPlugin plugin, int module) {
    final restart = isRunning;
    if (restart) stop();
    _plugin = plugin;
    _module = module;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString("amped.vis_plugin", "${plugin.id}:$module"),
      ),
    );
    notifyListeners();
    if (restart) start();
  }

  /// Whether the next module is picked at random (the options' Random).
  bool get random => _random;
  bool _random = false;

  void setRandom(bool value) {
    if (_random == value) return;
    _random = value;
    notifyListeners();
  }

  /// Every (plug-in, module) pair, in order.
  List<(VisPlugin, int)> get _allModules => [
    for (final plugin in plugins)
      for (var i = 0; i < plugin.modules.length; i++) (plugin, i),
  ];

  /// Moves to the next module (a random one when [random]).
  void next() => _step(1);

  /// Moves to the previous module (a random one when [random]).
  void previous() => _step(-1);

  void _step(int delta) {
    final all = _allModules;
    if (all.length < 2) return;
    final current = all.indexWhere(
      (e) => e.$1 == plugin && e.$2 == moduleIndex,
    );
    final int target;
    if (_random) {
      // Any module but the current one.
      target =
          (current + 1 + _randomSource.nextInt(all.length - 1)) % all.length;
    } else {
      target = (current + delta) % all.length;
    }
    select(all[target].$1, all[target].$2);
  }

  final Random _randomSource = Random();

  /// Saves [plugin]'s configuration (after its dialog closes).
  Future<void> saveConfig(VisPlugin plugin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      "amped.vis_config.${plugin.id}",
      jsonEncode(plugin.saveConfig()),
    );
    // The module runs on a copy of the configuration, so it starts anew
    // with the saved one.
    if (isRunning && identical(plugin, this.plugin)) {
      final fullscreen = _fullscreen;
      stop();
      start();
      setFullscreen(fullscreen);
    }
  }

  /// Visualization > Start/Stop plug-in.
  void toggle() => isRunning ? stop() : start();

  /// The latest sizes of the picture in the skinned window and on the
  /// screen. Both stay laid out (the hidden one too), so each reports its
  /// own and the current mode's is used.
  (int, int)? _windowSize, _screenSize;

  /// The picture's area in the skinned window or, when [fullscreen], on
  /// the screen is [w] by [h] pixels.
  void resize(int w, int h, {required bool fullscreen}) {
    if (w <= 0 || h <= 0) return;
    if (fullscreen) {
      _screenSize = (w, h);
    } else {
      _windowSize = (w, h);
    }
    _applySize();
  }

  /// Draws at the current mode's size, for modules without a fixed
  /// resolution.
  void _applySize() {
    final running = _running;
    final size = _fullscreen ? _screenSize : _windowSize;
    if (running == null || running.resolution != null || size == null) return;
    _size = size;
  }

  void start() {
    if (isRunning) return;
    final module = this.module;
    // Each start shows the window first, as the original's default.
    _fullscreen = false;
    _size = module.resolution ?? _windowSize ?? (640, 480);
    _running = module;
    final run = ++_run;
    player.engine.startVisualization();
    HardwareKeyboard.instance.addHandler(_onKey);
    unawaited(_startWorker(plugin, moduleIndex, run));
    // At the module's pace (`delayMs`), but no faster than the display.
    final delay = module.delay < const Duration(milliseconds: 16)
        ? const Duration(milliseconds: 16)
        : module.delay;
    _timer = Timer.periodic(delay, (_) => _render());
    notifyListeners();
  }

  /// Starts the isolate that runs the module (`Init` and `Render`), which
  /// frames wait for.
  Future<void> _startWorker(VisPlugin plugin, int module, int run) async {
    VisWorker? worker;
    try {
      worker = await VisWorker.start(
        plugins: createVisPlugins,
        pluginId: plugin.id,
        module: module,
        config: plugin.saveConfig(),
      );
    } on Object catch (error) {
      Arcane.log(
        "Visualization unavailable",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "VisHost",
      );
    }
    if (run != _run || !isRunning) {
      worker?.dispose();
      return;
    }
    if (worker == null) {
      stop();
      return;
    }
    _worker = worker;
  }

  void stop() {
    final module = _running;
    if (module == null) return;
    _running = null;
    // Not left fullscreen for whatever shows it next.
    _fullscreen = false;
    _timer?.cancel();
    _timer = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _run++;
    _worker?.dispose();
    _worker = null;
    _busy = false;
    player.engine.stopVisualization();
    _size = null;
    _title = null;
    _titleOpaque = false;
    notifyListeners();
    // Let the window go before its pictures.
    final current = picture.value, previous = _previous;
    picture.value = null;
    _previous = null;
    scheduleMicrotask(() {
      current?.dispose();
      previous?.dispose();
    });
  }

  /// Escape leaves fullscreen and Alt+Enter toggles it, wherever the
  /// keyboard focus is (the original's window passes other keys on to
  /// the main window).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape && _fullscreen) {
      setFullscreen(false);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isAltPressed) {
      toggleFullscreen();
      return true;
    }
    return false;
  }

  /// Has the worker draw a frame, unless it is still busy with the last.
  Future<void> _render() async {
    final module = _running;
    final worker = _worker;
    final size = _size;
    if (module == null || worker == null || size == null || _busy) return;
    _busy = true;
    final run = _run;
    final samples = player.engine.visualizationSamples;
    final silent = samples == null || !player.playing || player.paused;
    final VisWorkerFrame? frame;
    try {
      frame = await worker.render(
        left: silent ? null : samples.$1,
        right: silent ? null : samples.$2,
        spectrumChannels: module.spectrumChannels,
        waveformChannels: module.waveformChannels,
        width: size.$1,
        height: size.$2,
        title: title,
        positionSeconds: positionSeconds,
        lengthSeconds: lengthSeconds,
      );
    } on Object catch (error) {
      Arcane.log(
        "Visualization stopped",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "VisHost",
      );
      if (run == _run) stop();
      return;
    }
    if (run != _run) return;
    if (frame == null || !frame.keepRunning) {
      stop();
      return;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    _busy = false;
    if (run != _run) {
      image.dispose();
      return;
    }
    _title = frame.title;
    _titleOpaque = frame.titleOpaque;
    _previous?.dispose();
    _previous = picture.value;
    picture.value = image;
  }

  @override
  void dispose() {
    stop();
    picture.dispose();
    super.dispose();
  }
}
