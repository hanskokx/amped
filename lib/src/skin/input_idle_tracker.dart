import "dart:async";

import "package:flutter/gestures.dart";
import "package:flutter/services.dart";

/// Knows whether the person is using the app: work that competes with the UI
/// thread (drawing skin pictures) waits for a quiet moment.
class InputIdleTracker {
  InputIdleTracker({
    this.quiet = const Duration(seconds: 3),
    this.poll = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long without a pointer or key event counts as idle.
  final Duration quiet;

  /// How often a waiting caller looks again.
  final Duration poll;

  final DateTime Function() _now;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _started = false;

  /// Starts listening to pointer and key events. Once is enough.
  void start() {
    if (_started) return;
    _started = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _onPointer(PointerEvent event) => touch();

  bool _onKey(KeyEvent event) {
    touch();
    return false;
  }

  /// Notes that the person just did something.
  void touch() => _last = _now();

  /// Whether nothing has been done for [quiet].
  bool get isIdle => _now().difference(_last) >= quiet;

  /// Completes once the app has been left alone for [quiet].
  Future<void> whenIdle() async {
    while (!isIdle) {
      await Future<void>.delayed(poll);
    }
  }
}
