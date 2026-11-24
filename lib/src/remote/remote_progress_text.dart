import "remote_file_system.dart";

/// A byte count for showing: `812 KB`, `3.1 MB`.
String formatBytes(num bytes) {
  const units = ["B", "KB", "MB", "GB"];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return "${value.toStringAsFixed(digits)} ${units[unit]}";
}

/// A length of time for showing: `0:08`, `1:02:09`.
String formatDuration(Duration time) {
  final hours = time.inHours;
  final minutes = (time.inMinutes % 60).toString();
  final seconds = (time.inSeconds % 60).toString().padLeft(2, "0");
  return hours > 0
      ? "$hours:${minutes.padLeft(2, "0")}:$seconds"
      : "$minutes:$seconds";
}

/// The pieces of [progress] the buffering text is made of.
extension RemoteProgressText on RemoteProgress {
  String get speedText => formatBytes(speed);

  String get receivedText => formatBytes(received);

  String get elapsedText => formatDuration(elapsed);

  String? get remainingText {
    final left = remaining;
    return left == null ? null : formatDuration(left);
  }

  int? get percent {
    final part = fraction;
    return part == null ? null : (part * 100).floor().clamp(0, 100);
  }
}
