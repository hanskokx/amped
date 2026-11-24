import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "wasabi_host.dart";
import "wasabi_skin_data.dart";
import "wasabi_view.dart";

/// One launcher button of the Thinger, the strip a skin's
/// `<componentbucket>` fills: a window it toggles, the name shown while the
/// pointer is over it, and the bitmaps that draw it.
///
/// Wasabi 5 fills the bucket from `Wa2WndEmbed::createWindowOfType`
/// (gen_ff/wa2wndembed.cpp) with these items, in this order.
class WasabiThingerItem {
  const WasabiThingerItem({
    required this.param,
    required this.label,
    required this.bitmap,
    required this.icon,
  });

  /// The `TOGGLE` action parameter of the window the button opens and
  /// closes (`guid:pl`, ...).
  final String param;

  /// The text a `display="componentbucket"` text shows while the pointer is
  /// over the button (`BucketItemT::setAutoText`).
  final String label;

  /// The id of the button's bitmap, which a skin may define; `.hilited` is
  /// the hover image and `.selected` the one shown while the window is open
  /// (`thinger.xml`).
  final String bitmap;

  /// The glyph drawn when the skin has no [bitmap].
  final WasabiThingerIcon icon;

  /// The bitmap for a state: open window, hovered or pressed, or normal.
  String bitmapFor({required bool selected, required bool hilited}) => selected
      ? "$bitmap.selected"
      : hilited
      ? "$bitmap.hilited"
      : bitmap;
}

/// The glyphs amped draws for Thinger buttons a skin does not supply.
enum WasabiThingerIcon { playlist, library, video, vis }

/// The Thinger's buttons, in Wasabi 5's order. The classic player's Minibrowser item
/// (compiled out of Wasabi 5 behind `MINIBROWSER_SUPPORT`) is left out.
const List<WasabiThingerItem> wasabiThingerItems = [
  WasabiThingerItem(
    param: "guid:pl",
    label: "Playlist Editor",
    bitmap: "winamp.thinger.pledit",
    icon: WasabiThingerIcon.playlist,
  ),
  WasabiThingerItem(
    param: "guid:ml",
    label: "Amped Library",
    bitmap: "winamp.thinger.library",
    icon: WasabiThingerIcon.library,
  ),
  WasabiThingerItem(
    param: "guid:video",
    label: "Video Window",
    bitmap: "winamp.thinger.video",
    icon: WasabiThingerIcon.video,
  ),
  WasabiThingerItem(
    param: "guid:vis",
    label: "Visualizations",
    bitmap: "winamp.thinger.vis",
    icon: WasabiThingerIcon.vis,
  ),
];

/// The size of a drawn Thinger button, that of the classic player's own bitmaps.
const Size _iconSize = Size(44, 34);

/// Where each of [items] goes in a horizontal `<componentbucket>` of [size]
/// (`ComponentBucket2::onResize`): from `leftmargin` (2), `spacing` (2)
/// apart, centred vertically, and scaled to the bucket's height when their
/// own differs from it by more than a tenth.
List<Rect> wasabiThingerLayout(
  List<Size> items,
  Size size, {
  int leftMargin = 2,
  int spacing = 2,
}) {
  final rects = <Rect>[];
  var x = leftMargin.toDouble();
  for (final item in items) {
    var w = item.width;
    var h = item.height;
    final ratio = size.height / h;
    if ((ratio - 1).abs() > 0.1) {
      w = (w * ratio).truncateToDouble();
      h = (h * ratio).truncateToDouble();
    }
    rects.add(
      Rect.fromLTWH(x, ((size.height - h) / 2).truncateToDouble(), w, h),
    );
    x += w + spacing;
  }
  return rects;
}

/// How far the Thinger's buttons in a `<componentbucket>` [object] of [size]
/// reach, from its left edge: what its pages (`cb_nextpage`) scroll through.
double wasabiThingerExtent(
  WasabiObject object,
  Size size,
  WasabiSkinData skin,
) {
  final rects = wasabiThingerLayout(
    [
      for (final item in wasabiThingerItems)
        skin.bitmap(item.bitmap)?.size ?? _iconSize,
    ],
    size,
    leftMargin: object.intAttr("leftmargin", 2),
    spacing: object.intAttr("spacing", 2),
  );
  return rects.isEmpty ? 0 : rects.last.right + object.intAttr("spacing", 2);
}

/// A `<componentbucket>`: the Thinger's row of [wasabiThingerItems], each
/// toggling its window through the host's `TOGGLE` action.
class WasabiComponentBucket extends StatelessWidget {
  const WasabiComponentBucket({
    required this.object,
    required this.size,
    required this.skin,
    required this.host,
    required this.container,
    required this.onHover,
    super.key,
  });

  final WasabiObject object;
  final Size size;
  final WasabiSkinData skin;
  final WasabiHost host;

  /// The id of the container the bucket is in.
  final String container;

  /// Called with an item's label as the pointer enters it, and null as it
  /// leaves.
  final ValueChanged<String?> onHover;

