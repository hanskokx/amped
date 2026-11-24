import "dart:io";

import "package:flutter/foundation.dart";

/// A subtitle file found beside a video.
@immutable
class SubtitleFile {
  const SubtitleFile({
    required this.location,
    required this.title,
    this.language,
  });

  /// Where to read it: a path, or a URL on a network share.
  final String location;

  /// What to list it as: its file name.
  final String title;

  /// A language code taken from the name (`Movie.en.srt`), if there is one.
  final String? language;
}

/// The folders beside a video where its subtitles are also kept.
/// Compared in lower case.
const List<String> subtitleFolders = ["subs", "subtitles"];

/// Subtitle formats that are text, which the player can draw.
const Set<String> subtitleExtensions = {".srt", ".ass", ".ssa", ".vtt"};

/// The names in [names] that are subtitles of the video called [videoName]:
/// the same name with a subtitle extension, optionally with dotted tags in
/// between (`Movie.en.forced.srt`).
List<MapEntry<String, SubtitleFile>> matchSubtitles(
  String videoName,
  Iterable<String> names,
  String Function(String name) locate,
) {
  final base = _withoutExtension(_baseName(videoName)).toLowerCase();
  final found = <MapEntry<String, SubtitleFile>>[];
  for (final name in names) {
    final extension = _extension(name).toLowerCase();
    if (!subtitleExtensions.contains(extension)) continue;
    final stem = _withoutExtension(name);
    final lower = stem.toLowerCase();
    if (lower != base && !lower.startsWith("$base.")) continue;
    final tags = lower == base
        ? <String>[]
        : lower.substring(base.length + 1).split(".");
    String? language;
    for (final tag in tags) {
      if (RegExp(r"^[a-z]{2,3}(-[a-z0-9]{2,4})?$").hasMatch(tag)) {
        language = tag;
        break;
      }
    }
    found.add(
      MapEntry(
        name,
        SubtitleFile(location: locate(name), title: name, language: language),
      ),
    );
  }
  found.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return found;
}

/// The subtitle files beside the video at [videoPath], and in a `Subs`
/// folder next to it. Read without blocking, as the folder may be on a
/// network volume.
Future<List<SubtitleFile>> localSubtitles(String videoPath) async {
  final folder = File(videoPath).parent;
  final name = _baseName(videoPath);
  final result = <SubtitleFile>[];
  Future<List<Directory>> scan(
    Directory directory, {
    bool nested = false,
  }) async {
    final names = <String>[];
    final subfolders = <Directory>[];
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File) {
          names.add(_baseName(entry.path));
        } else if (!nested &&
            entry is Directory &&
            subtitleFolders.contains(_baseName(entry.path).toLowerCase())) {
          subfolders.add(entry);
        }
      }
    } on FileSystemException {
      return const [];
    }
    result.addAll(
      matchSubtitles(
        name,
        names,
        (n) => "${directory.path}${Platform.pathSeparator}$n",
      ).map((e) => e.value),
    );
    return subfolders;
  }

  for (final sub in await scan(folder)) {
    await scan(sub, nested: true);
  }
  return result;
}

String _extension(String name) {
  final dot = name.lastIndexOf(".");
  return dot <= 0 ? "" : name.substring(dot);
}

String _withoutExtension(String name) {
  final dot = name.lastIndexOf(".");
  return dot <= 0 ? name : name.substring(0, dot);
}

String _baseName(String path) {
  final cut = path.lastIndexOf(RegExp(r"[/\\]"));
  return cut < 0 ? path : path.substring(cut + 1);
}
