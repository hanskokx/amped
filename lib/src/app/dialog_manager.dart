import "dart:async";
import "dart:math";
import "dart:ui";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/rendering.dart" show BoxConstraints;
import "package:shared_preferences/shared_preferences.dart";
import "package:window_dock/window_dock.dart";

import "../player/player_state.dart";
import "amped_dialog.dart";
import "file_actions.dart";

/// The app's dialog windows: opening them, where they were left, and the
/// drags of the frameless ones.
class DialogManager {
  DialogManager({
    required this.player,
    required this.localizations,
    required this._files,
    required this._dock,
    required this._changed,
    required this.visFullscreen,
    required this._closedByUser,
    required this._removed,
  });

  final PlayerState player;
  final AppLocalizations localizations;
  final FileActions _files;
  final DockManager<SkinWindow> _dock;
  final void Function() _changed;

  /// Whether the visualization is running fullscreen (its frame is not
  /// remembered then).
  final bool Function() visFullscreen;

  /// A dialog's window went away; `current` says whether it was the one the
  /// app had (not an older one closed and opened again since).
  final void Function(AmpedDialog dialog, {required bool current})
  _closedByUser;

  /// A dialog was taken out of [windows] after its window went away.
  final void Function(AmpedDialog dialog) _removed;

  /// The open dialog windows.
  final Map<AmpedDialog, AppWindowController> windows = {};

  /// Takes the frames dialogs were left at from the saved [prefs].
  void restore(SharedPreferences prefs) {
    for (final dialog in AmpedDialog.values) {
      final saved = prefs.getStringList("amped.dialog_${dialog.name}");
      final values = saved?.map(double.tryParse).toList();
      if (values == null || values.length != 4 || values.contains(null)) {
        continue;
      }
      _frames[dialog] = Rect.fromLTWH(
        values[0]!,
        values[1]!,
        values[2]!,
        values[3]!,
      );
    }
  }

  /// Remembers where every open dialog is.
  Future<void> rememberAll() async {
    for (final dialog in windows.keys.toList()) {
      await remember(dialog);
    }
  }

  /// A dialog's window has been destroyed.
  void destroyed(AmpedDialog dialog, AppWindowController? controller) {
    final current = identical(windows[dialog], controller);
    _closedByUser(dialog, current: current);
    // Destruction is reported later; a dialog closed and opened again since
    // is another window, which must be left alone.
    if (!current) return;
    final wasOpen = windows.remove(dialog) != null;
    _removed(dialog);
    if (wasOpen) _changed();
  }

  /// The dialogs' last frames (position and size), restored when they
  /// open again.
  final Map<AmpedDialog, Rect> _frames = {};
  final Map<AmpedDialog, Timer> _saveTimers = {};

  /// Remembers where [dialog] is and how big, unless it fills the screen.
  Future<void> remember(AmpedDialog dialog) async {
    _saveTimers.remove(dialog)?.cancel();
    final controller = windows[dialog];
    if (controller == null) return;
    if (dialog == AmpedDialog.vis && visFullscreen()) {
      return;
    }
    if (dialog == AmpedDialog.video) return;
    final frame = NativeWindow.of(controller).frame;
    if (frame.isEmpty) return;
    _frames[dialog] = frame;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("amped.dialog_${dialog.name}", [
      "${frame.left}",
      "${frame.top}",
      "${frame.width}",
      "${frame.height}",
    ]);
  }

  /// Whether enough of [rect] is on a screen to grab it.
  static bool _onScreen(Rect rect) => NativeScreen.workAreas().any((area) {
    final overlap = area.intersect(rect);
    return overlap.width >= 16 && overlap.height >= 8;
  });

  /// The smallest a skinned dialog can be, in skin pixels.
  static const Size minSize = Size(275, 190);

  final Map<AmpedDialog, Size> _skinnedSizes = {};

  /// The shape (width over height) a skinned dialog keeps its picture in,
  /// for those that show one.
  final Map<AmpedDialog, double> _aspects = {};

  /// What the frame takes from a skinned dialog's size, in skin pixels: the
  /// borders and title bar around the content.
  static const Size frameInset = Size(19, 34);

