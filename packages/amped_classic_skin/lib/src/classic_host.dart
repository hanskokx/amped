import "package:amped_skin/amped_skin.dart";
import "package:amped_vis/amped_vis.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";

import "classic_skin_data.dart";
import "skin_cursors.dart";

/// The windows a classic skin draws.
/// The menus classic windows open; the app builds them.
enum ClassicMenu {
  main,
  options,
  visualization,
  eqPresets,
  playlistContext,
  playlistAdd,
  playlistRemove,
  playlistRemoveMisc,
  playlistSelect,
  playlistMisc,
  playlistFileInfo,
  playlistSort,
  playlistMiscOptions,
  playlistList,
}

/// Keyboard navigation in the playlist editor, provided by its window while
/// it is showing (`ID_PE_SCUP`, `ID_PE_TOP`, `ID_PE_SHOWPLAYING`, ...).
abstract interface class PlaylistNavigator {
  /// Moves the cursor by [delta] rows, selecting it ([extend]: from the
  /// anchor).
  void moveCursor(int delta, {required bool extend});

  /// Moves the cursor to row [index] (clamped).
  void cursorTo(int index, {required bool extend});

  /// Scrolls by [pages] pages.
  void page(int pages);
}

/// A playlist entry as the classic playlist editor shows it.
abstract interface class ClassicPlaylistEntry {
  String get title;
  Duration? get duration;
  int? get channels;

  /// Whether the file can't be reached now, so the row is dimmed.
  bool get unavailable;
}

/// The playlist the classic windows show and edit.
abstract interface class ClassicPlaylist implements Listenable {
  List<ClassicPlaylistEntry> get entries;
  int get length;
  bool get isEmpty;
  int get current;
  ClassicPlaylistEntry? get currentEntry;
  Set<int> get selected;

  /// How many entries were found so far while files or folders are being
  /// added; null when nothing is.
  int? get addingCount;
  void select(Set<int> indices);
  void selectAll();
  void selectNone();
  void invertSelection();
  void removeSelected();
  void crop();
  void clear();
}

/// The player state the classic windows show and control.
abstract interface class ClassicPlayer implements Listenable {
  ClassicPlaylist get playlist;

  bool get playing;
  bool get paused;
  bool get shuffle;
  bool get repeat;
  bool get timeRemaining;
  bool get alwaysOnTop;
  bool get windowShade;
  bool get eqOpen;
  bool get eqShade;
  bool get plOpen;
  bool get plShade;
  double get uiScale;

  /// 0..255.
  int get volume;

  /// -127..127.
  int get balance;

  /// 0..256 of the track.
  int get position;
  int get elapsedSec;
  int get durationSec;
  int get bitrate;
  int get mixrate;
  int get playIcon;

  /// The song title the main window shows.
  String get title;

  /// The EQ in the slider scale (0 top .. 63 bottom).
  int get preamp;
  List<int> get eqBands;
  bool get eqEnabled;
  bool get eqAuto;

  ClassicVisOptions get classicVis;
  void cycleClassicVis();

  /// The visualization's samples, while started.
  void startVisualization();
  void stopVisualization();
  (Float32List, Float32List)? get visualizationSamples;

  void togglePlay();
  void pause();
  void stop();
  void next();
  void prev();
  Future<void> playIndex(int index);
  void setSeek(int value);
  void setVolume(int value);
  void setBalance(int value);
  void setPreamp(int value);
  void setEqBand(int index, int value);
  void setEqEnabled(bool value);
  void setEqAuto(bool value);
  void setUiScale(double value);
  void toggleShuffle();
  void toggleRepeat();
  void toggleTimeRemaining();
  void toggleAlwaysOnTop();
  void toggleWindowShade();
  void toggleEqShade();
  void togglePlShade();
}

/// What the classic windows need from the app: the skin, the player, the
/// windows around them, menus and file dialogs. It notifies when the windows
/// change (open, moved, resized).
abstract interface class ClassicHost implements Listenable {
  /// The loaded classic skin (the base skin under a modern one).
  ClassicSkinData? get skin;

  ClassicPlayer get player;

  /// Text shown in the main window's song title while a control is held.
  ValueNotifier<String?> get songTitleOverride;

  /// The playlist editor's keyboard navigation, while it shows.
  PlaylistNavigator? get playlistNavigator;
  set playlistNavigator(PlaylistNavigator? navigator);

  /// [window]'s unscaled size now, and when not shaded.
  Size baseSize(SkinWindow window);
  Size fullSize(SkinWindow window);

  /// Resizes a resizable window (unscaled size).
  void resize(SkinWindow window, Size size);

  void setOpen(SkinWindow window, bool open);
  void toggle(SkinWindow window);
  bool isWindowVisible(SkinWindow window);

  /// [window]'s top-left corner, and the pointer, in global coordinates.
  Offset windowOrigin(SkinWindow window);
  Offset get cursorPosition;

  /// The global position of [skinPoint] (unscaled) in [window].
  Offset toGlobal(SkinWindow window, Offset skinPoint);

  /// Shows [menu] at the global [position] (the pointer when null).
  void showMenu(ClassicMenu menu, Offset? position);

  Future<void> openFiles();
  Future<void> openFolder();
  Future<void> openUrl();
  Future<void> addFiles();
  Future<void> addFolder();
  Future<void> addUrl();
  Future<void> loadList();
  Future<void> saveList();
  void minimize();
  Future<void> quit();

  /// The main window's close button: hides it or quits, as the platform
  /// expects.
  void closeMainWindow();

  /// A click on the classic visualization (next mode; double: plug-in).
  void clickClassicVis();

  /// A click on the main window's logo (`LIGHTNING_CLICK`): the About
  /// dialog.
  void showAbout();

  /// A double-click on the main window's song title (`main_mouse.cpp`): the
  /// File Info dialog of the current file.
  void showFileInfo();
}

/// Whether the window around a classic window is active, for title bars
/// drawn active or inactive. The app provides it.
class WindowActivity extends InheritedWidget {
  const WindowActivity({required this.active, required super.child, super.key});

  final bool active;

  /// Whether the window around [context] is active (true outside one).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(WindowActivity oldWidget) =>
      oldWidget.active != active;
}

/// Lets a control with a menu of its own keep a right-click from opening
/// the window's main menu. The window chrome checks [take] on release.
abstract final class SkinSecondaryClaim {
  static final Set<int> _claimed = {};

  /// Call from the control's `onPointerDown`.
  static void claim(PointerDownEvent event) => _claimed.add(event.pointer);

  /// Whether [pointer] was claimed (and forgets it).
  static bool take(int pointer) => _claimed.remove(pointer);
}

/// The cursor a classic window shows where no control sets one.
SkinCursor classicWindowCursor(SkinWindow window, {required bool shaded}) =>
    switch (window) {
      SkinWindow.main => shaded ? SkinCursor.wsNormal : SkinCursor.normal,
      SkinWindow.eq => SkinCursor.eqNormal,
      SkinWindow.pl => shaded ? SkinCursor.plWsNormal : SkinCursor.plNormal,
      _ => SkinCursor.normal,
    };
