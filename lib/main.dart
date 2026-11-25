import "dart:async";
import "dart:io";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:material_ui/material_ui.dart";
import "package:window_dock/window_dock.dart";

import "src/app/album_art_view.dart";
import "src/app/amped_menus.dart";
import "src/app/amped_shell.dart";
import "src/app/library_content.dart";
import "src/app/modern_window.dart";
import "src/app/notification_view.dart";
import "src/app/skinned_window.dart";
import "src/app/video_view.dart";
import "src/dialogs/dialog_windows.dart";
import "src/library/track_drag_out.dart";
import "src/platform/file_types.dart";
import "src/platform/single_instance.dart";
import "src/player/player_state.dart";
import "src/player/video_engine.dart";
import "src/skin/modern_preview_cache.dart";
import "src/skin/skin_manager.dart";
import "src/skin/skin_views.dart";
import "src/vis/vis_window.dart";

Future<void> main(List<String> arguments) => runAmped(arguments);

/// Loads the saved state and starts the app: one engine, with every Amped
/// window a native window created through Flutter's windowing API.
Future<void> runAmped([List<String> arguments = const []]) async {
  enableFlutterWindowing();
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogging.init();

  // Skin previews unpacked by an earlier run that didn't get to clean up.
  unawaited(ModernPreviewCache.purgeStale());
  final Locale locale = basicLocaleListResolution(
    WidgetsBinding.instance.platformDispatcher.locales,
    AppLocalizations.supportedLocales,
  );
  final AppLocalizations localizations = await AppLocalizations.delegate.load(
    locale,
  );
  // On Windows and Linux files arrive on the command line (macOS sends them
  // to the runner), and a second launch hands them to the first.
  LaunchRequest? launch;
  SingleInstance? instance;
  if (Platform.isWindows || Platform.isLinux) {
    launch = parseLaunchArguments(arguments);
    instance = await SingleInstance.claim(launch);
    if (instance == null) exit(0);
  }

  SkinPointerClaim.claim = WindowDragArea.claimPointer;
  WasabiPointerClaim.claim = WindowDragArea.claimPointer;

  final PlayerState player = PlayerState(
    windowShade: await PlayerState.loadWindowShade(),
    alwaysOnTop: await PlayerState.loadAlwaysOnTop(),
    mainOpen: await PlayerState.loadMainOpen(),
    eqOpen: await PlayerState.loadEqOpen(),
    eqShade: await PlayerState.loadEqShade(),
    plOpen: await PlayerState.loadPlOpen(),
    plShade: await PlayerState.loadPlShade(),
    videoOpen: await PlayerState.loadVideoOpen(),
    libraryOpen: await PlayerState.loadLibraryOpen(),
    albumArtOpen: await PlayerState.loadAlbumArtOpen(),
    timeRemaining: await PlayerState.loadTimeRemaining(),
    uiScale: await PlayerState.loadUiScale(),
    video: MediaKitVideoEngine(),
  );
  await player.loadVideoOptions();
  await player.loadEqualizer();
  await player.loadClassicVis();
  await player.loadCrossfade();

  unawaited(player.engine.init());
  final SkinManager skins = await SkinManager.load();
  final AmpedShell shell = await AmpedShell.load(
    player: player,
    skins: skins,
    localizations: localizations,
    launch: launch,
    instance: instance,
  );
  runWidget(AmpedApp(shell: shell, locale: locale));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    shell.initializeSystemTrayMenu();
  });
  unawaited(registerFileTypes());
}

class AmpedApp extends StatelessWidget {
  const AmpedApp({required this.shell, required this.locale, super.key});

  final AmpedShell shell;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => AppWindowViews(
        windows: [
          for (final MapEntry(key: window, value: controller)
              in shell.windowState.controllers.entries)
            AppWindowView(
              key: ValueKey(window),
              controller: controller,
              child: WidgetsApp(
                color: const Color(0xFF000000),
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, _) => TrackDropOutline(
                  dragOut: shell.trackDragOut,
                  window: window,
                  color: () => shell.skins.current.classicData.pledit.current,
                  child: _SkinnedWindowContent(shell: shell, window: window),
                ),
              ),
            ),
          for (final MapEntry(key: dialog, value: controller)
              in shell.dialogManager.windows.entries)
            AppWindowView(
              key: ValueKey(dialog),
              controller: controller,
              child: WidgetsApp(
                color: const Color(0xFF000000),
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, _) =>
                    DialogWindowContent(shell: shell, dialog: dialog),
              ),
            ),
        ],
      ),
    );
  }
}

class _SkinnedWindowContent extends StatelessWidget {
  const _SkinnedWindowContent({required this.shell, required this.window});

  final AmpedShell shell;
  final SkinWindow window;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([shell.player, shell.skins]),
      builder: (context, _) {
        if (window == SkinWindow.notifier &&
            !shell.skin.hasModernLook(window)) {
          return NotificationView(shell: shell);
        }
        if (shell.skin.hasModernLook(window)) {
          return ModernWindowView(shell: shell, window: window);
        }
        final host = shell.classic;
        final player = shell.player;
        final shaded = switch (window) {
          SkinWindow.main => player.windowShade,
          SkinWindow.eq => player.eqShade,
          SkinWindow.pl => player.plShade,
          _ => false,
        };
        final content = switch (window) {
          SkinWindow.main => MainWindowView(host: host),
          SkinWindow.eq => EqWindow(host: host),
          SkinWindow.pl => PlWindow(host: host),
          SkinWindow.video => ClassicVideoWindow(shell: shell),
          SkinWindow.library => LibraryWindow(
            host: host,
            title: shell.localizations.ampedLibraryWindow,
            content: LibraryContent(shell: shell, classicFrame: true),
          ),
          SkinWindow.vis => VisWindow(
            host: host,
            content: VisWindowContent(host: shell.vis, fullscreen: false),
            title: shell.localizations.visualizerTitle,
            labels: (
              previous: shell.localizations.previous,
              next: shell.localizations.next,
              random: shell.localizations.random,
              fullscreen: shell.localizations.fullscreen,
              options: shell.localizations.options,
            ),
            random: shell.vis.random,
            onPrevious: shell.vis.previous,
            onNext: shell.vis.next,
            onRandom: () => shell.vis.setRandom(!shell.vis.random),
            onFullscreen: shell.vis.toggleFullscreen,
            onOptions: (position) => shell.showMenu(
              AmpedMenus.visualizerOptions(shell),
              position,
            ),
          ),
          SkinWindow.albumArt => AlbumArtWindow(
            host: host,
            title: shell.localizations.albumArt,
            content: AlbumArtView(shell: shell),
          ),
          // Only modern skins have a Thinger or a notifier, and only they
          // define windows of their own.
          _ => null,
        };
        if (content == null) return const SizedBox.shrink();
        return SkinnedWindow(
          shell: shell,
          window: window,
          cursor: classicWindowCursor(window, shaded: shaded),
          child: content,
        );
      },
    );
  }
}
