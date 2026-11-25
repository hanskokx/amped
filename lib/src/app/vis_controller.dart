import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:window_dock/window_dock.dart";

import "../vis/vis_host.dart";
import "amped_dialog.dart";
import "dialog_manager.dart";

/// Where the visualization runs: in its skinned window, filling the screen
/// in a dialog of its own, or in a slot of a modern skin's window.
class VisController {
  VisController({
    required this.vis,
    required this.dialogs,
    required this.dock,
    required this._scripts,
    required this._slotsOnly,
    required this.playerChanged,
  });

  final VisHost vis;
  final DialogManager dialogs;
  final DockManager<SkinWindow> dock;
  final WasabiScriptRuntime? Function() _scripts;

  /// Whether the skin has no visualization window of its own, only slots in
  /// its other windows (ClassicPro's VIS tab).
  final bool Function() _slotsOnly;

  /// The player changed in a way that needs the windows brought up to date.
  final void Function() playerChanged;

  /// How many modern skin windows show the visualization in a slot of
  /// their own (a `guid:avs` windowholder outside the vis container).
  int _slots = 0;

  /// Whether the plug-in was started for those slots, and so stops with
  /// the last of them.
  bool _startedForSlot = false;

  /// Whether the visualization's own skinned window is the one showing it. A
  /// skin showing it in another window (Amped Modern's drawer) has it
  /// instead of its own window.
  bool get windowShows =>
      vis.isRunning && !vis.fullscreen && _slots == 0 && !_slotsOnly();

  /// Whether the visualization counts as open: its own window shows, or,
  /// for a skin that has only slots for it, the plug-in runs.
  bool get isOpen => _slotsOnly() ? vis.isRunning : windowShows;

  /// The visualization started, stopped or changed mode.
  ///
  /// Shows a running visualization in its skinned window, or fills the
  /// screen with it in fullscreen mode, and closes both when it stops.
  void changed() {
    // The skinned window follows `isOpen(SkinWindow.vis)`.
    playerChanged();
    final open = dialogs.windows.containsKey(AmpedDialog.vis);
    final wantFullscreen = vis.isRunning && vis.fullscreen;
    if (wantFullscreen && !open) {
      dialogs.open(AmpedDialog.vis);
      final controller = dialogs.windows[AmpedDialog.vis];
      if (controller == null) return;
      final native = NativeWindow.of(controller)
        ..configure()
        ..setFullscreen(true);
      vis.topInset = native.safeAreaTop;
      native.focus();
    } else if (!wantFullscreen && open) {
      final controller = dialogs.windows[AmpedDialog.vis];
      if (controller != null) NativeWindow.of(controller).setFullscreen(false);
      dialogs.close(AmpedDialog.vis);
      if (vis.isRunning) dock.nativeWindowOf(SkinWindow.vis)?.focus();
    }
  }

  /// A skin window put the visualization in its slot (Amped Modern's
  /// drawer, opened for vis): the plug-in runs there, starting if needed,
  /// and its own window closes.
  void attachSlot() {
    _slots++;
    if (_slots == 1 && !vis.isRunning) {
      _startedForSlot = true;
      vis.start();
    }
    changed();
  }

  /// The slot went away (the drawer closed): a plug-in started for it
  /// stops; one the user started goes back to its own window, or stops too
  /// when the skin has none.
  void detachSlot() {
    if (_slots == 0) return;
    _slots--;
    if (_slots == 0 && (_startedForSlot || _slotsOnly())) {
      _startedForSlot = false;
      vis.stop();
    }
    changed();
  }

  /// Starts or stops the visualization, unless the skin's scripts take
  /// that over (`System.onGetCancelComponent`): Amped Modern opens its
  /// drawer for it, where a slot then runs it, unless its Detach
  /// Visualizer option gave it a window of its own.
  void setRunning(bool run) {
    // A plug-in running with nowhere to show asks the skin again.
    final unseen = _slotsOnly() && _slots == 0;
    if (run == vis.isRunning && !(run && unseen)) return;
    final scripts = _scripts();
    if (scripts != null &&
        scripts.cancelsComponent(wasabiVisGuid, goingVisible: run)) {
      return;
    }
    run ? vis.start() : vis.stop();
  }

  /// A skin's scripts show the visualization (`System.showWindow`), as
  /// Amped Modern does when it detaches it from its drawer: it runs on,
  /// and gets its own window once no slot holds it.
  void showComponent() {
    _startedForSlot = false;
    if (vis.isRunning) {
      changed();
    } else {
      vis.start();
    }
  }

  /// A new skin is about to take over: the plug-in it was started for is
  /// the user's now.
  void skinChanging() => _startedForSlot = false;
}
