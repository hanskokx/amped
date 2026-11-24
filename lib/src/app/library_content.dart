import "dart:async";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";

import "../library/library_view.dart";
import "../library/watch_folders.dart";

import "../skin/skin_views.dart";
import "amped_menus.dart";
import "amped_shell.dart";

/// The Media Library's contents, wired to the shell: the same in a classic
/// skin's library window and in a modern skin's `guid:ml` component, in the
/// active skin's list colours.
class LibraryContent extends StatelessWidget {
  const LibraryContent({
    required this.shell,
    this.classicFrame = false,
    super.key,
  });

  final AmpedShell shell;

  /// Whether the content sits in the base skin's own window frame (which a
  /// modern skin without a library window gets): then it has that skin's
  /// colors and scrollbars, not the modern skin's.
  final bool classicFrame;

  /// The list colours of the active skin: a classic skin's playlist editor
  /// colours, or a modern skin's `wasabi.list.*` (Wasabi 5's `pledit.*`
  /// names as a fallback).
  PlEditConfig _colors(ClassicSkinData base) =>
      colorsFor(shell, base, classicFrame: classicFrame);

  /// [_colors] for [shell]'s active skin, for what else wears its colors.
  static PlEditConfig colorsFor(
    AmpedShell shell,
    ClassicSkinData base, {
    bool classicFrame = false,
  }) {
    final modern = shell.skin.wasabi;
    if (modern == null || classicFrame) return base.pledit;
    Color pick(List<String> ids, Color fallback) {
      for (final id in ids) {
        if (modern.color(id) case final color?) return color;
      }
      return fallback;
    }

    // A selection color that is gray (or none) is replaced by the theme's
    // accent, in a lightness that the list text reads on.
    final vivid = modern.accentColor;
    final accent = vivid == null
        ? null
        : HSLColor.fromColor(vivid)
              .withLightness(
                HSLColor.fromColor(vivid).lightness.clamp(0.3, 0.5),
              )
              .toColor();
    final text = pick([
      "wasabi.list.text",
      "pledit.text",
      "studio.list.text",
    ], base.pledit.normal);
    final background = pick([
      "wasabi.list.background",
      "pledit.background",
      "studio.list.background",
      // A Wasabi 3 palette without a list background: the LCD's, which its
      // list text colour is made for.
      if (modern.color("studio.list.text") != null) "studio.textBar.background",
    ], base.pledit.normalBg);
    final chosen = pick([
      "wasabi.list.text.selected.background",
      "pledit.text.selected.background",
      "studio.list.item.selected",
    ], base.pledit.selectedBg);
    final selectedBackground =
        accent != null && HSLColor.fromColor(chosen).saturation < 0.15
        ? accent
        : chosen;
    return base.pledit.copyWith(
      // A skin's own list colours can be too close to each other to read
      // in a list this size.
      normal: wasabiLegible(text, background),
      // The library paints highlighted rows in `selectedBg` with `current`,
      // so that is the skin's selected-text color, which must read on it.
      current: wasabiLegible(
        pick([
          "wasabi.list.text.selected",
          "studio.list.item.selected.fg",
          "wasabi.list.text.current",
          "pledit.text.current",
        ], base.pledit.current),
        selectedBackground,
      ),
      normalBg: background,
      selectedBg: selectedBackground,
      // The skin's default list font (`arial`); the system Arial when the
      // skin defines none of its own.
      fontName: modern.fontFamily("arial"),
    );
  }

  /// Draws the library's buttons with the modern skin's own button pieces,
  /// when it has them.
  Widget Function(String, bool, VoidCallback)? _buttonBuilder() {
    final modern = shell.skin.wasabi;
    if (modern == null || classicFrame || !WasabiGridButton.supported(modern)) {
      return null;
    }
    return (label, enabled, onPressed) => WasabiGridButton(
      skin: modern,
      label: label,
      enabled: enabled,
      onPressed: onPressed,
      height: 22,
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = shell.skins.current.classicData;
    // The library's presses are its own, in a modern skin's component as in a
    // classic window: they never drag the window or open its main menu.
    return SkinNoWindowDrag(
      child: ListenableBuilder(
        // A modern skin's color theme changes the colors it is drawn in.
        listenable: Listenable.merge([
          shell.sources,
          ?shell.skin.wasabi?.colorThemes,
        ]),
        builder: (context, _) => OfflineFolders(
          notifier: shell.watchFolders,
          child: LibraryView(
            library: shell.library,
            sections: shell.sources.sections(
              localLabel: shell.localizations.mlSourceLocal,
              allVideosLabel: shell.localizations.mlSourceAllVideos,
              moviesLabel: shell.localizations.mlSourceMovies,
              showsLabel: shell.localizations.mlSourceShows,
            ),
            colors: _colors(skin),
            buttonBuilder: _buttonBuilder(),
            // A modern skin has no scrollbar bitmaps: the list draws its own.
            skin: shell.skin is! ModernSkin || classicFrame ? skin : null,
            localizations: shell.localizations,
            onPlay: (paths) =>
                unawaited(shell.files.openPaths(paths, play: true)),
            onEnqueue: (paths) =>
                unawaited(shell.files.openPaths(paths, play: false)),
            onAddMedia: () => unawaited(shell.libraryActions.addToLibrary()),
            onPlayAt: (path, at) => unawaited(shell.files.playAt(path, at)),
            coverLoader: shell.covers.readCoverBytes,
            onOpenArtwork: shell.requests.showArtwork,
            settings: shell.libraryViewSettings,
            onSettingsChanged: shell.saveLibraryViewSettings,
            playlists: shell.savedPlaylists,
            playStats: shell.playStats,
            onSavePlaylist: () =>
                unawaited(shell.libraryActions.saveCurrentPlaylistToLibrary()),
            onNewPlaylist: () =>
                unawaited(shell.libraryActions.newSavedPlaylist()),
            onRemoveFromPlaylist: (id, indices) =>
                unawaited(shell.savedPlaylists.removeAt(id, indices)),
            onMoveInPlaylist: (id, indices, to) =>
                unawaited(shell.savedPlaylists.move(id, indices, to)),
            onDropOnPlaylist: (id, paths) =>
                unawaited(shell.libraryActions.addToSavedPlaylist(id, paths)),
            onImportPlaylists: () =>
                unawaited(shell.libraryActions.importPlaylists()),
            onPlaylistMenu: (id) => shell.showMenu(
              AmpedMenus.savedPlaylistContext(shell, id),
              null,
            ),
            onContextMenu: (paths) =>
                shell.showMenu(AmpedMenus.libraryContext(shell, paths), null),
          ),
        ),
      ),
    );
  }
}
