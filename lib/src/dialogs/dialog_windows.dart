import "dart:async";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart" show baseSkinName;
import "package:material_ui/material_ui.dart";

import "../app/amped_dialog.dart";
import "../app/amped_shell.dart";
import "../app/dialog_manager.dart";
import "../app/fullscreen_video.dart";
import "../app/library_content.dart";
import "../features/preferences/screens/preferences_screen.dart";
import "../main_window/presets_window.dart";
import "../skin/skin_views.dart";
import "../tags/tag_io.dart";
import "../tags/tag_lookup.dart";
import "../vis/vis_config_page.dart";
import "../vis/vis_window.dart";
import "about_window.dart";
import "artwork_page.dart";
import "dialog_theme.dart";
import "edit_metadata_page.dart";
import "file_info_page.dart";
import "playlist_search_page.dart";
import "remote_login_page.dart";
import "resume_page.dart";
import "update_page.dart";

/// The contents of a native-framed dialog window.
class DialogWindowContent extends StatelessWidget {
  const DialogWindowContent({
    required this.shell,
    required this.dialog,
    super.key,
  });

  final AmpedShell shell;
  final AmpedDialog dialog;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (dialog == AmpedDialog.vis) {
      return VisWindowContent(host: shell.vis, fullscreen: true);
    }
    if (dialog == AmpedDialog.video) {
      return FullscreenVideo(shell: shell);
    }
    final Widget body = switch (dialog) {
      AmpedDialog.presets ||
      AmpedDialog.searchPlaylist ||
      AmpedDialog.artwork => _SkinnedDialog(
        shell: shell,
        dialog: dialog,
      ),
      AmpedDialog.preferences => PreferencesScreen(shell: shell),
      AmpedDialog.about => AboutWindow(
        skin: shell.skin.wasabi,
        host: shell.wasabiHost,
      ),
      AmpedDialog.vis || AmpedDialog.video => const SizedBox(),
      AmpedDialog.visConfig => VisConfigPage(
        module: shell.vis.module,
        onClose: () => shell.dialogManager.close(AmpedDialog.visConfig),
      ),
      AmpedDialog.editMetadata => EditMetadataPage(
        key: ObjectKey(shell.requests.editMetadataPaths),
        paths: shell.requests.editMetadataPaths,
        read: readAllFileTagsInBackground,
        save: shell.tags.saveFileTags,
        onClose: () => shell.dialogManager.close(AmpedDialog.editMetadata),
      ),
      AmpedDialog.remoteLogin => RemoteLoginPage(
        key: ObjectKey(shell.requests.remoteLoginRequest),
        request: shell.requests.remoteLoginRequest,
        onAnswer: shell.requests.answerRemoteLogin,
      ),
      AmpedDialog.resume => ResumePage(
        key: ObjectKey(shell.requests.resumeRequest),
        title: shell.requests.resumeRequest?.title ?? "",
        position: shell.requests.resumeRequest?.position ?? Duration.zero,
        onAnswer: (resume) => shell.requests.answerResume(resume: resume),
      ),
      AmpedDialog.update => UpdatePage(
        key: ObjectKey(shell.requests.update),
        release: shell.requests.update,
        onAnswer: (download) => shell.requests.answerUpdate(download: download),
      ),
      AmpedDialog.fileInfo => FileInfoPage(
        key: ValueKey(shell.requests.fileInfoPath),
        path: shell.requests.fileInfoPath ?? "",
        read: readFileTagsInBackground,
        readPictures: readFilePicturesInBackground,
        save: shell.tags.saveFileTags,
        openImage: shell.tags.openArtworkImage,
        storeImage: shell.covers.storeCover,
        exportImage: shell.tags.saveArtworkAs,
        onClose: shell.requests.closeFileInfo,
        lookup: lookUpTags,
      ),
    };
    return ListenableBuilder(
      listenable: Listenable.merge([
        shell,
        ?shell.skin.wasabi?.colorThemes,
      ]),
      builder: (context, _) => _app(
        localizations,
        _skinTheme(shell),
        body,
      ),
    );
  }

  /// [dialogTheme] in the active skin's list colors (a classic skin's
  /// playlist editor colors), which a modern skin's color theme changes.
  static ThemeData _skinTheme(AmpedShell shell) {
    final colors = LibraryContent.colorsFor(
      shell,
      shell.skins.current.classicData,
    );
    return dialogTheme(
      background: colors.normalBg,
      accent: shell.skin.wasabi?.accentColor ?? colors.selectedBg,
      defaultSkin: shell.skins.active.name == baseSkinName,
    );
  }

  Widget _app(AppLocalizations localizations, ThemeData theme, Widget body) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(localizations.localeName),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: theme,
      home: Scaffold(
        backgroundColor: dialog.skinned ? const Color(0x00000000) : null,
        body: body,
      ),
    );
  }
}

/// A skinned dialog in the skin's frame (`gen.bmp`), with the skin's colours,
/// without the OS title bar.
class _SkinnedDialog extends StatelessWidget {
  const _SkinnedDialog({required this.shell, required this.dialog});

  final AmpedShell shell;
  final AmpedDialog dialog;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => _SkinnedDialogFrame(
        shell: shell,
        dialog: dialog,
      ),
    );
  }
}

class _SkinnedDialogFrame extends StatelessWidget {
  const _SkinnedDialogFrame({required this.shell, required this.dialog});

  final AmpedShell shell;
  final AmpedDialog dialog;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final skin = shell.skins.current.classicData;
    final size = shell.dialogManager.sizeOf(dialog);
    final scale = shell.player.uiScale;
    void close() => shell.dialogManager.close(dialog);
    final autoLoad = shell.presetsAutoLoad;
    final frame = SkinnedDialogFrame(
      skin: skin,
      title: switch (dialog) {
        AmpedDialog.searchPlaylist => localizations.jumpToFileTitle,
        AmpedDialog.artwork => DialogManager.fitTitle(
          shell.requests.artwork?.title ?? localizations.artworkTitle,
          size.width,
        ),
        _ =>
          autoLoad
              ? localizations.ampedAutoLoadPresetsTitle
              : localizations.ampedPresetsTitle,
      },
      size: size,
      onClose: close,
      onDragStart: () => shell.dialogManager.startDrag(dialog),
      onDragUpdate: () => shell.dialogManager.updateDrag(dialog),
      onResizeStart: () => shell.dialogManager.startResize(dialog),
      onResizeUpdate: () => shell.dialogManager.updateResize(dialog),
      child: switch (dialog) {
        // Pressing the picture drags the window, as in the Album Art
        // window.
        AmpedDialog.artwork => SkinDragTarget(
          cursor: skin.cursor(SkinCursor.titleBar),
          onStart: (_) => shell.dialogManager.startDrag(dialog),
          onUpdate: (_) => shell.dialogManager.updateDrag(dialog),
          child: ArtworkPage(
            image: shell.requests.artwork?.image,
            // WADLG_ITEMBG, like the Album Art window.
            background: skin.pledit.normalBg,
          ),
        ),
        AmpedDialog.searchPlaylist => PlaylistSearchPage(
          playlist: shell.player.playlist,
          skin: skin,
          onPlay: (index) => unawaited(shell.player.playIndex(index)),
          onClose: close,
        ),
        _ => PresetsWindow(
          key: ValueKey(autoLoad),
          mode: shell.presetsMode,
          skin: skin,
          autoLoad: autoLoad,
          player: shell.player,
          onClose: close,
        ),
      },
    );
    // At the skin's pixel size, scaled up like the skinned windows.
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size * scale,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: frame,
          ),
        ),
      ),
    );
  }
}
