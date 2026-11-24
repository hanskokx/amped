import "dart:async";
import "dart:math";

import "package:amped_classic_skin/amped_classic_skin.dart"
    show PlaylistNavigator;
import "package:amped_skin/amped_skin.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:window_dock/window_dock.dart";

import "../main_window/presets_window.dart";
import "../player/playlist.dart";
import "amped_dialog.dart";
import "amped_menus.dart";
import "amped_shell.dart";
import "script_keys.dart";

/// The keyboard shortcuts of a skinned window: the original's accelerator
/// tables (`IDR_ACCELERATOR_MAIN`, `_PL`, `_EQ` and `_GLOBAL` in its resource script),
/// plus media keys.
///
/// All windows share one engine and so one keyboard focus; the window the
/// OS activates takes the focus, so keys act on the window you are using.
class AmpedShortcuts extends StatefulWidget {
  const AmpedShortcuts({
    required this.shell,
    required this.window,
    required this.child,
    super.key,
  });

  final AmpedShell shell;
  final SkinWindow window;
  final Widget child;

  @override
  State<AmpedShortcuts> createState() => _AmpedShortcutsState();
}

class _AmpedShortcutsState extends State<AmpedShortcuts> {
  late final FocusNode _focus = FocusNode(
    debugLabel: "AmpedShortcuts(${widget.window.name})",
  );

  /// The mounted windows' shortcut layers.
  static final Set<_AmpedShortcutsState> _all = {};

  /// Before each key press is dispatched, hands the keyboard focus to the
  /// window the OS has activated. The windowing API does not report
  /// activation changes, so this asks at the moment it matters; keyboard
  /// handlers run before shortcut dispatch.
  static bool _syncFocus(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    for (final state in _all) {
      if (state._isActive && !state._focus.hasFocus) {
        state._focus.requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        break;
      }
    }
    return false;
  }

  bool get _isActive =>
      AppWindowController.maybeOf(context)?.isActivated ?? false;

  @override
  void initState() {
    super.initState();
    if (_all.isEmpty) HardwareKeyboard.instance.addHandler(_syncFocus);
    _all.add(this);
  }

  @override
  void dispose() {
    _all.remove(this);
    if (_all.isEmpty) HardwareKeyboard.instance.removeHandler(_syncFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final bindings = _merge([
      _globalKeys(shell),
      _playbackKeys(shell),
      switch (widget.window) {
        SkinWindow.pl => _playlistKeys(shell),
        SkinWindow.eq => _equalizerKeys(shell),
        SkinWindow.video => _videoKeys(shell),
        _ => const <ShortcutActivator, VoidCallback>{},
      },
    ]);
    // Not CallbackShortcuts: it takes a key even when its action does
    // nothing, and a key taken here never reaches the text field below.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) {
          return !_typing() &&
                  ScriptKeys.send(
                    event,
                    widget.window,
                    scripts: shell.wasabiScripts,
                    skin: shell.skin,
                  )
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        for (final entry in bindings.entries) {
          if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
          if (_isTextKey(entry.key) && _typing()) {
            return KeyEventResult.ignored;
          }
          entry.value();
          return KeyEventResult.handled;
        }
        // What no shortcut took goes to the skin's scripts.
        if (!_typing() &&
            ScriptKeys.send(
              event,
              widget.window,
              scripts: shell.wasabiScripts,
              skin: shell.skin,
            )) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Focus(
        focusNode: _focus,
        autofocus: widget.window == SkinWindow.main,
        child: widget.child,
      ),
    );
  }
}

/// Whether the keyboard focus is in a text field.
bool _typing() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null);
}

/// Whether [activator] is a key a text field uses: one with at most Shift.
bool _isTextKey(ShortcutActivator activator) {
  final a = activator as SingleActivator;
  return !a.control && !a.alt && !a.meta;
}

/// Merges key tables, later ones replacing earlier bindings of the same key
/// and modifiers (a window's own keys win over the shared ones).
/// [SingleActivator] has no value equality, so they are compared by hand.
Map<ShortcutActivator, VoidCallback> _merge(
  List<Map<ShortcutActivator, VoidCallback>> tables,
) {
  String id(ShortcutActivator activator) {
    final a = activator as SingleActivator;
    return "${a.trigger.keyId}:${a.control}:${a.shift}:${a.alt}:${a.meta}";
  }

  final merged = <String, MapEntry<ShortcutActivator, VoidCallback>>{};
  for (final table in tables) {
    for (final entry in table.entries) {
      merged[id(entry.key)] = entry;
    }
  }
  return Map.fromEntries(merged.values);
}

SingleActivator _key(
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
  bool alt = false,
}) => SingleActivator(key, control: control, shift: shift, alt: alt);

