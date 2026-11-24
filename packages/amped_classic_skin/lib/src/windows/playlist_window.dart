import "dart:async";
import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

const double _plShadeHeight = 14;
const double _listLeft = 12;

/// Row stride (`pe_fontheight` = 13 for the base-skin Arial 12).
const double _rowStride = 13;

/// First row's top in song-list-local coordinates (absolute 22 - 20).
const double _rowsLocalTop = 2;

/// The playlist font's GDI height (`PE_FONTSIZE`): the cell, ascent plus
/// descent, which gives the 13 px rows.
const double _plFontSize = 12;

/// [seconds] as the playlist shows times (`draw_pe.cpp`): `m:ss` under an
/// hour, else `h:mm:ss` with the hours uncapped (no days), so 25 days of
/// music reads `600:51:24`.
String formatPlaylistTime(int seconds) {
  final s = (seconds % 60).toString().padLeft(2, "0");
  if (seconds < 3600) return "${seconds ~/ 60}:$s";
  final m = (seconds ~/ 60 % 60).toString().padLeft(2, "0");
  return "${seconds ~/ 3600}:$m:$s";
}

/// Draws `text.bmp` glyphs as they are, background and all, as the
/// original copies them (`BitBlt` with `SRCCOPY`): their colour is the
/// skin's.
class _SkinFont {
  _SkinFont(this.font);

  final TextFont font;
  static final Paint _paint = Paint()..filterQuality = FilterQuality.none;

  /// Draws [text] left-to-right at ([x], [y]); `clipWidth` clips the line.
  void draw(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double? clipWidth,
  }) {
    if (text.isEmpty) return;
    canvas.save();
    if (clipWidth != null) {
      canvas.clipRect(Rect.fromLTWH(x, y, clipWidth, TextFont.charHeight));
    }
    var xp = x;
    for (final ch in text.characters) {
      canvas.drawImageRect(
        font.image,
        font.glyphRect(ch),
        Rect.fromLTWH(xp, y, TextFont.charWidth, TextFont.charHeight),
        _paint,
      );
      xp += TextFont.charWidth;
    }
    canvas.restore();
  }
}

/// The ClassicPlaylist Editor window, rendered from `pledit.bmp` (`draw_pe.cpp`),
/// with the controls of `Peui.cpp`. Resizable from the bottom-right corner in
/// 25×29 steps.
class PlWindow extends StatelessWidget {
  const PlWindow({required this.host, super.key});

  final ClassicHost host;

  @override
  Widget build(BuildContext context) {
    final skin = host.skin!;
    final shade = host.player.plShade;
    return shade
        ? _PlShadeLayout(host: host, skin: skin)
        : _PlMainLayout(host: host, skin: skin);
  }
}

/// The first visible row that puts row [index] as close to the middle of
/// [visibleRows] rows as a list of [length] rows allows.
@visibleForTesting
int centeredOffset(int index, int visibleRows, int length) {
  final last = max(0, length - visibleRows);
  return (index - visibleRows ~/ 2).clamp(0, last);
}

