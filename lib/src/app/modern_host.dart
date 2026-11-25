import "dart:async";
import "dart:io" show File;
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart"
    show ClassicMenu, SkinSecondaryClaim;
import "package:amped_logging/amped_logging.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_vis/amped_vis.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart" show HardwareKeyboard;
import "package:flutter/widgets.dart" show PointerDownEvent, Size;
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";
import "package:window_dock/window_dock.dart";

import "../library/library_view.dart" show LibraryView;
import "../player/player_state.dart";
import "../player/playlist.dart";
import "../player/playlist_search.dart";
import "../skin/skin_views.dart";
import "../vis/vis_host.dart";
import "amped_dialog.dart";
import "amped_menus.dart";
import "amped_shell.dart";

/// The values of the classic player config attributes skin controls are bound to
/// with `cfgattrib`. `Shuffle`, `Repeat` and `Enable crossfading` are the
/// player's; a skin's own options are only remembered, through [read] and
/// [write], so their controls keep their state.
class WasabiConfigValues extends ChangeNotifier {
  WasabiConfigValues(this.player, {required this.read, required this.write});

  final PlayerState player;
  final String? Function(String key) read;
  final void Function(String key, String value) write;

  /// The value Wasabi reads for [attribute] (`getValueAsInt`).
  int value(WasabiCfgAttrib attribute) => switch (attribute.setting) {
    AmpedSetting.shuffle => player.shuffle ? 1 : 0,
    AmpedSetting.repeat => player.repeatValue,
    AmpedSetting.crossfade => player.crossfade ? 1 : 0,
    AmpedSetting.alwaysOnTop => player.alwaysOnTop ? 1 : 0,
    AmpedSetting.tooltips => int.tryParse(read(attribute.key) ?? "") ?? 1,
    null => int.tryParse(read(attribute.key) ?? "") ?? 0,
  };

  /// Sets [attribute] to [value]; any value but 0 turns Shuffle or
  /// crossfading on, and Repeat takes 0 (off), above 0 (the playlist) or
  /// below 0 (the track; Wa2PlEditCfgItems::onSetShuffle, onSetRepeat).
  void setValue(WasabiCfgAttrib attribute, int value) {
    switch (attribute.setting) {
      case AmpedSetting.shuffle:
        if ((value != 0) != player.shuffle) player.toggleShuffle();
      case AmpedSetting.repeat:
        player.repeatValue = value;
      case AmpedSetting.crossfade:
        player.setCrossfade(value != 0);
      case AmpedSetting.alwaysOnTop:
        player.setAlwaysOnTop(value != 0);
      case AmpedSetting.tooltips:
        write(attribute.key, "$value");
        notifyListeners();
      case null:
        write(attribute.key, "$value");
        notifyListeners();
    }
  }
}

/// Connects a modern skin's buttons, sliders and displays to the player and
/// the windows, the way Wasabi's built-in actions drive the classic player core.
class ShellWasabiHost implements WasabiHost {
  ShellWasabiHost(this.shell);

  final AmpedShell shell;

  /// Where skin scripts keep their settings; loaded before scripts start.
  SharedPreferences? prefs;

  /// Settings written before [prefs] was loaded, or when it is missing.
  final Map<String, String> _private = {};

  /// The config attributes skin controls are bound to.
  late final WasabiConfigValues config = WasabiConfigValues(
    shell.player,
    read: (key) => readPrivate(_cfgSection, key),
    write: (key, value) => writePrivate(_cfgSection, key, value),
  );

  static const String _cfgSection = "cfgattrib";

  late final Listenable _changes = Listenable.merge([
    shell,
    shell.player,
    shell.player.playlist,
    shell.songTitleOverride,
    shell.albumArt,
    shell.onlineArt,
    config,
    NativeScreen.activationChanges,
  ]);

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  @override
  String get songTitle => shell.songTitleOverride.value ?? trackTitle;

