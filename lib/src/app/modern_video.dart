import "package:amped_wasabi/amped_wasabi.dart";

import "../player/player_state.dart";

/// Where a modern skin shows the video: in the Video window, or in a slot of
/// a window of its own (Amped Modern's drawer) that its scripts took it to.
class ModernVideo {
  ModernVideo({
    required this.player,
    required this._scripts,
    required this._changed,
  });

  final PlayerState player;
  final WasabiScriptRuntime? Function() _scripts;

  /// The player changed in a way that needs the windows brought up to date.
  final void Function() _changed;

  /// How many modern skin windows other than the Video window show the
  /// video in a slot of their own.
  int _slots = 0;

  /// Whether the skin's scripts took the video over when its window was to
  /// open (`System.onGetCancelComponent`), to show it in a slot.
  bool _inSkin = false;

  /// Whether the scripts asked for the Video window while a slot still
  /// had the video: the slot going away then leaves the window open.
  bool _keepWindow = false;

  late bool _wasOpen = player.videoOpen;
  bool _asking = false;

  /// Whether the video shows anywhere: in its window or in a skin's slot.
  bool get shown => player.videoOpen || _slots > 0;

  /// Whether the Video window is the one showing the video.
  bool get windowShows => player.videoOpen && !_inSkin && _slots == 0;

  /// Tells the skin's scripts the Video window is about to open or close,
  /// so they can show the video themselves instead (Amped Modern opens
  /// its drawer for it unless its Detach Video option is on).
  void follow() {
    final open = player.videoOpen;
    if (open == _wasOpen || _asking) return;
    _wasOpen = open;
    final scripts = _scripts();
    if (scripts == null) {
      _inSkin = false;
      return;
    }
    _asking = true;
    try {
      final taken = scripts.cancelsComponent(
        wasabiVideoGuid,
        goingVisible: open,
      );
      _inSkin = open && taken;
    } finally {
      _asking = false;
    }
  }

  /// A skin window put the video in its slot: the Video window closes.
  void attachSlot() {
    _slots++;
    // A new skin's slot took the video over from the old skin's.
    _keepWindow = false;
    _changed();
  }

  /// The slot went away (the drawer closed): the video is no longer shown,
  /// unless the scripts moved it to its window meanwhile. It plays on.
  void detachSlot() {
    if (_slots == 0) return;
    _slots--;
    if (_slots == 0) {
      if (_keepWindow) {
        _keepWindow = false;
      } else {
        _inSkin = false;
        if (player.videoOpen) player.closeVideoWindow(keepPlaying: true);
      }
    }
    _changed();
  }

  /// A skin's scripts show the video (`System.showWindow`), as the classic player
  /// Modern does when it detaches it from its drawer: it gets its window.
  void showComponent() {
    _inSkin = false;
    _keepWindow = _slots > 0;
    if (player.videoOpen) {
      _changed();
    } else {
      player.setVideoOpen(true);
    }
  }

  /// A skin's scripts hide the video's window (`System.hideNamedWindow`)
  /// to show it themselves, as Amped Modern does to reattach it.
  void hideComponent() {
    _inSkin = true;
    _changed();
  }

  /// A new skin is about to take over: the old skin's slots giving the
  /// video up (they detach after the next frame) must not end it.
  void skinChanging() {
    if (_slots > 0) _keepWindow = true;
  }

  /// The new skin is up and shows the video where it wants it.
  void skinChanged() {
    _inSkin = false;
    _wasOpen = false;
  }

  /// The skin's scripts are gone: they no longer hold the video.
  void scriptsStopped() => _inSkin = false;
}
