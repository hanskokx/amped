import "dart:ui" as ui;

import "package:flutter/widgets.dart";

import "skin_controls.dart";

/// A horizontal skin slider (volume, balance, seek): a track crop with a
/// thumb crop on top.
///
/// Mirrors `do_volbar`/`do_panbar`/`do_posbar`: pressing the thumb keeps the
/// grab offset, pressing elsewhere on the track centers the thumb on the
/// pointer, and the drag continues outside the control until release. The
/// caller maps between its value and [thumbLeft] so the original's slightly
/// uneven travel ranges are preserved; callbacks receive the proposed thumb
/// left edge in local pixels (unclamped, so callers clamp the value).
class SkinSlider extends StatefulWidget {
  const SkinSlider({
    required this.image,
    required this.trackSrc,
    required this.thumbSrc,
    required this.thumbSrcPressed,
    required this.width,
    required this.trackHeight,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.thumbLeft,
    this.thumbTop,
    this.showThumb = true,
    this.grabCenter,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.cursor = MouseCursor.defer,
    super.key,
  });

  final ui.Image image;

  /// Track crop drawn into the full `width` × `trackHeight` box.
  final Rect trackSrc;

  final Rect thumbSrc;
  final Rect thumbSrcPressed;
  final double width;
  final double trackHeight;
  final double thumbWidth;
  final double thumbHeight;

  /// The thumb's left edge in local pixels.
  final double thumbLeft;

  /// The thumb's top edge; defaults to vertically centered.
  final double? thumbTop;

  /// Whether the thumb is drawn (the seek bar hides it while stopped).
  final bool showThumb;

  /// The grab offset used when the press misses the thumb; defaults to half
  /// the thumb width.
  final double? grabCenter;

  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final MouseCursor cursor;

  @override
  State<SkinSlider> createState() => _SkinSliderState();
}

class _SkinSliderState extends State<SkinSlider> {
  double? _grab;

  double _left(Offset local) => local.dx - (_grab ?? 0);

  void _start(Offset local) {
    final onThumb =
        widget.showThumb &&
        local.dx >= widget.thumbLeft &&
        local.dx < widget.thumbLeft + widget.thumbWidth;
    setState(() {
      _grab = onThumb
          ? local.dx - widget.thumbLeft
          : (widget.grabCenter ?? (widget.thumbWidth / 2).floorToDouble());
    });
    widget.onChangeStart?.call(_left(local));
    widget.onChanged?.call(_left(local));
  }

  void _update(Offset local) {
    if (_grab == null) return;
    widget.onChanged?.call(_left(local));
  }

  void _end(Offset local) {
    if (_grab == null) return;
    final left = _left(local);
    setState(() => _grab = null);
    widget.onChangeEnd?.call(left);
  }

  @override
  Widget build(BuildContext context) {
    return SkinDragTarget(
      cursor: widget.cursor,
      onStart: _start,
      onUpdate: _update,
      onEnd: _end,
      child: CustomPaint(
        size: Size(widget.width, widget.trackHeight),
        painter: _SkinSliderPainter(
          image: widget.image,
          trackSrc: widget.trackSrc,
          thumbSrc: _grab != null ? widget.thumbSrcPressed : widget.thumbSrc,
          thumbRect: widget.showThumb
              ? Rect.fromLTWH(
                  widget.thumbLeft,
                  widget.thumbTop ??
                      (widget.trackHeight - widget.thumbHeight) / 2,
                  widget.thumbWidth,
                  widget.thumbHeight,
                )
              : null,
        ),
      ),
    );
  }
}

class _SkinSliderPainter extends CustomPainter {
  const _SkinSliderPainter({
    required this.image,
    required this.trackSrc,
    required this.thumbSrc,
    required this.thumbRect,
  });

  final ui.Image image;
  final Rect trackSrc;
  final Rect thumbSrc;
  final Rect? thumbRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(image, trackSrc, Offset.zero & size, paint);
    final thumb = thumbRect;
    if (thumb != null) canvas.drawImageRect(image, thumbSrc, thumb, paint);
  }

  @override
  bool shouldRepaint(_SkinSliderPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.trackSrc != trackSrc ||
        oldDelegate.thumbSrc != thumbSrc ||
        oldDelegate.thumbRect != thumbRect;
  }
}