  @override
  String get trackTitle =>
      shell.player.playlist.currentEntry?.playingTitle ?? "Amped";

  @override
  String get songInfoText {
    final entry = shell.player.playlist.currentEntry;
    if (entry == null || playbackStatus == 0) return "";
    return wasabiSongInfoText(
      bitrate: entry.bitrate ?? 0,
      sampleRate: entry.sampleRate ?? 0,
      channels: entry.channels ?? 0,
    );
  }

  @override
  bool get videoPlaying => shell.player.videoPlaying;

  @override
  bool get videoFullscreen => shell.videoFullscreen;

  @override
  bool get appMinimized => shell.isMinimized;

  @override
  void activateApplication() => shell.activateApplication();

  @override
  double layoutScale(String container) {
    final window = shell.skin.modern?.windowForContainer(
      container.toLowerCase(),
    );
    return window == null ? 1 : shell.windowState.scaleOf(window);
  }

  @override
  ui.Rect get viewport {
    final areas = NativeScreen.workAreas();
    final main = shell.dock.rectOf(SkinWindow.main);
    final area = main == null ? null : DockGeometry.workAreaFor(main, areas);
    return area ??
        (areas.isEmpty
            ? const ui.Rect.fromLTWH(0, 0, 1920, 1080)
            : areas.first);
  }

  @override
  String playItemMetadata(String name) {
    final playlist = shell.player.playlist;
    // The current song, once it was picked or plays; a playlist that only
    // defaulted to its first entry has none while stopped.
    if (playbackStatus == 0 && !playlist.hasChosenCurrent) return "";
    return _metadata(playlist.currentEntry, name);
  }

  String _metadata(PlaylistEntry? entry, String name) {
    if (entry == null) return "";
    // What the tag cache knows of the file, for what the entry does not
    // carry.
    final tags = entry.isUrl ? null : shell.sources.tagsOf(entry.location);
    final bitrate = entry.bitrate ?? tags?.bitrate;
    final sampleRate = entry.sampleRate ?? tags?.sampleRate;
    final channels = entry.channels ?? tags?.channels;
    final genres = entry.genres.isNotEmpty ? entry.genres : tags?.genres ?? [];
    return switch (name.toLowerCase()) {
      "title" => entry.trackTitle ?? tags?.title ?? entry.title,
      "artist" => entry.artist ?? tags?.artist ?? "",
      "album" => entry.album ?? tags?.album ?? "",
      "track" =>
        (entry.trackNumber ?? tags?.trackNumber) == null
            ? ""
            : "${entry.trackNumber ?? tags?.trackNumber}",
      "length" =>
        entry == shell.player.playlist.currentEntry
            ? "${shell.player.durationSec * 1000}"
            : "${entry.duration?.inMilliseconds ?? 0}",
      // A station: its name and the title it sends (`streamtype` 2 is
      // SHOUTcast).
      "streamname" => entry.isUrl ? entry.title : "",
      "streamtype" => entry.isUrl ? "2" : "",
      "streamtitle" => entry.streamTitle ?? "",
      // What the file is (Lithium's song memory keeps `filename` to play it
      // again).
      "filename" => entry.location,
      "filesize" => _fileSize(entry),
      "genre" => genres.join(", "),
      "year" => "${tags?.year ?? ""}",
      "disc" =>
        (entry.discNumber ?? tags?.discNumber) == null
            ? ""
            : "${entry.discNumber ?? tags?.discNumber}",
      "bitrate" => bitrate == null ? "" : "$bitrate",
      "srate" => sampleRate == null ? "" : "$sampleRate",
      "stereo" => channels == null ? "" : (channels > 1 ? "1" : "0"),
      _ => "",
    };
  }

  /// The size in bytes of the file [entry] plays, or "" for a station or a
  /// file that cannot be read.
  static String _fileSize(PlaylistEntry entry) {
    if (entry.isUrl) return "";
    try {
      return "${File(entry.location).lengthSync()}";
    } on Object {
      return "";
    }
  }