  @override
  Widget build(BuildContext context) {
    final sizes = [
      for (final item in wasabiThingerItems)
        skin.bitmap(item.bitmap)?.size ?? _iconSize,
    ];
    final rects = wasabiThingerLayout(
      sizes,
      size,
      leftMargin: object.intAttr("leftmargin", 2),
      spacing: object.intAttr("spacing", 2),
    );
    // A page turned (`cb_nextpage`) moves the buttons along.
    final scroll = object.intAttr("#scroll").toDouble();
    return ClipRect(
      child: Stack(
        children: [
          for (var i = 0; i < wasabiThingerItems.length; i++)
            Positioned.fromRect(
              rect: rects[i].shift(Offset(-scroll, 0)),
              child: _ThingerButton(
                item: wasabiThingerItems[i],
                skin: skin,
                host: host,
                container: container,
                onHover: onHover,
              ),
            ),
        ],
      ),
    );
  }
}

class _ThingerButton extends StatefulWidget {
  const _ThingerButton({
    required this.item,
    required this.skin,
    required this.host,
    required this.container,
    required this.onHover,
  });

  final WasabiThingerItem item;
  final WasabiSkinData skin;
  final WasabiHost host;
  final String container;
  final ValueChanged<String?> onHover;

  @override
  State<_ThingerButton> createState() => _ThingerButtonState();
}

class _ThingerButtonState extends State<_ThingerButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.host.isActive("TOGGLE", item.param);
    final hilited = _hover || _pressed;
    final skin = widget.skin;
    final bitmap =
        skin.bitmap(item.bitmapFor(selected: selected, hilited: hilited)) ??
        skin.bitmap(item.bitmap);
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHover(item.label);
      },
      onExit: (_) {
        setState(() => _hover = false);
        widget.onHover(null);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          WasabiPointerClaim.claim?.call(event);
          setState(() => _pressed = true);
        },
        onPointerUp: (event) {
          if (!_pressed) return;
          setState(() => _pressed = false);
          final box = context.findRenderObject() as RenderBox?;
          if (box == null ||
              !(Offset.zero & box.size).contains(event.localPosition)) {
            return;
          }
          widget.host.runAction(
            WasabiAction("TOGGLE", item.param, container: widget.container),
          );
        },
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: CustomPaint(
          size: Size.infinite,
          painter: bitmap == null
              ? _IconPainter(item.icon, selected: selected, hilited: hilited)
              : _ThingerBitmapPainter(bitmap),
        ),
      ),
    );
  }
}

class _ThingerBitmapPainter extends CustomPainter {
  _ThingerBitmapPainter(this.bitmap) : image = bitmap.image;

  final WasabiBitmap bitmap;

  /// [bitmap]'s picture in the color theme it is painted in.
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      bitmap.src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_ThingerBitmapPainter oldDelegate) =>
      oldDelegate.bitmap != bitmap || oldDelegate.image != image;
}

/// amped's own Thinger glyphs: a rounded plate with a symbol, dim when
/// idle, bright under the pointer, lit while the window is open.
class _IconPainter extends CustomPainter {
  const _IconPainter(
    this.icon, {
    required this.selected,
    required this.hilited,
  });

  final WasabiThingerIcon icon;
  final bool selected;
  final bool hilited;

  @override
  void paint(Canvas canvas, Size size) {
    final plate = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(2),
      const Radius.circular(5),
    );
    if (selected || hilited) {
      canvas.drawRRect(
        plate,
        Paint()
          ..color = selected
              ? const Color(0x5590B8FF)
              : const Color(0x30FFFFFF),
      );
    }
    final ink = Paint()
      ..color = selected
          ? const Color(0xFFFFFFFF)
          : hilited
          ? const Color(0xFFE0E8FF)
          : const Color(0xFF8A96B4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ink.color;
    // The glyph is drawn in a 20x16 box in the middle.
    final scale = math.min(
      size.width / _iconSize.width,
      size.height / _iconSize.height,
    );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-10, -8);
    switch (icon) {
      case WasabiThingerIcon.playlist:
        for (var i = 0; i < 4; i++) {
          final y = 2.0 + i * 4;
          canvas
            ..drawCircle(Offset(1.5, y), 1.2, fill)
            ..drawLine(Offset(5, y), Offset(i.isEven ? 19 : 15, y), ink);
        }
      case WasabiThingerIcon.library:
        for (final (x, h) in const [(2.0, 14.0), (7.0, 12.0), (12.0, 14.0)]) {
          canvas.drawRect(Rect.fromLTWH(x, 16 - h, 3, h), ink);
        }
        canvas.drawLine(const Offset(16, 3), const Offset(19, 16), ink);
      case WasabiThingerIcon.video:
        canvas.drawRRect(
          RRect.fromLTRBR(1, 1, 19, 13, const Radius.circular(2)),
          ink,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8, 4)
            ..lineTo(13, 7)
            ..lineTo(8, 10)
            ..close(),
          fill,
        );
        canvas.drawLine(const Offset(6, 16), const Offset(14, 16), ink);
      case WasabiThingerIcon.vis:
        for (final (i, h) in const [
          (0, 6.0),
          (1, 12.0),
          (2, 16.0),
          (3, 9.0),
          (4, 13.0),
        ]) {
          final x = 2.0 + i * 4;
          canvas.drawLine(Offset(x, 16), Offset(x, 16 - h), ink);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.selected != selected ||
      oldDelegate.hilited != hilited;
}
