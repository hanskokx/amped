import "dart:ui" as ui;

import "package:amped_vis/amped_vis.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart" show PointerDownEvent, Size;

import "wasabi_config.dart";
import "wasabi_menu.dart";
import "wasabi_skin_data.dart";

/// An action fired by a skin button (`action="PLAY"`, `action="SWITCH"
/// param="shade"`, ...), with the container whose window it is in.
class WasabiAction {
  const WasabiAction(this.action, this.param, {required this.container});

  /// The upper-cased action name.
  final String action;

  final String? param;

  /// The id of the container the button is in.
  final String container;

  @override
  String toString() => "WasabiAction($action, $param, $container)";
}

/// The playing track's technical info the way the classic player's core puts it
/// (`Core::getSongInfoText`), e.g. "128kbps stereo 44.1kHz", which skin
/// scripts take apart for their kbps and kHz displays; "" when nothing is
/// known. [sampleRate] is in Hz.
String wasabiSongInfoText({
  required int bitrate,
  required int sampleRate,
  required int channels,
}) {
  if (bitrate == 0 && sampleRate == 0) return "";
  final text = StringBuffer("${bitrate}kbps");
  if (channels == 1) {
    text.write(" mono");
  } else if (channels == 2) {
    text.write(" stereo");
  } else if (channels > 2) {
    text.write(" $channels Channels");
  }
  text.write(" ${(sampleRate / 1000).toStringAsFixed(1)}kHz");
  return text.toString();
}

/// What a modern skin's widgets read from and do to the player: the app
/// implements this over its player state. It notifies whenever any value
/// shown by a skin changes.
/// An entry of a script's `PopupMenu`: a command with an `id`, a separator,
/// or a submenu of [children].
class WasabiPopupItem {
  const WasabiPopupItem({
    required this.label,
    this.id = 0,
    this.checked = false,
    this.disabled = false,
    this.children = const [],
  }) : separator = false;

  const WasabiPopupItem.separator()
    : label = "",
      id = 0,
      checked = false,
      disabled = false,
      children = const [],
      separator = true;

  final String label;
  final int id;
  final bool checked;
  final bool disabled;
  final bool separator;
  final List<WasabiPopupItem> children;
}

abstract class WasabiHost implements Listenable {
  /// The current song's title (`core_getTitle`), or the program name.
  String get songTitle;

  /// The current track's title, or the program name: [songTitle] without a
  /// status (such as "Sorting playlist...") shown in its place. Scripts'
  /// `onTitleChange` follows this, so a status is not taken for a new track.
  String get trackTitle;

  /// The current track's bitrate, channels and sample rate as
  /// [wasabiSongInfoText] puts them, or "" when stopped
  /// (`System.getSongInfoText`).
  String get songInfoText;

  /// Whether the playing item is a video (`System.isVideo`).
  bool get videoPlaying;

  /// Whether the video fills the screen (`System.isVideoFullscreen`).
  bool get videoFullscreen;

  /// A field of the playing item's metadata, as skin scripts ask for it
  /// (`System.getPlayItemMetaDataString`): `title`, `artist`, `album`,
  /// `track`, `length` (milliseconds), `streamname`, `streamtype`,
  /// `streamtitle`. "" when the item has none.
  String playItemMetadata(String name);

  /// The usable area of the screen the player is on, in screen pixels
  /// (`System.getViewportLeft`, ...): where pop-ups such as the classic player
  /// Modern's notifier go.
  ui.Rect get viewport;

  /// How many times larger than its layout the window showing container
  /// [container] is drawn (the classic player's double size mode): `Layout.getScale`.
  double layoutScale(String container);

  /// Whether the application is minimized (`System.isMinimized`).
  bool get appMinimized;

  /// Brings the application back to the front, restored if it was
  /// minimized (`System.restoreApplication`, `activateApplication`).
  void activateApplication();

  /// What a video window's status line says about the playing video
  /// (`display="VID_Info"`), or "" when none plays.
  String get videoInfoText;

  /// The current song's length in milliseconds, or -1 when unknown.
  int get lengthMs;

  /// The playing position in milliseconds, or -1 when stopped.
  int get positionMs;

