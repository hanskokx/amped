import "package:flutter/foundation.dart";

/// How an episode is judged to be played.
enum CompletionMode {
  /// Once a share of it was played.
  percent,

  /// Once no more than some time of it is left.
  remaining,
}

/// When a podcast episode counts as played, so that the number of new
/// episodes follows how people really listen: not every episode is heard to
/// the last second.
@immutable
class PodcastCompletion {
  const PodcastCompletion({
    this.mode = CompletionMode.percent,
    this.percent = 90,
    this.remaining = const Duration(minutes: 1),
  });

  final CompletionMode mode;

  /// The share played, in percent, for [CompletionMode.percent]; at least
  /// [minPercent].
  final int percent;

  /// The time left, for [CompletionMode.remaining].
  final Duration remaining;

  /// The least share that can be chosen: less would call episodes played
  /// that were hardly heard.
  static const minPercent = 75;

  static const percentChoices = [75, 80, 85, 90, 95, 100];

  static const remainingChoices = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];

  /// An episode of [duration] that was played to [position].
  bool isCompleted({required Duration position, required Duration duration}) =>
      switch (mode) {
        CompletionMode.percent =>
          position.inMilliseconds >=
              duration.inMilliseconds * percent.clamp(minPercent, 100) / 100,
        CompletionMode.remaining => duration - position <= remaining,
      };

  /// An episode that was played [progress] of the way (0 to 1), when it is
  /// [duration] long (null when that isn't known: then only played to the
  /// very end counts for [CompletionMode.remaining]).
  bool isCompletedAt(double progress, Duration? duration) {
    if (progress >= 1) return true;
    return switch (mode) {
      CompletionMode.percent =>
        progress >= percent.clamp(minPercent, 100) / 100,
      CompletionMode.remaining =>
        duration != null &&
            duration.inMilliseconds * (1 - progress) <=
                remaining.inMilliseconds,
    };
  }

  PodcastCompletion copyWith({
    CompletionMode? mode,
    int? percent,
    Duration? remaining,
  }) => PodcastCompletion(
    mode: mode ?? this.mode,
    percent: percent ?? this.percent,
    remaining: remaining ?? this.remaining,
  );

  Map<String, dynamic> toJson() => {
    "mode": mode.name,
    "percent": percent,
    "remainingSeconds": remaining.inSeconds,
  };

  // ignore: prefer_constructors_over_static_methods
  static PodcastCompletion fromJson(Map<String, dynamic>? json) {
    const usual = PodcastCompletion();
    if (json == null) return usual;
    final percent = json["percent"];
    final seconds = json["remainingSeconds"];
    return PodcastCompletion(
      mode: CompletionMode.values.firstWhere(
        (mode) => mode.name == json["mode"],
        orElse: () => usual.mode,
      ),
      // Saved before there was a least, or by hand: brought into range.
      percent: percent is int ? percent.clamp(minPercent, 100) : usual.percent,
      remaining: seconds is int && seconds >= 0
          ? Duration(seconds: seconds)
          : usual.remaining,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PodcastCompletion &&
      other.mode == mode &&
      other.percent == percent &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(mode, percent, remaining);
}

/// What can be set for each remote source.
@immutable
class SourceSettings {
  const SourceSettings({
    this.refresh = true,
    this.refreshEvery = const Duration(minutes: 15),
    this.refreshFirst = const Duration(seconds: 30),
    this.completion = const PodcastCompletion(),
  });

  /// The usual settings for a source of its kind: podcasts are looked at
  /// again in the background, the (much larger) music sources are not
  /// unless asked.
  const SourceSettings.music()
    : refresh = false,
      refreshEvery = const Duration(minutes: 15),
      refreshFirst = const Duration(seconds: 30),
      completion = const PodcastCompletion();

  /// The usual settings for a podcast source (which refreshes) or another
  /// kind of source.
  // ignore: prefer_constructors_over_static_methods
  static SourceSettings usualFor({required bool podcast}) =>
      podcast ? const SourceSettings() : const SourceSettings.music();

  /// Whether the source is looked at again in the background.
  final bool refresh;

  /// How often.
  final Duration refreshEvery;

  /// How long after the app starts the first time is.
  final Duration refreshFirst;

  /// When an episode counts as played (podcast sources).
  final PodcastCompletion completion;

  /// The intervals offered.
  static const intervals = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 6),
  ];

  /// The delays after starting offered.
  static const startDelays = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  SourceSettings copyWith({
    bool? refresh,
    Duration? refreshEvery,
    Duration? refreshFirst,
    PodcastCompletion? completion,
  }) => SourceSettings(
    refresh: refresh ?? this.refresh,
    refreshEvery: refreshEvery ?? this.refreshEvery,
    refreshFirst: refreshFirst ?? this.refreshFirst,
    completion: completion ?? this.completion,
  );

  Map<String, dynamic> toJson() => {
    "refresh": refresh,
    "refreshMinutes": refreshEvery.inMinutes,
    "refreshFirstSeconds": refreshFirst.inSeconds,
    "completion": completion.toJson(),
  };

  /// The saved settings; [usual] stands for what is missing or unusable.
  // ignore: prefer_constructors_over_static_methods
  static SourceSettings fromJson(
    Map<String, dynamic>? json,
    SourceSettings usual,
  ) {
    if (json == null) return usual;
    final minutes = json["refreshMinutes"];
    final seconds = json["refreshFirstSeconds"];
    return SourceSettings(
      refresh: json["refresh"] as bool? ?? usual.refresh,
      // A zero would refresh in a tight loop.
      refreshEvery: minutes is int && minutes >= 1
          ? Duration(minutes: minutes)
          : usual.refreshEvery,
      refreshFirst: seconds is int && seconds >= 0
          ? Duration(seconds: seconds)
          : usual.refreshFirst,
      completion: PodcastCompletion.fromJson(
        json["completion"] as Map<String, dynamic>?,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceSettings &&
      other.refresh == refresh &&
      other.refreshEvery == refreshEvery &&
      other.refreshFirst == refreshFirst &&
      other.completion == completion;

  @override
  int get hashCode =>
      Object.hash(refresh, refreshEvery, refreshFirst, completion);
}
