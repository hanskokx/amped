import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "../skin/skin_views.dart";
import "amped_menus.dart";
import "amped_shell.dart";

/// Inside the classic Album Art window (gen_classicart `art_dlgproc`): the
/// playing item's cover on the skin's list background, kept to its shape
/// unless "Lock aspect ratio" is off. A double-click opens the file's
/// folder; a right-click opens the window's menu.
class AlbumArtView extends StatefulWidget {
  const AlbumArtView({required this.shell, super.key});

  final AmpedShell shell;

  @override
  State<AlbumArtView> createState() => _AlbumArtViewState();
}

class _AlbumArtViewState extends State<AlbumArtView> {
  int? _menuPointer;

  AmpedShell get _shell => widget.shell;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kSecondaryButton) return;
    // The window would open the main menu on release otherwise.
    SkinSecondaryClaim.claim(event);
    _menuPointer = event.pointer;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _menuPointer) return;
    _menuPointer = null;
    _shell.showMenu(AmpedMenus.albumArt(_shell, lockAspect: true), null);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      child: GestureDetector(
        onDoubleTap: _shell.covers.openAlbumArtFolder,
        child: ListenableBuilder(
          listenable: Listenable.merge([_shell, _shell.albumArt]),
          builder: (context, _) => ColoredBox(
            // WADLG_ITEMBG: the playlist's background without a genex.bmp.
            color: _shell.skins.current.classicData.pledit.normalBg,
            child: SizedBox.expand(
              child: RawImage(
                image: _shell.albumArt.image,
                fit: _shell.albumArtLockAspect ? BoxFit.contain : BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
