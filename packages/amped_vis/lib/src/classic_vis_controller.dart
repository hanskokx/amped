import "dart:async";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";

import "classic_vis.dart";
import "vis_worker.dart";

/// Drives a classic visualization view (the main window's, the playlist's
/// and a skin's `<vis>`): each 16 ms [tick] it has a [VisWorker] analyze
/// the samples and draw, and keeps the latest [picture] for the view's
/// painter. The view only paints; the FFT and the drawing stay off the UI
/// isolate.
class ClassicVisController extends ChangeNotifier {
  Future<VisWorker>? _worker;
  int _cycle = 0;

  /// Cycles asked of the worker and not yet answered.
  int _inFlight = 0;

  /// Bumped when the picture is blanked, so that pictures of cycles asked
  /// before are dropped.
  int _epoch = 0;
  bool _disposed = false;

  /// The latest picture, or null while the visualization is blank.
  ClassicVisPicture? get picture => _picture;
  ClassicVisPicture? _picture;

  /// Whether a picture is showing.
  bool get showing => _picture != null;

  /// Bumped on each new [picture].
  int get frame => _frame;
  int _frame = 0;

  /// One 16 ms cycle. While [running] it analyzes [left] and [right] (the
  /// latest samples; silence when null) and, every `refresh` cycles,
  /// draws. Otherwise the last picture stays if [keepPicture] (paused)
  /// and is blanked if not.
  void tick({
    required bool running,
    required bool keepPicture,
    required ClassicVisOptions options,
    required bool windowShade,
    required Float32List? left,
    required Float32List? right,
  }) {
    if (_disposed) return;
    if (!running) {
      if (keepPicture) return;
      if (showing) _blank();
      return;
    }
    // A stalled worker is not fed more than a few cycles.
    if (_inFlight >= 4) return;
    final draw = ++_cycle >= options.refresh;
    if (draw) _cycle = 0;
    final worker = _worker ??= VisWorker.startClassic();
    final epoch = _epoch;
    _inFlight++;
    unawaited(
      worker
          .then(
            (worker) => worker.classic(
              left: left,
              right: right,
              options: options,
              windowShade: windowShade,
              draw: draw,
            ),
          )
          .then<ClassicVisPicture?>(
            (picture) => picture,
            onError: (Object error) {
              Arcane.log(
                "Classic visualization unavailable",
                level: Level.warning,
                module: "ClassicVisController",
                metadata: {"error": "$error"},
              );
              return null;
            },
          )
          .then((picture) {
            _inFlight--;
            if (_disposed || picture == null || epoch != _epoch) return;
            _picture = picture;
            _frame++;
            notifyListeners();
          }),
    );
  }

  void _blank() {
    _epoch++;
    _picture = null;
    final worker = _worker;
    if (worker != null) unawaited(worker.then((w) => w.resetClassic()));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final worker = _worker;
    if (worker != null) unawaited(worker.then((w) => w.dispose()));
    super.dispose();
  }
}
