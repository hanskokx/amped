import "dart:async";
import "dart:isolate";
import "dart:typed_data";

import "package:amped_vis_api/amped_vis_api.dart";

import "classic_vis.dart";

/// Makes the visualization plug-ins. The app and a [VisWorker]'s isolate each
/// build their own (plug-ins hold state and callbacks, so they can't be sent
/// between isolates), so it must be a top-level function or a static method.
typedef VisPluginFactory = List<VisPlugin> Function();

/// A picture a [VisWorker] drew.
class VisWorkerFrame {
  const VisWorkerFrame({
    required this.pixels,
    required this.width,
    required this.height,
    required this.title,
    required this.titleOpaque,
    required this.keepRunning,
  });

  /// RGBA bytes, [width] by [height].
  final Uint8List pixels;
  final int width;
  final int height;
  final String? title;
  final bool titleOpaque;

  /// False when the module asked to end the visualization.
  final bool keepRunning;
}

/// Runs visualizations in an isolate of its own, so that the FFT and the
/// drawing (milliseconds a frame at full screen) stay off the UI isolate.
/// Every visualization goes through one: a plug-in [VisModule] ([start],
/// [render]) or the classic analyzer and oscilloscope ([startClassic],
/// [classic]). A module is built in the isolate from the plug-in's saved
/// configuration; changes to the configuration need a new worker.
class VisWorker {
  VisWorker._(this._isolate, this._commands, this._replies) {
    _subscription = _replies.listen((message) {
      if (_pending.isNotEmpty) _pending.removeFirst().complete(message);
    });
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  late final StreamSubscription<Object?> _subscription;
  final _pending = _Queue();
  bool _disposed = false;

  /// Starts a worker for module [module] of the plug-in [pluginId], with
  /// the plug-in's [config] (as `saveConfig` made it). Returns null when
  /// there is no such module or its `init` failed.
  static Future<VisWorker?> start({
    required VisPluginFactory plugins,
    required String pluginId,
    required int module,
    required Object? config,
  }) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_entry, [replies.sendPort, plugins]);
    final events = StreamIterator<Object?>(replies);
    await events.moveNext();
    final commands = events.current! as SendPort;
    await events.cancel();
    final worker = VisWorker._(isolate, commands, ReceivePort());
    // The first reply is to the start request.
    final reply = worker._request([
      "start",
      pluginId,
      module,
      config,
    ]);
    final ok = (await reply) as bool;
    if (!ok) {
      worker.dispose();
      return null;
    }
    return worker;
  }

  /// Starts a worker for the classic visualization.
  static Future<VisWorker> startClassic() async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_entry, [replies.sendPort, null]);
    final events = StreamIterator<Object?>(replies);
    await events.moveNext();
    final commands = events.current! as SendPort;
    await events.cancel();
    return VisWorker._(isolate, commands, ReceivePort());
  }

  /// One 16 ms cycle of the classic visualization from the latest samples
  /// (silence when null): the picture when this cycle [draw]s, else null.
  /// Cycles are drawn in the order asked.
  Future<ClassicVisPicture?> classic({
    required Float32List? left,
    required Float32List? right,
    required ClassicVisOptions options,
    required bool windowShade,
    required bool draw,
  }) async {
    final reply = await _request([
      "classic",
      left,
      right,
      options.mode.index,
      options.analyzerStyle.index,
      options.thinBands,
      options.scopeStyle.index,
      options.peaks,
      options.falloff,
      options.peakFalloff,
      options.refresh,
      windowShade,
      draw,
    ]);
    if (reply is! TransferableTypedData) return null;
    return ClassicVisPicture(reply.materialize().asUint8List());
  }

  /// Blanks the classic visualization's bars.
  Future<void> resetClassic() => _request(["classicReset"]);

  /// Draws a frame of [width] by [height] pixels from [left] and [right]
  /// (or silence when they are null), for a module wanting the given
  /// channels. Only one frame can be asked for at a time.
  Future<VisWorkerFrame?> render({
    required Float32List? left,
    required Float32List? right,
    required int spectrumChannels,
    required int waveformChannels,
    required int width,
    required int height,
    required String title,
    required int positionSeconds,
    required int lengthSeconds,
  }) async {
    final reply = await _request([
      "render",
      left,
      right,
      spectrumChannels,
      waveformChannels,
      width,
      height,
      title,
      positionSeconds,
      lengthSeconds,
    ]);
    if (reply is! List) return null;
    return VisWorkerFrame(
      pixels: (reply[0] as TransferableTypedData).materialize().asUint8List(),
      width: reply[1] as int,
      height: reply[2] as int,
      title: reply[3] as String?,
      titleOpaque: reply[4] as bool,
      keepRunning: reply[5] as bool,
    );
  }

  Future<Object?> _request(List<Object?> message) {
    if (_disposed) return Future.value();
    final completer = Completer<Object?>();
    _pending.add(completer);
    _commands.send([_replies.sendPort, ...message]);
    return completer.future;
  }

  /// Quits the module and ends the isolate.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commands.send(["quit"]);
    unawaited(_subscription.cancel());
    _replies.close();
    for (final completer in _pending.drain()) {
      completer.complete(null);
    }
    // The isolate exits itself after `quit`; this is only for one that is
    // stuck in a long render.
    Timer(const Duration(seconds: 2), () => _isolate.kill());
  }
}