  /// The least a dialog that keeps a shape can be.
  static const Size _leastShaped = Size(140, 90);

  /// The size of a skinned dialog whose content is [aspect] wide for each
  /// unit of height and at least [width] wide (a content is never so small
  /// that it can't be seen).
  static Size shapedSize(double aspect, double width) {
    var w = max(_leastShaped.width, width);
    var h = (w - frameInset.width) / aspect + frameInset.height;
    if (h < _leastShaped.height) {
      h = _leastShaped.height;
      w = (h - frameInset.height) * aspect + frameInset.width;
    }
    return Size(w.roundToDouble(), h.roundToDouble());
  }

  /// [title] cut (with "...") to what the title bar of a skinned dialog
  /// [width] skin pixels wide has room for: the frame keeps 100 pixels for
  /// its corners and lines, and a character of its font is about 6 wide.
  static String fitTitle(String title, double width) {
    final room = ((width - 100) / 6).floor().clamp(6, 60);
    if (title.length <= room) return title;
    return "${title.substring(0, room - 3).trimRight()}...";
  }

  /// Makes the dialog's content [aspect] (width over height) from now on and
  /// resizes it to that: as large as fits in what it is now.
  void keepShape(AmpedDialog dialog, double aspect) {
    if (!aspect.isFinite || aspect <= 0) return;
    _aspects[dialog] = aspect;
    final now = sizeOf(dialog);
    final box = Size(
      now.width - frameInset.width,
      now.height - frameInset.height,
    );
    // The widest picture of that shape that fits the box.
    final width = min(box.width, box.height * aspect) + frameInset.width;
    final size = shapedSize(aspect, width);
    _skinnedSizes[dialog] = size;
    final controller = windows[dialog];
    if (controller != null) {
      final native = NativeWindow.of(controller);
      native.setFrame(native.frame.topLeft & (size * player.uiScale));
    }
    _changed();
  }

  /// A skinned dialog's size in skin pixels (it is drawn at the skin's size,
  /// then scaled to the UI scale).
  Size sizeOf(AmpedDialog dialog) =>
      _skinnedSizes[dialog] ??
      (dialog == AmpedDialog.artwork ? dialog.size : minSize);

