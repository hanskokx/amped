import "dart:convert";

import "package:arcane_framework/arcane_framework.dart";
import "package:flutter/foundation.dart";
import "package:logger/logger.dart" as l;

/// Writes log events to the console through `logger`. It does not mask
/// anything itself: register [redactingInterceptor] so events arrive masked.
class ConsoleInterface extends LoggingInterface {
  /// A console that writes each line to [output], or to the console.
  const ConsoleInterface({this.output});

  /// Where a finished log goes; null is the console.
  final void Function(String text)? output;

  /// What [log] writes for [message] and [metadata].
  static String format(String message, Map<String, Object?>? metadata) {
    final Map<String, Object?> rest = {...?metadata}
      ..remove("module")
      ..remove("method")
      ..remove("filenameAndLineNumber");
    final String prefix = [
      if (metadata?["module"] != null) "[${metadata!["module"]}]",
      if (metadata?["method"] != null) "[${metadata!["method"]}]",
    ].join();
    var text = prefix.isEmpty ? message : "$prefix $message";
    if (rest.isNotEmpty) {
      text +=
          "\n\n${const JsonEncoder.withIndent("  ", _encode).convert(rest)}";
    }
    return text;
  }

  static Object? _encode(Object? value) => "$value";

  @override
  void log(
    String message, {
    Map<String, Object?>? metadata,
    Level? level,
    StackTrace? stackTrace,
    Object? extra,
  }) {
    final l.Level logLevel = l.Level.values.firstWhere(
      (value) => value.name == (level ?? Level.debug).name,
      orElse: () => l.Level.debug,
    );
    final Object? error = metadata?["error"] ?? extra;
    final l.Logger logger = l.Logger(
      level: logLevel,
      output: output == null ? null : _Output(output!),
      printer: l.PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 8,
        colors: output == null && defaultTargetPlatform != TargetPlatform.iOS,
      ),
    );
    logger.log(
      logLevel,
      format(message, metadata),
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _Output extends l.LogOutput {
  _Output(this.write);

  final void Function(String text) write;

  @override
  void output(l.OutputEvent event) => write(event.lines.join("\n"));
}