class _Queue {
  final List<Completer<Object?>> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(Completer<Object?> item) => _items.add(item);

  Completer<Object?> removeFirst() => _items.removeAt(0);

  List<Completer<Object?>> drain() {
    final all = List.of(_items);
    _items.clear();
    return all;
  }
}

class _WorkerContext implements VisContext {
  @override
  String title = "";

  @override
  int positionSeconds = 0;

  @override
  int lengthSeconds = 0;
}

void _entry(List<Object?> arguments) {
  final ready = arguments[0]! as SendPort;
  final makePlugins = arguments[1] as VisPluginFactory?;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  final context = _WorkerContext();
  VisModule? module;
  VisSurface? surface;
  final classic = ClassicVisRenderer();
  commands.listen((Object? message) {
    final m = message! as List<Object?>;
    final reply = m[0];
    if (reply is! SendPort) {
      // "quit"
      module?.quit();
      commands.close();
      return;
    }
    switch (m[1]) {
      case "classicReset":
        classic.reset();
        reply.send(null);
      case "classic":
        final options = ClassicVisOptions(
          mode: ClassicVisMode.values[m[4]! as int],
          analyzerStyle: AnalyzerStyle.values[m[5]! as int],
          thinBands: m[6]! as bool,
          scopeStyle: ScopeStyle.values[m[7]! as int],
          peaks: m[8]! as bool,
          falloff: m[9]! as int,
          peakFalloff: m[10]! as int,
          refresh: m[11]! as int,
        );
        final picture = classic.cycle(
          m[2] as Float32List?,
          m[3] as Float32List?,
          options,
          windowShade: m[12]! as bool,
          draw: m[13]! as bool,
        );
        reply.send(
          picture == null
              ? null
              : TransferableTypedData.fromList([picture.buffer]),
        );
      case "start":
        final plugins = (makePlugins?.call() ?? const <VisPlugin>[]).where(
          (p) => p.id == m[2],
        );
        if (plugins.isEmpty) {
          reply.send(false);
          return;
        }
        final plugin = plugins.first..loadConfig(m[4]);
        final index = m[3]! as int;
        if (index < 0 || index >= plugin.modules.length) {
          reply.send(false);
          return;
        }
        final candidate = plugin.modules[index];
        final ok = candidate.init(context);
        if (ok) module = candidate;
        reply.send(ok);
      case "render":
        final running = module;
        if (running == null) {
          reply.send(null);
          return;
        }
        final left = m[2] as Float32List?;
        final right = m[3] as Float32List?;
        final width = m[6]! as int;
        final height = m[7]! as int;
        context
          ..title = m[8]! as String
          ..positionSeconds = m[9]! as int
          ..lengthSeconds = m[10]! as int;
        var target = surface;
        if (target == null ||
            target.width != width ||
            target.height != height) {
          target = surface = VisSurface(width, height);
        }
        final frame = left == null || right == null
            ? VisFrame.silent()
            : VisFrame.compute(
                left,
                right,
                spectrumChannels: m[4]! as int,
                waveformChannels: m[5]! as int,
              );
        final keepRunning = running.render(frame, target);
        reply.send([
          TransferableTypedData.fromList([target.pixels]),
          width,
          height,
          target.title,
          target.titleOpaque,
          keepRunning,
        ]);
    }
  });
}