  @override
  String get videoInfoText {
    final video = shell.player.video;
    final size = video?.videoSize;
    if (video == null || !video.active || size == null) return "";
    return "${size.width.round()}x${size.height.round()}";
  }

  @override
  int get lengthMs {
    final seconds = shell.player.durationSec;
    return seconds > 0 ? seconds * 1000 : -1;
  }

  @override
  int get positionMs {
    final player = shell.player;
    return player.playing || player.paused ? player.elapsedSec * 1000 : -1;
  }

  @override
  bool get timeRemaining => shell.player.timeRemaining;

  @override
  void toggleTimeRemaining() => shell.player.toggleTimeRemaining();

  /// The window a `toggle` action's `param` names (`guid:pl`, ...), or the
  /// skin's own window of that container id.
  SkinWindow? _windowNamed(String? param) =>
      _playerWindowNamed(param) ??
      (param == null || param.isEmpty
          ? null
          : shell.skin.modern?.windowForContainer(param));

  static SkinWindow? _playerWindowNamed(String? param) =>
      _windowOfGuid(param) ??
      switch (param?.toLowerCase()) {
        "guid:pl" || "guid:playlist" || "pl" || "playlist" => SkinWindow.pl,
        "guid:eq" || "eq" || "equalizer" => SkinWindow.eq,
        "guid:ml" || "guid:library" || "ml" || "library" => SkinWindow.library,
        "guid:video" || "video" => SkinWindow.video,
        "guid:main" || "main" => SkinWindow.main,
        // The Thinger's Visualizations button (`VisBucketItem`).
        "guid:vis" || "vis" => SkinWindow.vis,
        "thinger" => SkinWindow.thinger,
        _ => null,
      };

  /// The window of a component named by its GUID (`{F0816D7B-...}`, which
  /// Lithium's V button uses for the video), or null.
  static SkinWindow? _windowOfGuid(String? param) {
    final text = (param ?? "").toLowerCase();
    if (text.contains("45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d")) {
      return SkinWindow.pl;
    }
    if (text.contains("6b0edf80-c9a5-11d3-9f26-00c04f39ffc6")) {
      return SkinWindow.library;
    }
    if (text.contains("f0816d7b-fffc-4343-80f2-e8199aa15cc3")) {
      return SkinWindow.video;
    }
    if (text.contains("0000000a-000c-0010-ff7b-01014263450c")) {
      return SkinWindow.vis;
    }
    return null;
  }

  /// The popup menu a Wasabi 5 playlist button's action opens: the same
  /// menus as the classic playlist's ADD, REM, SEL, MISC and LIST buttons
  /// (gen_ff `menuactions.cpp`, `WA2_PLEDITPOPUP_*`).
  static ClassicMenu? playlistMenuFor(String action) => switch (action) {
    "PE_ADD" => ClassicMenu.playlistAdd,
    "PE_REM" => ClassicMenu.playlistRemove,
    "PE_SEL" => ClassicMenu.playlistSelect,
    "PE_MISC" => ClassicMenu.playlistMisc,
    "PE_LIST" => ClassicMenu.playlistList,
    _ => null,
  };

  @override
  bool isActive(String action, String? param) {
    final player = shell.player;
    return switch (action) {
      "EQ_TOGGLE" => player.eqEnabled,
      "EQ_AUTO" => player.eqAuto,
      "SHUFFLE" || "TOGGLE_SHUFFLE" => player.shuffle,
      "REPEAT" || "TOGGLE_REPEAT" => player.repeat,
      "VIS_RANDOM" => shell.vis.random,
      "TOGGLE" => switch (_windowNamed(param)) {
        final window? => shell.isOpen(window),
        null => false,
      },
      "PL" => shell.isOpen(SkinWindow.pl),
      "EQ" => shell.isOpen(SkinWindow.eq),
      _ => false,
    };
  }