class _PlMainLayout extends StatefulWidget {
  const _PlMainLayout({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  State<_PlMainLayout> createState() => _PlMainLayoutState();
}

class _PlMainLayoutState extends State<_PlMainLayout>
    implements PlaylistNavigator {
  int _offset = 0;
  bool _scrolling = false;

  /// The row a Shift-click (or Shift+arrow) extends the selection from.
  int _anchor = 0;

  /// The keyboard cursor row (the last clicked or arrowed-to row).
  int _cursor = 0;
  Duration? _lastClickTime;
  int _lastClickIndex = -1;
  _SkinFont? _skinFont;

  /// The playing row last seen, so a track change can be told from a rebuild.
  int _lastCurrent = -1;

  /// Set when a double click in this list starts the track: that row is
  /// already under the pointer, so the list stays put.
  bool _playedFromList = false;

  Size get _size => widget.host.baseSize(SkinWindow.pl);

  int get _visibleRows =>
      ((_size.height - 20 - 38 - _rowsLocalTop) / _rowStride).floor();

  _SkinFont get _font =>
      _skinFont ??= _SkinFont(TextFont(widget.skin.image("text.bmp")!));

  @override
  void didUpdateWidget(_PlMainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skin != widget.skin) _skinFont = null;
  }

  ClassicPlaylist get _playlist => widget.host.player.playlist;

  @override
  void initState() {
    super.initState();
    widget.host.playlistNavigator = this;
  }

  @override
  void dispose() {
    if (identical(widget.host.playlistNavigator, this)) {
      widget.host.playlistNavigator = null;
    }
    super.dispose();
  }

  /// Scrolls so row [index] is visible.
  void _reveal(int index) {
    if (index < _offset) {
      setState(() => _offset = index);
    } else if (index >= _offset + _visibleRows) {
      setState(() => _offset = index - _visibleRows + 1);
    }
  }

  @override
  void moveCursor(int delta, {required bool extend}) {
    if (_playlist.isEmpty) return;
    final index = (_cursor + delta).clamp(0, _playlist.length - 1);
    _setCursor(index, extend: extend);
  }

  @override
  void cursorTo(int index, {required bool extend}) {
    if (_playlist.isEmpty) return;
    _setCursor(index.clamp(0, _playlist.length - 1), extend: extend);
  }

  void _setCursor(int index, {required bool extend}) {
    _cursor = index;
    if (extend) {
      final from = min(_anchor, index);
      final to = max(_anchor, index);
      _playlist.select({for (var i = from; i <= to; i++) i});
    } else {
      _anchor = index;
      _playlist.select({index});
    }
    _reveal(index);
  }

  @override
  void page(int pages) => _scrollBy(pages * max(1, _visibleRows - 1));

  /// A click in the list (`do_lb`): selects the row, Cmd/Ctrl-click toggles
  /// it, Shift-click selects the range from the last clicked row, and a
  /// double click plays it.
  void _onListPress(Offset local) {
    final row = ((local.dy - _rowsLocalTop) / _rowStride).floor();
    if (row < 0 || row >= _visibleRows) return;
    final index = _offset + row;
    if (index >= _playlist.length) {
      _playlist.selectNone();
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final doubleClick =
        index == _lastClickIndex &&
        _lastClickTime != null &&
        now - _lastClickTime! < kDoubleTapTimeout;
    _lastClickTime = doubleClick ? null : now;
    _lastClickIndex = index;
    if (doubleClick) {
      _playedFromList = true;
      unawaited(widget.host.player.playIndex(index));
      return;
    }
    _cursor = index;
    if (keyboard.isShiftPressed) {
      final from = min(_anchor, index);
      final to = max(_anchor, index);
      _playlist.select({for (var i = from; i <= to; i++) i});
      return;
    }
    _anchor = index;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      final selection = Set.of(_playlist.selected);
      if (!selection.remove(index)) selection.add(index);
      _playlist.select(selection);
    } else {
      _playlist.select({index});
    }
  }

  void _scrollTo(double y) {
    final t = _playlist.length - _visibleRows;
    if (t < 1) return;
    final trackHeight = _size.height - 20 - 38 - 18;
    final pos = ((y - 9) / trackHeight * t).round().clamp(0, t);
    if (pos != _offset) setState(() => _offset = pos);
  }

  /// Scrolls the list by [lines] rows (`ID_PE_SCROLLUP`/`ID_PE_SCROLLDOWN`).
  void _scrollBy(int lines) {
    final t = _playlist.length - _visibleRows;
    if (t < 1) return;
    final pos = (_offset + lines).clamp(0, t);
    if (pos != _offset) setState(() => _offset = pos);
  }

  /// The pointer of a right-click in the list, whose release opens the
  /// per-track menu.
  int? _menuPointer;

  /// A right-click in the list (`PE_OnRButtonUp`): an unselected row
  /// becomes the selection (Cmd/Ctrl toggles it instead); a click below the
  /// last row clears the selection. The per-track menu opens on release.
  void _onListRightPress(Offset local) {
    final index = _offset + ((local.dy - _rowsLocalTop) / _rowStride).floor();
    final keyboard = HardwareKeyboard.instance;
    final toggle = keyboard.isControlPressed || keyboard.isMetaPressed;
    final selection = Set.of(_playlist.selected);
    final onRow = index >= 0 && index < _playlist.length;
    if (!toggle && !(onRow && selection.contains(index))) selection.clear();
    if (onRow) {
      if (toggle && selection.contains(index)) {
        selection.remove(index);
      } else {
        selection.add(index);
      }
    }
    _playlist.select(selection);
  }

  /// "selected/total" playing time (`draw_pe_infostr`); a "+" marks totals
  /// that include tracks of unknown length.
  String _infoString() {
    final adding = _playlist.addingCount;
    if (adding != null) return "ADDING $adding";
    final entries = _playlist.entries;
    String total(Iterable<ClassicPlaylistEntry> tracks) {
      var seconds = 0;
      var unknown = false;
      for (final track in tracks) {
        final duration = track.duration;
        if (duration == null) {
          unknown = true;
        } else {
          seconds += duration.inSeconds;
        }
      }
      return "${formatPlaylistTime(seconds)}${unknown ? "+" : ""}";
    }

    final selected = [for (final i in _playlist.selected) entries[i]];
    return "${total(selected)}/${total(entries)}";
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final skin = widget.skin;
    final player = host.player;
    final pledit = skin.image("pledit.bmp")!;
    final width = _size.width;
    final height = _size.height;
    final bodyHeight = height - 20 - 38;
    final elapsed = player.elapsedSec;
    final shown = player.timeRemaining
        ? (player.durationSec - elapsed).clamp(0, 1 << 30)
        : elapsed;
    final normal = skin.cursor(SkinCursor.plNormal);
    final playlist = _playlist;
    // Keep the scroll position valid as entries come and go.
    final current = playlist.current;
    if (current != _lastCurrent) {
      _lastCurrent = current;
      if (_playedFromList) {
        _playedFromList = false;
      } else if (current >= 0 && current < playlist.length) {
        _offset = centeredOffset(current, _visibleRows, playlist.length);
      }
    }
    _offset = _offset.clamp(0, max(0, playlist.length - _visibleRows));
    return SkinWheelScroll(
      onScroll: _scrollBy,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: skin.overlay
                  ? const Color(0x00000000)
                  : const Color(0xFF000000),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(width, 20),
              painter: _PlTitlebarPainter(
                image: pledit,
                active: WindowActivity.of(context),
              ),
            ),
          ),
          CursorZone(
            skin: skin,
            rect: Rect.fromLTRB(0, 0, width, 14),
            cursor: SkinCursor.plTitleBar,
          ),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            height: bodyHeight,
            child: CustomPaint(
              size: Size(width, bodyHeight),
              painter: _PlBodyPainter(pledit),
            ),
          ),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            height: bodyHeight,
            child: CustomPaint(
              size: Size(width, bodyHeight),
              painter: _PlSongListPainter(
                skin: skin,
                entries: playlist.entries,
                current: playlist.current,
                offset: _offset,
                selected: playlist.selected,
                dragging: _scrolling,
              ),
            ),
          ),
          // The song list (`do_lb`).
          Positioned(
            top: 20,
            left: _listLeft,
            width: width - 20 - _listLeft,
            height: bodyHeight,
            child: Listener(
              onPointerDown: (event) {
                if (event.buttons != kSecondaryButton) return;
                SkinSecondaryClaim.claim(event);
                _menuPointer = event.pointer;
                _onListRightPress(
                  event.localPosition + const Offset(_listLeft, 0),
                );
              },
              onPointerUp: (event) {
                if (event.pointer != _menuPointer) return;
                _menuPointer = null;
                host.showMenu(ClassicMenu.playlistContext, null);
              },
              child: SkinDragTarget(
                cursor: normal,
                onStart: (p) => _onListPress(p + const Offset(_listLeft, 0)),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // The scrollbar (`do_vscroll`).
          Positioned(
            top: 20,
            left: width - 15,
            width: 8,
            height: bodyHeight,
            child: SkinDragTarget(
              cursor: skin.cursor(SkinCursor.plVScroll),
              onStart: (p) {
                setState(() => _scrolling = true);
                _scrollTo(p.dy);
              },
              onUpdate: (p) => _scrollTo(p.dy),
              onEnd: (_) => setState(() => _scrolling = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 38,
            child: CustomPaint(
              size: Size(width, 38),
              painter: _PlBottomPainter(pledit),
            ),
          ),
          // The mini visualization while the main window is closed, in a
          // wide enough editor (`hPLVisWindow`).
          if (width >= 350)
            Positioned(
              left: width - 150 - 75,
              top: height - 26,
              width: 75,
              height: 18,
              child: _PlMiniVis(host: host, colors: skin.visColors),
            ),
          Positioned(
            left: width - 143,
            top: height - 28,
            child: CustomPaint(
              size: const Size(90, 6),
              painter: _PlInfoPainter(font: _font, text: _infoString()),
            ),
          ),
          // Time display: click toggles elapsed/remaining (`do_timedisplay`).
          Positioned(
            left: width - 87,
            top: height - 18,
            width: 34,
            height: 9,
            child: SkinDragTarget(
              cursor: normal,
              onStart: (_) => player.toggleTimeRemaining(),
              child: Padding(
                padding: const EdgeInsets.only(left: 1, top: 3),
                child: CustomPaint(
                  size: const Size(32, 6),
                  painter: _PlTimePainter(
                    font: _font,
                    minutes: shown ~/ 60,
                    seconds: shown % 60,
                  ),
                ),
              ),
            ),
          ),
          // The mini transport (`do_mb`): prev, play, pause, stop, next, eject.
          for (final (i, left, w) in const [
            (0, 0.0, 7.0),
            (1, 7.0, 10.0),
            (2, 17.0, 10.0),
            (3, 27.0, 9.0),
            (4, 36.0, 9.0),
            (5, 45.0, 9.0),
          ])
            Positioned(
              left: width - 144 + left,
              top: height - 15,
              child: SkinButton(
                size: Size(w, 8),
                cursor: normal,
                onPressed: [
                  player.prev,
                  player.togglePlay,
                  player.pause,
                  player.stop,
                  player.next,
                  null,
                ][i],
                builder: (context, pressed) => const SizedBox.shrink(),
              ),
            ),
          PlPopupButton(
            image: pledit,
            left: 14,
            height: height,
            bar: 48,
            normalX: 0,
            pressedX: 23,
            rows: const [149, 130, 111],
            cursor: normal,
            host: host,
            contextMenu: ClassicMenu.playlistAdd,
            actions: [
              () => unawaited(host.addFiles()),
              () => unawaited(host.addFolder()),
              () => unawaited(host.addUrl()),
            ],
          ),
          PlPopupButton(
            image: pledit,
            left: 43,
            height: height,
            bar: 100,
            normalX: 54,
            pressedX: 77,
            rows: const [149, 130, 111, 168],
            cursor: normal,
            host: host,
            contextMenu: ClassicMenu.playlistRemove,
            actions: [
              playlist.removeSelected,
              playlist.crop,
              playlist.clear,
              () => host.showMenu(
                ClassicMenu.playlistRemoveMisc,
                host.toGlobal(
                  SkinWindow.pl,
                  Offset(64, height - 30 - 18 * 3),
                ),
              ),
            ],
          ),
          PlPopupButton(
            image: pledit,
            left: 72,
            height: height,
            bar: 150,
            normalX: 104,
            pressedX: 127,
            rows: const [149, 130, 111],
            cursor: normal,
            host: host,
            contextMenu: ClassicMenu.playlistSelect,
            actions: [
              playlist.selectAll,
              playlist.selectNone,
              playlist.invertSelection,
            ],
          ),
          PlPopupButton(
            image: pledit,
            left: 101,
            height: height,
            bar: 200,
            normalX: 154,
            pressedX: 177,
            rows: const [149, 130, 111],
            cursor: normal,
            host: host,
            contextMenu: ClassicMenu.playlistMisc,
            // Bottom to top, as in pledit.bmp: misc options (y 149), file
            // info (y 130), sort list (y 111). Peui.cpp `do_miscbut`.
            actions: [
              () => host.showMenu(
                ClassicMenu.playlistMiscOptions,
                host.toGlobal(SkinWindow.pl, Offset(122, height - 30)),
              ),
              () => host.showMenu(
                ClassicMenu.playlistFileInfo,
                host.toGlobal(
                  SkinWindow.pl,
                  Offset(122, height - 30 - 18),
                ),
              ),
              () => host.showMenu(
                ClassicMenu.playlistSort,
                host.toGlobal(
                  SkinWindow.pl,
                  Offset(122, height - 30 - 36),
                ),
              ),
            ],
          ),
          PlPopupButton(
            image: pledit,
            left: width - 44,
            height: height,
            bar: 250,
            normalX: 204,
            pressedX: 227,
            rows: const [149, 130, 111],
            cursor: normal,
            host: host,
            contextMenu: ClassicMenu.playlistList,
            actions: [
              () => unawaited(host.loadList()),
              () => unawaited(host.saveList()),
              playlist.clear,
            ],
          ),
          _PlTitleButtons(host: host, skin: skin, width: width, shade: false),
          _PlResizeHandle(
            host: host,
            skin: skin,
            width: width,
            height: height,
            shade: false,
          ),
        ],
      ),
    );
  }
}

