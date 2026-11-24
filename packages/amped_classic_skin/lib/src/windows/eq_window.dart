import "dart:math";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";

/// The Equalizer window, rendered from `eqmain.bmp` (`draw_eq.cpp`), with the
/// controls of `Equi.cpp`. Windowshade mode uses `eq_ex.bmp`.
class EqWindow extends StatelessWidget {
  const EqWindow({required this.host, super.key});

  final ClassicHost host;

  @override
  Widget build(BuildContext context) {
    final skin = host.skin!;
    return host.player.eqShade
        ? _EqShadeLayout(host: host, skin: skin)
        : _EqMainLayout(host: host, skin: skin);
  }
}

class _EqMainLayout extends StatelessWidget {
  const _EqMainLayout({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final eqmain = skin.image("eqmain.bmp")!;
    final eqex = skin.image("eq_ex.bmp")!;
    final normal = skin.cursor(SkinCursor.eqNormal);
    final onX = 10.0 + (player.eqEnabled ? 59 : 0);
    final autoX = 35.0 + (player.eqAuto ? 59 : 0);
    return Stack(
      children: [
        SkinImage(image: eqmain, src: const Rect.fromLTWH(0, 0, 275, 116)),
        // Active or inactive title bar (`draw_eq_tbar`).
        SkinImage(
          image: eqmain,
          src: Rect.fromLTWH(
            0,
            WindowActivity.of(context) ? 134 : 149,
            275,
            14,
          ),
        ),
        CursorZone(
          skin: skin,
          rect: const Rect.fromLTRB(0, 0, 276, 14),
          cursor: SkinCursor.eqTitleBar,
        ),
        // ON / AUTO (`do_togbuts`).
        Positioned(
          left: 14,
          top: 18,
          child: SkinButton(
            image: eqmain,
            src: Rect.fromLTWH(onX, 119, 25, 12),
            pressedSrc: Rect.fromLTWH(onX + 118, 119, 25, 12),
            cursor: normal,
            onPressed: () => player.setEqEnabled(!player.eqEnabled),
          ),
        ),
        Positioned(
          left: 39,
          top: 18,
          child: SkinButton(
            image: eqmain,
            src: Rect.fromLTWH(autoX, 119, 33, 12),
            pressedSrc: Rect.fromLTWH(autoX + 118, 119, 33, 12),
            cursor: normal,
            onPressed: () => player.setEqAuto(!player.eqAuto),
          ),
        ),
        // Presets (`do_presetbutton` -> EQ_PRESETS popup menu).
        Positioned(
          left: 217,
          top: 18,
          child: SkinButton(
            image: eqmain,
            src: const Rect.fromLTWH(224, 164, 44, 12),
            pressedSrc: const Rect.fromLTWH(224, 176, 44, 12),
            cursor: normal,
            onPressed: () => host.showMenu(
              ClassicMenu.eqPresets,
              host.toGlobal(SkinWindow.eq, const Offset(217, 30)),
            ),
          ),
        ),
        Positioned(
          left: 86,
          top: 17,
          child: SizedBox(
            width: 113,
            height: 19,
            child: Stack(
              children: [
                SkinImage(
                  image: eqmain,
                  src: const Rect.fromLTWH(0, 294, 113, 19),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EqCurvePainter(
                      image: eqmain,
                      preamp: player.preamp,
                      bands: List.of(player.eqBands),
                      enabled: player.eqEnabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _EqSliders(host: host, skin: skin),
        // Window-shade and close (`draw_eq_tbutton`).
        Positioned(
          left: 254,
          top: 3,
          child: SkinButton(
            cursor: normal,
            size: const Size(9, 9),
            onPressed: player.toggleEqShade,
            builder: (context, pressed) => pressed
                ? SkinImage(image: eqex, src: const Rect.fromLTWH(1, 38, 9, 9))
                : SkinImage(
                    image: eqmain,
                    src: const Rect.fromLTWH(254, 137, 9, 9),
                  ),
          ),
        ),
        Positioned(
          left: 264,
          top: 3,
          child: SkinButton(
            image: eqmain,
            src: const Rect.fromLTWH(0, 116, 9, 9),
            pressedSrc: const Rect.fromLTWH(0, 125, 9, 9),
            cursor: skin.cursor(SkinCursor.eqClose),
            onPressed: () => host.setOpen(SkinWindow.eq, false),
          ),
        ),
      ],
    );
  }
}

/// The preamp and the 10 band sliders (`do_sliders`).
///
/// While a band slider is held, moving the pointer across the other band
/// columns drags those sliders instead, so the curve can be "painted" in one
/// stroke. The value is shown in the main window's song title.
class _EqSliders extends StatefulWidget {
  const _EqSliders({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  State<_EqSliders> createState() => _EqSlidersState();
}

class _EqSlidersState extends State<_EqSliders> {
  static const double _top = 38;
  static const int _numPos = 63 - 11;
  static const List<String> _labels = [
    "Preamp",
    "70Hz",
    "180Hz",
    "320Hz",
    "600Hz",
    "1KHz",
    "3KHz",
    "6KHz",
    "12KHz",
    "14KHz",
    "16KHz",
  ];

  int? _active;
  double _clickOffset = 5;

  ClassicPlayer get _player => widget.host.player;

  static double _columnLeft(int which) =>
      which == 0 ? 21 : 78 + (which - 1) * 18.0;

  int _value(int which) =>
      which == 0 ? _player.preamp : _player.eqBands[which - 1];

  double _thumbTop(int which) =>
      63 - 12 - ((63 - _value(which)) * _numPos) / 64;

  /// The band column under [x] (inclusive of the 12 px hit width).
  int? _columnAt(double x, {required bool bands}) {
    for (var which = bands ? 1 : 0; which <= (bands ? 10 : 0); which++) {
      final left = _columnLeft(which);
      if (x >= left && x <= left + 12) return which;
    }
    return null;
  }

  void _set(int which, Offset local) {
    var d = ((local.dy - _clickOffset - _top) * 64 / _numPos).floor().clamp(
      0,
      63,
    );
    if (d >= 30 && d <= 32) d = 31;
    if (which == 0) {
      _player.setPreamp(d);
    } else {
      _player.setEqBand(which - 1, d);
    }
    var db = -(d - 31.5) / 31.5 * 12;
    if (db.abs() <= 0.32) db = 0;
    widget.host.songTitleOverride.value =
        "EQ: ${_labels[which]}: ${db >= 0 ? "+" : ""}${db.toStringAsFixed(1)} DB";
  }

  void _start(Offset local, {required bool bands}) {
    final which = _columnAt(local.dx, bands: bands);
    if (which == null) return;
    final thumb = _thumbTop(which);
    final y = local.dy - _top;
    _clickOffset = y >= thumb - 1 && y < thumb + 11 ? y - thumb : 5;
    setState(() => _active = which);
    _set(which, local);
  }

  void _update(Offset local, {required bool bands}) {
    final active = _active;
    if (active == null) return;
    final left = _columnLeft(active);
    if (bands && (local.dx < left - 3 || local.dx > left + 15)) {
      final other = _columnAt(local.dx, bands: true);
      if (other == null) return;
      _clickOffset = 5;
      setState(() => _active = other);
      _set(other, local);
      return;
    }
    _set(active, local);
  }

  void _end() {
    setState(() => _active = null);
    widget.host.songTitleOverride.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final eqmain = widget.skin.image("eqmain.bmp")!;
    final cursor = widget.skin.cursor(SkinCursor.eqSlider);
    // Hit areas are relative to (0, 0) of the window so local positions match
    // the original's window coordinates.
    return Stack(
      children: [
        for (var which = 0; which <= 10; which++)
          Positioned(
            left: _columnLeft(which),
            top: _top,
            child: _EqSliderSprite(
              image: eqmain,
              value: _value(which),
              pressed: _active == which,
            ),
          ),
        for (final bands in const [false, true])
          Positioned(
            left: bands ? 78 : 21,
            top: _top,
            width: bands ? 9 * 18 + 14 : 14,
            height: 63,
            child: SkinDragTarget(
              cursor: cursor,
              onStart: (p) =>
                  _start(p + Offset(bands ? 78 : 21, _top), bands: bands),
              onUpdate: (p) =>
                  _update(p + Offset(bands ? 78 : 21, _top), bands: bands),
              onEnd: (_) => _end(),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// One slider (`draw_eq_slid`): a track crop selected by the value, plus the
/// 11×11 thumb.
class _EqSliderSprite extends StatelessWidget {
  const _EqSliderSprite({
    required this.image,
    required this.value,
    required this.pressed,
  });

  final ui.Image image;
  final int value;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final n = (27 - value * 28 ~/ 64).clamp(0, 27);
    final track = n < 14
        ? Rect.fromLTWH(13.0 + n * 15, 164, 14, 63)
        : Rect.fromLTWH(13.0 + (n - 14) * 15, 229, 14, 63);
    final thumbTop = 63 - 12 - ((63 - value) * (63 - 11)) / 64;
    return SizedBox(
      width: 14,
      height: 63,
      child: Stack(
        children: [
          SkinImage(image: image, src: track),
          Positioned(
            left: 1,
            top: thumbTop.floorToDouble(),
            child: SkinImage(
              image: image,
              src: Rect.fromLTWH(0, pressed ? 176 : 164, 11, 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Windowshade (275×14) from `eq_ex.bmp`, with tiny volume and balance
/// sliders (`do_volctrl`/`do_panctrl`).
class _EqShadeLayout extends StatelessWidget {
  const _EqShadeLayout({required this.host, required this.skin});

  final ClassicHost host;
  final ClassicSkinData skin;

  @override
  Widget build(BuildContext context) {
    final player = host.player;
    final eqex = skin.image("eq_ex.bmp")!;
    final normal = skin.cursor(SkinCursor.eqNormal);
    final volBal = skin.cursor(SkinCursor.volBal);
    final title = host.songTitleOverride;
    String volumeText() => "Volume: ${player.volume * 100 ~/ 255}%";
    String balanceText() => player.balance == 0
        ? "Balance: Center"
        : "Balance: ${player.balance.abs() * 100 ~/ 127}% ${player.balance < 0 ? "Left" : "Right"}";
    return Stack(
      children: [
        SkinImage(
          image: eqex,
          src: Rect.fromLTWH(0, WindowActivity.of(context) ? 0 : 15, 275, 14),
        ),
        CursorZone(
          skin: skin,
          rect: const Rect.fromLTRB(0, 0, 276, 14),
          cursor: SkinCursor.eqTitleBar,
        ),
        Positioned(
          left: 61,
          top: 3,
          width: 102,
          height: 9,
          child: SkinDragTarget(
            cursor: volBal,
            onStart: (p) {
              player.setVolume(p.dx.clamp(0, 96) * 255 ~/ 96);
              title.value = volumeText();
            },
            onUpdate: (p) {
              player.setVolume(p.dx.clamp(0, 96) * 255 ~/ 96);
              title.value = volumeText();
            },
            onEnd: (_) => title.value = null,
            child: Stack(
              children: [
                Positioned(
                  left: player.volume * 96 / 255 - 1,
                  top: 1,
                  child: SkinImage(
                    image: eqex,
                    src: Rect.fromLTWH(
                      1.0 + player.volume * 3 ~/ 256 * 3,
                      30,
                      3,
                      7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 163,
          top: 3,
          width: 44,
          height: 9,
          child: SkinDragTarget(
            cursor: volBal,
            onStart: (p) {
              _setPan(player, p.dx);
              title.value = balanceText();
            },
            onUpdate: (p) {
              _setPan(player, p.dx);
              title.value = balanceText();
            },
            onEnd: (_) => title.value = null,
            child: Stack(
              children: [
                Positioned(
                  left: (player.balance + 127) * 42 / 254,
                  top: 1,
                  child: SkinImage(
                    image: eqex,
                    src: Rect.fromLTWH(
                      11.0 + (player.balance + 128) * 3 ~/ 256 * 3,
                      30,
                      3,
                      7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 254,
          top: 3,
          child: SkinButton(
            image: eqex,
            src: const Rect.fromLTWH(254, 3, 9, 9),
            pressedSrc: const Rect.fromLTWH(1, 47, 9, 9),
            cursor: normal,
            onPressed: player.toggleEqShade,
          ),
        ),
        Positioned(
          left: 264,
          top: 3,
          child: SkinButton(
            image: eqex,
            src: const Rect.fromLTWH(11, 38, 9, 9),
            pressedSrc: const Rect.fromLTWH(11, 47, 9, 9),
            cursor: skin.cursor(SkinCursor.eqClose),
            onPressed: () => host.setOpen(SkinWindow.eq, false),
          ),
        ),
      ],
    );
  }

  static void _setPan(ClassicPlayer player, double x) {
    final t = (x - 1).clamp(0, 42);
    var p = (t * 255 ~/ 42 - 127).clamp(-127, 127);
    if (p.abs() < 9) p = 0;
    player.setBalance(p);
  }
}

class _EqCurvePainter extends CustomPainter {
  const _EqCurvePainter({
    required this.image,
    required this.preamp,
    required this.bands,
    required this.enabled,
  });

  final ui.Image image;
  final int preamp;
  final List<int> bands;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    final lineY = 35 - (preamp * 19 / 64).toInt();
    canvas.drawImageRect(
      image,
      const Rect.fromLTWH(0, 314, 113, 1),
      Rect.fromLTWH(0, lineY.toDouble(), 113, 1),
      paint,
    );
    final keys = List<double>.filled(12, 0);
    for (var i = 0; i < 10; i++) {
      // The curve follows the sliders whether the EQ is on or off.
      keys[i + 1] = bands[i] * 19 / 64;
    }
    keys[0] = keys[1];
    keys[11] = keys[10];
    // Each column joins the last with a vertical run, so steep stretches
    // stay connected (`draw_eq_graphthingy`).
    int? lastP;
    for (var x = 0; x < 109; x++) {
      final p = _splinePoint(keys, 1.0 + x / 12.0);
      final thisP = p.toInt().clamp(0, 18);
      final top = lastP == null ? thisP : min(thisP, lastP);
      final bottom = lastP == null ? thisP : max(thisP, lastP);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(115, (294 + top).toDouble(), 1, bottom - top + 1.0),
        Rect.fromLTWH(2 + x.toDouble(), top.toDouble(), 1, bottom - top + 1.0),
        paint,
      );
      lastP = thisP;
    }
  }

  /// A 1-D Kochanek–Bartels spline, mirroring `plSplineGetPoint` from the
  /// original plush library (`original/Src/the classic player/plush/SPLINE.C`).
  double _splinePoint(List<double> keys, double frame) {
    const tens = 0.1;
    const cont = 0.0;
    const bias = 0.0;
    const a = (1 - tens) * (1 + cont) * (1 + bias);
    const b = (1 - tens) * (1 - cont) * (1 - bias);
    const c = (1 - tens) * (1 - cont) * (1 + bias);
    const d = (1 - tens) * (1 + cont) * (1 - bias);
    const t1 = -a / 2;
    const v1 = t1;
    const u1 = a;
    const u2 = (-6 - 2 * a + 2 * b + c) / 2;
    const v2 = (a - b) / 2;
    const t2 = (4 + a - b - c) / 2;
    const t3 = (-4 + b + c - d) / 2;
    const u3 = (6 - 2 * b - c + d) / 2;
    const v3 = b / 2;
    const t4 = d / 2;
    const u4 = -t4;

    final i0 = frame.toInt();
    var i_1 = i0 - 1;
    while (i_1 < 0) {
      i_1 += 12;
    }
    var i1 = i0 + 1;
    while (i1 >= 12) {
      i1 -= 12;
    }
    var i2 = i0 + 2;
    while (i2 >= 12) {
      i2 -= 12;
    }
    final time1 = frame - frame.toInt();
    final time2 = time1 * time1;
    final time3 = time2 * time1;
    final ka = t1 * keys[i_1] + t2 * keys[i0] + t3 * keys[i1] + t4 * keys[i2];
    final kb = u1 * keys[i_1] + u2 * keys[i0] + u3 * keys[i1] + u4 * keys[i2];
    final kc = v1 * keys[i_1] + v2 * keys[i0] + v3 * keys[i1];
    return ka * time3 + kb * time2 + kc * time1 + keys[i0];
  }

  @override
  bool shouldRepaint(_EqCurvePainter oldDelegate) {
    return oldDelegate.preamp != preamp ||
        oldDelegate.bands != bands ||
        oldDelegate.enabled != enabled;
  }
}