  /// Whether the timer shows the remaining time.
  bool get timeRemaining;

  /// A click on a time display flips elapsed/remaining.
  void toggleTimeRemaining();

  /// Whether a toggling action is on (EQ_TOGGLE, SHUFFLE, REPEAT, ...);
  /// buttons draw their `activeimage` then.
  bool isActive(String action, String? param);

  /// Runs a button's [action].
  void runAction(WasabiAction action);

  /// The value of the config attribute a control is bound to with
  /// `cfgattrib` (the classic player's `Shuffle`, `Repeat`, ..., or a skin's own), as
  /// Wasabi reads it for a toggle button (`guiobject_getCfgInt`); 0 when
  /// it was never set.
  int configValue(WasabiCfgAttrib attribute);

  /// Sets the config attribute a control is bound to, as a toggle button
  /// does when clicked: its `cfgval` when it turns on, 0 when it turns off.
  void setConfigValue(WasabiCfgAttrib attribute, int value);

  /// Opens the menu a skin's `<Menu>` object names (`WA5:File`, ...) below
  /// its anchor. Completes when the menu has closed.
  Future<void> openMenu(WasabiMenuRequest request);

  /// The value of the slider bound to [action] (VOLUME, SEEK, EQ_BAND with
  /// [param] 1..10, EQ_PREAMP, PAN), from 0 (left/bottom) to 1 (right/top),
  /// or null when the slider has nothing to show (SEEK while stopped).
  double? sliderValue(String action, String? param);

  /// Moves the slider bound to [action] to [value] (0..1) while it is
  /// dragged; [done] is set on release (the seeker only seeks then).
  void setSliderValue(
    String action,
    String? param,
    double value, {
    required bool done,
  });

  /// 1 while playing, -1 while paused, 0 when stopped (`System.getStatus`).
  int get playbackStatus;

  /// The current item's file name or URL, or "" (`getPlayItemString`).
  String get playItemLocation;

  /// The current item's cover art, decoded, or null when it has none or it
  /// is still loading (the `AlbumArt` object, gen_ff `AlbumArt.cpp`).
  ui.Image? get albumArt;

  /// Where the pointer is on the screen (`System.getMousePosX`).
  ui.Offset get cursorPosition;

  /// Where the window of container [id] is on the screen, or null when it
  /// has none (`GuiObject.getLeft` of its layout).
  ui.Offset? windowOrigin(String id);

  /// The current item's cover looked up online (a skin's notifier set to an
  /// "Internet" cover, which the classic player showed in a browser), or null.
  ui.Image? get onlineAlbumArt;

  /// Whether [albumArt] is being read (`AlbumArtLayer.isLoading`).
  bool get albumArtLoading;

  /// Reads the current item's cover art again (`AlbumArtLayer.refresh`).
  void refreshAlbumArt();

  /// A right-button press on an `<AlbumArt>`: keeps the window's own
  /// right-click menu from opening for [event].
  void pressAlbumArtMenu(PointerDownEvent event);

  /// The playlist entries that match [query] (Amped Modern's "Search in
  /// Playlist" box), as indices in playlist order.
  List<int> searchPlaylist(String query);

  /// The release of that press: the album art menu (Refresh album art,
  /// Open folder), which the stock skins' `albumart.maki` builds with a
  /// `PopupMenu`.
  void showAlbumArtMenu();

  /// A double-click on an `<AlbumArt>`: shows the current file's folder
  /// (`albumart.maki`'s `navigateUrl(getPath(...))`).
  void openAlbumArtFolder();

  /// Seeks the current item to [ms].
  void seekTo(int ms);

  /// A right press on an object with a `rightclickaction`: [action] runs,
  /// and the window's own menu does not open for that press.
  void pressSecondaryAction(WasabiAction action, PointerDownEvent event);

  /// Pops [items] up at the pointer (a script's `PopupMenu`); [chosen] hears
  /// the `id` of the entry picked, and nothing when the menu is dismissed.
  void showPopup(List<WasabiPopupItem> items, void Function(int id) chosen);