/// The playlist editor's mini visualization (`hPLVisWindow`): the classic
/// visualization's first 72 columns at (2, 0) of its 75×18 hot spot,
/// drawn only while the main window is closed. A click cycles the mode
/// while playing (a double-click toggles the visualization window); a right-click opens the Visualization menu.
class _PlMiniVis extends StatefulWidget {
  const _PlMiniVis({required this.host, required this.colors});

  final ClassicHost host;
  final List<int> colors;

  @override
  State<_PlMiniVis> createState() => _PlMiniVisState();
}

class _PlMiniVisState extends State<_PlMiniVis> {
  int? _menuPointer;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final colors = widget.colors;
    final player = host.player;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) {
          SkinSecondaryClaim.claim(event);
          _menuPointer = event.pointer;
        } else if (event.buttons == kPrimaryButton && player.playing) {
          SkinPointerClaim.claim?.call(event);
          host.clickClassicVis();
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _menuPointer) return;
        _menuPointer = null;
        host.showMenu(ClassicMenu.visualization, null);
      },
      child: ListenableBuilder(
        listenable: host,
        builder: (context, _) => host.isWindowVisible(SkinWindow.main)
            ? const SizedBox.expand()
            : Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: ClipRect(
                    child: SizedBox(
                      width: 72,
                      height: 16,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxWidth: 76,
                        child: ClassicVisView(
                          player: player,
                          colors: colors,
                          windowShade: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The 20 px titlebar strip (`draw_pe_tbar`), tiling `pledit.bmp` row 0/21.
class _PlTitlebarPainter extends CustomPainter {
  const _PlTitlebarPainter({required this.image, required this.active});

  final ui.Image image;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final state = active ? 0.0 : 21.0;
    final w = size.width;
    var xp = 0.0;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, state, 25, 20),
      Rect.fromLTWH(xp, 0, 25, 20),
      paint,
    );
    xp += 25;
    var nt = ((w - 150) / 25).floor();
    if ((nt & 1) != 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(127, state, 12, 20),
        Rect.fromLTWH(xp, 0, 12, 20),
        paint,
      );
      xp += 12;
    }
    nt ~/= 2;
    while (nt > 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(127, state, 25, 20),
        Rect.fromLTWH(xp, 0, 25, 20),
        paint,
      );
      xp += 25;
      nt--;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(26, state, 100, 20),
      Rect.fromLTWH(xp, 0, 100, 20),
      paint,
    );
    xp += 100;
    nt = ((w - 150) / 25).floor();
    if ((nt & 1) != 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(127, state, 13, 20),
        Rect.fromLTWH(xp, 0, 13, 20),
        paint,
      );
      xp += 13;
    }
    nt ~/= 2;
    while (nt > 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(127, state, 25, 20),
        Rect.fromLTWH(xp, 0, 25, 20),
        paint,
      );
      xp += 25;
      nt--;
    }
    final rem = (w - 150) % 25;
    if (rem > 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(127, state, 25, 20),
        Rect.fromLTWH(xp, 0, rem, 20),
        paint,
      );
      xp += rem;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(153, state, 25, 20),
      Rect.fromLTWH(xp, 0, 25, 20),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlTitlebarPainter oldDelegate) {
    return oldDelegate.active != active;
  }
}

