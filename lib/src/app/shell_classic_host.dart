import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";
import "package:window_dock/window_dock.dart";

import "../player/player_state.dart";
import "../skin/skin_views.dart";
import "amped_dialog.dart";
import "amped_menus.dart";
import "amped_shell.dart";

/// What the classic skin windows need from the app, over [AmpedShell].
class ShellClassicHost implements ClassicHost {
  ShellClassicHost(this.shell);

  final AmpedShell shell;

  late final Listenable _changes = Listenable.merge([shell, shell.dock]);

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  @override
  ClassicSkinData? get skin => shell.skins.current.classicData;

  @override
  PlayerState get player => shell.player;

  @override
  ValueNotifier<String?> get songTitleOverride => shell.songTitleOverride;

  @override
  PlaylistNavigator? get playlistNavigator => shell.playlistNavigator;

  @override
  set playlistNavigator(PlaylistNavigator? navigator) =>
      shell.playlistNavigator = navigator;

  @override
  Size baseSize(SkinWindow window) => shell.windowState.baseSize(window);

  @override
  Size fullSize(SkinWindow window) => shell.windowState.fullSize(window);

  @override
  void resize(SkinWindow window, Size size) => shell.resize(window, size);

  @override
  void setOpen(SkinWindow window, bool open) => shell.setOpen(window, open);

  @override
  void toggle(SkinWindow window) => shell.toggle(window);

  @override
  bool isWindowVisible(SkinWindow window) => shell.dock.isVisible(window);

  @override
  Offset windowOrigin(SkinWindow window) =>
      shell.dock.rectOf(window)?.topLeft ?? Offset.zero;

  @override
  Offset get cursorPosition => NativeScreen.cursorPosition();

  @override
  Offset toGlobal(SkinWindow window, Offset skinPoint) =>
      shell.toGlobal(window, skinPoint);

  @override
  void showMenu(ClassicMenu menu, Offset? position) {
    final playlist = shell.player.playlist;
    shell.showMenu(switch (menu) {
      ClassicMenu.main => AmpedMenus.main(shell),
      ClassicMenu.options => AmpedMenus.options(shell),
      ClassicMenu.visualization => AmpedMenus.visualization(shell),
      ClassicMenu.eqPresets => AmpedMenus.eqPresets(shell),
      ClassicMenu.playlistContext => AmpedMenus.playlistContext(shell),
      ClassicMenu.playlistAdd => AmpedMenus.playlistAdd(shell),
      ClassicMenu.playlistRemove => AmpedMenus.playlistRemove(
        playlist,
        shell.localizations,
      ),
      ClassicMenu.playlistRemoveMisc => AmpedMenus.playlistRemoveMisc(
        playlist,
        shell.localizations,
      ),
      ClassicMenu.playlistSelect => AmpedMenus.playlistSelect(
        playlist,
        shell.localizations,
      ),
      ClassicMenu.playlistMisc => AmpedMenus.playlistMisc(
        playlist,
        shell.localizations,
        onFileInfo: shell.requests.showSelectedFileInfo,
      ),
      ClassicMenu.playlistFileInfo => AmpedMenus.playlistFileInfo(
        shell.localizations,
        onFileInfo: shell.requests.showSelectedFileInfo,
      ),
      ClassicMenu.playlistSort => AmpedMenus.playlistSort(
        playlist,
        shell.localizations,
      ),
      ClassicMenu.playlistMiscOptions => AmpedMenus.playlistMiscOptions(
        playlist,
        shell.localizations,
      ),
      ClassicMenu.playlistList => AmpedMenus.playlistList(shell),
    }, position);
  }

  @override
  Future<void> openFiles() => shell.files.openFiles();

  @override
  Future<void> openFolder() => shell.files.openFolder();

  @override
  Future<void> openUrl() => shell.files.openUrl();

  @override
  Future<void> addFiles() => shell.files.addFiles();

  @override
  Future<void> addFolder() => shell.files.addFolder();

  @override
  Future<void> addUrl() => shell.files.addUrl();

  @override
  Future<void> loadList() => shell.files.loadList();

  @override
  Future<void> saveList() => shell.files.saveList();

  @override
  void minimize() => shell.minimize();

  @override
  Future<void> quit() => shell.quit();

  @override
  void closeMainWindow() => shell.closeMainWindow();

  @override
  void clickClassicVis() => shell.clickClassicVis();

  @override
  void showAbout() => shell.dialogManager.open(AmpedDialog.about);

  @override
  void showFileInfo() => shell.requests.showCurrentFileInfo();
}
