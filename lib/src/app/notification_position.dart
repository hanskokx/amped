import "package:flutter/painting.dart";

/// Where Amped's own notification appears on the screen.
enum NotificationPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  bool get isTop => index < 3;

  /// 0 for the left column, 1 for the center, 2 for the right.
  int get column => index % 3;

  /// The edge the notification slides out from: the right side slides out
  /// to the left, the left side to the right, and the middle both ways.
  Alignment get slideAnchor => switch (column) {
    0 => Alignment.centerLeft,
    1 => Alignment.center,
    _ => Alignment.centerRight,
  };

  /// The top-left corner of a [size] notification inside [area], [margin]
  /// away from the edges.
  Offset originIn(Rect area, Size size, {double margin = 16}) {
    final x = switch (column) {
      0 => area.left + margin,
      1 => area.left + (area.width - size.width) / 2,
      _ => area.right - size.width - margin,
    };
    final y = isTop ? area.top + margin : area.bottom - size.height - margin;
    return Offset(x, y);
  }

  static NotificationPosition fromName(String? name) => values.firstWhere(
    (position) => position.name == name,
    orElse: () => bottomRight,
  );
}

/// When a modern skin's own notifier shows, as the skin's options name it
/// (Amped Modern's Options > Notifications).
enum SkinNotifierMode {
  always("Show always"),
  windowshade("Show with windowshade and when minimized"),
  minimized("Show only when minimized"),
  never("Never show");

  const SkinNotifierMode(this.option);

  /// The skin option that is on for this mode.
  final String option;
}