/// The 14 px windowshade titlebar strip (`draw_pe_tbar` shade path).
class _PlShadeTitlebarPainter extends CustomPainter {
  const _PlShadeTitlebarPainter({required this.image, required this.active});

  final ui.Image image;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final state = active ? 57.0 : 42.0;
    final w = size.width;
    var xp = 0.0;
    canvas.drawImageRect(
      image,
      const Rect.fromLTWH(72, 42, 25, 14),
      Rect.fromLTWH(xp, 0, 25, 14),
      paint,
    );
    xp += 25;
    var n = ((w - 50) / 25).floor() - 1;
    while (n > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(72, 57, 25, 14),
        Rect.fromLTWH(xp, 0, 25, 14),
        paint,
      );
      xp += 25;
      n--;
    }
    final rem = (w - 50) % 25;
    if (rem > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(72, 57, 24, 14),
        Rect.fromLTWH(xp, 0, rem, 14),
        paint,
      );
      xp += rem;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(99, state, 50, 14),
      Rect.fromLTWH(xp, 0, 50, 14),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlShadeTitlebarPainter oldDelegate) {
    return oldDelegate.active != active;
  }
}

/// The left/right 29 px body border tiles (`draw_pl`).
class _PlBodyPainter extends CustomPainter {
  const _PlBodyPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final w = size.width;
    var yp = 0.0;
    var count = (size.height / 29).floor();
    while (count > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(0, 42, 12, 29),
        Rect.fromLTWH(0, yp, 12, 29),
        paint,
      );
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(31, 42, 5, 29),
        Rect.fromLTWH(w - 20, yp, 5, 29),
        paint,
      );
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(44, 42, 7, 29),
        Rect.fromLTWH(w - 7, yp, 7, 29),
        paint,
      );
      yp += 29;
      count--;
    }
    final rem = size.height % 29;
    if (rem > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(0, 42, 12, 29),
        Rect.fromLTWH(0, yp, 12, rem),
        paint,
      );
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(31, 42, 5, 29),
        Rect.fromLTWH(w - 20, yp, 5, rem),
        paint,
      );
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(44, 42, 7, 29),
        Rect.fromLTWH(w - 7, yp, 7, rem),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlBodyPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