  @override
  void runAction(WasabiAction action) {
    final player = shell.player;
    final window = shell.skin.modern?.windowForContainer(action.container);
    switch (action.action) {
      case "PREV":
        player.prev();
      case "PLAY":
        player.togglePlay();
      case "PAUSE":
        player.pause();
      case "STOP":
        player.stop();
      case "NEXT":
        player.next();
      case "EJECT":
        unawaited(shell.files.openFiles());
      case "SWITCH":
        // The notifier has whichever layout its script showed.
        if (window == SkinWindow.notifier) {
          shell.skin.modern?.notifierLayout = action.param;
          return;
        }
        if (window == null) return;
        // A layout of the container by that name, whatever it is called.
        if (shell.switchModernLayout(window, action.param)) return;
        // Else switching to a `shade` layout is windowshade mode.
        final shade = action.param?.toLowerCase().contains("shade") ?? false;
        if (shade != shell.isShaded(window)) shell.toggleShade(window);
      case "MINIMIZE":
        shell.minimize();
      case "EXIT":
        unawaited(shell.quit());
      case "CLOSE":
        if (window == null || window == SkinWindow.main) {
          shell.closeMainWindow();
        } else {
          shell.setOpen(window, false);
        }
      case "TOGGLE":
        // A skin's own windows (Anexa's `colour_window`, its colour themes,
        // alarm and about tabs) are not shown here, so toggling one does
        // nothing.
        // The Preferences "component" (ASNW's gear button names it by GUID).
        if ((action.param ?? "").toLowerCase().contains(
          "b397a4ce-455a-4d62-8bf6-d0f91acb70e6",
        )) {
          shell.dialogManager.open(AmpedDialog.preferences);
          return;
        }
        // The lightning bolt (Amped Modern's bottom right logo): the same as a
        // click on the classic main window's logo.
        if ((action.param ?? "").toLowerCase().contains(
          "d6201408-476a-4308-bf1b-7baca1124b12",
        )) {
          shell.classic.showAbout();
          return;
        }
        final target = _windowNamed(action.param);
        if (target != null) shell.toggle(target);
      case "PL":
        shell.toggle(SkinWindow.pl);
      case "EQ":
        shell.toggle(SkinWindow.eq);
      case "CONTROLMENU" || "SYSMENU":
        shell.showMainMenu();
      case "MENU":
        if (action.param?.toLowerCase() == "presets") {
          shell.showMenu(AmpedMenus.eqPresets(shell), null);
        }
      case "EQ_TOGGLE":
        player.setEqEnabled(!player.eqEnabled);
      case "EQ_AUTO":
        player.setEqAuto(!player.eqAuto);
      // The song title's double click and right click (`dblclickaction`,
      // `rightclickaction`): the file's info, and its menu.
      case "TRACKINFO":
        shell.requests.showCurrentFileInfo();
      case "TRACKMENU":
        shell.showMenu(
          AmpedMenus.playlistFileInfo(
            shell.localizations,
            onFileInfo: shell.requests.showCurrentFileInfo,
          ),
          null,
        );
      case "PE_ADD" || "PE_REM" || "PE_SEL" || "PE_MISC" || "PE_LIST":
        // The classic player pops these up over the button; the pointer is on it.
        shell.classic.showMenu(playlistMenuFor(action.action)!, null);
      // The visualization's buttons (Amped Modern's drawer and its
      // Visualizer window). The classic player passes these to the plug-in, which goes
      // through its presets; here they go through the plug-in's modules.
      case "VIS_PREV":
        shell.vis.previous();
      case "VIS_NEXT":
        shell.vis.next();
      case "VIS_RANDOM":
        shell.vis.setRandom(!shell.vis.random);
      case "VIS_FS":
        if (shell.vis.isRunning) shell.vis.toggleFullscreen();
      case "VIS_MENU":
        shell.showMenu(AmpedMenus.visualizerOptions(shell), null);
      case "VIS_CFG":
        shell.configureVisPlugin();
      // The video's buttons.
      case "VID_FS":
        shell.toggleVideoFullscreen();
      case "VID_1X":
        shell.zoomModernVideo(1);
      case "VID_2X":
        shell.zoomModernVideo(2);
      case "VID_TV":
        shell.setOpen(SkinWindow.library, true);
      case "VID_MISC":
        shell.showMenu(AmpedMenus.video(shell), null);
      case "SHUFFLE" || "TOGGLE_SHUFFLE":
        player.toggleShuffle();
      case "REPEAT" || "TOGGLE_REPEAT":
        player.toggleRepeat();
      default:
        Arcane.log(
          "Unhandled skin action",
          metadata: {"action": action.action, "param": action.param},
          level: Level.warning,
          module: "ModernHost",
        );
    }
  }

