import "package:amped_media_source/amped_media_source.dart";
import "package:arcane_framework/arcane_framework.dart";

/// Masks every token and secret in a log event (message, metadata at any
/// depth, error) before any interface sees it. Registered globally by
/// `AppLogging.init`, so the console, the DevTools buffer and anything
/// added later only ever get masked text.
const LogInterceptor redactingInterceptor = LogInterceptor(_redactEvent);

LogEvent? _redactEvent(LogEvent event, LogInterceptorContext context) {
  final Map<String, Object?>? metadata = event.metadata;
  return event.copyWith(
    message: redact(event.message),
    metadata: metadata == null ? null : _clean(metadata),
    extra: event.extra == null ? null : redactError(event.extra),
  );
}

Map<String, Object?> _clean(Map<Object?, Object?> map) => {
  for (final MapEntry<Object?, Object?> entry in map.entries)
    "${entry.key}": _cleanValue(entry.value),
};

Object? _cleanValue(Object? value) => switch (value) {
  null || num() || bool() => value,
  String() => redact(value),
  Map<Object?, Object?>() => _clean(value),
  Iterable<Object?>() => [for (final Object? item in value) _cleanValue(item)],
  _ => redactError(value),
};
