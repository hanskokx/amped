import "package:arcane_framework/arcane_framework.dart";
import "package:flutter/foundation.dart";

import "console_interface.dart";
import "memory_interface.dart";
import "redacting_interceptor.dart";

/// Configures Arcane's logger for Amped. Messages are logged with
/// [Arcane.log]; this only sets where they go.
abstract class AppLogging {
  /// The latest log events, masked, for a bug report.
  static final MemoryInterface recent = MemoryInterface();

  /// Registers the console and [redactingInterceptor], which masks tokens and
  /// secrets in every event, and routes
  /// `debugPrint` and unhandled errors through [Arcane.log] so what Flutter
  /// itself prints (windowing, framework errors) is masked too. Amped code
  /// never calls `debugPrint`.
  static Future<void> init() async {
    Arcane.logger.reset();
    Arcane.logger.interceptors.add(redactingInterceptor);
    await Arcane.logger.registerInterface(const ConsoleInterface());
    recent.clear();
    await Arcane.logger.registerInterface(recent);
    _routeDebugPrint();
  }

  static void _routeDebugPrint() {
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        Arcane.log(message, module: "Flutter", skipAutodetection: true);
      }
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      Arcane.log(
        "Unhandled error",
        level: Level.error,
        module: "Flutter",
        skipAutodetection: true,
        metadata: {"error": "$error"},
        stackTrace: stack,
      );
      return true;
    };
  }
}
