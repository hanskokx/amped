import "dart:async";
import "dart:math";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart"
    show
        WasabiScriptRuntime,
        WasabiSkinOption,
        wasabiSelectColorTheme,
        wasabiShareColorTheme,
        wasabiSharesColorTheme;
import "package:flutter/foundation.dart" show VoidCallback, visibleForTesting;
import "package:window_dock/window_dock.dart";

import "../features/preferences/preferences_page.dart";
import "../library/library_source_manager.dart";
import "../library/playlist_generator.dart";
import "../main_window/presets_window.dart";
import "../player/playlist.dart";
import "../player/video_cast.dart" show VideoCastController;
import "../player/video_engine.dart" show TrackOption;
import "../skin/skin_views.dart";
import "amped_dialog.dart";
import "amped_shell.dart";

/// The popup menus of the classic player (`IDR_MAINMENU` and friends), built from
/// the current shell state. Entries without a feature behind them yet are
/// shown disabled.
abstract final class AmpedMenus {
  /// The main menu: right-click on a window, or the main window's menu button.
  static List<NativeMenuItem> main(AmpedShell shell) {
    return [
      about(shell),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.play,
        children: openMedia(shell),
      ),
      const NativeMenuItem.separator(),
      ...windows(shell),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.skins,
        children: skins(shell),
      ),
      ...skinLayouts(shell),
      NativeMenuItem(
        label: shell.localizations.options,
        children: options(shell),
      ),
      NativeMenuItem(
        label: shell.localizations.playback,
        children: playback(shell),
      ),
      const NativeMenuItem.separator(),
      exit(shell),
    ];
  }

  /// The layouts the main window of a modern skin can take, to pick one from
  /// a menu: a skin's own mode button may be out of reach in a layout (a
  /// strip too small for it), and there would be no way back.
  static List<NativeMenuItem> skinLayouts(AmpedShell shell) {
    final modern = shell.skin.modern;
    final container = modern?.container(SkinWindow.main);
    if (modern == null || container == null || container.layouts.length < 2) {
      return const [];
    }
    final current = modern.layout(SkinWindow.main);
    return [
      NativeMenuItem(
        label: shell.localizations.skinLayouts,
        children: [
          for (final layout in container.layouts)
            NativeMenuItem(
              label: layout.id,
              checked: identical(layout, current),
              checkable: true,
              onSelected: () =>
                  shell.switchModernLayout(SkinWindow.main, layout.id),
            ),
        ],
      ),
    ];
  }

  /// The menus a modern skin's menu bars open (Wasabi 5's
  /// `WA5_MENUBAR`: `WA5:File`, `WA5:PE_Sort`, ...), made of the
  /// entries of the menus above; null for a menu amped does not have.
  static List<NativeMenuItem>? skinMenu(AmpedShell shell, String name) {
    final playlist = shell.player.playlist;
    final localizations = shell.localizations;
    return switch (name.trim().toLowerCase()) {
      "wa5:file" => [
        ...openMedia(shell),
        const NativeMenuItem.separator(),
        ...playlistList(shell),
        const NativeMenuItem.separator(),
        exit(shell),
      ],
      "wa5:play" => playback(shell),
      "wa5:options" => [
        NativeMenuItem(label: localizations.skins, children: skins(shell)),
        NativeMenuItem(
          label: localizations.visualization,
          children: visualization(shell),
        ),
        NativeMenuItem(
          label: localizations.equalizer,
          children: eqPresets(shell),
        ),
        const NativeMenuItem.separator(),
        ...options(shell),
      ],
      "wa5:windows" => windows(shell),
      "wa5:help" || "wa5:pe_help" || "wa5:ml_help" => [about(shell)],
      "wa5:pe_file" => [
        ...playlistList(shell),
        const NativeMenuItem.separator(),
        ...playlistAdd(shell),
        const NativeMenuItem.separator(),
        windowToggle(shell, SkinWindow.pl),
      ],
      "wa5:pe_playlist" => [
        ...playlistSelect(playlist, localizations),
        const NativeMenuItem.separator(),
        ...playlistRemove(playlist, localizations),
      ],
      "wa5:pe_sort" => playlistSort(playlist, localizations),
      "wa5:ml_file" => mediaLibraryFile(shell),
      "wa5:ml_view" => mediaLibraryView(shell),
      _ => null,
    };
  }

  /// The Media Library's File menu (`ML_File` in the classic player's menus). The
  /// playlist entries work on the current playlist, the others fill the
  /// library.
  static List<NativeMenuItem> mediaLibraryFile(AmpedShell shell) =>
      mediaLibraryFileItems(
        localizations: shell.localizations,
        libraryOpen: shell.isOpen(SkinWindow.library),
        onNew: shell.player.playlist.clear,
        onImport: () => unawaited(shell.files.loadList()),
        onExport: () => unawaited(shell.files.saveList()),
        onAddMedia: () => unawaited(shell.libraryActions.addToLibrary()),
        onAddPlaylist: () =>
            unawaited(shell.libraryActions.addPlaylistToLibrary()),
        onToggleLibrary: () => shell.toggle(SkinWindow.library),
      );

  /// The entries of [mediaLibraryFile], with what they do passed in.
  @visibleForTesting
  static List<NativeMenuItem> mediaLibraryFileItems({
    required AppLocalizations localizations,
    required bool libraryOpen,
    required VoidCallback onNew,
    required VoidCallback onImport,
    required VoidCallback onExport,
    required VoidCallback onAddMedia,
    required VoidCallback onAddPlaylist,
    required VoidCallback onToggleLibrary,
  }) => [
    NativeMenuItem(
      label: localizations.mlNewPlaylist,
      shortcut: "Shift+Ins",
      onSelected: onNew,
    ),
    NativeMenuItem(
      label: localizations.mlImportPlaylist,
      onSelected: onImport,
    ),
    NativeMenuItem(
      label: localizations.mlExportPlaylist,
      onSelected: onExport,
    ),
    const NativeMenuItem.separator(),
    NativeMenuItem(label: localizations.mlAddMedia, onSelected: onAddMedia),
    NativeMenuItem(
      label: localizations.mlAddPlaylist,
      onSelected: onAddPlaylist,
    ),
    const NativeMenuItem.separator(),
    NativeMenuItem(
      label: libraryOpen
          ? localizations.mlCloseLibrary
          : localizations.mlOpenLibrary,
      shortcut: "Alt+L",
      onSelected: onToggleLibrary,
    ),
  ];

  /// The Media Library's View menu (`ML_View`): clearing the library and
  /// its preferences.
  static List<NativeMenuItem> mediaLibraryView(AmpedShell shell) => [
    NativeMenuItem(
      label: shell.localizations.mlClearLibrary,
      enabled: !shell.library.isEmpty,
      onSelected: () => unawaited(shell.library.clear()),
    ),
    const NativeMenuItem.separator(),
    NativeMenuItem(
      label: shell.localizations.mlPreferences,
      onSelected: () => shell.showPreferences(PreferencesPage.mediaLibrary),
    ),
  ];

  /// The About entry.
  static NativeMenuItem about(AmpedShell shell) => NativeMenuItem(
    label: shell.localizations.menuAmped,
    onSelected: () => shell.dialogManager.open(AmpedDialog.about),
  );

  /// The Exit entry.
  static NativeMenuItem exit(AmpedShell shell) => NativeMenuItem(
    label: shell.localizations.exit,
    onSelected: () => unawaited(shell.quit()),
  );

  /// The "Play" submenu of the main menu: open a file, URL or folder.
  static List<NativeMenuItem> openMedia(AmpedShell shell) => [
    NativeMenuItem(
      label: shell.localizations.file,
      shortcut: "L",
      onSelected: () => unawaited(shell.files.openFiles()),
    ),
    NativeMenuItem(
      label: shell.localizations.url,
      shortcut: "Ctrl+L",
      onSelected: () => unawaited(shell.files.openUrl()),
    ),
    NativeMenuItem(
      label: shell.localizations.folder,
      shortcut: "Shift+L",
      onSelected: () => unawaited(shell.files.openFolder()),
    ),
  ];

  /// The windows the main menu opens and closes, with their shortcuts.
  static const List<(SkinWindow, String)> _menuWindows = [
    (SkinWindow.pl, "Alt+E"),
    (SkinWindow.library, "Alt+L"),
    (SkinWindow.eq, "Alt+G"),
    (SkinWindow.video, "Alt+V"),
    // gen_classicart puts it after the windows (IDS_ALBUM_ART_MENU).
    (SkinWindow.albumArt, "Alt+A"),
  ];

  /// The main menu's window entries.
  static List<NativeMenuItem> windows(AmpedShell shell) => [
    for (final (window, _) in _menuWindows) windowToggle(shell, window),
    // The panels the active modern skin brings of its own.
    for (final (window, container) in shell.skin.windows)
      NativeMenuItem(
        label: container.name.trim().isEmpty ? container.id : container.name,
        checked: shell.isOpen(window),
        onSelected: () => shell.toggle(window),
      ),
  ];

  /// The entry that opens or closes [window].
  static NativeMenuItem windowToggle(AmpedShell shell, SkinWindow window) {
    String? shortcut;
    for (final (w, s) in _menuWindows) {
      if (w == window) shortcut = s;
    }
    return NativeMenuItem(
      label: windowLabel(window, shell.localizations),
      shortcut: shortcut,
      checked: shell.isOpen(window),
      onSelected: () => shell.toggle(window),
    );
  }

  /// The Playback submenu.
  static List<NativeMenuItem> playback(AmpedShell shell) {
    final player = shell.player;
    return [
      NativeMenuItem(
        label: shell.localizations.previous,
        shortcut: "Z",
        onSelected: player.prev,
      ),
      NativeMenuItem(
        label: shell.localizations.play,
        shortcut: "X",
        onSelected: player.togglePlay,
      ),
      NativeMenuItem(
        label: shell.localizations.pause,
        shortcut: "C",
        onSelected: player.pause,
      ),
      NativeMenuItem(
        label: shell.localizations.stop,
        shortcut: "V",
        onSelected: player.stop,
      ),
      NativeMenuItem(
        label: shell.localizations.next,
        shortcut: "B",
        onSelected: player.next,
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.repeat,
        shortcut: "R",
        checked: player.repeat,
        onSelected: player.toggleRepeat,
      ),
      NativeMenuItem(
        label: shell.localizations.shuffle,
        shortcut: "S",
        checked: player.shuffle,
        onSelected: player.toggleShuffle,
      ),
      const NativeMenuItem.separator(),
      cast(shell),
    ];
  }

  /// The Cast submenu: the devices to play what is playing on, or the way
  /// back while it plays on one.
  static NativeMenuItem cast(AmpedShell shell) {
    final l = shell.localizations;
    final device = shell.chromecast;
    final player = shell.player;
    final casting = device.active || device.connecting;
    if (!casting && device.targets.isEmpty && !device.discovering) {
      device.discover();
    }
    return NativeMenuItem(
      label: l.videoCast,
      // Only what a device plays as it is can be sent to one.
      enabled:
          casting ||
          ((player.playing || player.paused) &&
              VideoCastController.canCast(
                player.playlist.currentEntry?.location ?? "",
              )),
      children: [
        if (casting) ...[
          NativeMenuItem(
            label: l.videoCastingTo(device.current?.name ?? ""),
            enabled: false,
          ),
          NativeMenuItem(label: l.videoCastStop, onSelected: device.stop),
        ] else ...[
          for (final target in device.targets)
            NativeMenuItem(
              label: target.name,
              onSelected: () => unawaited(shell.castTo(target)),
            ),
          if (device.targets.isEmpty)
            NativeMenuItem(
              label: device.discovering
                  ? l.videoCastSearching
                  : l.videoCastNone,
              enabled: false,
            ),
          if (!device.discovering) ...[
            const NativeMenuItem.separator(),
            NativeMenuItem(
              label: l.videoCastSearchAgain,
              onSelected: device.discover,
            ),
          ],
        ],
      ],
    );
  }

  /// The Options menu (also the clutterbar "O" button).
  static List<NativeMenuItem> options(AmpedShell shell) {
    final player = shell.player;
    return [
      NativeMenuItem(
        label: shell.localizations.preferences,
        shortcut: "Ctrl+P",
        onSelected: () => shell.dialogManager.open(AmpedDialog.preferences),
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.timeElapsed,
        shortcut: "Ctrl+T toggles",
        checked: !player.timeRemaining,
        onSelected: player.timeRemaining ? player.toggleTimeRemaining : () {},
      ),
      NativeMenuItem(
        label: shell.localizations.timeRemaining,
        checked: player.timeRemaining,
        onSelected: player.timeRemaining ? () {} : player.toggleTimeRemaining,
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.alwaysOnTop,
        shortcut: "Ctrl+A",
        checked: player.alwaysOnTop,
        mixed: player.videoAlwaysOnTop,
        onSelected: player.toggleAlwaysOnTop,
      ),
      NativeMenuItem(
        label: shell.localizations.doubleSizeMode,
        shortcut: "Ctrl+D",
        checked: player.uiScale == 2,
        onSelected: () => player.setUiScale(player.uiScale == 2 ? 1 : 2),
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.playbackNotifications,
        checked: shell.notifications.enabled,
        checkable: true,
        onSelected: shell.notifications.toggle,
      ),
      NativeMenuItem(
        label: shell.localizations.nativeNotifications,
        checked: shell.notifications.native,
        checkable: true,
        onSelected: shell.notifications.toggleNative,
      ),
      NativeMenuItem(
        label: shell.localizations.showNotification,
        onSelected: shell.notifications.showNow,
      ),
      NativeMenuItem(
        label: shell.localizations.mainWindowShade,
        shortcut: "Ctrl+W",
        checked: player.windowShade,
        onSelected: player.toggleWindowShade,
      ),
      ...skinOptions(shell),
    ];
  }

  /// The options the active modern skin's scripts add to the Options menu,
  /// below a separator (`MenuActions::installSkinOptions`), such as the classic player
  /// Modern's "Animate Config Drawer"; empty for other skins.
  static List<NativeMenuItem> skinOptions(AmpedShell shell) {
    final scripts = shell.wasabiScripts;
    if (scripts == null) return const [];
    final options = scripts.skinOptions;
    if (options.isEmpty) return const [];
    return [
      const NativeMenuItem.separator(),
      ..._skinOptionItems(scripts, options),
    ];
  }

  /// [label] of a skin option as amped shows it: the name of the classic player a skin
  /// uses reads "Amped".
  static String skinOptionLabel(String label) =>
      label.replaceAll(RegExp(r"\bWinamp\b"), "Amped");

  static List<NativeMenuItem> _skinOptionItems(
    WasabiScriptRuntime scripts,
    List<WasabiSkinOption> options,
  ) => [
    for (final option in options)
      if (option.separator)
        const NativeMenuItem.separator()
      else
        _skinOptionItem(scripts, option),
  ];

  static NativeMenuItem _skinOptionItem(
    WasabiScriptRuntime scripts,
    WasabiSkinOption option,
  ) {
    // The classic player shows what follows a tab as the shortcut. Skins name their
    // pages after the player ("Amped Modern"); this one is amped (as
    // gen_ff's localizeSkinWindowName swaps in its own names).
    final text = skinOptionLabel(option.label);
    final tab = text.indexOf("\t");
    final label = tab < 0 ? text : text.substring(0, tab);
    final shortcut = tab < 0 ? null : text.substring(tab + 1);
    final children = option.children;
    if (children != null) {
      return NativeMenuItem(
        label: label,
        shortcut: shortcut,
        enabled: children.isNotEmpty,
        children: _skinOptionItems(scripts, children),
      );
    }
    return NativeMenuItem(
      label: label,
      shortcut: shortcut,
      checkable: true,
      checked: option.checked,
      onSelected: () => scripts.toggleSkinOption(option),
    );
  }

  /// The Skins submenu.
  static List<NativeMenuItem> skins(AmpedShell shell) {
    final active = shell.skins.active.name;
    return [
      NativeMenuItem(
        label: shell.localizations.skinBrowser,
        shortcut: "Alt+S",
        onSelected: shell.openSkinBrowser,
      ),
      NativeMenuItem(
        label: shell.localizations.onlineSkinBrowser,
        onSelected: shell.openOnlineSkinBrowser,
      ),
      const NativeMenuItem.separator(),
      for (final info in shell.skins.sortedSkins)
        NativeMenuItem(
          label: info.name,
          checked: info.name == active,
          onSelected: () => shell.skins.apply(info),
        ),
      ...colorThemes(shell),
    ];
  }

  /// The active modern skin's color themes, to choose from, below a
  /// separator (the classic player's Color Themes menu); empty when the skin has fewer
  /// than two.
  static List<NativeMenuItem> colorThemes(AmpedShell shell) {
    final skin = shell.skin.wasabi;
    if (skin == null || skin.colorThemes.sets.length < 2) return const [];
    final themes = skin.colorThemes;
    final current = themes.current?.name;
    return [
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.colorThemes,
        children: [
          for (final name in themes.names)
            NativeMenuItem(
              label: name,
              checked: name == current,
              onSelected: () =>
                  wasabiSelectColorTheme(skin, shell.wasabiHost, name),
            ),
          const NativeMenuItem.separator(),
          NativeMenuItem(
            label: shell.localizations.shareColorThemes,
            checkable: true,
            checked: wasabiSharesColorTheme(shell.wasabiHost),
            onSelected: () => wasabiShareColorTheme(
              shell.wasabiHost,
              share: !wasabiSharesColorTheme(shell.wasabiHost),
            ),
          ),
        ],
      ),
    ];
  }

  /// The Dock icon menu (taskbar, launcher, dock).
  static List<NativeMenuItem> dock(AmpedShell shell) {
    final player = shell.player;
    return [
      NativeMenuItem(
        label: shell.localizations.windows,
        children: [
          NativeMenuItem(
            label: shell.localizations.equalizer,
            checked: shell.isOpen(SkinWindow.eq),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.eq,
              !shell.isOpen(SkinWindow.eq),
            ),
          ),
          NativeMenuItem(
            label: shell.localizations.playlistEditor,
            checked: shell.isOpen(SkinWindow.pl),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.pl,
              !shell.isOpen(SkinWindow.pl),
            ),
          ),
          NativeMenuItem(
            label: shell.localizations.video,
            checked: shell.isOpen(SkinWindow.video),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.video,
              !shell.isOpen(SkinWindow.video),
            ),
          ),
          NativeMenuItem(
            label: shell.localizations.library,
            checked: shell.isOpen(SkinWindow.library),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.library,
              !shell.isOpen(SkinWindow.library),
            ),
          ),
          NativeMenuItem(
            label: shell.localizations.visualization,
            checked: shell.isOpen(SkinWindow.vis),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.vis,
              !shell.isOpen(SkinWindow.vis),
            ),
          ),
          NativeMenuItem(
            label: shell.localizations.albumArt,
            checked: shell.isOpen(SkinWindow.albumArt),
            checkable: true,
            onSelected: () => shell.setOpen(
              SkinWindow.albumArt,
              !shell.isOpen(SkinWindow.albumArt),
            ),
          ),
          // The panels the active modern skin brings of its own.
          for (final (window, container) in shell.skin.windows)
            NativeMenuItem(
              label: container.name.trim().isEmpty
                  ? container.id
                  : container.name,
              checked: shell.isOpen(window),
              checkable: true,
              onSelected: () => shell.toggle(window),
            ),
        ],
      ),
      NativeMenuItem(
        label: shell.localizations.skins,
        children: skins(shell),
      ),
      NativeMenuItem(
        label: shell.localizations.settings,
        children: [
          NativeMenuItem(
            label: shell.localizations.preferences,
            onSelected: () => shell.dialogManager.open(AmpedDialog.preferences),
          ),
          NativeMenuItem(
            label: shell.localizations.alwaysOnTop,
            checked: player.alwaysOnTop,
            mixed: player.videoAlwaysOnTop,
            checkable: true,
            onSelected: player.toggleAlwaysOnTop,
          ),
          NativeMenuItem(
            label: shell.localizations.playbackNotifications,
            checked: shell.notifications.enabled,
            checkable: true,
            onSelected: shell.notifications.toggle,
          ),
          NativeMenuItem(
            label: shell.localizations.nativeNotifications,
            checked: shell.notifications.native,
            checkable: true,
            onSelected: shell.notifications.toggleNative,
          ),
          NativeMenuItem(
            label: shell.localizations.showNotification,
            onSelected: shell.notifications.showNow,
          ),
          NativeMenuItem(
            label: shell.localizations.windowShade,
            checked: player.allShadesShaded,
            checkable: true,
            onSelected: player.toggleAllShades,
          ),
          NativeMenuItem(
            label: shell.localizations.doubleSizeMode,
            checked: player.uiScale == 2,
            checkable: true,
            onSelected: () => player.setUiScale(player.uiScale == 2 ? 1 : 2),
          ),
        ],
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.quit,
        onSelected: () => unawaited(shell.quit()),
      ),
    ];
  }

  /// The Equalizer presets button menu (`Eq.cpp`).
  static List<NativeMenuItem> eqPresets(AmpedShell shell) {
    return [
      NativeMenuItem(
        label: shell.localizations.load,
        children: [
          NativeMenuItem(
            label: shell.localizations.preset,
            onSelected: () => shell.openPresets(PresetsMode.load),
          ),
          NativeMenuItem(
            label: shell.localizations.autoLoadPreset,
            onSelected: () =>
                shell.openPresets(PresetsMode.load, autoLoad: true),
          ),
          NativeMenuItem(
            label: shell.localizations.fromEqf,
            onSelected: () => unawaited(shell.files.loadEqf()),
          ),
        ],
      ),
      NativeMenuItem(
        label: shell.localizations.save,
        children: [
          NativeMenuItem(
            label: shell.localizations.preset,
            onSelected: () => shell.openPresets(PresetsMode.save),
          ),
          NativeMenuItem(
            label: shell.localizations.autoLoadPreset,
            onSelected: () =>
                shell.openPresets(PresetsMode.save, autoLoad: true),
          ),
          NativeMenuItem(
            label: shell.localizations.toEqf,
            onSelected: () => unawaited(shell.files.saveEqf()),
          ),
        ],
      ),
      NativeMenuItem(
        label: shell.localizations.delete,
        children: [
          NativeMenuItem(
            label: shell.localizations.preset,
            onSelected: () => shell.openPresets(PresetsMode.delete),
          ),
          NativeMenuItem(
            label: shell.localizations.autoLoadPreset,
            onSelected: () =>
                shell.openPresets(PresetsMode.delete, autoLoad: true),
          ),
        ],
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.reset,
        onSelected: () => shell.player.applyEq(31, List.filled(10, 31)),
      ),
    ];
  }

  /// The playlist's per-track menu (right-click in the list; the original's
  /// "Context" menu).
  static List<NativeMenuItem> playlistContext(AmpedShell shell) {
    final playlist = shell.player.playlist;
    final selected = playlist.selected;
    final hasSelection = selected.isNotEmpty;
    return [
      NativeMenuItem(
        label: shell.localizations.playItems,
        shortcut: "Enter",
        onSelected: hasSelection
            ? () => unawaited(shell.player.playIndex(selected.reduce(min)))
            : null,
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.removeItems,
        shortcut: "Delete",
        onSelected: hasSelection ? playlist.removeSelected : null,
      ),
      NativeMenuItem(
        label: shell.localizations.cropFiles,
        shortcut: "Ctrl+Delete",
        onSelected: hasSelection ? playlist.crop : null,
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.editMetadata,
        shortcut: "Shift+E",
        onSelected: hasSelection ? shell.requests.showEditMetadata : null,
      ),
      NativeMenuItem(
        label: shell.localizations.viewFileInfo,
        shortcut: "Alt+3",
        onSelected: hasSelection ? shell.requests.showSelectedFileInfo : null,
      ),
      NativeMenuItem(
        label: shell.localizations.playlistEntry,
        shortcut: "Ctrl+E",
      ),
      NativeMenuItem(
        label: shell.localizations.bookmarkItems,
        shortcut: "Ctrl+Alt+B",
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.rateItems,
        children: [
          const NativeMenuItem(label: "*****"),
          const NativeMenuItem(label: "****"),
          const NativeMenuItem(label: "***"),
          const NativeMenuItem(label: "**"),
          const NativeMenuItem(label: "*"),
          NativeMenuItem(label: shell.localizations.noRating),
        ],
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: shell.localizations.exploreItemsFolder,
        shortcut: "Ctrl+F",
        onSelected: hasSelection ? shell.files.exploreSelection : null,
      ),
    ];
  }

  /// The Media Library's menu for the tracks at [paths] (right-click): what
  /// the playlist's context menu offers for files, plus playing and
  /// enqueueing them and removing them from the library. The labels are
  /// singular for one track and plural for several.
  static List<NativeMenuItem> libraryContext(
    AmpedShell shell,
    List<String> paths,
  ) {
    final localizations = shell.localizations;
    final count = paths.length;
    final books = paths.isNotEmpty && paths.every(shell.sources.isBook);
    // Tracks of a server are no files here: there is nothing to remove from
    // the library, tag, rate or reveal, and the playlists are generated from
    // the local library.
    final fromServer = paths.any(SourceLocation.isSource);
    return [
      NativeMenuItem(
        label: localizations.mlMenuPlay(count),
        shortcut: "Enter",
        onSelected: () => unawaited(shell.files.openPaths(paths, play: true)),
      ),
      NativeMenuItem(
        label: localizations.mlMenuEnqueue(count),
        onSelected: () => unawaited(shell.files.openPaths(paths, play: false)),
      ),
      if (!fromServer) const NativeMenuItem.separator(),
      if (!fromServer)
        NativeMenuItem(
          label: localizations.mlMenuGenerate,
          children: [
            for (final (criterion, label) in [
              (PlaylistCriterion.similar, localizations.mlGenerateSimilar),
              (PlaylistCriterion.artist, localizations.mlGenerateSameArtist),
              (PlaylistCriterion.album, localizations.mlGenerateSameAlbum),
              (PlaylistCriterion.genre, localizations.mlGenerateSameGenre),
            ])
              NativeMenuItem(
                label: label,
                onSelected: () => unawaited(
                  shell.files.openPaths(
                    PlaylistGenerator.generate(
                      library: shell.library.tracks,
                      seeds: [
                        for (final track in shell.library.tracks)
                          if (paths.contains(track.path)) track,
                      ],
                      criterion: criterion,
                    ),
                    play: true,
                  ),
                ),
              ),
          ],
        ),
      NativeMenuItem(
        label: localizations.mlMenuAddToPlaylist,
        children: [
          NativeMenuItem(
            label: localizations.mlMenuNewPlaylist,
            onSelected: () =>
                unawaited(shell.libraryActions.addToSavedPlaylist(null, paths)),
          ),
          if (shell.savedPlaylists.playlists.isNotEmpty)
            const NativeMenuItem.separator(),
          for (final playlist in shell.savedPlaylists.playlists)
            NativeMenuItem(
              label: playlist.name,
              onSelected: () => unawaited(
                shell.libraryActions.addToSavedPlaylist(playlist.id, paths),
              ),
            ),
        ],
      ),
      if (paths.isNotEmpty && paths.every(shell.sources.isPodcast)) ...[
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: books
              ? localizations.mlMenuMarkBookPlayed(count)
              : localizations.mlMenuMarkPlayed(count),
          onSelected: () =>
              unawaited(shell.sources.markPlayed(paths, played: true)),
        ),
        NativeMenuItem(
          label: books
              ? localizations.mlMenuMarkBookUnplayed(count)
              : localizations.mlMenuMarkUnplayed(count),
          onSelected: () =>
              unawaited(shell.sources.markPlayed(paths, played: false)),
        ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: books
              ? localizations.mlMenuRefreshBooks
              : localizations.mlMenuRefreshPodcast,
          onSelected: () {
            for (final id in LibrarySourceManager.sourcesOf(paths)) {
              unawaited(shell.sources.reload(id));
            }
          },
        ),
      ],
      if (!fromServer) ...[
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: localizations.mlMenuRemove(count),
          onSelected: () => unawaited(shell.library.remove(paths)),
        ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: localizations.mlMenuEditMetadata(count),
          onSelected: () => shell.requests.showEditMetadataFor(paths),
        ),
        NativeMenuItem(
          label: localizations.mlMenuFileInfo(count),
          onSelected: () => shell.requests.showFileInfo(paths),
        ),
        NativeMenuItem(label: localizations.mlMenuBookmark(count)),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: localizations.mlMenuRate(count),
          children: [
            const NativeMenuItem(label: "*****"),
            const NativeMenuItem(label: "****"),
            const NativeMenuItem(label: "***"),
            const NativeMenuItem(label: "**"),
            const NativeMenuItem(label: "*"),
            NativeMenuItem(label: localizations.noRating),
          ],
        ),
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: localizations.mlMenuExplore(count),
          onSelected: () => shell.files.revealPaths(paths),
        ),
      ],
    ];
  }

  /// The context menu of a saved playlist in the Media Library's tree.
  static List<NativeMenuItem> savedPlaylistContext(AmpedShell shell, int id) {
    final localizations = shell.localizations;
    return [
      NativeMenuItem(
        label: localizations.mlMenuPlay(2),
        onSelected: () =>
            unawaited(shell.libraryActions.openSavedPlaylist(id, play: true)),
      ),
      NativeMenuItem(
        label: localizations.mlMenuEnqueue(2),
        onSelected: () =>
            unawaited(shell.libraryActions.openSavedPlaylist(id, play: false)),
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: localizations.mlMenuRenamePlaylist,
        onSelected: () =>
            unawaited(shell.libraryActions.renameSavedPlaylist(id)),
      ),
      NativeMenuItem(
        label: localizations.mlMenuDuplicatePlaylist,
        onSelected: () =>
            unawaited(shell.libraryActions.duplicateSavedPlaylist(id)),
      ),
      NativeMenuItem(
        label: localizations.mlMenuExportPlaylist,
        onSelected: () =>
            unawaited(shell.libraryActions.exportSavedPlaylist(id)),
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: localizations.mlMenuDeletePlaylist,
        onSelected: () =>
            unawaited(shell.libraryActions.deleteSavedPlaylist(id)),
      ),
    ];
  }

  /// The playlist ADD button's menu (right-click).
  static List<NativeMenuItem> playlistAdd(AmpedShell shell) => [
    NativeMenuItem(
      label: shell.localizations.addFiles,
      shortcut: "L",
      onSelected: () => unawaited(shell.files.addFiles()),
    ),
    NativeMenuItem(
      label: shell.localizations.addFolder,
      shortcut: "Shift+L",
      onSelected: () => unawaited(shell.files.addFolder()),
    ),
    NativeMenuItem(
      label: shell.localizations.addUrl,
      shortcut: "Ctrl+L",
      onSelected: () => unawaited(shell.files.addUrl()),
    ),
  ];

  /// The playlist REM button's menu (right-click).
  static List<NativeMenuItem> playlistRemove(
    Playlist playlist,
    AppLocalizations localizations,
  ) => [
    NativeMenuItem(
      label: localizations.removeSelected,
      shortcut: "Delete",
      onSelected: playlist.removeSelected,
    ),
    NativeMenuItem(
      label: localizations.cropSelected,
      shortcut: "Ctrl+Delete",
      onSelected: playlist.crop,
    ),
    NativeMenuItem(
      label: localizations.clearPlaylist,
      shortcut: "Ctrl+Shift+Delete",
      onSelected: playlist.clear,
    ),
    NativeMenuItem(
      label: localizations.remove,
      children: playlistRemoveMisc(playlist, localizations),
    ),
  ];

  /// The REM button's "Remove..." menu (its top option, and a submenu of
  /// [playlistRemove]).
  static List<NativeMenuItem> playlistRemoveMisc(
    Playlist playlist,
    AppLocalizations localizations,
  ) => [
    NativeMenuItem(
      label: localizations.removeMissingFiles,
      shortcut: "Alt+Delete",
      onSelected: playlist.removeDeadFiles,
    ),
    NativeMenuItem(label: localizations.physicallyRemoveFiles),
  ];

  /// The playlist SEL button's menu (right-click).
  static List<NativeMenuItem> playlistSelect(
    Playlist playlist,
    AppLocalizations localizations,
  ) => [
    NativeMenuItem(
      label: localizations.selectAll,
      shortcut: "Ctrl+A",
      onSelected: playlist.selectAll,
    ),
    NativeMenuItem(
      label: localizations.selectNone,
      onSelected: playlist.selectNone,
    ),
    NativeMenuItem(
      label: localizations.invertSelection,
      shortcut: "Ctrl+I",
      onSelected: playlist.invertSelection,
    ),
  ];

  /// The playlist MISC button's menu (right-click).
  static List<NativeMenuItem> playlistMisc(
    Playlist playlist,
    AppLocalizations localizations, {
    VoidCallback? onFileInfo,
  }) => [
    NativeMenuItem(
      label: localizations.fileInfo,
      children: playlistFileInfo(localizations, onFileInfo: onFileInfo),
    ),
    NativeMenuItem(
      label: localizations.sort,
      children: playlistSort(playlist, localizations),
    ),
    NativeMenuItem(
      label: localizations.misc,
      children: playlistMiscOptions(playlist, localizations),
    ),
  ];

  /// The playlist MISC button's "Sort" menu.
  static List<NativeMenuItem> playlistSort(
    Playlist playlist,
    AppLocalizations localizations,
  ) => [
    NativeMenuItem(
      label: localizations.sortByTitle,
      shortcut: "Ctrl+Shift+1",
      onSelected: () => unawaited(playlist.sort(PlaylistSort.title)),
    ),
    NativeMenuItem(
      label: localizations.sortByFilename,
      shortcut: "Ctrl+Shift+2",
      onSelected: () => unawaited(playlist.sort(PlaylistSort.fileName)),
    ),
    NativeMenuItem(
      label: localizations.sortByPath,
      shortcut: "Ctrl+Shift+3",
      onSelected: () => unawaited(playlist.sort(PlaylistSort.path)),
    ),
    NativeMenuItem(
      label: localizations.sortByArtist,
      onSelected: () => unawaited(playlist.sort(PlaylistSort.artist)),
    ),
    NativeMenuItem(
      label: localizations.sortByAlbum,
      onSelected: () => unawaited(playlist.sort(PlaylistSort.album)),
    ),
    NativeMenuItem(
      label: localizations.sortByArtistAlbum,
      onSelected: () => unawaited(playlist.sort(PlaylistSort.artistAlbum)),
    ),
    const NativeMenuItem.separator(),
    NativeMenuItem(
      label: localizations.reverseList,
      shortcut: "Ctrl+R",
      onSelected: playlist.reverse,
    ),
    NativeMenuItem(
      label: localizations.randomizeList,
      shortcut: "Ctrl+Shift+R",
      onSelected: playlist.randomize,
    ),
  ];

  /// The playlist MISC button's "File info" menu.
  static List<NativeMenuItem> playlistFileInfo(
    AppLocalizations localizations, {
    VoidCallback? onFileInfo,
  }) => [
    NativeMenuItem(
      label: localizations.fileInfoEllipsis,
      shortcut: "Alt+3",
      onSelected: onFileInfo,
    ),
    NativeMenuItem(
      label: localizations.playlistEntryEllipsis,
      shortcut: "Ctrl+E",
    ),
  ];

  /// The playlist MISC button's "Misc" menu.
  static List<NativeMenuItem> playlistMiscOptions(
    Playlist playlist,
    AppLocalizations localizations,
  ) => [
    NativeMenuItem(
      label: localizations.generateHtmlPlaylist,
      shortcut: "Ctrl+Alt+G",
    ),
    const NativeMenuItem.separator(),
    NativeMenuItem(
      label: localizations.rebuildTitles,
      shortcut: "Ctrl+Alt+E",
      onSelected: () => unawaited(playlist.rebuildSelectedTitles()),
    ),
  ];

  /// The playlist LIST button's menu (right-click).
  static List<NativeMenuItem> playlistList(AmpedShell shell) => [
    NativeMenuItem(
      label: shell.localizations.openPlaylist,
      shortcut: "Ctrl+O",
      onSelected: () => unawaited(shell.files.loadList()),
    ),
    NativeMenuItem(
      label: shell.localizations.savePlaylist,
      shortcut: "Ctrl+S",
      onSelected: () => unawaited(shell.files.saveList()),
    ),
    NativeMenuItem(
      label: shell.localizations.newPlaylist,
      shortcut: "Ctrl+N",
      onSelected: shell.player.playlist.clear,
    ),
    // PE_ListOfLists: the saved playlists, to load one into the player.
    if (shell.savedPlaylists.playlists.isNotEmpty)
      const NativeMenuItem.separator(),
    for (final playlist in shell.savedPlaylists.playlists)
      NativeMenuItem(
        label: playlist.name,
        onSelected: () => unawaited(
          shell.libraryActions.openSavedPlaylist(playlist.id, play: true),
        ),
      ),
  ];

  /// The Album Art window's right-click menu (gen_classicart
  /// `IDR_MENU1`): with [lockAspect] for the classic window, whose shape
  /// setting it toggles; a modern skin's `<AlbumArt>` decides that itself.
  /// The video's menu (right-click on the picture, the Video window's misc
  /// button): the audio and subtitle tracks, fullscreen, the classic
  /// window's zoom and always on top.
  static List<NativeMenuItem> video(AmpedShell shell) {
    final l = shell.localizations;
    final playing = shell.player.videoPlaying;
    // The zoom buttons are the classic skin's; a modern skin has its own.
    final windowed =
        shell.dialogManager.windows[AmpedDialog.video] == null &&
        !shell.skin.hasModernLook(SkinWindow.video);
    return [
      ...videoTracks(shell),
      if (windowed) ...[
        NativeMenuItem(
          label: "1x",
          enabled: playing,
          onSelected: () => shell.zoomVideo(1),
        ),
        NativeMenuItem(
          label: "2x",
          enabled: playing,
          onSelected: () => shell.zoomVideo(2),
        ),
      ],
      const NativeMenuItem.separator(),
      cast(shell),
      NativeMenuItem(
        // With every window on top the entry is the plain one, and turns
        // it off; otherwise it is for this window alone.
        label: shell.player.alwaysOnTop
            ? l.alwaysOnTop
            : l.alwaysOnTopVideoOnly,
        checkable: true,
        checked: shell.player.alwaysOnTop || shell.player.videoAlwaysOnTop,
        onSelected: shell.player.toggleVideoAlwaysOnTop,
      ),
    ];
  }

  /// The audio and subtitle tracks of the playing video, and fullscreen.
  static List<NativeMenuItem> videoTracks(AmpedShell shell) {
    final l = shell.localizations;
    final video = shell.player.video;
    final audio = video?.audioTracks ?? const <TrackOption>[];
    final subtitles = video?.subtitles ?? const <TrackOption>[];
    String name(TrackOption track, int index) =>
        track.label(l.videoSubtitleTrack(index + 1));
    return [
      NativeMenuItem(
        label: l.videoAudio,
        enabled: audio.length > 1,
        children: [
          for (var i = 0; i < audio.length; i++)
            NativeMenuItem(
              label: name(audio[i], i),
              checkable: true,
              checked: video?.audioId == audio[i].id,
              onSelected: () => video?.selectAudio(audio[i].id),
            ),
        ],
      ),
      NativeMenuItem(
        label: l.videoSubtitles,
        enabled: subtitles.isNotEmpty,
        children: [
          NativeMenuItem(
            label: l.videoSubtitlesOff,
            checkable: true,
            checked: video?.subtitleId == null,
            onSelected: () => video?.selectSubtitle(null),
          ),
          for (var i = 0; i < subtitles.length; i++)
            NativeMenuItem(
              label: subtitles[i].supported
                  ? name(subtitles[i], i)
                  : "${name(subtitles[i], i)} (${l.videoTrackUnsupported})",
              enabled: subtitles[i].supported,
              checkable: true,
              checked: video?.subtitleId == subtitles[i].id,
              onSelected: () => video?.selectSubtitle(subtitles[i].id),
            ),
        ],
      ),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        label: l.fullscreen,
        enabled: shell.player.videoPlaying,
        onSelected: shell.toggleVideoFullscreen,
      ),
    ];
  }

  static List<NativeMenuItem> albumArt(
    AmpedShell shell, {
    required bool lockAspect,
  }) {
    final localizations = shell.localizations;
    final entry = shell.player.playlist.currentEntry;
    return [
      NativeMenuItem(
        label: localizations.refreshAlbumArt,
        onSelected: shell.albumArt.refresh,
      ),
      NativeMenuItem(
        label: localizations.getAlbumArt,
        enabled: shell.covers.canGetAlbumArt,
        onSelected: shell.covers.getAlbumArt,
      ),
      NativeMenuItem(
        label: localizations.openAlbumArtFolder,
        enabled: entry != null && !entry.isUrl,
        onSelected: shell.covers.openAlbumArtFolder,
      ),
      if (lockAspect) ...[
        const NativeMenuItem.separator(),
        NativeMenuItem(
          label: localizations.lockAspectRatio,
          checkable: true,
          checked: shell.albumArtLockAspect,
          onSelected: shell.toggleAlbumArtLockAspect,
        ),
      ],
    ];
  }

  /// The menu label of [window].
  static String windowLabel(
    SkinWindow window,
    AppLocalizations localizations,
  ) => switch (window) {
    SkinWindow.main => localizations.mainWindow,
    SkinWindow.eq => localizations.equalizer,
    SkinWindow.pl => localizations.playlistEditor,
    SkinWindow.video => localizations.video,
    SkinWindow.library => localizations.mediaLibrary,
    SkinWindow.vis => localizations.visualization,
    SkinWindow.thinger => localizations.thinger,
    SkinWindow.albumArt => localizations.albumArt,
    SkinWindow.notifier => "Notifier",
    _ => localizations.skinWindow,
  };

  static String windowTitle(
    SkinWindow window,
    AppLocalizations localizations,
  ) => switch (window) {
    SkinWindow.main => localizations.appName,
    SkinWindow.eq => localizations.ampedEqualizerWindow,
    SkinWindow.pl => localizations.ampedPlaylistWindow,
    SkinWindow.video => localizations.ampedVideoWindow,
    SkinWindow.library => localizations.ampedLibraryWindow,
    SkinWindow.vis => localizations.ampedVisualizationWindow,
    SkinWindow.thinger => localizations.ampedThingerWindow,
    SkinWindow.albumArt => localizations.ampedAlbumArtWindow,
    SkinWindow.notifier => "Amped Notifier",
    _ => localizations.skinWindow,
  };

  /// The visualization menu (clutterbar \"V\" button). The analyzer is
  /// simulated, so its modes are placeholders.
  static List<NativeMenuItem> visualization(AmpedShell shell) {
    return [
      NativeMenuItem(
        label: shell.localizations.startStopPlugin,
        shortcut: "Ctrl+Shift+K",
        onSelected: shell.toggleVisPlugin,
      ),
      NativeMenuItem(
        label: shell.localizations.configurePlugin,
        shortcut: "Alt+K",
        onSelected: shell.configureVisPlugin,
      ),
      NativeMenuItem(
        label: shell.localizations.selectPlugin,
        shortcut: "Ctrl+K",
        onSelected: shell.selectVisPlugin,
      ),
    ];
  }

  /// The options menu of a classic skin's visualization window: the
  /// Visualization menu with the module navigation of the classic player's base skin.
  static List<NativeMenuItem> visualizerOptions(AmpedShell shell) {
    final localizations = shell.localizations;
    return [
      NativeMenuItem(
        label: localizations.previous,
        onSelected: shell.vis.previous,
      ),
      NativeMenuItem(label: localizations.next, onSelected: shell.vis.next),
      NativeMenuItem(
        label: localizations.random,
        checkable: true,
        checked: shell.vis.random,
        onSelected: () => shell.vis.setRandom(!shell.vis.random),
      ),
      NativeMenuItem(
        label: localizations.fullscreen,
        shortcut: "Alt+Enter",
        onSelected: shell.vis.toggleFullscreen,
      ),
      const NativeMenuItem.separator(),
      ...visualization(shell),
    ];
  }
}
