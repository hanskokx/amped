import "dart:async";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../platform/native_notifier.dart";
import "../player/player_state.dart";
import "../player/playlist.dart";
import "../player/tag_cache.dart";
import "episode_click_action.dart";
import "notification_position.dart";
import "notification_view.dart" show NotificationText;

/// The popup (or the operating system's notification, or a modern skin's own
/// notifier) shown when playback moves to another item, and the settings
/// that go with it.
class Notifications {
  Notifications({
    required this.player,
    required MethodChannel channel,
    required this._scripts,
    required this._ownNotifier,
    required this._readCover,
    required this._placeNotifier,
    required this._playerChanged,
    required this._changed,
    required this._enabled,
    required this._native,
    required this._position,
    required this._sourceTags,
    this._episodeClick = EpisodeClickAction.nothing,
  }) : _nativeNotifier = NativeNotifier(channel) {
    _nativeNotifier.onClicked = clicked;
  }

  final PlayerState player;

  /// What the loaded sources know of the item at a location.
  final TrackTags? Function(String location) _sourceTags;
  final WasabiScriptRuntime? Function() _scripts;

  /// Whether the skin-independent popup stands in for the notifier: the skin
  /// has no notifier container of its own.
  final bool Function() _ownNotifier;
  final Future<Uint8List?> Function(String path) _readCover;
  final void Function() _placeNotifier;
  final void Function() _playerChanged;
  final void Function() _changed;
  final NativeNotifier _nativeNotifier;

  /// Takes the saved settings from [prefs].
  static ({
    bool enabled,
    bool native,
    NotificationPosition position,
    EpisodeClickAction episodeClick,
  })
  saved(SharedPreferences prefs) => (
    enabled: prefs.getBool(_notificationsKey) ?? true,
    native: prefs.getBool(_nativeKey) ?? false,
    position: NotificationPosition.fromName(
      prefs.getString(_positionKey),
    ),
    episodeClick: EpisodeClickAction.fromName(
      prefs.getString(_episodeClickKey),
    ),
  );

  /// Asks the system's permission when its notifications are on.
  void start() {
    if (enabled && _native) unawaited(_nativeNotifier.requestPermission());
  }

  /// Tells the user of something that happened in the background, in a
  /// notification of the system; nothing when notifications are off.
  Future<void> announce({
    required String title,
    required String body,
    Uint8List? artwork,
    List<String> episodes = const [],
  }) async {
    if (!enabled) return;
    await _nativeNotifier.requestPermission();
    await _nativeNotifier.show(
      title: title,
      body: body,
      artwork: artwork,
      locations: episodes,
    );
  }

  /// What clicking the notification of new episodes does.
  EpisodeClickAction get episodeClick => _episodeClick;
  EpisodeClickAction _episodeClick;

  static const String _episodeClickKey = "amped.episode_click_action";