  void open(AmpedDialog dialog) {
    final existing = windows[dialog];
    if (existing != null) {
      existing.activate();
      _changed();
      return;
    }
    final delegate = _DialogDelegate(this, dialog);
    final controller = AppWindowController(
      // Skinned dialogs are drawn at the skin's pixel size, like the skinned
      // windows.
      size: dialog.skinned ? sizeOf(dialog) * player.uiScale : dialog.size,
      constraints: dialog.minSize == null
          ? null
          : BoxConstraints(
              minWidth: dialog.minSize!.width,
              minHeight: dialog.minSize!.height,
            ),
      title: switch (dialog) {
        AmpedDialog.presets => localizations.ampedPresetsTitle,
        AmpedDialog.searchPlaylist => localizations.jumpToFileTitle,
        AmpedDialog.preferences => localizations.ampedPreferencesTitle,
        AmpedDialog.about => localizations.aboutAmpedTitle,
        AmpedDialog.vis => localizations.ampedVisualizationWindow,
        AmpedDialog.video => localizations.ampedVideoWindow,
        AmpedDialog.visConfig => localizations.configureVisualizationTitle,
        AmpedDialog.fileInfo => localizations.fileInfoTitle,
        AmpedDialog.editMetadata => localizations.editMetadataTitle,
        AmpedDialog.remoteLogin => localizations.remoteLoginTitle,
        AmpedDialog.resume => localizations.resumeTitle,
        AmpedDialog.update => localizations.updateTitle,
        AmpedDialog.artwork => localizations.artworkTitle,
      },
      delegate: delegate,
    );
    delegate.controller = controller;
    windows[dialog] = controller;
    final native = NativeWindow.of(controller);
    // A skinned dialog is drawn in the skin, frame and all.
    if (dialog.skinned) {
      native.configure(transparent: true);
    }
    native.setAlwaysOnTop(player.alwaysOnTop);
    // Flutter's window constraints aren't enforced on every platform.
    if (dialog.minSize case final least?) native.setMinSize(least);
    _files.acceptDrops(controller, playDropped: false);
    var saved = _frames[dialog];
    if (saved != null && dialog.skinned) {
      // The size it was left at, in skin pixels, and not below the least.
      final scale = player.uiScale;
      final size = Size(
        max(minSize.width, (saved.width / scale).roundToDouble()),
        max(
          minSize.height,
          (saved.height / scale).roundToDouble(),
        ),
      );
      _skinnedSizes[dialog] = size;
      saved = saved.topLeft & (size * scale);
    }
    final least = dialog.minSize;
    if (saved != null && least != null && !dialog.skinned) {
      // Remembered from before the least size was enforced.
      saved =
          saved.topLeft &
          Size(
            max(saved.width, least.width),
            max(saved.height, least.height),
          );
    }
    if (saved != null && _onScreen(saved)) {
      native.setFrame(saved);
    } else {
      final anchor =
          _dock.rectOf(SkinWindow.eq) ?? _dock.rectOf(SkinWindow.main);
      if (anchor != null) native.setPosition(anchor.topRight);
    }
    // Resizes notify the controller; moves are caught when it closes.
    controller.addListener(() {
      _saveTimers[dialog]?.cancel();
      _saveTimers[dialog] = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(remember(dialog)),
      );
    });
    _changed();
  }

  Offset? _dragGrab;
  Offset? _resizeGrab;

  /// A drag on a frameless dialog's title bar: starts holding the window by
  /// where the pointer is on it.
  void startDrag(AmpedDialog dialog) {
    final controller = windows[dialog];
    if (controller == null) return;
    _dragGrab =
        NativeScreen.cursorPosition() -
        NativeWindow.of(controller).frame.topLeft;
  }

  /// The pointer moved in that drag: the window follows.
  void updateDrag(AmpedDialog dialog) {
    final controller = windows[dialog];
    final grab = _dragGrab;
    if (controller == null || grab == null) return;
    NativeWindow.of(controller).setPosition(
      NativeScreen.cursorPosition() - grab,
    );
  }

  /// A drag on a skinned dialog's resize grip: starts holding its
  /// bottom-right corner by where the pointer is.
  void startResize(AmpedDialog dialog) {
    final controller = windows[dialog];
    if (controller == null) return;
    _resizeGrab =
        NativeWindow.of(controller).frame.bottomRight -
        NativeScreen.cursorPosition();
  }

  /// The pointer moved in that drag: the window's corner follows, in whole
  /// skin pixels.
  void updateResize(AmpedDialog dialog) {
    final controller = windows[dialog];
    final grab = _resizeGrab;
    if (controller == null || grab == null) return;
    final native = NativeWindow.of(controller);
    final frame = native.frame;
    final scale = player.uiScale;
    final corner = NativeScreen.cursorPosition() + grab - frame.topLeft;
    final aspect = _aspects[dialog];
    final Size size;
    if (aspect == null) {
      size = Size(
        max(minSize.width, (corner.dx / scale).roundToDouble()),
        max(minSize.height, (corner.dy / scale).roundToDouble()),
      );
    } else {
      // The shape is kept: the window is as large as the pointer asks for
      // either way, the other side following.
      final byWidth = corner.dx / scale;
      final byHeight =
          (corner.dy / scale - frameInset.height) * aspect + frameInset.width;
      size = shapedSize(aspect, max(byWidth, byHeight));
    }
    _skinnedSizes[dialog] = size;
    native.setFrame(frame.topLeft & (size * scale));
    _changed();
  }

  void close(AmpedDialog dialog) {
    _aspects.remove(dialog);
    unawaited(remember(dialog));
    windows.remove(dialog)?.destroy();
    _changed();
  }
}

class _DialogDelegate with AppWindowDelegate {
  _DialogDelegate(this.shell, this.dialog);

  final DialogManager shell;
  final AmpedDialog dialog;

  /// The window this delegate belongs to.
  AppWindowController? controller;

  @override
  void onWindowCloseRequested(AppWindowController controller) {
    unawaited(shell.remember(dialog));
    super.onWindowCloseRequested(controller);
  }

  @override
  void onWindowDestroyed() {
    super.onWindowDestroyed();
    shell.destroyed(dialog, controller);
  }
}