  @override
  int configValue(WasabiCfgAttrib attribute) => config.value(attribute);

  @override
  void setConfigValue(WasabiCfgAttrib attribute, int value) =>
      config.setValue(attribute, value);

  @override
  Future<void> openMenu(WasabiMenuRequest request) {
    final window = shell.skin.modern?.windowForContainer(request.container);
    final items = AmpedMenus.skinMenu(shell, request.menu);
    if (window == null || items == null) {
      Arcane.log(
        "Unhandled skin menu",
        metadata: {"menu": request.menu},
        level: Level.warning,
        module: "ModernHost",
      );
      return Future.value();
    }
    final done = Completer<void>();
    // Deferred like [AmpedShell.showMenu]: the native menu blocks while
    // open, so it must not open inside the pointer event.
    Timer.run(() {
      try {
        NativeMenu.show(
          items,
          shell.toGlobal(window, request.anchor.bottomLeft),
        );
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  @override
  double? sliderValue(String action, String? param) {
    final player = shell.player;
    switch (action) {
      case "VOLUME":
        return player.volume / 255;
      case "PAN":
        return (player.balance + 127) / 254;
      case "SEEK":
        if (!(player.playing || player.paused) || player.durationSec <= 0) {
          return null;
        }
        return player.position / 256;
      case "EQ_PREAMP":
        // 0 is the top (+12 dB) in the player's scale.
        return 1 - player.preamp / 63;
      case "EQ_BAND" when param?.toLowerCase() == "preamp":
        // Wasabi sliders take the preamp as a band too (pslider.cpp).
        return 1 - player.preamp / 63;
      case "EQ_BAND":
        final band = (int.tryParse(param ?? "") ?? 0) - 1;
        if (band < 0 || band >= player.eqBands.length) return null;
        return 1 - player.eqBands[band] / 63;
    }
    return null;
  }

  @override
  void setSliderValue(
    String action,
    String? param,
    double value, {
    required bool done,
  }) {
    final player = shell.player;
    switch (action) {
      case "VOLUME":
        player.setVolume((value * 255).round());
      case "PAN":
        player.setBalance((value * 254).round() - 127);
      case "SEEK":
        if (done) player.setSeek((value * 256).round());
      case "EQ_PREAMP":
        player.setPreamp(((1 - value) * 63).round());
      case "EQ_BAND" when param?.toLowerCase() == "preamp":
        player.setPreamp(((1 - value) * 63).round());
      case "EQ_BAND":
        final band = (int.tryParse(param ?? "") ?? 0) - 1;
        player.setEqBand(band, ((1 - value) * 63).round());
    }
  }

  @override
  int get playbackStatus {
    final player = shell.player;
    if (player.paused) return -1;
    return player.playing ? 1 : 0;
  }

  @override
  String get playItemLocation =>
      shell.player.playlist.currentEntry?.location ?? "";

  @override
  ui.Image? get albumArt => playbackStatus == 0 ? null : shell.albumArt.image;

  @override
  ui.Offset get cursorPosition => NativeScreen.cursorPosition();

  @override
  ui.Offset? windowOrigin(String id) {
    final window = shell.skin.modern?.windowForContainer(id);
    return window == null ? null : shell.dock.rectOf(window)?.topLeft;
  }

  @override
  ui.Image? get onlineAlbumArt => shell.onlineArt.image;

  @override
  bool get albumArtLoading => shell.albumArt.loading;

  @override
  void refreshAlbumArt() => shell.albumArt.refresh();

  @override
  void pressSecondaryAction(WasabiAction action, PointerDownEvent event) {
    SkinSecondaryClaim.claim(event);
    runAction(action);
  }

  @override
  void pressAlbumArtMenu(PointerDownEvent event) =>
      SkinSecondaryClaim.claim(event);

  @override
  void showAlbumArtMenu() => shell.showMenu(
    AmpedMenus.albumArt(shell, lockAspect: false),
    null,
  );

  @override
  void openAlbumArtFolder() => shell.covers.openAlbumArtFolder();

  @override
  void openPath(String path, {required bool play}) =>
      unawaited(shell.files.openPaths([path], play: play));

  @override
  void revealPath(String path) => shell.files.revealPaths([path]);

  @override
  void openFolder(String path) => _launch(Uri.directory(path));

  @override
  void openExternal(String path) {
    final uri = path.contains("://") ? Uri.tryParse(path) : Uri.file(path);
    if (uri == null) return;
    if (uri.host == "amped.invalid" ||
        uri.host == "winamp.com" ||
        uri.host.endsWith(".winamp.com")) {
      _openGoneHostLink(uri);
      return;
    }
    _launch(uri);
  }

  /// A link to a host that is gone (winamp.com) or that never existed
  /// (`amped.invalid`, which Amped Modern uses): a skin's notification that
  /// sends its artist there (`/nowplaying/artist/?artistName=`) searches the
  /// library for the artist instead. The others go nowhere.
  void _openGoneHostLink(Uri uri) {
    final artist = uri.queryParameters["artistName"];
    if (artist == null || artist.isEmpty) {
      Arcane.log(
        "A skin linked to winamp.com, which is gone",
        metadata: {"path": uri.path},
        level: Level.info,
        module: "ShellWasabiHost",
      );
      return;
    }
    LibraryView.searchRequest.value = artist;
    shell.setOpen(SkinWindow.library, true);
  }

  /// Hands [uri] to the system (the file manager, or the program a file
  /// belongs to).
  void _launch(Uri uri) {
    unawaited(
      launchUrl(uri).catchError((Object error) {
        Arcane.log(
          "Could not open the path",
          metadata: {"path": uri.toFilePath(), "error": "$error"},
          level: Level.warning,
          module: "ShellWasabiHost",
        );
        return false;
      }),
    );
  }

  /// How opaque popup menus are, 0 to 1: the skin's "Popup menu alpha"
  /// option of the classic player's "Skins and UI Tweaks" (0 to 255, 240 unless set).
  double get popupMenuOpacity {
    final skin = shell.skin.modern;
    final value = skin == null
        ? null
        : int.tryParse(
            readPrivate(
                  "${skin.name}/config/skins and ui tweaks",
                  "popup menu alpha",
                ) ??
                "",
          );
    return ((value ?? 240).clamp(0, 255)) / 255;
  }

  @override
  void showPopup(List<WasabiPopupItem> items, void Function(int id) chosen) {
    List<NativeMenuItem> convert(List<WasabiPopupItem> list) => [
      for (final item in list)
        if (item.separator)
          const NativeMenuItem.separator()
        else if (item.children.isNotEmpty)
          NativeMenuItem(
            label: item.label,
            enabled: !item.disabled,
            children: convert(item.children),
          )
        else
          NativeMenuItem(
            label: item.label,
            checked: item.checked,
            checkable: item.checked,
            enabled: !item.disabled,
            onSelected: () => chosen(item.id),
          ),
    ];
    shell.showMenu(convert(items), null);
  }

  @override
  void seekTo(int ms) {
    final length = shell.player.durationSec * 1000;
    if (length <= 0) return;
    shell.player.setSeek((ms.clamp(0, length) * 256 / length).round());
  }

  /// The preference that keeps a skin's private setting [item] of
  /// [section].
  static String privateKey(String section, String item) =>
      "wasabi.private.$section.$item";

  @override
  String? readPrivate(String section, String item) {
    final key = privateKey(section, item);
    return _private[key] ?? prefs?.getString(key);
  }

  @override
  void writePrivate(String section, String item, String value) {
    final key = privateKey(section, item);
    final prefs = this.prefs;
    if (prefs == null) {
      _private[key] = value;
      return;
    }
    _private.remove(key);
    unawaited(prefs.setString(key, value));
  }

  /// Whether the skin should show the visualization component: whenever it
  /// runs. Going fullscreen must not report it hidden, or the skin's script
  /// closes the slot it is docked in and Escape then opens a window of its
  /// own besides.
  static bool visComponentVisible(VisHost vis) => vis.isRunning;

  @override
  bool isContainerVisible(String id) {
    final window = shell.skin.modern?.windowForContainer(id.toLowerCase());
    // The visualization itself, by its GUID: showing wherever it is, in
    // its own window or in a skin's slot (Amped Modern's drawer).
    if (window == null && wasabiComponentOf(id) == "vis") {
      return visComponentVisible(shell.vis);
    }
    if (window == null && wasabiComponentOf(id) == "video") {
      return shell.modernVideo.shown;
    }
    return window != null && shell.isOpen(window);
  }

  @override
  bool isContainerActive(String id) {
    final window = shell.skin.modern?.windowForContainer(id.toLowerCase());
    final controller = window == null
        ? null
        : shell.windowState.controllers[window];
    return controller?.isActivated ?? false;
  }

  @override
  void setContainerVisible(String id, bool visible) {
    final window = shell.skin.modern?.windowForContainer(id.toLowerCase());
    if (window == null && wasabiComponentOf(id) == "vis") {
      visible ? shell.visualization.showComponent() : shell.vis.stop();
      return;
    }
    if (window == null && wasabiComponentOf(id) == "video") {
      visible
          ? shell.modernVideo.showComponent()
          : shell.modernVideo.hideComponent();
      return;
    }
    if (window != null && shell.isOpen(window) != visible) {
      shell.setOpen(window, visible);
    }
  }

  @override
  String? currentLayout(String id) {
    final window = shell.skin.modern?.windowForContainer(id.toLowerCase());
    return window == null ? null : shell.skin.modern?.layout(window)?.id;
  }

  @override
  void resizeLayout(String container, WasabiLayout layout, Size size) =>
      shell.resizeModern(container, layout, size);

  @override
  int get playlistLength => shell.player.playlist.length;

  @override
  String playlistTitle(int index) => shell.player.playlist.entries[index].title;

  @override
  int playlistItemLengthMs(int index) =>
      shell.player.playlist.entries[index].duration?.inMilliseconds ?? -1;

  @override
  String playlistLocation(int index) =>
      shell.player.playlist.entries[index].location;

  @override
  String playlistMetadata(int index, String name) =>
      _metadata(shell.player.playlist.entries[index], name);

  @override
  void removePlaylistItem(int index) => shell.player.playlist.removeAt({index});

  @override
  void clearPlaylist() => shell.player.playlist.clear();

  @override
  void movePlaylistItem(int from, int to) =>
      shell.player.playlist.move(from, to);

  @override
  void switchSkin(String name) {
    final wanted = name.toLowerCase();
    for (final info in shell.skins.skins) {
      if (info.name.toLowerCase() == wanted) {
        unawaited(shell.skins.apply(info));
        return;
      }
    }
  }

  @override
  ui.Rect? get appRect => shell.dock.rectOf(SkinWindow.main);

  @override
  void centerWindow(String container) {
    final window = shell.skin.modern?.windowForContainer(container);
    final rect = window == null ? null : shell.dock.rectOf(window);
    if (window == null || rect == null) return;
    shell.dock.moveTo(
      window,
      viewport.center - ui.Offset(rect.width / 2, rect.height / 2),
    );
  }

  @override
  void focusWindow(String container) {
    var window = shell.skin.modern?.windowForContainer(container);
    // A frame drawn over another window (the Apple-styled skin's player) focuses that
    // window; a closed window has no window to focus, and focusing it would
    // show it.
    if (window == SkinWindow.main && shell.mainIsCompanion) {
      window = SkinWindow.pl;
    }
    if (window == null || !shell.isOpen(window)) return;
    // As Windows' SetFocus: it moves the keyboard among the app's windows
    // but does not bring the app forward from behind another one (a skin's
    // timer focusing its frames would never let the user switch away), and
    // a window that has the keyboard keeps it.
    final controllers = shell.windowState.controllers;
    if (!controllers.values.any((c) => c.isActivated)) return;
    if (controllers[window]?.isActivated ?? false) return;
    shell.dock.nativeWindowOf(window)?.focus();
  }

  @override
  int get playlistCurrent => shell.player.playlist.current;

  @override
  bool isPlaylistSelected(int index) =>
      shell.player.playlist.selected.contains(index);

  /// The anchor of Shift-click range selections.
  int? _selectionAnchor;

  @override
  void selectPlaylistItem(
    int index, {
    required bool extend,
    required bool toggle,
  }) {
    final playlist = shell.player.playlist;
    final anchor = _selectionAnchor;
    if (extend && anchor != null) {
      final low = anchor < index ? anchor : index;
      final high = anchor < index ? index : anchor;
      playlist.select({for (var i = low; i <= high; i++) i});
      return;
    }
    _selectionAnchor = index;
    if (toggle) {
      final selected = {...playlist.selected};
      if (!selected.remove(index)) selected.add(index);
      playlist.select(selected);
    } else {
      playlist.select({index});
    }
  }

  @override
  void playPlaylistItem(int index) => unawaited(shell.player.playIndex(index));

  @override
  List<int> searchPlaylist(String query) => PlaylistSearch.search(
    shell.player.playlist,
    query,
  ).map((match) => match.index).toList()..sort();

  @override
  void pressPlaylistMenu(int? index, PointerDownEvent event) {
    // The playlist's menu, not the window's.
    SkinSecondaryClaim.claim(event);
    final playlist = shell.player.playlist;
    final keyboard = HardwareKeyboard.instance;
    final toggle = keyboard.isControlPressed || keyboard.isMetaPressed;
    final selection = Set.of(playlist.selected);
    // As in the classic playlist: a press on the selection keeps it; one
    // elsewhere selects just that entry (Ctrl/Cmd adds or removes it).
    if (!toggle && !(index != null && selection.contains(index))) {
      selection.clear();
    }
    if (index != null) {
      if (toggle && selection.contains(index)) {
        selection.remove(index);
      } else {
        selection.add(index);
        _selectionAnchor = index;
      }
    }
    playlist.select(selection);
  }

  @override
  void showPlaylistMenu() =>
      shell.showMenu(AmpedMenus.playlistContext(shell), null);

  @override
  ClassicVisOptions get visOptions => shell.player.classicVis;

  @override
  void clickVis() => shell.clickClassicVis();

  @override
  bool get visRunning => shell.player.playing && !shell.player.paused;

  @override
  void startVisualization() => shell.player.engine.startVisualization();

  @override
  void stopVisualization() => shell.player.engine.stopVisualization();

  @override
  (Float32List, Float32List)? get visSamples =>
      shell.player.engine.visualizationSamples;
}
