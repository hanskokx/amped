import "dart:ui" as ui;

import "package:flutter/widgets.dart";

/// Draws a crop (`src`) of [image] into a `width` × `height` box, the Flutter
/// equivalent of a GDI `BitBlt(SRCCOPY)` from a skin bitmap. Uses nearest
/// neighbor (no smoothing) by default so upscaled skin art stays pixel crisp.
class SkinImage extends StatelessWidget {
  const SkinImage({
    required this.image,
    required this.src,
    super.key,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.none,
  });

  final ui.Image image;
  final Rect src;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width ?? src.width, height ?? src.height),
      painter: _SkinImagePainter(image, src, filterQuality),
    );
  }
}

class _SkinImagePainter extends CustomPainter {
  const _SkinImagePainter(this.image, this.src, this.filterQuality);

  final ui.Image image;
  final Rect src;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = filterQuality,
    );
  }

  @override
  bool shouldRepaint(_SkinImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.src != src ||
        oldDelegate.filterQuality != filterQuality;
  }
}
