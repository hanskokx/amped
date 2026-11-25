import "dart:collection";

import "package:arcane_framework/arcane_framework.dart";

import "console_interface.dart";

/// Keeps the latest log events in memory, to attach to a bug report. Register
/// [redactingInterceptor] too, so events arrive masked.
class MemoryInterface extends LoggingInterface {
  /// Keeps up to [maxCharacters] of text; the oldest events go first.
  MemoryInterface({this.maxCharacters = 200000});

  final int maxCharacters;

  final Queue<String> _entries = Queue<String>();
  int _size = 0;

  /// The events kept, oldest first, one after another.
  String get text => _entries.join("\n");

  /// Forgets everything.
  void clear() {
    _entries.clear();
    _size = 0;
  }

  @override
  void log(
    String message, {
    Map<String, Object?>? metadata,
    Level? level,
    StackTrace? stackTrace,
    Object? extra,
  }) {
    final Object? error = metadata?["error"] ?? extra;
    final String entry = [
      "${DateTime.now().toIso8601String()} "
          "${(level ?? Level.debug).name.toUpperCase()} "
          "${ConsoleInterface.format(message, metadata)}",
      if (error != null && metadata?["error"] == null) "$error",
      if (stackTrace != null) "$stackTrace",
    ].join("\n");
    _entries.addLast(entry);
    _size += entry.length + 1;
    while (_size > maxCharacters && _entries.length > 1) {
      _size -= _entries.removeFirst().length + 1;
    }
  }
}
