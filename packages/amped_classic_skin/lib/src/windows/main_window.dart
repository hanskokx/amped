import "dart:async";
import "dart:math";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/foundation.dart" show listEquals;
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

/// The main the classic player player window, rendered from the skin bitmaps.
///
/// Every element is a crop blitted where the original's `draw_main.cpp` put it,
/// and every control follows the original `Ui.cpp` mouse handling.
class MainWindowView extends StatefulWidget {
  const MainWindowView({required this.host, super.key});

  final ClassicHost host;

  @override
  State<MainWindowView> createState() => _MainWindowViewState();
}

class _MainWindowViewState extends State<MainWindowView> {
  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final skin = host.skin!;
    final player = host.player;
    return player.windowShade
        ? _ShadeLayout(host: host, skin: skin)
        : _NormalLayout(
            host: host,
            skin: skin,
            songOverride: host.songTitleOverride,
          );
  }
}

/// Where the song title text goes: its top-left, its width in pixels and
/// whether the skin shows it (`mainwinText*` hints; 111, 27 and 154 in the
/// classic layout).
({double left, double top, double width, bool visible}) _titleField(
  ClassicSkinData skin,
) {
  final hints = skin.hints;
  return (
    left: hints.value("mainwinTextX", 111).toDouble(),
    top: hints.value("mainwinTextY", 27).toDouble(),
    width: hints.value("mainwinTextWidth", 154).toDouble(),
    visible: hints.flag("mainwinTextVisible", fallback: true),
  );
}

/// A skin crop at a fixed position.
class _Sprite extends StatelessWidget {
  const _Sprite({
    required this.image,
    required this.src,
    required this.left,
    required this.top,
  });

  final ui.Image image;
  final Rect src;
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: SkinImage(image: image, src: src),
    );
  }
}

/// A [SkinButton] at a fixed position.
class _Button extends StatelessWidget {
  const _Button({
    required this.left,
    required this.top,
    required this.image,
    required this.src,
    required this.pressedSrc,
    required this.onPressed,
    required this.cursor,
  });

  final double left;
  final double top;
  final ui.Image image;
  final Rect src;
  final Rect pressedSrc;
  final VoidCallback? onPressed;
  final MouseCursor cursor;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: SkinButton(
        image: image,
        src: src,
        pressedSrc: pressedSrc,
        onPressed: onPressed,
        cursor: cursor,
      ),
    );
  }
}