/// `IDR_ACCELERATOR_GLOBAL`: window toggles and app commands.
Map<ShortcutActivator, VoidCallback> _globalKeys(AmpedShell shell) {
  final player = shell.player;
  return {
    // Jump to file: search the playlist.
    _key(LogicalKeyboardKey.keyJ): shell.showPlaylistSearch,
    _key(LogicalKeyboardKey.keyW, alt: true): () =>
        shell.toggle(SkinWindow.main),
    _key(LogicalKeyboardKey.keyE, alt: true): () => shell.toggle(SkinWindow.pl),
    _key(LogicalKeyboardKey.keyG, alt: true): () => shell.toggle(SkinWindow.eq),
    _key(LogicalKeyboardKey.keyV, alt: true): () =>
        shell.toggle(SkinWindow.video),
    _key(LogicalKeyboardKey.keyL, alt: true): () =>
        shell.toggle(SkinWindow.library),
    // gen_classicart's global accelerator.
    _key(LogicalKeyboardKey.keyA, alt: true): () =>
        shell.toggle(SkinWindow.albumArt),
    _key(LogicalKeyboardKey.keyM, alt: true): shell.minimize,
    _key(LogicalKeyboardKey.keyF, alt: true): shell.showMainMenu,
    _key(LogicalKeyboardKey.keyS, alt: true): () =>
        shell.dialogManager.open(AmpedDialog.preferences),
    _key(LogicalKeyboardKey.keyP, control: true): () =>
        shell.dialogManager.open(AmpedDialog.preferences),
    _key(LogicalKeyboardKey.f1, control: true): () =>
        shell.dialogManager.open(AmpedDialog.about),
    _key(LogicalKeyboardKey.f4, alt: true): () => unawaited(shell.quit()),
    _key(LogicalKeyboardKey.tab, control: true): shell.focusNextWindow,
    _key(LogicalKeyboardKey.keyD, control: true): () =>
        player.setUiScale(player.uiScale == 2 ? 1 : 2),
    _key(LogicalKeyboardKey.keyT, control: true): player.toggleTimeRemaining,
    _key(LogicalKeyboardKey.keyW, control: true): player.toggleWindowShade,
    _key(LogicalKeyboardKey.keyW, control: true, alt: true):
        player.toggleEqShade,
    _key(LogicalKeyboardKey.keyW, control: true, shift: true):
        player.togglePlShade,
    _key(LogicalKeyboardKey.keyA, control: true): player.toggleAlwaysOnTop,
    _key(LogicalKeyboardKey.keyO, control: true): () =>
        unawaited(shell.files.loadList()),
    _key(LogicalKeyboardKey.keyS, control: true): () =>
        unawaited(shell.files.saveList()),
  };
}