  void setEpisodeClick(EpisodeClickAction action) {
    if (action == _episodeClick) return;
    _episodeClick = action;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_episodeClickKey, action.name),
      ),
    );
    _changed();
  }

  /// The user clicked a notification of the new episodes at [locations]:
  /// does what [episodeClick] says.
  Future<void> clicked(List<String> locations) async {
    if (locations.isEmpty || _episodeClick == EpisodeClickAction.nothing) {
      return;
    }
    final first = await player.playlist.add(locations);
    if (_episodeClick == EpisodeClickAction.play && first >= 0) {
      await player.playIndex(first);
    }
  }

  void dispose() => _notificationTimer?.cancel();

  /// Whether the notifier window shows: the popup while it is up, or the
  /// skin's notifier while its scripts have it showing ([skinShown]).
  bool windowShows({required bool skinShown}) =>
      enabled && !_native && (_ownNotifier() ? _notificationShown : skinShown);

  /// A modern skin's notifier option set to "never" off and back on.
  void skinPickedMode() {
    if (!skinHasNotifier) return;
    final mode = skinNotifierMode;
    if (mode != null && mode != SkinNotifierMode.never) {
      _modeBeforeOff = mode;
      if (!_enabled) {
        _enabled = true;
        unawaited(
          SharedPreferences.getInstance().then(
            (prefs) => prefs.setBool(_notificationsKey, true),
          ),
        );
      }
    }
    _changed();
  }

  /// Whether track changes pop up a notification (any skin; a modern skin's
  /// own notifier when it has one, else a notification in the classic
  /// skin's colors).
  ///
  /// With a modern skin's own notifier this follows the skin's option: its
  /// "Never show" is the same as off.
  bool get enabled =>
      _enabled &&
      (!skinHasNotifier || skinNotifierMode != SkinNotifierMode.never);
  bool _enabled;

  /// Whether a modern skin's own notifier (and so its options) stands in
  /// for Amped's popup.
  bool get skinHasNotifier =>
      !_ownNotifier() &&
      (_scripts()?.hasConfigAttribute(SkinNotifierMode.always.option) ?? false);

  /// The "when to show" option the skin's notifier is on, or null when the
  /// skin has none.
  SkinNotifierMode? get skinNotifierMode {
    final scripts = _scripts();
    if (scripts == null) return null;
    for (final mode in SkinNotifierMode.values) {
      if (scripts.configAttribute(mode.option) == "1") return mode;
    }
    return null;
  }

  /// What the skin's notifier was on before notifications were turned off.
  SkinNotifierMode _modeBeforeOff = SkinNotifierMode.always;

  void setSkinNotifierMode(SkinNotifierMode mode) {
    _scripts()?.setConfigAttribute(mode.option, "1");
    _changed();
  }

  /// A modern skin's notifier option such as `Disable in fullscreen`, or
  /// null when the skin has none.
  String? skinNotifierOption(String name) => _scripts()?.configAttribute(name);

  void setSkinNotifierOption(String name, String value) {
    _scripts()?.setConfigAttribute(name, value);
    _changed();
  }

  static const String _notificationsKey = "amped.notifications_enabled";

  /// Whether the notification comes from the operating system instead of
  /// Amped's own popup (or a modern skin's notifier).
  bool get native => _native;
  bool _native;

  static const String _nativeKey = "amped.native_notifications";

  /// Where Amped's own notification appears on the screen.
  NotificationPosition get position => _position;
  NotificationPosition _position;

  static const String _positionKey = "amped.notification_position";

  void setPosition(NotificationPosition position) {
    if (position == _position) return;
    _position = position;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_positionKey, position.name),
      ),
    );
    _placeNotifier();
    _changed();
  }

  void toggleNative() {
    setNative(enabled: !_native);
  }

  void setNative({required bool enabled}) {
    if (enabled == _native) return;
    _native = enabled;
    if (enabled) unawaited(_nativeNotifier.requestPermission());
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_nativeKey, _native),
      ),
    );
    hide();
    _playerChanged();
    _changed();
  }

  Future<void> _postNative(PlaylistEntry entry) async {
    final playlist = player.playlist;
    final text = NotificationText.of(
      entry,
      playlist.current,
      playlist.length,
      tags: _sourceTags(entry.location),
    );
    final artwork = entry.isUrl && !entry.isSource
        ? null
        : await _readCover(entry.location);
    await _nativeNotifier.show(
      title: text.title,
      body: [?text.artist, ?text.album].join("\n"),
      artwork: artwork,
    );
  }

  /// How long the skin-independent notification stays up.
  static const _notificationDuration = Duration(seconds: 5);
  Timer? _notificationTimer;
  bool _notificationShown = false;

  /// Whether the popup is out (true while it is up, false while it slides
  /// away before its window hides).
  bool get revealed => _notificationRevealed;
  bool _notificationRevealed = false;

  /// How long the popup takes to slide in and out.
  static const slide = Duration(milliseconds: 250);
  PlaylistEntry? _notifiedEntry;
  bool _wasPlaying = false;

  void toggle() => setEnabled(
    enabled: !_enabled,
  );

  void setEnabled({required bool enabled}) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (skinHasNotifier) {
      // The skin's option is the switch: off is "Never show", on brings
      // back what it was on.
      final mode = skinNotifierMode;
      if (!enabled) {
        if (mode != null && mode != SkinNotifierMode.never) {
          _modeBeforeOff = mode;
        }
        setSkinNotifierMode(SkinNotifierMode.never);
      } else if (mode == SkinNotifierMode.never) {
        setSkinNotifierMode(_modeBeforeOff);
      }
    }
    if (!_enabled) hide();
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_notificationsKey, _enabled),
      ),
    );
    _playerChanged();
    _changed();
  }

  void hide() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _notificationShown = false;
    _notificationRevealed = false;
  }

  /// Shows the notification for the playing item now, whatever the
  /// notification settings say (the classic player's "show notification" command):
  /// the system's notification when those are chosen (the skin's own
  /// notifier is not asked), else the skin's notifier when its scripts
  /// handle `System.onShowNotification`, else Amped's popup.
  void showNow() {
    final entry = player.playlist.currentEntry;
    if (entry == null) return;
    if (_native) {
      unawaited(_postNative(entry));
      return;
    }
    if (!_ownNotifier() && (_scripts()?.showNotification() ?? false)) return;
    _showPopup();
    _playerChanged();
    _changed();
  }

  /// Slides Amped's popup in for a few seconds.
  void _showPopup() {
    _notificationShown = true;
    _notificationRevealed = true;
    _notificationTimer?.cancel();
    _notificationTimer = Timer(_notificationDuration, () {
      // Slide away first, then hide the window.
      _notificationRevealed = false;
      _changed();
      _notificationTimer = Timer(slide, () {
        _notificationShown = false;
        _playerChanged();
      });
    });
  }

  /// Pops the notification up when playback moves to another item.
  void follow() {
    final entry = player.playlist.currentEntry;
    final playing = player.playIcon == 0;
    final changed = entry != null && !identical(entry, _notifiedEntry);
    if (playing && (changed || !_wasPlaying) && entry != null) {
      if (enabled && _native && (changed || _notifiedEntry == null)) {
        unawaited(_postNative(entry));
      } else if (changed || _notifiedEntry == null) {
        _showPopup();
      }
    }
    if (playing) _notifiedEntry = entry;
    _wasPlaying = playing;
  }
}
