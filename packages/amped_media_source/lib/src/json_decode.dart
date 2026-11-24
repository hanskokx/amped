import "dart:convert";
import "dart:isolate";

/// Bodies shorter than this are parsed right here: starting an isolate costs
/// more than parsing them.
const _isolateThreshold = 32 * 1024;

/// Parses [text] as JSON, off the UI thread when it is big (a page of a
/// server's library). Throws [FormatException] when it isn't JSON.
Future<Object?> decodeJson(String text) async => text.length < _isolateThreshold
    ? jsonDecode(text)
    : await Isolate.run(() => jsonDecode(text));
