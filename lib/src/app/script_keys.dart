import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/services.dart";

import "../skin/skin_views.dart";

/// Keys a modern skin's scripts hear (`System.onKeyDown`, `<accelerators>`).
abstract final class ScriptKeys {
  /// Gives the modern skin's scripts a key the app has no use for
  /// (`System.onKeyDown`), true when one took it.
  static bool send(
    KeyEvent event,
    SkinWindow window, {
    required WasabiScriptRuntime? scripts,
    required Skin skin,
  }) {
    if (scripts == null || event is KeyRepeatEvent) return false;
    final name = nameOf(event.logicalKey);
    if (name == null) return false;
    final held = <String>[
      if (HardwareKeyboard.instance.isControlPressed && name != "ctrl") "ctrl",
      if (HardwareKeyboard.instance.isAltPressed && name != "alt") "alt",
      if (HardwareKeyboard.instance.isShiftPressed && name != "shift") "shift",
      name,
    ];
    final key = held.join("+");
    // A key the skin binds to an action (`<accelerators>`) is told to its
    // scripts as that, in the window's section then the general one, and
    // goes no further (`Keyboard::onForwardOnKeyDown`).
    final wasabi = skin.wasabi;
    if (wasabi != null && event is KeyDownEvent) {
      final layout = skin.modern?.layout(window)?.id;
      for (final section in [?layout, "general"]) {
        final action = wasabi.accelerator(section, key);
        if (action == null) continue;
        scripts.accelerator(action, section, key);
        return true;
      }
    }
    return scripts.keyEvent(key, down: event is KeyDownEvent);
  }

  /// A key's name as Wasabi writes it (`Keyboard::getVkName`).
  static String? nameOf(LogicalKeyboardKey key) {
    final names = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowUp: "up",
      LogicalKeyboardKey.arrowDown: "down",
      LogicalKeyboardKey.arrowLeft: "left",
      LogicalKeyboardKey.arrowRight: "right",
      LogicalKeyboardKey.space: "space",
      LogicalKeyboardKey.enter: "return",
      LogicalKeyboardKey.escape: "esc",
      LogicalKeyboardKey.tab: "tab",
      LogicalKeyboardKey.backspace: "backspace",
      LogicalKeyboardKey.delete: "delete",
      LogicalKeyboardKey.insert: "insert",
      LogicalKeyboardKey.home: "home",
      LogicalKeyboardKey.end: "end",
      LogicalKeyboardKey.pageUp: "pageup",
      LogicalKeyboardKey.pageDown: "pagedown",
      LogicalKeyboardKey.controlLeft: "ctrl",
      LogicalKeyboardKey.controlRight: "ctrl",
      LogicalKeyboardKey.altLeft: "alt",
      LogicalKeyboardKey.altRight: "alt",
      LogicalKeyboardKey.shiftLeft: "shift",
      LogicalKeyboardKey.shiftRight: "shift",
    };
    final named = names[key];
    if (named != null) return named;
    final label = key.keyLabel.toLowerCase();
    if (label.length == 1) return label;
    if (RegExp(r"^f\d{1,2}$").hasMatch(label)) return label;
    return null;
  }
}