/// `IDR_ACCELERATOR_MAIN`: transport, seeking, volume and opening files,
/// shared by every window; plus media keys.
Map<ShortcutActivator, VoidCallback> _playbackKeys(AmpedShell shell) {
  final player = shell.player;
  void openFiles() => unawaited(shell.files.openFiles());
  void openFolder() => unawaited(shell.files.openFolder());
  void openUrl() => unawaited(shell.files.openUrl());
  void back() => player.seekBy(const Duration(seconds: -5));
  void forward() => player.seekBy(const Duration(seconds: 5));
  void louder() => player.volumeBy(4);
  void quieter() => player.volumeBy(-4);
  return {
    _key(LogicalKeyboardKey.keyZ): player.prev,
    _key(LogicalKeyboardKey.keyZ, control: true): player.firstTrack,
    _key(LogicalKeyboardKey.keyZ, shift: true): back,
    _key(LogicalKeyboardKey.keyX): player.togglePlay,
    _key(LogicalKeyboardKey.keyX, shift: true): openFiles,
    _key(LogicalKeyboardKey.keyX, control: true): openUrl,
    _key(LogicalKeyboardKey.keyC): player.pause,
    // Not in the original, but expected today: Space pauses and resumes,
    // or starts playback when stopped.
    _key(LogicalKeyboardKey.space): () =>
        player.playing || player.paused ? player.pause() : player.togglePlay(),
    _key(LogicalKeyboardKey.keyV): player.stop,
    _key(LogicalKeyboardKey.keyV, control: true): player.toggleStopAfterCurrent,
    _key(LogicalKeyboardKey.keyV, shift: true): () =>
        unawaited(player.fadeOutAndStop()),
    _key(LogicalKeyboardKey.keyB): player.next,
    _key(LogicalKeyboardKey.keyB, control: true): player.lastTrack,
    _key(LogicalKeyboardKey.keyB, shift: true): forward,
    _key(LogicalKeyboardKey.keyR): player.toggleRepeat,
    _key(LogicalKeyboardKey.keyS): player.toggleShuffle,
    _key(LogicalKeyboardKey.keyL): openFiles,
    _key(LogicalKeyboardKey.keyL, shift: true): openFolder,
    _key(LogicalKeyboardKey.keyL, control: true): openUrl,
    _key(LogicalKeyboardKey.keyK, control: true, shift: true):
        shell.toggleVisPlugin,
    _key(LogicalKeyboardKey.keyK, control: true): shell.selectVisPlugin,
    _key(LogicalKeyboardKey.keyK, alt: true): shell.configureVisPlugin,
    // EDIT_ID3: the current file's File Info.
    _key(LogicalKeyboardKey.digit3, alt: true):
        shell.requests.showCurrentFileInfo,
    _key(LogicalKeyboardKey.insert): openFolder,
    _key(LogicalKeyboardKey.arrowLeft): back,
    _key(LogicalKeyboardKey.arrowRight): forward,
    _key(LogicalKeyboardKey.arrowUp): louder,
    _key(LogicalKeyboardKey.arrowDown): quieter,
    _key(LogicalKeyboardKey.numpad4): player.prev,
    _key(LogicalKeyboardKey.numpad5): player.togglePlay,
    _key(LogicalKeyboardKey.numpad6): player.next,
    _key(LogicalKeyboardKey.numpad7): back,
    _key(LogicalKeyboardKey.numpad9): forward,
    _key(LogicalKeyboardKey.numpad8): louder,
    _key(LogicalKeyboardKey.numpad2): quieter,
    _key(LogicalKeyboardKey.numpad1): () => player.jumpTracks(-10),
    _key(LogicalKeyboardKey.numpad3): () => player.jumpTracks(10),
    _key(LogicalKeyboardKey.numpad0): openFiles,
    _key(LogicalKeyboardKey.numpad0, control: true): openUrl,
    // Media keys that arrive as key presses (common on Windows and Linux;
    // macOS routes them through the Now Playing session instead).
    _key(LogicalKeyboardKey.mediaPlayPause): () {
      if (player.playing) {
        player.pause();
      } else {
        player.togglePlay();
      }
    },
    _key(LogicalKeyboardKey.mediaPlay): () {
      if (!player.playing) player.togglePlay();
    },
    _key(LogicalKeyboardKey.mediaPause): () {
      if (player.playing) player.pause();
    },
    _key(LogicalKeyboardKey.mediaStop): player.stop,
    _key(LogicalKeyboardKey.mediaTrackNext): player.next,
    _key(LogicalKeyboardKey.mediaTrackPrevious): player.prev,
    _key(LogicalKeyboardKey.mediaFastForward): forward,
    _key(LogicalKeyboardKey.mediaRewind): back,
    _key(LogicalKeyboardKey.audioVolumeUp): louder,
    _key(LogicalKeyboardKey.audioVolumeDown): quieter,
  };
}

