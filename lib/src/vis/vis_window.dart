import "dart:async";
import "dart:ui" as ui;

import "package:flutter/widgets.dart";

import "vis_host.dart";

/// A visualization plug-in's picture, scaled to fit (keeping its shape) on
/// black, with the title line over it: inside the skinned visualization
/// window, or filling the screen with no pointer when [fullscreen]. A
/// double-click switches between the two (as does Alt+Enter; Escape leaves
/// fullscreen, see [VisHost]).
class VisWindowContent extends StatelessWidget {
  const VisWindowContent({
    required this.host,
    required this.fullscreen,
    super.key,
  });

  final VisHost host;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = fullscreen ? host.topInset : 0.0;
        host.resize(
          constraints.maxWidth.toInt(),
          (constraints.maxHeight - top).toInt(),
          fullscreen: fullscreen,
        );
        return GestureDetector(
          onDoubleTap: host.toggleFullscreen,
          child: MouseRegion(
            cursor: fullscreen ? SystemMouseCursors.none : MouseCursor.defer,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: ValueListenableBuilder(
                valueListenable: host.picture,
                builder: (context, image, _) => Padding(
                  padding: EdgeInsets.only(top: top),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _VisPicturePainter(
                      image: image,
                      title: host.overlayTitle,
                      opaque: host.overlayOpaque,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VisPicturePainter extends CustomPainter {
  const _VisPicturePainter({
    required this.image,
    required this.title,
    required this.opaque,
  });

  final ui.Image? image;
  final String? title;
  final bool opaque;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final scale = (size.width / iw) < (size.height / ih)
        ? size.width / iw
        : size.height / ih;
    final dest = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: iw * scale,
      height: ih * scale,
    );
    // Enlarged pixels stay sharp; a picture shrunk into the small window
    // is smoothed.
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      dest,
      Paint()
        ..filterQuality = scale < 1 ? FilterQuality.medium : FilterQuality.none,
    );
    final title = this.title;
    if (title == null || title.isEmpty) return;
    // Drawn into the picture's own pixels and scaled with it, as the
    // original draws it into its framebuffer. (Re-laying out large text
    // every frame also trips Impeller's glyph cache.)
    final line = _TitleCache.image(title, opaque: opaque, width: image.width);
    canvas.drawImageRect(
      line,
      Rect.fromLTWH(0, 0, line.width.toDouble(), line.height.toDouble()),
      Rect.fromLTWH(
        dest.left,
        dest.top,
        line.width * scale,
        line.height * scale,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_VisPicturePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.title != title ||
      oldDelegate.opaque != opaque;
}

/// The title line, rendered once per text: Arial bold 12 pt at 96 dpi
/// (16 px), white, centred in the picture's top 32 rows (`DrawText(...,
/// DT_CENTER|DT_TOP)`), on black when [opaque].
abstract final class _TitleCache {
  static String? _key;
  static ui.Image? _image;

  static ui.Image image(
    String title, {
    required bool opaque,
    required int width,
  }) {
    final key = "$opaque|$width|$title";
    final cached = _image;
    if (key == _key && cached != null) return cached;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final text = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontFamily: "Arial",
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: const Color(0xFFFFFFFF),
          backgroundColor: opaque ? const Color(0xFF000000) : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: width.toDouble());
    text.paint(canvas, Offset((width - text.width) / 2, 0));
    text.dispose();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, 32);
    picture.dispose();
    // The previous line may still be on screen this frame.
    final old = _image;
    if (old != null) scheduleMicrotask(old.dispose);
    _key = key;
    _image = image;
    return image;
  }
}