  /// Opens [path] (a file or a URL) in the playlist and plays it
  /// (`System.playFile`), or only adds it ([play] false, `enqueueFile`).
  void openPath(String path, {required bool play});

  /// Shows the file at [path] in the file manager (`ClassicProFile.exploreFile`).
  void revealPath(String path);

  /// Opens the folder at [path] in the file manager
  /// (`ClassicProFile.exploreFolder`).
  void openFolder(String path);

  /// Opens the file at [path] with the program it belongs to
  /// (`ClassicProFile.openFile`). The runtime has already refused programs.
  void openExternal(String path);

  /// A setting a skin script stored with `setPrivateString`/`Int`, or null.
  String? readPrivate(String section, String item);

  /// Stores a skin script's setting so it survives restarts.
  void writePrivate(String section, String item, String value);

  /// Whether the window of container [id] is open.
  bool isContainerVisible(String id);

  /// Opens or closes the window of container [id].
  void setContainerVisible(String id, bool visible);

  /// Whether the window of container [id] is the one in front, with the
  /// keyboard (`Layout.isActive`).
  bool isContainerActive(String id);

  /// The id of the layout container [id] shows, or null.
  String? currentLayout(String id);

  /// Resizes the window of [container], which shows [layout], to [size]
  /// (layout pixels): a drag on a `resize="..."` handle.
  void resizeLayout(String container, WasabiLayout layout, Size size);

  /// The playlist, for skins that show it (`<component param="guid:pl">`).
  int get playlistLength;

  /// Entry [index]'s title as the playlist shows it.
  String playlistTitle(int index);

  /// Entry [index]'s length in milliseconds, or -1 when unknown.
  int playlistItemLengthMs(int index);

  /// The playing entry's index, or -1.
  int get playlistCurrent;

  bool isPlaylistSelected(int index);

  /// Entry [index]'s file name or URL (`PlEdit.getFileName`).
  String playlistLocation(int index);

  /// Entry [index]'s tag [name] (`PlEdit.getMetaData`): title, artist,
  /// album, track, ...; "" when it has none.
  String playlistMetadata(int index, String name);

  /// Removes entry [index] (`PlEdit.removeTrack`).
  void removePlaylistItem(int index);

  /// Empties the playlist (`PlEdit.clear`).
  void clearPlaylist();

  /// Moves entry [from] to position [to] (`PlEdit.moveTo`).
  void movePlaylistItem(int from, int to);

  /// Loads the skin named [name] (`System.switchSkin`).
  void switchSkin(String name);

  /// The window a script treats as the application's (`getCurApp*`), or null.
  ui.Rect? get appRect;

  /// Centers the window of [container] on its screen (`Layout.center`).
  void centerWindow(String container);

  /// Gives the window of [container] the keyboard focus
  /// (`GuiObject.setFocus`).
  void focusWindow(String container);

  /// Selects entry [index]: alone, from the last selected one ([extend]), or
  /// adding/removing it ([toggle]).
  void selectPlaylistItem(
    int index, {
    required bool extend,
    required bool toggle,
  });

  /// Plays entry [index] (a double-click).
  void playPlaylistItem(int index);

  /// A right-button press on the playlist, on entry [index] (null below the
  /// last one): selects it as the classic player does before its menu (keeping a
  /// selection the press is on), and keeps the window's own right-click
  /// menu from opening for [event].
  void pressPlaylistMenu(int? index, PointerDownEvent event);

  /// The release of that press: the playlist's item menu (Play, Remove,
  /// Edit metadata for selection..., View file info...).
  void showPlaylistMenu();

  /// The classic visualization's options.
  ClassicVisOptions get visOptions;

  /// A click on a `<vis>`: the next mode, or for a double-click the
  /// visualization plug-in instead (SAWnd::onLeftButtonDown, and
  /// main_mouse.cpp for the double-click).
  void clickVis();

  /// Whether audio is playing and not paused (the visualization runs).
  bool get visRunning;

  /// Starts and stops delivering [visSamples].
  void startVisualization();
  void stopVisualization();

  /// The latest stereo samples for the visualization, or null.
  (Float32List, Float32List)? get visSamples;
}
