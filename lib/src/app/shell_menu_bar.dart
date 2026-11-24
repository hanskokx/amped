import "dart:async";
import "dart:io";

import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart"
    show wasabiSelectColorTheme, wasabiShareColorTheme, wasabiSharesColorTheme;
import "package:flutter/services.dart";

import "../skin/skin_views.dart";
import "amped_dialog.dart";
import "amped_menus.dart";
import "amped_shell.dart";

/// The native menu bar (macOS) and tray's side of the shell: what its items
/// ask the app to do, and what the shell tells it to show.
class ShellMenuBar {
  ShellMenuBar(this.shell);

  final AmpedShell shell;

  Future<dynamic> handleCall(MethodCall call) async {
    switch (call.method) {
      case "toggleWindow":
        final key = call.arguments as String;
        for (final window in SkinWindow.values) {
          if (window.key == key) shell.toggle(window);
        }
      case "showMainWindow":
        shell.setOpen(SkinWindow.main, true);
        shell.dock.nativeWindowOf(SkinWindow.main)?.focus();
      case "toggleAlwaysOnTop":
        shell.player.toggleAlwaysOnTop();
      case "toggleWindowShade":
        shell.player.toggleAllShades();
      case "toggleUiScale":
        shell.player.toggleUiScale();
        await ampedChannel.invokeMethod("setUiScale", {
          "scale": shell.player.uiScale,
        });
      case "setUiScale":
        final arguments = call.arguments as Map;
        shell.player.setUiScale((arguments["scale"] as num).toDouble());
      case "openFiles":
        await shell.files.openPaths(
          (call.arguments as List).cast<String>(),
          play: true,
        );
      case "notificationClicked":
        await shell.notifications.clicked(
          (call.arguments as List).cast<String>(),
        );
      case "remoteCommand":
        final args = call.arguments as Map;
        shell.nowPlaying.handleCommand(
          args["command"] as String,
          position: (args["position"] as num?)?.toDouble(),
        );
      case "selectSkin":
        final name = call.arguments as String;
        for (final info in shell.skins.skins) {
          if (info.name == name) await shell.skins.apply(info);
        }
      case "onlineSkinBrowser":
        shell.openOnlineSkinBrowser();
      case "selectColorTheme":
        final skin = shell.skin.wasabi;
        if (skin != null) {
          await wasabiSelectColorTheme(
            skin,
            shell.wasabiHost,
            call.arguments as String,
          );
        }
      case "shareColorThemes":
        wasabiShareColorTheme(
          shell.wasabiHost,
          share: !wasabiSharesColorTheme(shell.wasabiHost),
        );
      case "preferences":
        shell.dialogManager.open(AmpedDialog.preferences);
      case "about":
        shell.dialogManager.open(AmpedDialog.about);
      case "quit":
        await shell.quit();
    }
  }

  /// The windows listed under Window > Windows in the macOS menu bar, in the
  /// order of the classic player main menu, with their Cmd key equivalents.
  static const List<(SkinWindow, String?)> _menuBarWindows = [
    (SkinWindow.main, null),
    (SkinWindow.pl, "l"),
    (SkinWindow.library, null),
    (SkinWindow.eq, "e"),
    (SkinWindow.video, null),
    (SkinWindow.thinger, null),
    (SkinWindow.vis, null),
    (SkinWindow.albumArt, null),
  ];

  void syncSoon() => unawaited(sync());

  Future<void> sync() async {
    shell.refreshSystemTrayMenu();
    try {
      if (Platform.isMacOS) {
        await ampedChannel.invokeMethod("setNativeMenuLabels", {
          "labels": {
            "appName": shell.localizations.appName,
            "windows": shell.localizations.windows,
            "equalizer": shell.localizations.equalizer,
            "playlistEditor": shell.localizations.playlistEditor,
            "video": shell.localizations.video,
            "library": shell.localizations.library,
            "visualization": shell.localizations.visualization,
            "albumArt": shell.localizations.albumArt,
            "skins": shell.localizations.skins,
            "skinMenu": shell.localizations.skinMenu,
            "skinBrowser": shell.localizations.skinBrowser,
            "onlineSkinBrowser": shell.localizations.onlineSkinBrowser,
            "colorThemes": shell.localizations.colorThemes,
            "shareColorThemes": shell.localizations.shareColorThemes,
            "settings": shell.localizations.settings,
            "preferences": shell.localizations.preferences,
            "alwaysOnTop": shell.localizations.alwaysOnTop,
            "windowShade": shell.localizations.windowShade,
            "doubleSizeMode": shell.localizations.doubleSizeMode,
            "quit": shell.localizations.quit,
            "ampedTagline": shell.localizations.ampedTagline,
            "macAboutMenu": shell.localizations.macAboutMenu,
            "macHideMenu": shell.localizations.macHideMenu,
            "macQuitMenu": shell.localizations.macQuitMenu,
          },
        });
      }
      await ampedChannel.invokeMethod("setAlwaysOnTop", {
        "isAlwaysOnTop": shell.player.alwaysOnTop,
      });
      await ampedChannel.invokeMethod("setWindowShade", {
        "on": shell.player.allShadesShaded,
      });
      await ampedChannel.invokeMethod("setWindows", [
        for (final (window, container) in shell.skin.windows)
          {
            "key": window.key,
            "title": container.name,
            "open": shell.isOpen(window),
          },
        for (final (window, shortcut) in _menuBarWindows)
          if (window != SkinWindow.thinger ||
              shell.skin.modern?.container(SkinWindow.thinger) != null)
            {
              "key": window.key,
              "title": AmpedMenus.windowLabel(window, shell.localizations),
              "open": shell.isOpen(window),
              "shortcut": ?shortcut,
            },
      ]);
      await ampedChannel.invokeMethod("setUiScale", {
        "scale": shell.player.uiScale,
      });
      await ampedChannel.invokeMethod("setSkins", {
        "names": [for (final info in shell.skins.sortedSkins) info.name],
        "active": shell.skins.active.name,
        "colorThemes": ?switch (shell.skin.wasabi?.colorThemes) {
          final themes? when themes.sets.length >= 2 => {
            "names": themes.names.toList(),
            "current": themes.current?.name,
            "shared": wasabiSharesColorTheme(shell.wasabiHost),
          },
          _ => null,
        },
      });
    } on Object {
      // Menu sync is best-effort (no menu bar on Windows/Linux).
    }
  }
}