/// `IDR_ACCELERATOR_PL`: list navigation and editing (these replace the
/// arrow keys' seek/volume meaning inside the playlist).
Map<ShortcutActivator, VoidCallback> _playlistKeys(AmpedShell shell) {
  final player = shell.player;
  final playlist = player.playlist;
  PlaylistNavigator? nav() => shell.playlistNavigator;
  return {
    _key(LogicalKeyboardKey.arrowUp): () =>
        nav()?.moveCursor(-1, extend: false),
    _key(LogicalKeyboardKey.arrowDown): () =>
        nav()?.moveCursor(1, extend: false),
    _key(LogicalKeyboardKey.arrowUp, shift: true): () =>
        nav()?.moveCursor(-1, extend: true),
    _key(LogicalKeyboardKey.arrowDown, shift: true): () =>
        nav()?.moveCursor(1, extend: true),
    _key(LogicalKeyboardKey.home): () => nav()?.cursorTo(0, extend: false),
    _key(LogicalKeyboardKey.end): () =>
        nav()?.cursorTo(playlist.length - 1, extend: false),
    _key(LogicalKeyboardKey.pageUp): () => nav()?.page(-1),
    _key(LogicalKeyboardKey.pageDown): () => nav()?.page(1),
    _key(LogicalKeyboardKey.arrowUp, alt: true): () =>
        playlist.moveSelection(-1),
    _key(LogicalKeyboardKey.arrowDown, alt: true): () =>
        playlist.moveSelection(1),
    _key(LogicalKeyboardKey.enter): () {
      final selected = playlist.selected;
      if (selected.isNotEmpty) {
        unawaited(player.playIndex(selected.reduce(min)));
      }
    },
    _key(LogicalKeyboardKey.delete): playlist.removeSelected,
    _key(LogicalKeyboardKey.backspace): playlist.removeSelected,
    _key(LogicalKeyboardKey.delete, control: true): playlist.crop,
    _key(LogicalKeyboardKey.delete, control: true, shift: true): playlist.clear,
    _key(LogicalKeyboardKey.delete, alt: true): playlist.removeDeadFiles,
    _key(LogicalKeyboardKey.keyL): () => unawaited(shell.files.addFiles()),
    _key(LogicalKeyboardKey.keyL, shift: true): () =>
        unawaited(shell.files.addFolder()),
    _key(LogicalKeyboardKey.keyL, control: true): () =>
        unawaited(shell.files.addUrl()),
    _key(LogicalKeyboardKey.insert): () => unawaited(shell.files.addFolder()),
    _key(LogicalKeyboardKey.insert, control: true): () =>
        unawaited(shell.files.addFiles()),
    _key(LogicalKeyboardKey.insert, shift: true): () =>
        unawaited(shell.files.addUrl()),
    _key(LogicalKeyboardKey.keyA, control: true): playlist.selectAll,
    _key(LogicalKeyboardKey.keyA, control: true, alt: true):
        player.toggleAlwaysOnTop,
    _key(LogicalKeyboardKey.keyI, control: true): playlist.invertSelection,
    _key(LogicalKeyboardKey.keyN, control: true): playlist.clear,
    _key(LogicalKeyboardKey.keyR, control: true): playlist.reverse,
    _key(LogicalKeyboardKey.keyR, control: true, shift: true):
        playlist.randomize,
    _key(LogicalKeyboardKey.digit1, control: true, shift: true): () =>
        unawaited(playlist.sort(PlaylistSort.title)),
    _key(LogicalKeyboardKey.digit2, control: true, shift: true): () =>
        unawaited(playlist.sort(PlaylistSort.fileName)),
    _key(LogicalKeyboardKey.digit3, control: true, shift: true): () =>
        unawaited(playlist.sort(PlaylistSort.path)),
    _key(LogicalKeyboardKey.keyE, control: true, alt: true): () =>
        unawaited(playlist.rebuildSelectedTitles()),
    _key(LogicalKeyboardKey.keyF, control: true): shell.files.exploreSelection,
    // ID_PE_EDIT_SEL: the selection's tags together.
    _key(LogicalKeyboardKey.keyE, shift: true): shell.requests.showEditMetadata,
    // ID_PE_ID3: each selected entry's File Info in turn.
    _key(LogicalKeyboardKey.digit3, alt: true):
        shell.requests.showSelectedFileInfo,
    _key(LogicalKeyboardKey.f4, control: true): () =>
        shell.setOpen(SkinWindow.pl, false),
  };
}

/// The Video window's own keys: X stops the video there (elsewhere it plays,
/// from the start, as in the original).
Map<ShortcutActivator, VoidCallback> _videoKeys(AmpedShell shell) => {
  _key(LogicalKeyboardKey.keyX): shell.player.stop,
};

/// `IDR_ACCELERATOR_EQ`: 1–0 raise bands, Q–P lower them (2 steps each),
/// ` and Tab move the preamp, N/A toggle EQ and auto, S opens the presets
/// menu, Left/Right pan.
Map<ShortcutActivator, VoidCallback> _equalizerKeys(AmpedShell shell) {
  final player = shell.player;
  const raise = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
    LogicalKeyboardKey.digit0,
  ];
  const lower = [
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyT,
    LogicalKeyboardKey.keyY,
    LogicalKeyboardKey.keyU,
    LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyP,
  ];
  // Band values run 0 (top, +12 dB) to 63 (bottom), so raising subtracts.
  void band(int index, int delta) =>
      player.setEqBand(index, player.eqBands[index] - delta);
  return {
    for (var i = 0; i < 10; i++) _key(raise[i]): () => band(i, 2),
    for (var i = 0; i < 10; i++) _key(lower[i]): () => band(i, -2),
    _key(LogicalKeyboardKey.backquote): () =>
        player.setPreamp(player.preamp - 2),
    _key(LogicalKeyboardKey.tab): () => player.setPreamp(player.preamp + 2),
    _key(LogicalKeyboardKey.keyN): () => player.setEqEnabled(!player.eqEnabled),
    _key(LogicalKeyboardKey.keyA): () => player.setEqAuto(!player.eqAuto),
    _key(LogicalKeyboardKey.keyS): () => shell.showMenu(
      AmpedMenus.eqPresets(shell),
      shell.toGlobal(SkinWindow.eq, const Offset(217, 30)),
    ),
    _key(LogicalKeyboardKey.keyS, control: true, alt: true): () =>
        shell.openPresets(PresetsMode.load),
    _key(LogicalKeyboardKey.arrowLeft): () =>
        player.setBalance(player.balance - 4),
    _key(LogicalKeyboardKey.arrowRight): () =>
        player.setBalance(player.balance + 4),
    _key(LogicalKeyboardKey.f4, control: true): () =>
        shell.setOpen(SkinWindow.eq, false),
  };
}