/// The 38 px bottom bar (`draw_pl`), including the five button-column backs.
class _PlBottomPainter extends CustomPainter {
  const _PlBottomPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final w = size.width;
    canvas.drawImageRect(
      image,
      const Rect.fromLTWH(0, 72, 125, 38),
      const Rect.fromLTWH(0, 0, 125, 38),
      paint,
    );
    var xp = 125.0;
    final stretch = w - 125 - 150;
    var count = (stretch / 25).floor();
    var wide = false;
    if (count >= 3) {
      count -= 3;
      wide = true;
    }
    while (count > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(179, 0, 25, 38),
        Rect.fromLTWH(xp, 0, 25, 38),
        paint,
      );
      xp += 25;
      count--;
    }
    final rem = stretch % 25;
    if (rem > 0) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(179, 0, 25, 38),
        Rect.fromLTWH(xp, 0, rem, 38),
        paint,
      );
      xp += rem;
    }
    if (wide) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(205, 0, 75, 38),
        Rect.fromLTWH(xp, 0, 75, 38),
        paint,
      );
      xp += 75;
    }
    canvas.drawImageRect(
      image,
      const Rect.fromLTWH(126, 72, 150, 38),
      Rect.fromLTWH(xp, 0, 150, 38),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlBottomPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

/// Draws the playlist's scrollbar (`draw_pe_vslide`) in a [trackH] tall
/// track at [x], with the thumb [yp] from the top.
void _drawScrollbar(
  Canvas canvas,
  ui.Image pledit,
  double x,
  double trackH,
  int yp, {
  required bool dragging,
}) {
  const slidH = 18;
  final paint = Paint()..filterQuality = FilterQuality.none;
  var y = 0;
  for (; y < yp - 28; y += 29) {
    canvas.drawImageRect(
      pledit,
      const Rect.fromLTWH(36, 42, 8, 29),
      Rect.fromLTWH(x, y.toDouble(), 8, 29),
      paint,
    );
  }
  var oy = y + 29;
  if (slidH + yp > oy) oy += 29;
  if (y < yp) {
    canvas.drawImageRect(
      pledit,
      Rect.fromLTWH(36, 42, 8, (yp - y).toDouble()),
      Rect.fromLTWH(x, y.toDouble(), 8, (yp - y).toDouble()),
      paint,
    );
  }
  canvas.drawImageRect(
    pledit,
    Rect.fromLTWH(dragging ? 61.0 : 52.0, 53, 8, 18),
    Rect.fromLTWH(x, yp.toDouble(), 8, 18),
    paint,
  );
  y = yp + 18;
  if (y < oy && y < trackH) {
    final h = y < trackH - 29 ? oy - y : trackH - y;
    canvas.drawImageRect(
      pledit,
      Rect.fromLTWH(36, (42 + 29 - (oy - y)).toDouble(), 8, h.toDouble()),
      Rect.fromLTWH(x, y.toDouble(), 8, h.toDouble()),
      paint,
    );
  }
  y = oy;
  for (; y < trackH; y += 29) {
    final h = y < trackH - 29 ? 29.0 : (trackH - y).toDouble();
    canvas.drawImageRect(
      pledit,
      const Rect.fromLTWH(36, 42, 8, 29),
      Rect.fromLTWH(x, y.toDouble(), 8, h),
      paint,
    );
  }
}

/// A scrollbar in the skin's playlist style, for a list scrolled by
/// [controller]: drag the thumb, or press the track to page. Horizontal, it
/// is the same picture turned on its side.
class SkinScrollbar extends StatefulWidget {
  const SkinScrollbar({
    required this.skin,
    required this.controller,
    this.axis = Axis.vertical,
    super.key,
  });

  final ClassicSkinData skin;
  final ScrollController controller;

  /// Which way the list scrolls.
  final Axis axis;

  /// The scrollbar's width (its height, when horizontal).
  static const double width = 8;

  @override
  State<SkinScrollbar> createState() => _SkinScrollbarState();
}

class _SkinScrollbarState extends State<SkinScrollbar> {
  static const double _thumb = 18;

  /// The pointer's offset from the thumb's start while dragging it.
  double? _grab;

  bool get _horizontal => widget.axis == Axis.horizontal;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SkinScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The list's position, once it has been laid out.
  ScrollPosition? get _position {
    if (!widget.controller.hasClients) return null;
    final position = widget.controller.position;
    return position.hasContentDimensions ? position : null;
  }

  double _thumbTop(double trackH) {
    final position = _position;
    if (position == null || position.maxScrollExtent <= 0) return 0;
    final fraction = (position.pixels / position.maxScrollExtent).clamp(0, 1);
    return ((trackH - _thumb) * fraction).floorToDouble();
  }

  void _dragTo(double y, double trackH) {
    final position = _position;
    final grab = _grab;
    if (position == null || grab == null || trackH <= _thumb) return;
    final fraction = ((y - grab) / (trackH - _thumb)).clamp(0.0, 1.0);
    widget.controller.jumpTo(position.maxScrollExtent * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final pledit = widget.skin.image("pledit.bmp")!;
    // The list is laid out after this: look again when it has been.
    if (_position == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _position != null) setState(() {});
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = _horizontal;
        final trackH = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final top = _thumbTop(trackH);
        double along(Offset offset) => horizontal ? offset.dx : offset.dy;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            // Pressing the scrollbar never drags the window.
            SkinPointerClaim.claim?.call(event);
            final position = _position;
            if (event.buttons != kPrimaryButton || position == null) return;
            final y = along(event.localPosition);
            if (y < top) {
              widget.controller.jumpTo(
                (position.pixels - position.viewportDimension).clamp(
                  0,
                  position.maxScrollExtent,
                ),
              );
            } else if (y > top + _thumb) {
              widget.controller.jumpTo(
                (position.pixels + position.viewportDimension).clamp(
                  0,
                  position.maxScrollExtent,
                ),
              );
            } else {
              setState(() => _grab = y - top);
            }
          },
          onPointerMove: (event) => _dragTo(along(event.localPosition), trackH),
          onPointerUp: (_) => setState(() => _grab = null),
          onPointerCancel: (_) => setState(() => _grab = null),
          child: MouseRegion(
            cursor: widget.skin.cursor(
              horizontal ? SkinCursor.posbar : SkinCursor.plVScroll,
            ),
            child: CustomPaint(
              size: horizontal
                  ? Size(trackH, SkinScrollbar.width)
                  : Size(SkinScrollbar.width, trackH),
              painter: _SkinScrollbarPainter(
                pledit: pledit,
                trackH: trackH,
                thumbTop: top.round(),
                dragging: _grab != null,
                horizontal: horizontal,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkinScrollbarPainter extends CustomPainter {
  const _SkinScrollbarPainter({
    required this.pledit,
    required this.trackH,
    required this.thumbTop,
    required this.dragging,
    required this.horizontal,
  });

  final ui.Image pledit;
  final double trackH;
  final int thumbTop;
  final bool dragging;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    // On its side: the vertical drawing with its two axes swapped.
    if (horizontal) {
      canvas.transform(
        Float64List.fromList([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      );
    }
    _drawScrollbar(canvas, pledit, 0, trackH, thumbTop, dragging: dragging);
  }

  @override
  bool shouldRepaint(_SkinScrollbarPainter old) =>
      old.horizontal != horizontal ||
      old.trackH != trackH ||
      old.thumbTop != thumbTop ||
      old.dragging != dragging ||
      old.pledit != pledit;
}

/// The song rows and vertical scrollbar (`draw_pl2` + `draw_pe_vslide`).
class _PlSongListPainter extends CustomPainter {
  _PlSongListPainter({
    required this.skin,
    required this.entries,
    required this.current,
    required this.offset,
    required this.selected,
    required this.dragging,
  });

  final ClassicSkinData skin;
  final List<ClassicPlaylistEntry> entries;
  final int current;
  final int offset;
  final Set<int> selected;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    _paintRows(canvas, size);
    _paintScrollbar(canvas, size);
  }

  void _paintRows(Canvas canvas, Size paintSize) {
    final colors = skin.pledit;
    final listRight = paintSize.width - 20;
    final listWidth = listRight - _listLeft;
    final visibleRows = ((paintSize.height - _rowsLocalTop) / _rowStride)
        .floor()
        .clamp(0, entries.length)
        .toInt();
    final rowsBottom = _rowsLocalTop + visibleRows * _rowStride;
    canvas.drawRect(
      Rect.fromLTWH(_listLeft, 0, listWidth, 3),
      Paint()..color = colors.normalBg,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        _listLeft,
        rowsBottom,
        listWidth,
        paintSize.height - rowsBottom,
      ),
      Paint()..color = colors.normalBg,
    );
    final visible = (entries.length - offset).clamp(0, visibleRows);
    for (var i = 0; i < visible; i++) {
      final absIndex = offset + i;
      final y = _rowsLocalTop + i * _rowStride;
      final isCurrent = absIndex == current;
      final isSelected = selected.contains(absIndex);
      canvas.drawRect(
        Rect.fromLTWH(_listLeft, y, listWidth, _rowStride),
        Paint()..color = isSelected ? colors.selectedBg : colors.normalBg,
      );
      _paintPlaylistLine(
        canvas,
        Rect.fromLTRB(_listLeft, y, listRight, y + _rowStride),
        "${absIndex + 1}. ${entries[absIndex].title}",
        entries[absIndex].duration?.inSeconds,
        _rowColor(
          isCurrent ? colors.current : colors.normal,
          entries[absIndex],
        ),
        colors.fontName,
      );
    }
  }

  /// [color], dimmed for a file that can't be reached now.
  static Color _rowColor(Color color, ClassicPlaylistEntry entry) =>
      entry.unavailable ? color.withAlpha(110) : color;

  void _paintScrollbar(Canvas canvas, Size paintSize) {
    final pledit = skin.image("pledit.bmp")!;
    final trackH = paintSize.height;
    const slidH = 18;
    if (trackH < slidH + _rowsLocalTop) return;
    final visibleRows = ((trackH - _rowsLocalTop) / _rowStride).floor();
    final t = entries.length - visibleRows;
    int yp;
    if (t < 1) {
      yp = 0;
    } else {
      final p = offset.clamp(0, t);
      yp = (((trackH - slidH) * p) ~/ t).clamp(0, trackH - slidH).toInt();
    }
    _drawScrollbar(
      canvas,
      pledit,
      paintSize.width - 15,
      trackH,
      yp,
      dragging: dragging,
    );
  }

  @override
  // Entries are mutated in place as tags are read, so always repaint; the
  // list only rebuilds when the playlist or player changes.
  bool shouldRepaint(_PlSongListPainter oldDelegate) => true;
}

/// The bottom-left `seltime/totaltime` string (`draw_pe_infostr`).
class _PlInfoPainter extends CustomPainter {
  const _PlInfoPainter({required this.font, required this.text});

  final _SkinFont font;
  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    var s = text;
    s = s.length > 18 ? s.substring(0, 18) : s.padRight(18, " ");
    font.draw(canvas, s, 0, 0);
  }

  @override
  bool shouldRepaint(_PlInfoPainter oldDelegate) {
    return oldDelegate.text != text;
  }
}

/// The bottom-right `M:SS` elapsed display (`draw_pe_timedisp`).
class _PlTimePainter extends CustomPainter {
  const _PlTimePainter({
    required this.font,
    required this.minutes,
    required this.seconds,
  });

  final _SkinFont font;
  final int minutes;
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final m = minutes.clamp(0, 599);
    final s = seconds.clamp(0, 59);
    if (m < 100) {
      font.draw(canvas, " ", 0, 0, clipWidth: 4);
      font.draw(canvas, " ", 4, 0, clipWidth: 3);
      font.draw(canvas, "${(m ~/ 10) % 10}", 9, 0);
    } else {
      font.draw(canvas, " ", 0, 0, clipWidth: 3);
      font.draw(canvas, "${(m ~/ 100) % 10}", 4, 0);
      font.draw(canvas, "${(m ~/ 10) % 10}", 9, 0);
    }
    font.draw(canvas, "${m % 10}", 14, 0);
    font.draw(canvas, "${(s ~/ 10) % 10}", 22, 0);
    font.draw(canvas, "${s % 10}", 27, 0);
  }

  @override
  bool shouldRepaint(_PlTimePainter oldDelegate) {
    return oldDelegate.minutes != minutes || oldDelegate.seconds != seconds;
  }
}

/// One of the five bottom buttons (ADD, REM, SEL, MISC, LIST) with its popup
/// column of options (`do_addbut` ... `do_filebut`, drawn by
/// `draw_pe_addbut` ...).
///
/// Pressing the button pops the column open, highlighting the option under
/// the pointer. Dragging onto an option and releasing activates it; releasing
/// on the button itself leaves the column open, and the next click activates
/// the option under the pointer (or closes the column when it misses), as the
/// original does with `config_ospb` off.
@visibleForTesting
class PlPopupButton extends StatefulWidget {
  const PlPopupButton({
    required this.image,
    required this.left,
    required this.height,
    required this.bar,
    required this.normalX,
    required this.pressedX,
    required this.rows,
    required this.actions,
    required this.cursor,
    required this.contextMenu,
    required this.host,
  });

  final ClassicHost host;

  /// The button's full menu, shown on right-click (`PE_OnRButtonUp`).
  final ClassicMenu contextMenu;

  final ui.Image image;

  /// The column's x position in the window.
  final double left;

  /// The window height (the column hangs from `height - 30`).
  final double height;

  /// The x of the 3 px decoration bar in `pledit.bmp`.
  final double bar;

  final double normalX;
  final double pressedX;

  /// The `pledit.bmp` y of each option, from the bottom (the button) up.
  final List<double> rows;

  /// The action of each option, parallel to [rows].
  final List<VoidCallback?> actions;

  final MouseCursor cursor;

  @override
  State<PlPopupButton> createState() => PlPopupButtonState();
}

class PlPopupButtonState extends State<PlPopupButton> {
  bool _open = false;
  bool _sticky = false;
  bool _leftButton = false;
  int _hovered = -1;

  @visibleForTesting
  bool get isOpenForTest => _open;

  int get _count => widget.rows.length;

  double get _columnTop => widget.height - 30 - 18.0 * (_count - 1);

  /// The option under [local] (relative to the column's top-left), or -1.
  int _optionAt(Offset local) {
    if (local.dx < 0 || local.dx >= 22) return -1;
    final fromBottom = ((18.0 * _count - local.dy) / 18).ceil() - 1;
    return fromBottom >= 0 && fromBottom < _count ? fromBottom : -1;
  }

  void _close() {
    _stopWatchingClicks();
    setState(() {
      _open = false;
      _sticky = false;
      _hovered = -1;
    });
  }

  /// A click anywhere while the column stays open (sticky) closes it,
  /// unless it was on the button, which has the column, or on the column.
  /// Other buttons and the rest of the window sit above this one's own
  /// catch-all, so they get the click first and it is told of it here.
  bool _watchingClicks = false;

  void _watchClicks() {
    if (_watchingClicks) return;
    _watchingClicks = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onAnyPointer);
  }

  void _stopWatchingClicks() {
    if (!_watchingClicks) return;
    _watchingClicks = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onAnyPointer);
  }

  void _onAnyPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !_open || !_sticky) return;
    // The catch-all and the button have already seen this click: they have
    // closed the column or taken it over, which clears the sticky state.
    _close();
  }

  @override
  void dispose() {
    _stopWatchingClicks();
    super.dispose();
  }

  void _activate(int option) {
    _close();
    if (option >= 0) widget.actions[option]?.call();
  }

  int? _menuPointer;

  void _onButtonDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryButton) {
      SkinSecondaryClaim.claim(event);
      _menuPointer = event.pointer;
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    SkinPointerClaim.claim?.call(event);
    setState(() {
      _open = true;
      _sticky = false;
      _leftButton = false;
      _hovered = 0;
    });
  }

  void _onButtonMove(PointerMoveEvent event) {
    if (!_open || _sticky) return;
    final option = _optionAt(
      event.localPosition + Offset(0, 18.0 * (_count - 1)),
    );
    if (option != 0) _leftButton = true;
    if (option != _hovered) setState(() => _hovered = option);
  }

  void _onButtonUp(PointerUpEvent event) {
    if (event.pointer == _menuPointer) {
      _menuPointer = null;
      widget.host.showMenu(widget.contextMenu, null);
      return;
    }
    if (!_open || _sticky) return;
    if (_leftButton) {
      _activate(_hovered);
    } else {
      setState(() => _sticky = true);
      _watchClicks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    return Stack(
      children: [
        if (_open)
          Positioned(
            left: widget.left - 3,
            top: _columnTop,
            child: IgnorePointer(
              child: SizedBox(
                width: 25,
                height: 18.0 * _count,
                child: Stack(
                  children: [
                    SkinImage(
                      image: image,
                      src: Rect.fromLTWH(widget.bar, 111, 3, 18.0 * _count),
                    ),
                    for (var i = 0; i < _count; i++)
                      Positioned(
                        left: 3,
                        top: 18.0 * (_count - 1 - i),
                        child: SkinImage(
                          image: image,
                          src: Rect.fromLTWH(
                            i == _hovered ? widget.pressedX : widget.normalX,
                            widget.rows[i],
                            22,
                            18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          left: widget.left,
          top: widget.height - 30,
          width: 22,
          height: 18,
          child: MouseRegion(
            cursor: widget.cursor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onButtonDown,
              onPointerMove: _onButtonMove,
              onPointerUp: _onButtonUp,
              onPointerCancel: (_) => _close(),
            ),
          ),
        ),
        // Sticky mode: the next click anywhere picks the option under it.
        // Above the button, so a click on the bottom option (which sits
        // over the button) picks it rather than reopening the column.
        if (_sticky)
          Positioned.fill(
            child: MouseRegion(
              cursor: widget.cursor,
              onHover: (event) {
                final option = _optionAt(
                  event.localPosition - Offset(widget.left, _columnTop),
                );
                if (option != _hovered) setState(() => _hovered = option);
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  SkinPointerClaim.claim?.call(event);
                  _activate(
                    _optionAt(
                      event.localPosition - Offset(widget.left, _columnTop),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Turns mouse-wheel and trackpad scrolling over [child] into whole-row steps
/// (Pledit.cpp `WM_MOUSEWHEEL`).
///
/// A wheel notch scrolls 2 rows (`config_plscrollsize` 1, doubled by
/// `config_plmw2xscroll`, both on by default). Trackpad scrolling, which
/// Flutter reports as pan gestures (and momentum as scroll events), moves one
/// row per row height scrolled, carrying the remainder over.
class SkinWheelScroll extends StatefulWidget {
  const SkinWheelScroll({
    required this.onScroll,
    required this.child,
    this.rowsPerNotch = 2,
    super.key,
  });

  /// The rows a wheel notch scrolls.
  final int rowsPerNotch;

  /// Called with the rows to scroll; positive moves towards later rows.
  final ValueChanged<int> onScroll;

  final Widget child;

  @override
  State<SkinWheelScroll> createState() => SkinWheelScrollState();
}

class SkinWheelScrollState extends State<SkinWheelScroll> {
  /// Scroll distance (in logical pixels) not yet turned into rows.
  double _carry = 0;

  /// The logical pixels Flutter reports for one discrete wheel notch.
  static const double _pixelsPerNotch = 50;

  void _pixels(double dy) {
    if (dy.sign != _carry.sign) _carry = 0;
    _carry += dy;
    final rows = _carry ~/ _rowStride;
    if (rows == 0) return;
    _carry -= rows * _rowStride;
    widget.onScroll(rows);
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    if (event.kind == PointerDeviceKind.trackpad) {
      _pixels(dy);
      return;
    }
    // A discrete wheel: at least one notch per event.
    final notches = (dy.abs() / _pixelsPerNotch).round().clamp(1, 10);
    widget.onScroll(dy.sign.toInt() * notches * widget.rowsPerNotch);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onSignal,
      onPointerPanZoomStart: (_) => _carry = 0,
      // Fingers moving up reveal later rows.
      onPointerPanZoomUpdate: (event) => _pixels(-event.localPanDelta.dy),
      child: widget.child,
    );
  }
}

/// The title-bar window-shade and close buttons (`draw_pe_tbutton`).
class _PlTitleButtons extends StatelessWidget {
  const _PlTitleButtons({
    required this.host,
    required this.skin,
    required this.width,
    required this.shade,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final double width;
  final bool shade;

  @override
  Widget build(BuildContext context) {
    final pledit = skin.image("pledit.bmp")!;
    return Stack(
      children: [
        Positioned(
          left: width - 20,
          top: 3,
          child: SkinButton(
            image: pledit,
            src: shade
                ? const Rect.fromLTWH(128, 45, 9, 9)
                : const Rect.fromLTWH(157, 3, 9, 9),
            pressedSrc: shade
                ? const Rect.fromLTWH(150, 42, 9, 9)
                : const Rect.fromLTWH(62, 42, 9, 9),
            cursor: skin.cursor(
              shade ? SkinCursor.plWsWinBut : SkinCursor.plWinBut,
            ),
            onPressed: host.player.togglePlShade,
          ),
        ),
        Positioned(
          left: width - 11,
          top: 3,
          child: SkinButton(
            image: pledit,
            src: shade
                ? const Rect.fromLTWH(138, 45, 9, 9)
                : const Rect.fromLTWH(167, 3, 9, 9),
            pressedSrc: const Rect.fromLTWH(52, 42, 9, 9),
            cursor: skin.cursor(
              shade ? SkinCursor.plWsClose : SkinCursor.plClose,
            ),
            onPressed: () => host.setOpen(SkinWindow.pl, false),
          ),
        ),
      ],
    );
  }
}

/// The resize grip: the bottom-right corner normally, or the strip left of
/// the title buttons in windowshade mode (`do_size`).
class _PlResizeHandle extends StatefulWidget {
  const _PlResizeHandle({
    required this.host,
    required this.skin,
    required this.width,
    required this.height,
    required this.shade,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final double width;
  final double height;
  final bool shade;

  @override
  State<_PlResizeHandle> createState() => _PlResizeHandleState();
}

class _PlResizeHandleState extends State<_PlResizeHandle> {
  Offset? _grab;

  /// The pointer position in unscaled window pixels, read natively because
  /// the handle moves while the window resizes.
  Offset _pointer() {
    final host = widget.host;
    final origin = host.windowOrigin(SkinWindow.pl);
    return (host.cursorPosition - origin) / host.player.uiScale;
  }

  void _start(Offset _) {
    final size = widget.host.fullSize(SkinWindow.pl);
    final height = widget.shade ? SkinWindow.shadeHeight : size.height;
    _grab = Offset(size.width, height) - _pointer();
  }

  void _update(Offset _) {
    final grab = _grab;
    if (grab == null) return;
    final target = _pointer() + grab;
    final full = widget.host.fullSize(SkinWindow.pl);
    widget.host.resize(
      SkinWindow.pl,
      Size(target.dx, widget.shade ? full.height : target.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cursor = widget.skin.cursor(
      widget.shade ? SkinCursor.plWsSize : SkinCursor.plSize,
    );
    final rect = widget.shade
        ? Rect.fromLTWH(widget.width - 29, 3, 9, 10)
        : Rect.fromLTWH(widget.width - 20, widget.height - 20, 20, 20);
    return Positioned.fromRect(
      rect: rect,
      child: SkinDragTarget(
        cursor: cursor,
        onStart: _start,
        onUpdate: _update,
        onEnd: (_) => _grab = null,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Windowshade (width×14) built from `pledit.bmp`.
class _PlShadeLayout extends StatelessWidget {
  const _PlShadeLayout({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  Widget build(BuildContext context) {
    final pledit = skin.image("pledit.bmp")!;
    final width = host.baseSize(SkinWindow.pl).width;
    final player = host.player;
    final entry = player.playlist.currentEntry;
    // In windowshade mode the wheel changes tracks (Pledit.cpp
    // `WM_MOUSEWHEEL`: BUTTON1 / BUTTON5).
    return SkinWheelScroll(
      onScroll: (lines) => lines < 0 ? player.prev() : player.next(),
      child: Stack(
        children: [
          CustomPaint(
            size: Size(width, _plShadeHeight),
            painter: _PlShadeTitlebarPainter(
              image: pledit,
              active: WindowActivity.of(context),
            ),
          ),
          CustomPaint(
            size: Size(width, _plShadeHeight),
            painter: _PlShadeSongPainter(
              title: entry == null
                  ? ""
                  : "${host.player.playlist.current + 1}. ${entry.title}",
              seconds: entry?.duration?.inSeconds,
              width: width,
              font: _SkinFont(TextFont(skin.image("text.bmp")!)),
            ),
          ),
          _PlTitleButtons(host: host, skin: skin, width: width, shade: true),
          _PlResizeHandle(
            host: host,
            skin: skin,
            width: width,
            height: _plShadeHeight,
            shade: true,
          ),
        ],
      ),
    );
  }
}

/// The windowshade current-song line (`draw_pe_song` with `pos = -1`), in
/// the `text.bmp` font as classic draws it (Wasabi 5's bitmap-font
/// option): 5 px cells from x = 4, the name cut with an ellipsis cell, the
/// time ending 29 px from the right, blanks between.
class _PlShadeSongPainter extends CustomPainter {
  const _PlShadeSongPainter({
    required this.title,
    required this.seconds,
    required this.width,
    required this.font,
  });

  final String title;
  final int? seconds;
  final double width;
  final _SkinFont font;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 4.0, top = 4.0;
    final w = width.toInt();
    var cells = (w - 29 - 4) ~/ 5;
    final time = seconds == null ? null : formatPlaylistTime(seconds!);
    if (time != null) cells -= time.length + 1;
    final chars = title.characters.toList();
    final line = StringBuffer();
    var x = 0;
    for (; x < cells && x < chars.length; x++) {
      // The last cell of a name that doesn't fit shows the ellipsis.
      line.write(x == cells - 1 && x + 1 < chars.length ? "\u0001" : chars[x]);
    }
    if (x >= chars.length) {
      if (time != null) cells++;
      while (x++ < cells) {
        line.write(" ");
      }
    }
    if (time != null) line.write(" ");
    font.draw(canvas, line.toString(), left, top);
    var xpos = left + line.length * 5;
    if (time != null) {
      xpos = w - 29 - 5.0 * time.length;
      font.draw(canvas, time, xpos, top);
      xpos += 5.0 * time.length;
    }
    // Blanks up to 30 px from the right.
    if (xpos < w - 30) {
      font.draw(canvas, " ", xpos, top, clipWidth: w - 30 - xpos);
    }
  }

  @override
  bool shouldRepaint(_PlShadeSongPainter oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.seconds != seconds ||
        oldDelegate.width != width ||
        oldDelegate.font.font.image != font.font.image;
  }
}

/// Draws one playlist line in the skin's font (`pledit.txt` `Font=`, Arial by
/// default), like `draw_pe_song`: the time right-aligned as " m:ss ", the
/// name left-aligned and ended with an ellipsis when it does not fit, both
/// vertically centered in [rect] and clipped to it, as `DrawText` clips.
///
/// [cellHeight] is the GDI font height the original asks for: the cell,
/// ascent plus descent, not the em size Flutter takes.
void _paintPlaylistLine(
  Canvas canvas,
  Rect rect,
  String name,
  int? seconds,
  Color color,
  String fontName, {
  double cellHeight = _plFontSize,
}) {
  final family = fontName.isEmpty ? "Arial" : fontName;
  canvas
    ..save()
    ..clipRect(rect);
  // The text is drawn white and tinted to [color] through a layer: Impeller
  // corrupts cached glyphs for some text colors (e.g. os8_amp's #6363CE), and
  // white renders reliably.
  canvas.saveLayer(
    rect,
    Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
  );
  final style = TextStyle(
    color: const Color(0xFFFFFFFF),
    fontFamily: family,
    fontSize: cellHeight * _emPerCell(family),
  );
  // DT_VCENTER: the font's cell centred in the line (whole pixels), so the
  // baseline sits its ascent below the cell's top.
  final cellTop = rect.top + ((rect.height - cellHeight) / 2).floorToDouble();
  final baseline =
      cellTop + (cellHeight * _cellMetrics(family).ascentShare).roundToDouble();
  double topFor(TextPainter painter) =>
      baseline -
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);

  var right = rect.right;
  // Tracks of unknown length show no time, like the original before it has
  // read the file.
  if (seconds != null) {
    final time = TextPainter(
      text: TextSpan(text: " ${formatPlaylistTime(seconds)} ", style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (time.width < rect.width) {
      right -= time.width;
      time.paint(canvas, Offset(right, topFor(time)));
    }
    time.dispose();
  }
  final title = TextPainter(
    text: TextSpan(text: name, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: "...",
  )..layout(maxWidth: max(0, right - rect.left));
  title.paint(canvas, Offset(rect.left, topFor(title)));
  title.dispose();
  canvas
    ..restore()
    ..restore();
}

/// A font's ascent and descent as shares of its cell (GDI's `tmHeight`).
typedef _CellMetrics = ({double emShare, double ascentShare});

final Map<String, _CellMetrics> _cellMetricsCache = {};

_CellMetrics _cellMetrics(String family) => _cellMetricsCache[family] ??= () {
  final probe = TextPainter(
    text: TextSpan(
      text: "Xg",
      style: TextStyle(fontFamily: family, fontSize: 100),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final line = probe.computeLineMetrics().first;
  probe.dispose();
  final cell = line.ascent + line.descent;
  return (emShare: 100 / cell, ascentShare: line.ascent / cell);
}();

/// The em size per pixel of cell height: GDI sizes fonts by their cell
/// (`CreateFont` with a positive height), Flutter by the em.
double _emPerCell(String family) => _cellMetrics(family).emShare;
