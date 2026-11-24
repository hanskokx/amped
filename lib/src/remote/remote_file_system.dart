import "dart:io";

/// One name in a folder of a network share.
class RemoteEntry {
  const RemoteEntry(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;
}

/// A connection to a network share, whatever the protocol: the part of
/// browsing and playing from it that differs between SMB and WebDAV.
///
/// Paths are decoded and start at the share's root: `/share/folder/a.mp3`.
abstract class RemoteFileSystem {
  /// What is in the folder at [path].
  Future<List<RemoteEntry>> list(String path);

  /// Copies the file at [path] to [destination], telling [onProgress] how
  /// many bytes have arrived and how many there will be (null if the
  /// server doesn't say).
  Future<void> download(
    String path,
    File destination, {
    void Function(int received, int? total)? onProgress,
  });

  /// The size in bytes of the file at [path].
  Future<int> size(String path);

  /// The bytes of the file at [path] from [start] up to (not including)
  /// [end], or to the end of the file when [end] is null.
  Stream<List<int>> openRead(String path, int start, [int? end]);

  /// Ends the connection.
  Future<void> close();
}

/// How far a download has come.
class RemoteProgress {
  const RemoteProgress(this.received, this.total, this.elapsed);

  final int received;

  /// The file's size, or null when it isn't known.
  final int? total;

  final Duration elapsed;

  /// 0..1, or null when the size isn't known.
  double? get fraction {
    final size = total;
    return size == null || size <= 0 ? null : received / size;
  }

  /// Bytes per second so far.
  double get speed {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : received / seconds;
  }

  /// How long the rest should take at the speed so far, or null when that
  /// can't be told.
  Duration? get remaining {
    final size = total;
    if (size == null || speed <= 0) return null;
    return Duration(seconds: ((size - received) / speed).ceil());
  }
}

/// Something went wrong talking to a network share.
class RemoteFileException implements Exception {
  const RemoteFileException(this.message);

  final String message;

  @override
  String toString() => "RemoteFileException: $message";
}