class _NormalLayout extends StatelessWidget {
  const _NormalLayout({
    required this.host,
    required this.skin,
    required this.songOverride,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final ValueNotifier<String?> songOverride;

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final main = skin.image("main.bmp")!;
    final titlebar = skin.image("titlebar.bmp")!;
    final cbuttons = skin.image("cbuttons.bmp")!;
    final shufrep = skin.image("shufrep.bmp")!;
    final normal = skin.cursor(SkinCursor.normal);
    final hints = skin.hints;
    final size = skin.mainSize;
    // The position of a control: where the skin's hints put it, else where
    // the classic layout does. A control placed past the window's edge is
    // one the skin leaves out.
    Offset at(String name, double x, double y) =>
        hints.point(name, Offset(x, y));
    const buttonNames = [
      "mainwinPrevious",
      "mainwinPlay",
      "mainwinPause",
      "mainwinStop",
      "mainwinNext",
    ];
    final eject = at("mainwinEject", 136, 89);
    final shuffle = at("mainwinShuffle", 164, 89);
    final repeat = at("mainwinRepeat", 210, 89);
    final eq = at("mainwinEQButton", 219, 58);
    final pl = at("mainwinPLButton", 242, 58);
    final about = at("mainwinAbout", 253, 91);
    final text = _titleField(skin);
    return Stack(
      children: [
        _Sprite(
          image: main,
          src: Rect.fromLTWH(0, 0, size.width, size.height),
          left: 0,
          top: 0,
        ),
        // Active or inactive title bar (`draw_tbar`). A skin of another size
        // draws its own.
        if (size.width == 275)
          _Sprite(
            image: titlebar,
            src: Rect.fromLTWH(
              27,
              WindowActivity.of(context) ? 0 : 15,
              275,
              14,
            ),
            left: 0,
            top: 0,
          ),
        // Cursor zones behind the controls (`ui_handlecursor` b_normal).
        CursorZone(
          skin: skin,
          rect: Rect.fromLTRB(0, 0, size.width + 1, 14),
          cursor: SkinCursor.titleBar,
        ),
        if (text.visible)
          CursorZone(
            skin: skin,
            rect: Rect.fromLTWH(
              text.left - 6,
              text.top - 3,
              text.width + 8,
              12,
            ),
            cursor: SkinCursor.songName,
          ),
        _TitleButtons(host: host, skin: skin, shade: false),
        if (hints.flag("mainwinMenurowVisible", fallback: true))
          _Clutterbar(host: host, skin: skin, songOverride: songOverride),
        _Display(host: host, skin: skin, songOverride: songOverride),
        _Sliders(host: host, skin: skin, songOverride: songOverride),
        for (var i = 0; i < 5; i++)
          _Button(
            left: at(buttonNames[i], 16.0 + i * 23, 88).dx,
            top: at(buttonNames[i], 16.0 + i * 23, 88).dy,
            image: cbuttons,
            src: Rect.fromLTWH(i * 23.0, 0, i == 4 ? 22 : 23, 18),
            pressedSrc: Rect.fromLTWH(i * 23.0, 18, i == 4 ? 22 : 23, 18),
            onPressed: [
              player.prev,
              player.togglePlay,
              player.pause,
              player.stop,
              player.next,
            ][i],
            cursor: normal,
          ),
        _Button(
          left: eject.dx,
          top: eject.dy,
          image: cbuttons,
          src: const Rect.fromLTWH(114, 0, 22, 16),
          pressedSrc: const Rect.fromLTWH(114, 16, 22, 16),
          // Eject (`__do_buttons(5)`): open files; Shift: a folder; Ctrl: a
          // URL.
          onPressed: () {
            final keyboard = HardwareKeyboard.instance;
            if (keyboard.isControlPressed) {
              unawaited(host.openUrl());
            } else if (keyboard.isShiftPressed) {
              unawaited(host.openFolder());
            } else {
              unawaited(host.openFiles());
            }
          },
          cursor: normal,
        ),
        _Button(
          left: shuffle.dx,
          top: shuffle.dy,
          image: shufrep,
          src: Rect.fromLTWH(28, player.shuffle ? 30 : 0, 47, 15),
          pressedSrc: Rect.fromLTWH(28, player.shuffle ? 45 : 15, 47, 15),
          onPressed: player.toggleShuffle,
          cursor: normal,
        ),
        _Button(
          left: repeat.dx,
          top: repeat.dy,
          image: shufrep,
          src: Rect.fromLTWH(0, player.repeat ? 30 : 0, 28, 15),
          pressedSrc: Rect.fromLTWH(0, player.repeat ? 45 : 15, 28, 15),
          onPressed: player.toggleRepeat,
          cursor: normal,
        ),
        _Button(
          left: eq.dx,
          top: eq.dy,
          image: shufrep,
          src: Rect.fromLTWH(0, player.eqOpen ? 73 : 61, 23, 12),
          pressedSrc: Rect.fromLTWH(46, player.eqOpen ? 73 : 61, 23, 12),
          onPressed: () => host.toggle(SkinWindow.eq),
          cursor: normal,
        ),
        _Button(
          left: pl.dx,
          top: pl.dy,
          image: shufrep,
          src: Rect.fromLTWH(23, player.plOpen ? 73 : 61, 23, 12),
          pressedSrc: Rect.fromLTWH(69, player.plOpen ? 73 : 61, 23, 12),
          onPressed: () => host.toggle(SkinWindow.pl),
          cursor: normal,
        ),
        // The logo (`do_icon`, `inreg(253,91,265,105)`): releasing a click
        // over it opens the About dialog (`LIGHTNING_CLICK`).
        Positioned(
          left: about.dx,
          top: about.dy,
          child: SkinButton(
            key: const ValueKey("main-logo"),
            size: const Size(13, 15),
            onPressed: host.showAbout,
            cursor: normal,
            builder: (_, _) => const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// The menu, minimize, windowshade and close buttons (`draw_tbuttons`).
class _TitleButtons extends StatelessWidget {
  const _TitleButtons({
    required this.host,
    required this.skin,
    required this.shade,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final bool shade;

  @override
  Widget build(BuildContext context) {
    final tb = skin.image("titlebar.bmp")!;
    final shadeY = shade ? 27.0 : 18.0;
    // Audacious skins may move these (a skin without hints keeps them).
    final hints = shade ? const SkinHints() : skin.hints;
    final minimize = hints.point("mainwinMinimize", const Offset(244, 3));
    final shadeAt = hints.point("mainwinShade", const Offset(254, 3));
    final close = hints.point("mainwinClose", const Offset(264, 3));
    return Stack(
      children: [
        _Button(
          left: 6,
          top: 3,
          image: tb,
          src: const Rect.fromLTWH(0, 0, 9, 9),
          pressedSrc: const Rect.fromLTWH(0, 9, 9, 9),
          onPressed: () => host.showMenu(
            ClassicMenu.main,
            host.toGlobal(SkinWindow.main, const Offset(6, 12)),
          ),
          cursor: skin.cursor(
            shade ? SkinCursor.wsMainMenu : SkinCursor.mainMenu,
          ),
        ),
        _Button(
          left: minimize.dx,
          top: minimize.dy,
          image: tb,
          src: const Rect.fromLTWH(9, 0, 9, 9),
          pressedSrc: const Rect.fromLTWH(9, 9, 9, 9),
          onPressed: host.minimize,
          cursor: skin.cursor(shade ? SkinCursor.wsMin : SkinCursor.min),
        ),
        _Button(
          left: shadeAt.dx,
          top: shadeAt.dy,
          image: tb,
          src: Rect.fromLTWH(0, shadeY, 9, 9),
          pressedSrc: Rect.fromLTWH(9, shadeY, 9, 9),
          onPressed: host.player.toggleWindowShade,
          cursor: skin.cursor(shade ? SkinCursor.wsWinBut : SkinCursor.winBut),
        ),
        _Button(
          left: close.dx,
          top: close.dy,
          image: tb,
          src: const Rect.fromLTWH(18, 0, 9, 9),
          pressedSrc: const Rect.fromLTWH(18, 9, 9, 9),
          // Shift closes just the main window (`MAIN_WINDOW`).
          onPressed: () => HardwareKeyboard.instance.isShiftPressed
              ? host.setOpen(SkinWindow.main, false)
              : host.closeMainWindow(),
          cursor: skin.cursor(shade ? SkinCursor.wsClose : SkinCursor.close),
        ),
      ],
    );
  }
}

/// The O/A/I/D/V "clutterbar" (`do_clutterbar`). Pressing shows the item's
/// help text in the song title; releasing over an item activates it.
class _Clutterbar extends StatelessWidget {
  const _Clutterbar({
    required this.host,
    required this.skin,
    required this.songOverride,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final ValueNotifier<String?> songOverride;

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final tb = skin.image("titlebar.bmp")!;
    // (top, height, selected sprite, help text, action, latched)
    final items = <(double, double, Rect, String, VoidCallback, bool)>[
      (
        3,
        8,
        const Rect.fromLTWH(304, 47, 8, 8),
        "Options Menu",
        () => host.showMenu(
          ClassicMenu.options,
          host.toGlobal(SkinWindow.main, const Offset(14, 25)),
        ),
        false,
      ),
      (
        11,
        7,
        const Rect.fromLTWH(312, 55, 8, 7),
        player.alwaysOnTop ? "Disable Always-On-Top" : "Enable Always-On-Top",
        player.toggleAlwaysOnTop,
        player.alwaysOnTop,
      ),
      (
        18,
        7,
        const Rect.fromLTWH(320, 62, 8, 7),
        "File Info Box",
        () {},
        false,
      ),
      (
        25,
        8,
        const Rect.fromLTWH(328, 69, 8, 8),
        player.uiScale == 2
            ? "Disable Doublesize Mode"
            : "Enable Doublesize Mode",
        () => player.setUiScale(player.uiScale == 2 ? 1 : 2),
        player.uiScale == 2,
      ),
      (
        33,
        7,
        const Rect.fromLTWH(336, 77, 8, 7),
        "Visualization Menu",
        () => host.showMenu(
          ClassicMenu.visualization,
          host.toGlobal(SkinWindow.main, const Offset(14, 56)),
        ),
        false,
      ),
    ];
    final normal = skin.cursor(SkinCursor.normal);
    return Positioned(
      left: 10,
      top: 22,
      width: 8,
      height: 43,
      child: Stack(
        children: [
          SkinImage(image: tb, src: const Rect.fromLTWH(304, 0, 8, 43)),
          for (final (top, height, selected, help, action, latched) in items)
            Positioned(
              left: 0,
              top: top,
              child: SkinButton(
                size: Size(8, height),
                cursor: normal,
                onPressed: action,
                onPressedChanged: (pressed) =>
                    songOverride.value = pressed ? help : null,
                builder: (context, pressed) => pressed || latched
                    ? SkinImage(image: tb, src: selected)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({
    required this.host,
    required this.skin,
    required this.songOverride,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final ValueNotifier<String?> songOverride;

  /// The 3-slot bitrate field (`draw_bitmixrate`).
  static String _bitrateField(int bitrate) {
    if (bitrate >= 10000) {
      final hundredThousands = bitrate >= 100000
          ? "${(bitrate ~/ 100000) % 10}"
          : " ";
      return "$hundredThousands${(bitrate ~/ 10000) % 10}C";
    }
    if (bitrate >= 1000)
      return "${(bitrate ~/ 1000) % 10}${(bitrate ~/ 100) % 10}H";
    final hundreds = bitrate >= 100 ? "${(bitrate ~/ 100) % 10}" : " ";
    final tens = bitrate >= 10 ? "${(bitrate ~/ 10) % 10}" : " ";
    return "$hundreds$tens${bitrate % 10}";
  }

  static String _mixrateField(int mixrate) {
    final tens = mixrate >= 10 ? "${(mixrate ~/ 10) % 10}" : " ";
    return "$tens${mixrate % 10}";
  }

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final playpaus = skin.image("playpaus.bmp")!;
    final mono = skin.image("monoster.bmp")!;
    final font = TextFont(skin.image("text.bmp")!);
    final playing = player.playing;
    final loaded = player.playing || player.paused;
    // `draw_monostereo(nch)`: one channel lights mono, more light stereo,
    // none while stopped. Streams of unknown layout count as stereo.
    final channels = loaded ? (player.playlist.currentEntry?.channels ?? 2) : 0;
    final iconSrc = switch (player.playIcon) {
      0 => const Rect.fromLTWH(0, 0, 9, 9),
      1 => const Rect.fromLTWH(9, 0, 9, 9),
      _ => const Rect.fromLTWH(18, 0, 9, 9),
    };
    final normal = skin.cursor(SkinCursor.normal);
    final hints = skin.hints;
    final status = hints.point("mainwinPlayStatus", const Offset(24, 28));
    // The x of the minus sign and the four digits (36, 48, 60, 78, 90).
    const classicNumbers = [36, 48, 60, 78, 90];
    final numberXs = [
      for (var i = 0; i < 5; i++)
        hints.value("mainwinNumber${i}X", classicNumbers[i]).toDouble(),
    ];
    final numberY = hints.value("mainwinNumber0Y", 26).toDouble();
    final title = _titleField(skin);
    final streamInfo = hints.flag("mainwinStreaminfoVisible", fallback: true);
    final otherText = hints.flag("mainwinOthertextVisible", fallback: false);
    // The status line (volume, seeking) shows in the info text instead of
    // the title when the skin says so.
    final statusInInfo =
        otherText && hints.flag("mainwinOthertextIsStatus", fallback: false);
    final vis = hints.point("mainwinVis", const Offset(24, 43));
    final showVis = hints.flag("mainwinVisVisible", fallback: true);
    return Stack(
      children: [
        _Sprite(
          image: playpaus,
          src: iconSrc,
          left: status.dx + 2,
          top: status.dy,
        ),
        _Sprite(
          image: playpaus,
          src: playing
              ? const Rect.fromLTWH(36, 0, 3, 9)
              : const Rect.fromLTWH(27, 0, 3, 9),
          left: status.dx,
          top: status.dy,
        ),
        // Clicking the time display toggles elapsed/remaining
        // (`do_timedisplay`, on mouse-down).
        Positioned(
          left: numberXs[0],
          top: numberY,
          width: max(63, numberXs[4] + 9 - numberXs[0]),
          height: 13,
          child: SkinDragTarget(
            cursor: normal,
            onStart: (_) => player.toggleTimeRemaining(),
            child: _TimeDigits(
              image: skin.timeDigits,
              extended: skin.numbersExtended,
              seconds: _displaySeconds(player),
              negative: player.timeRemaining,
              xs: [for (final x in numberXs) x - numberXs[0]],
            ),
          ),
        ),
        // The song title, or a status shown in its place.
        if (title.visible)
          Positioned(
            left: title.left - 6,
            top: title.top - 3,
            width: title.width + 8,
            height: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: host.showFileInfo,
              child: ValueListenableBuilder<String?>(
                valueListenable: songOverride,
                builder: (context, status, _) => _SongTitleField(
                  font: font,
                  title: player.title.toUpperCase(),
                  status: statusInInfo ? null : status?.toUpperCase(),
                  track: player.playlist.currentEntry,
                  playing: playing,
                  cursor: skin.cursor(SkinCursor.songName),
                  textWidth: title.width,
                ),
              ),
            ),
          ),
        if (otherText)
          Positioned(
            left: hints.value("mainwinInfobarX", 111).toDouble(),
            top: hints.value("mainwinInfobarY", 43).toDouble(),
            child: ValueListenableBuilder<String?>(
              valueListenable: songOverride,
              builder: (context, status, _) => SkinText(
                font: font,
                text: statusInInfo && status != null
                    ? status.toUpperCase()
                    : _infoText(player, loaded: loaded, channels: channels),
                clip: Rect.fromLTWH(
                  0,
                  0,
                  hints.value("mainwinInfobarWidth", 160).toDouble(),
                  6,
                ),
              ),
            ),
          ),
        if (streamInfo) ...[
          Positioned(
            left: 111,
            top: 43,
            child: SkinText(
              font: font,
              text: loaded && player.bitrate > 0
                  ? _bitrateField(player.bitrate)
                  : "",
              clip: const Rect.fromLTWH(0, 0, 15, 6),
            ),
          ),
          Positioned(
            left: 156,
            top: 43,
            child: SkinText(
              font: font,
              text: loaded && player.mixrate > 0
                  ? _mixrateField(player.mixrate)
                  : "",
              clip: const Rect.fromLTWH(0, 0, 10, 6),
            ),
          ),
          _Sprite(
            image: mono,
            src: Rect.fromLTWH(29, channels == 1 ? 0 : 12, 27, 12),
            left: 212,
            top: 41,
          ),
          _Sprite(
            image: mono,
            src: Rect.fromLTWH(0, channels >= 2 ? 0 : 12, 29, 12),
            left: 239,
            top: 41,
          ),
        ],
        if (showVis)
          Positioned(
            left: vis.dx,
            top: vis.dy,
            width: 76,
            height: 16,
            child: ClassicVisView(
              player: player,
              colors: skin.visColors,
              windowShade: false,
            ),
          ),
        // A click cycles spectrum, oscilloscope and off while playing.
        if (playing && showVis)
          Positioned(
            left: vis.dx + 3,
            top: vis.dy - 3,
            width: 72,
            height: 21,
            child: SkinDragTarget(
              onStart: (_) => host.clickClassicVis(),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// The info text some Audacious skins show in one line (`mainwinInfobar*`):
/// the bitrate, the sample rate and the channels.
String _infoText(
  ClassicPlayer player, {
  required bool loaded,
  required int channels,
}) {
  if (!loaded) return "";
  final parts = <String>[
    if (player.bitrate > 0) "${player.bitrate} KBPS",
    if (player.mixrate > 0) "${player.mixrate} KHZ",
    if (channels == 1) "MONO" else if (channels >= 2) "STEREO",
  ];
  return parts.join(", ");
}

int _displaySeconds(ClassicPlayer player) {
  final elapsed = player.elapsedSec;
  return player.timeRemaining
      ? (player.durationSec - elapsed).clamp(0, 1 << 30)
      : elapsed;
}

/// The song title field (154 x 6 px of text inside the song-name area).
/// While a [status] replaces the title, the field still shows the track for
/// a moment when playback starts or the track changes: the text slides up a
/// pixel at a time like an LED sign, then back down to the status. A click
/// swaps between the two.
class _SongTitleField extends StatefulWidget {
  const _SongTitleField({
    required this.font,
    required this.title,
    required this.status,
    required this.track,
    required this.playing,
    required this.cursor,
    this.textWidth = 154,
  });

  /// The width of the text line in pixels.
  final double textWidth;

  final TextFont font;
  final String title;

  /// Text shown in place of the title, or null.
  final String? status;

  /// The current track, to notice a new one.
  final Object? track;
  final bool playing;
  final MouseCursor cursor;

  @override
  State<_SongTitleField> createState() => _SongTitleFieldState();
}

class _SongTitleFieldState extends State<_SongTitleField>
    with SingleTickerProviderStateMixin {
  /// Rows from one line of text to the next: the 6 px font and 2 blank.
  static const double _pitch = 8;

  /// How long the track shows before the status returns.
  static const Duration _peek = Duration(milliseconds: 2500);

  /// 0 shows the status, 1 the track.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_onSlide);

  Timer? _peekTimer;

  /// The whole-pixel shift last drawn, so frames between pixels skip.
  int _shift = 0;

  void _onSlide() {
    final shift = (_slide.value * _pitch).round();
    if (shift != _shift) setState(() => _shift = shift);
  }

  void _showTrack(bool track) {
    if (track) {
      unawaited(_slide.forward());
    } else {
      unawaited(_slide.reverse());
    }
  }

  void _peekAtTrack() {
    _peekTimer?.cancel();
    _showTrack(true);
    _peekTimer = Timer(_peek, () {
      _peekTimer = null;
      _showTrack(false);
    });
  }

  void _swap() {
    _peekTimer?.cancel();
    _peekTimer = null;
    _showTrack(
      _slide.status != AnimationStatus.forward &&
          _slide.status != AnimationStatus.completed,
    );
  }

  @override
  void didUpdateWidget(_SongTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == null) {
      // Nothing to swap with: the title shows plainly, and the next status
      // starts out showing.
      _peekTimer?.cancel();
      _peekTimer = null;
      _shift = 0; // First, so the listener sees nothing to redraw.
      _slide.value = 0;
    } else if (oldWidget.status != null &&
        (!identical(widget.track, oldWidget.track) ||
            (widget.playing && !oldWidget.playing))) {
      _peekAtTrack();
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final titleRow = _ScrollingTitle(
      key: const ValueKey("title"),
      font: widget.font,
      text: widget.title,
      width: widget.textWidth,
    );
    return Stack(
      children: [
        Positioned(
          left: 6,
          top: 3,
          width: widget.textWidth,
          height: 6,
          child: status == null
              ? titleRow
              : ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: -_shift.toDouble(),
                        child: _ScrollingTitle(
                          key: const ValueKey("status"),
                          font: widget.font,
                          text: status,
                          width: widget.textWidth,
                          keepPlace: true,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: _pitch - _shift,
                        child: titleRow,
                      ),
                    ],
                  ),
                ),
        ),
        if (status != null)
          Positioned.fill(
            child: SkinDragTarget(
              cursor: widget.cursor,
              onStart: (_) => _swap(),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// The song title, scrolling one character at a time when it does not fit
/// (`draw_songname` with `config_autoscrollname`), with " *** " between
/// repeats.
class _ScrollingTitle extends StatefulWidget {
  const _ScrollingTitle({
    required this.font,
    required this.text,
    super.key,
    this.keepPlace = false,
    this.width = 154,
  });

  /// The visible width in pixels.
  final double width;

  final TextFont font;
  final String text;

  /// Whether to keep scrolling from where it is when [text] changes, for a
  /// status that changes as it goes (a count), instead of starting over.
  final bool keepPlace;

  @override
  State<_ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<_ScrollingTitle> {
  /// The visible width in characters (5 px glyphs).
  int get _visible => widget.width ~/ 5;

  int _offset = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (widget.text.length <= _visible) return;
      setState(() => _offset++);
    });
  }

  @override
  void didUpdateWidget(_ScrollingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !widget.keepPlace) _offset = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var text = widget.text;
    if (text.length > _visible) {
      final loop = "$text  ***  ";
      final start = _offset % loop.length;
      text = (loop + loop).substring(start, start + _visible);
    }
    return SkinText(
      font: widget.font,
      text: text,
      clip: Rect.fromLTWH(0, 0, widget.width, 6),
    );
  }
}

class _Sliders extends StatelessWidget {
  const _Sliders({
    required this.host,
    required this.skin,
    required this.songOverride,
  });

  final ClassicHost host;
  final ClassicSkinData skin;
  final ValueNotifier<String?> songOverride;

  static String _volumeText(int volume) => "Volume: ${volume * 100 ~/ 255}%";

  static String _balanceText(int balance) {
    if (balance == 0) return "Balance: Center";
    final percent = balance.abs() * 100 ~/ 127;
    return "Balance: $percent% ${balance < 0 ? "Left" : "Right"}";
  }

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final posbar = skin.image("posbar.bmp")!;
    final vol = skin.image("volume.bmp")!;
    final bal = skin.image("balance.bmp")!;
    final volBal = skin.cursor(SkinCursor.volBal);
    final volY = player.volume * 27 ~/ 255 * 15.0;
    final balY = player.balance.abs() * 27 ~/ 127 * 15.0;
    // Volume: `v = (x - clickx - 107) * 255 / 51`.
    int volumeFrom(double left) => (left * 255 ~/ 51).clamp(0, 255);
    // Balance: `p = (x - clickx - 177 - 12) * 127 / 12`, snapping to center.
    int balanceFrom(double left) {
      var p = ((left - 12) * 127 ~/ 12).clamp(-127, 127);
      if (p.abs() < 27) p = 0;
      return p;
    }

    const seekRange = 257 - 29 - 10;
    int seekFrom(double left) => left.clamp(0, seekRange) * 256 ~/ seekRange;
    String seekText(int position) {
      final total = player.durationSec;
      final t = position * total ~/ 256;
      String two(int v) => v.toString().padLeft(2, "0");
      return "Seek to: ${two(t ~/ 60)}:${two(t % 60)}/${two(total ~/ 60)}:${two(total % 60)} (${t * 100 ~/ max(total, 1)}%)";
    }

    final hints = skin.hints;
    final volumeAt = hints.point("mainwinVolume", const Offset(107, 57));
    final balanceAt = hints.point("mainwinBalance", const Offset(177, 57));
    final positionAt = hints.point("mainwinPosition", const Offset(16, 72));
    return Stack(
      children: [
        Positioned(
          left: volumeAt.dx,
          top: volumeAt.dy,
          child: SkinSlider(
            image: vol,
            trackSrc: Rect.fromLTWH(0, volY, 68, 13),
            thumbSrc: const Rect.fromLTWH(15, 422, 14, 11),
            thumbSrcPressed: const Rect.fromLTWH(0, 422, 14, 11),
            width: 68,
            trackHeight: 13,
            thumbWidth: 14,
            thumbHeight: 11,
            thumbTop: 1,
            thumbLeft: player.volume * 51 / 255,
            cursor: volBal,
            onChanged: (left) {
              player.setVolume(volumeFrom(left));
              songOverride.value = _volumeText(player.volume);
            },
            onChangeEnd: (_) => songOverride.value = null,
          ),
        ),
        Positioned(
          left: balanceAt.dx,
          top: balanceAt.dy,
          child: SkinSlider(
            image: bal,
            trackSrc: Rect.fromLTWH(9, balY, 38, 13),
            thumbSrc: const Rect.fromLTWH(15, 422, 14, 11),
            thumbSrcPressed: const Rect.fromLTWH(0, 422, 14, 11),
            width: 38,
            trackHeight: 13,
            thumbWidth: 14,
            thumbHeight: 11,
            thumbTop: 1,
            thumbLeft: player.balance * 12 / 127 + 12,
            cursor: volBal,
            onChanged: (left) {
              player.setBalance(balanceFrom(left));
              songOverride.value = _balanceText(player.balance);
            },
            onChangeEnd: (_) => songOverride.value = null,
          ),
        ),
        Positioned(
          left: positionAt.dx,
          top: positionAt.dy,
          child: _SeekBar(
            image: posbar,
            cursor: skin.cursor(SkinCursor.posbar),
            player: player,
            seekFrom: seekFrom,
            seekText: seekText,
            songOverride: songOverride,
          ),
        ),
      ],
    );
  }
}

/// The position bar. Only active while playing; dragging previews the target
/// in the song title and seeks on release (`do_posbar`).
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.image,
    required this.cursor,
    required this.player,
    required this.seekFrom,
    required this.seekText,
    required this.songOverride,
  });

  final ui.Image image;
  final MouseCursor cursor;
  final ClassicPlayer player;
  final int Function(double left) seekFrom;
  final String Function(int position) seekText;
  final ValueNotifier<String?> songOverride;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  int? _preview;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final active = player.playing || player.paused;
    final position = _preview ?? player.position;
    final slider = SkinSlider(
      image: widget.image,
      trackSrc: const Rect.fromLTWH(0, 0, 248, 10),
      thumbSrc: const Rect.fromLTWH(248, 0, 29, 10),
      thumbSrcPressed: const Rect.fromLTWH(278, 0, 29, 10),
      width: 248,
      trackHeight: 10,
      thumbWidth: 29,
      thumbHeight: 10,
      showThumb: active,
      thumbLeft: position * (257 - 29 - 10) / 256,
      cursor: widget.cursor,
      onChanged: (left) {
        final target = widget.seekFrom(left);
        setState(() => _preview = target);
        widget.songOverride.value = widget.seekText(target);
      },
      onChangeEnd: (left) {
        player.setSeek(widget.seekFrom(left));
        setState(() => _preview = null);
        widget.songOverride.value = null;
      },
    );
    // While stopped the bar is inert; the background still shows.
    return IgnorePointer(ignoring: !active, child: slider);
  }
}

class _ShadeLayout extends StatelessWidget {
  const _ShadeLayout({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final tb = skin.image("titlebar.bmp")!;
    final wsSeek = player.position * 12 ~/ 256 + 1;
    final knobX = wsSeek < 6 ? 17.0 : (wsSeek < 9 ? 20.0 : 23.0);
    final active = player.playing || player.paused;
    final normal = skin.cursor(SkinCursor.wsNormal);
    final actions = [
      player.prev,
      player.togglePlay,
      player.pause,
      player.stop,
      player.next,
      () => unawaited(host.openFiles()),
    ];
    const edges = [168.0, 176.0, 186.0, 195.0, 204.0, 215.0, 225.0];
    return Stack(
      children: [
        _Sprite(
          image: tb,
          src: Rect.fromLTWH(27, WindowActivity.of(context) ? 29 : 42, 275, 14),
          left: 0,
          top: 0,
        ),
        // The windowshade transport hit areas (`do_timedisplay`).
        for (var i = 0; i < 6; i++)
          Positioned(
            left: edges[i],
            top: 2,
            child: SkinButton(
              size: Size(edges[i + 1] - edges[i], 10),
              cursor: normal,
              onPressed: actions[i],
              builder: (context, pressed) => const SizedBox.shrink(),
            ),
          ),
        Positioned(
          left: 126,
          top: 4,
          width: 32,
          height: 6,
          child: SkinDragTarget(
            cursor: normal,
            onStart: (_) => player.toggleTimeRemaining(),
            child: _WsDigits(
              image: skin.image("text.bmp")!,
              seconds: _displaySeconds(player),
              negative: player.timeRemaining,
            ),
          ),
        ),
        Positioned(
          left: 226,
          top: 4,
          child: IgnorePointer(
            ignoring: !active,
            child: SkinSlider(
              image: tb,
              trackSrc: const Rect.fromLTWH(0, 36, 17, 7),
              thumbSrc: Rect.fromLTWH(knobX, 36, 3, 7),
              thumbSrcPressed: Rect.fromLTWH(knobX, 36, 3, 7),
              width: 17,
              trackHeight: 7,
              thumbWidth: 3,
              thumbHeight: 7,
              showThumb: active,
              grabCenter: 0,
              thumbLeft: (wsSeek - 1).toDouble(),
              cursor: skin.cursor(SkinCursor.wsPosbar),
              onChangeEnd: (left) =>
                  player.setSeek(left.clamp(0, 13) * 256 ~/ 13),
            ),
          ),
        ),
        Positioned(
          left: 79,
          top: 5,
          child: ClassicVisView(
            player: player,
            colors: skin.visColors,
            windowShade: true,
          ),
        ),
        Positioned(
          left: 78,
          top: 4,
          width: 38,
          height: 7,
          child: SkinDragTarget(
            onStart: (_) => host.clickClassicVis(),
            child: const SizedBox.expand(),
          ),
        ),
        _TitleButtons(host: host, skin: skin, shade: true),
      ],
    );
  }
}

/// The 9×13 time digits from `numbers.bmp`, with the minus sign in remaining
/// mode (`ui_drawtime`).
class _TimeDigits extends StatelessWidget {
  const _TimeDigits({
    required this.image,
    required this.extended,
    required this.seconds,
    required this.negative,
    required this.xs,
  });

  final ui.Image image;
  final bool extended;
  final int seconds;
  final bool negative;

  /// The x of the minus sign and the four digits, from the widget's left.
  final List<double> xs;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(max(63, xs.last + 9), 13),
      painter: _TimeDigitsPainter(image, extended, seconds, negative, xs),
    );
  }
}

class _TimeDigitsPainter extends CustomPainter {
  const _TimeDigitsPainter(
    this.image,
    this.extended,
    this.seconds,
    this.negative,
    this.xs,
  );

  final ui.Image image;
  final List<double> xs;

  /// `nums_ex.bmp`: the minus is a full 9×13 glyph at x = 99.
  final bool extended;
  final int seconds;
  final bool negative;

  @override
  void paint(Canvas canvas, Size size) {
    final minutes = seconds ~/ 60 % 100;
    final secs = seconds % 60;
    final paint = Paint()..filterQuality = ui.FilterQuality.none;
    void digit(double x, int d) => canvas.drawImageRect(
      image,
      Rect.fromLTWH(d * 9.0, 0, 9, 13),
      Rect.fromLTWH(x, 0, 9, 13),
      paint,
    );
    if (negative && extended) {
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(99, 0, 9, 13),
        Rect.fromLTWH(xs[0], 0, 9, 13),
        paint,
      );
    } else if (negative) {
      // The minus sign is a 5×1 strip of numbers.bmp (20,6).
      canvas.drawImageRect(
        image,
        const Rect.fromLTWH(20, 6, 5, 1),
        Rect.fromLTWH(xs[0] + 2, 6, 5, 1),
        paint,
      );
    }
    digit(xs[1], minutes ~/ 10);
    digit(xs[2], minutes % 10);
    digit(xs[3], secs ~/ 10);
    digit(xs[4], secs % 10);
  }

  @override
  bool shouldRepaint(_TimeDigitsPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.extended != extended ||
      oldDelegate.seconds != seconds ||
      oldDelegate.negative != negative ||
      !listEquals(oldDelegate.xs, xs);
}

/// The 5×6 windowshade time digits (`text.bmp` row 6).
class _WsDigits extends StatelessWidget {
  const _WsDigits({
    required this.image,
    required this.seconds,
    required this.negative,
  });

  final ui.Image image;
  final int seconds;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 6),
      painter: _WsDigitsPainter(image, seconds, negative),
    );
  }
}

class _WsDigitsPainter extends CustomPainter {
  const _WsDigitsPainter(this.image, this.seconds, this.negative);

  final ui.Image image;
  final int seconds;
  final bool negative;

  @override
  void paint(Canvas canvas, Size size) {
    final minutes = seconds ~/ 60 % 100;
    final secs = seconds % 60;
    final paint = Paint()..filterQuality = ui.FilterQuality.none;
    void glyph(double x, Rect src) => canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(x, 0, src.width, 6),
      paint,
    );
    // Minus (text.bmp 75,6) or blank (text.bmp 142,0), at x = 130.
    glyph(
      4,
      negative
          ? const Rect.fromLTWH(75, 6, 3, 6)
          : const Rect.fromLTWH(142, 0, 3, 6),
    );
    glyph(8, Rect.fromLTWH((minutes ~/ 10) * 5.0, 6, 5, 6));
    glyph(13, Rect.fromLTWH((minutes % 10) * 5.0, 6, 5, 6));
    glyph(21, Rect.fromLTWH((secs ~/ 10) * 5.0, 6, 5, 6));
    glyph(26, Rect.fromLTWH((secs % 10) * 5.0, 6, 5, 6));
  }

  @override
  bool shouldRepaint(_WsDigitsPainter oldDelegate) =>
      oldDelegate.seconds != seconds || oldDelegate.negative != negative;
}
