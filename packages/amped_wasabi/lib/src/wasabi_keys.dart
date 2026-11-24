import "package:flutter/services.dart";

/// The Windows virtual-key code of [key], as Wasabi hands it to a script's
/// `onKeyDown(int vk_code)`, or null for a key without one here.
int? wasabiVirtualKey(LogicalKeyboardKey key) {
  final named = _named[key];
  if (named != null) return named;
  final label = key.keyLabel;
  if (label.length == 1) {
    final code = label.toUpperCase().codeUnitAt(0);
    // 0-9 and A-Z are their ASCII codes.
    if ((code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A)) {
      return code;
    }
  }
  final function = RegExp(r"^F(\d{1,2})$").firstMatch(label);
  if (function != null) {
    final n = int.parse(function.group(1)!);
    if (n >= 1 && n <= 24) return 0x6F + n; // VK_F1 is 0x70
  }
  return null;
}

final Map<LogicalKeyboardKey, int> _named = {
  LogicalKeyboardKey.backspace: 0x08,
  LogicalKeyboardKey.tab: 0x09,
  LogicalKeyboardKey.enter: 0x0D,
  LogicalKeyboardKey.numpadEnter: 0x0D,
  LogicalKeyboardKey.shiftLeft: 0x10,
  LogicalKeyboardKey.shiftRight: 0x10,
  LogicalKeyboardKey.controlLeft: 0x11,
  LogicalKeyboardKey.controlRight: 0x11,
  LogicalKeyboardKey.altLeft: 0x12,
  LogicalKeyboardKey.altRight: 0x12,
  LogicalKeyboardKey.escape: 0x1B,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.insert: 0x2D,
  LogicalKeyboardKey.delete: 0x2E,
};
