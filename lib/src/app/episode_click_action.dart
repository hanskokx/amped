/// What clicking the notification of newly added podcast episodes does.
enum EpisodeClickAction {
  /// The notification only goes away.
  nothing,

  /// The new episodes are added to the end of the playlist.
  enqueue,

  /// The new episodes are added to the playlist and the first one plays.
  play;

  /// The action saved as [name], or [nothing] for anything else.
  static EpisodeClickAction fromName(String? name) => values.firstWhere(
    (action) => action.name == name,
    orElse: () => nothing,
  );
}
