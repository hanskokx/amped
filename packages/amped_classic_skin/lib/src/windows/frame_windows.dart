import "dart:typed_data";
import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";

/// Where the picture goes inside the Video window's `video.bmp` frame
/// (`LayoutChildren`: at 11, 20, the window less 19×58).
const EdgeInsets videoWindowInsets = EdgeInsets.fromLTRB(11, 20, 8, 38);

/// The Video window, framed by `video.bmp` (`draw_vw.cpp`) around the
/// picture.
class VideoWindow extends StatelessWidget {
  const VideoWindow({
    required this.host,
    required this.content,
    this.title = "",
    this.time = "",
    this.badge = "",
    this.onZoom,
    this.onFullscreen,
    this.onTv,
    this.onMisc,
    super.key,
  });

  final ClassicHost host;

  /// The picture, inside the frame.
  final Widget content;

  /// The status line under the picture (`draw_vw_info`): the video's [title]
  /// on the left, cut short when the window is narrow; the playback [time]
  /// and the picture size [badge] (`FHD`) right-aligned.
  final String title;
  final String time;
  final String badge;

  /// The 1x and 2x buttons, with the zoom asked for (`VIDCMD_1X`, `_2X`).
  final ValueChanged<double>? onZoom;

  /// The fullscreen button (`VIDCMD_FULLSCREEN`).
  final VoidCallback? onFullscreen;

  /// The TV button (`VIDCMD_TV`).
  final VoidCallback? onTv;

  /// The misc button, which opens the video options menu (`VIDCMD_MISC`).
  final VoidCallback? onMisc;

  @override
  Widget build(BuildContext context) {
    final skin = host.skin!;
    final video = skin.image("video.bmp")!;
    final size = host.baseSize(SkinWindow.video);
    final normal = skin.cursor(SkinCursor.normal);
    final onZoom = this.onZoom;
    final fontName = skin.pledit.fontName;
    return Stack(
      children: [
        CustomPaint(
          size: size,
          painter: _VideoFramePainter(
            video,
            active: WindowActivity.of(context),
          ),
        ),
        Positioned(
          left: videoWindowInsets.left,
          top: videoWindowInsets.top,
          right: videoWindowInsets.right,
          bottom: videoWindowInsets.bottom,
          child: content,
        ),
        // `draw_vw_info`: the playlist font in the minibrowser colours.
        if (title.isNotEmpty || time.isNotEmpty || badge.isNotEmpty)
          Positioned(
            left: 92,
            right: 25,
            top: size.height - 27,
            height: 14,
            child: _VideoInfo(
              title: title,
              time: time,
              badge: badge,
              style: TextStyle(
                fontFamily: fontName.isEmpty ? "Arial" : fontName,
                fontSize: 10,
                height: 1.2,
                color: skin.pledit.mbFg,
                backgroundColor: skin.pledit.mbBg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              badgeColor: skin.pledit.mbFg,
              background: skin.pledit.mbBg,
            ),
          ),
        CursorZone(
          skin: skin,
          rect: Rect.fromLTRB(0, 0, size.width, 14),
          cursor: SkinCursor.titleBar,
        ),
        // Fullscreen, 1x, 2x, TV, misc (`draw_vw_mbuts`).
        for (var i = 0; i < 5; i++)
          Positioned(
            left: 9.0 + i * 15,
            top: size.height - 29,
            child: SkinButton(
              image: video,
              src: Rect.fromLTWH(9.0 + i * 15, 51, 15, 18),
              pressedSrc: Rect.fromLTWH(158.0 + i * 15, 42, 15, 18),
              cursor: normal,
              onPressed: switch (i) {
                0 => onFullscreen,
                3 => onTv,
                4 => onMisc,
                1 || 2 when onZoom != null => () => onZoom(i.toDouble()),
                _ => null,
              },
            ),
          ),
        Positioned(
          left: size.width - 11,
          top: 3,
          child: SkinButton(
            image: video,
            src: const Rect.fromLTWH(167, 3, 9, 9),
            pressedSrc: const Rect.fromLTWH(148, 42, 9, 9),
            cursor: skin.cursor(SkinCursor.close),
            onPressed: () => host.setOpen(SkinWindow.video, false),
          ),
        ),
        _ResizeGrip(
          host: host,
          window: SkinWindow.video,
          skin: skin,
          size: size,
        ),
      ],
    );
  }
}

/// The Video window's status line. The time takes the room its widest form
/// would, so the title does not shift as the digits change.
class _VideoInfo extends StatelessWidget {
  const _VideoInfo({
    required this.title,
    required this.time,
    required this.badge,
    required this.style,
    required this.badgeColor,
    required this.background,
  });

  final String title;
  final String time;
  final String badge;
  final TextStyle style;
  final Color badgeColor;
  final Color background;

  static double _width(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final timeWidth = _width(time.replaceAll(RegExp(r"\d"), "0"), style);
    final badgeWidth = badge.isEmpty ? 0.0 : _width(badge, style) + 8;
    return ColoredBox(
      color: background,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (time.isNotEmpty)
            SizedBox(
              width: timeWidth,
              child: Text(
                time,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          if (badge.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              width: badgeWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: badgeColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(badge, maxLines: 1, style: style),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Media Library, shown in the generic skinned frame of embedded windows
/// (`gen.bmp`, `draw_embed.cpp`) around [content].
class LibraryWindow extends StatelessWidget {
  const LibraryWindow({
    required this.host,
    required this.title,
    required this.content,
    super.key,
  });

  final ClassicHost host;

  /// The title bar text.
  final String title;

  /// What the library shows, inside the frame.
  final Widget content;

  @override
  Widget build(BuildContext context) => _EmbedWindow(
    host: host,
    window: SkinWindow.library,
    title: title,
    content: content,
  );
}

/// The window visualization plug-ins draw in, in the generic skinned frame
/// of embedded windows (`gen.bmp`): resizable, docking with the others,
/// closing ends the visualization. Double-click or Alt+Enter for
/// fullscreen.
class VisWindow extends StatelessWidget {
  const VisWindow({
    required this.host,
    required this.content,
    required this.title,
    required this.labels,
    required this.random,
    required this.onPrevious,
    required this.onNext,
    required this.onRandom,
    required this.onFullscreen,
    required this.onOptions,
    super.key,
  });

  final ClassicHost host;

  /// What the visualization plug-in draws, inside the frame.
  final Widget content;

  /// The title bar text ("Visualizer").
  final String title;

  /// The button labels: previous, next, random, fullscreen, options.
  final ({
    String previous,
    String next,
    String random,
    String fullscreen,
    String options,
  })
  labels;

  /// Whether the next module is picked at random.
  final bool random;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRandom;
  final VoidCallback onFullscreen;

  /// Opens the options menu at the global position.
  final void Function(Offset position) onOptions;

  @override
  Widget build(BuildContext context) {
    final size = host.baseSize(SkinWindow.vis);
    return Stack(
      children: [
        _EmbedWindow(
          contentDragsWindow: true,
          host: host,
          window: SkinWindow.vis,
          title: title,
          content: content,
          bottomExtra: _visBarHeight,
        ),
        // The base skin's buttons, on a bar between the picture and the
        // frame's bottom edge.
        Positioned(
          left: embedWindowInsets.left,
          top: size.height - embedWindowInsets.bottom - _visBarHeight,
          right: embedWindowInsets.right,
          height: _visBarHeight,
          child: StripFrame(
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              // A narrow window clips the last buttons.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    StripButton(
                      icon: _VisIcon.previous,
                      label: labels.previous,
                      onPressed: onPrevious,
                    ),
                    StripButton(
                      icon: _VisIcon.next,
                      label: labels.next,
                      onPressed: onNext,
                    ),
                    StripButton(
                      icon: _VisIcon.random,
                      label: labels.random,
                      onPressed: onRandom,
                      selected: random,
                    ),
                    StripButton(
                      icon: _VisIcon.fullscreen,
                      label: labels.fullscreen,
                      onPressed: onFullscreen,
                    ),
                    StripButton(
                      icon: _VisIcon.options,
                      label: labels.options,
                      onPressed: () => onOptions(host.cursorPosition),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _VisIcon { previous, next, random, fullscreen, options }

/// A raised, hoverable button of the bottom strip of the embedded windows
/// (visualization, library): a small icon, if any, and its label.
class StripButton extends StatefulWidget {
  const StripButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.enabled = true,
    super.key,
  });

  final String label;

  /// Null for a button of text alone.
  final Object? icon;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;

  @override
  State<StripButton> createState() => _StripButtonState();
}

/// The frame the bottom strip of an embedded window sits in: black with an
/// inset edge, like the bar under the Video window's picture.
class StripFrame extends StatelessWidget {
  const StripFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0xFF000000),
      border: Border(
        top: BorderSide(color: Color(0xFF1C1C2A)),
        left: BorderSide(color: Color(0xFF1C1C2A)),
        right: BorderSide(color: Color(0xFF6A6A88)),
        bottom: BorderSide(color: Color(0xFF6A6A88)),
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(1), child: child),
  );
}

class _StripButtonState extends State<StripButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final lit = enabled && (_hover || widget.selected);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: enabled ? widget.onPressed : null,
          child: Container(
            height: 12,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: _down
                  ? const Color(0xFF14141C)
                  : lit
                  ? const Color(0xFF50506A)
                  : const Color(0xFF30303F),
              border: Border.all(
                color: lit ? const Color(0xFFB4B4D0) : const Color(0xFF70708A),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon case final _VisIcon icon) ...[
                  CustomPaint(
                    size: const Size(7, 7),
                    painter: _VisIconPainter(icon),
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 8,
                    height: 1,
                    color: enabled
                        ? const Color(0xFFE4E4F0)
                        : const Color(0xFF8A8AA0),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisIconPainter extends CustomPainter {
  const _VisIconPainter(this.icon);

  final _VisIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFE4E4F0);
    final line = Paint()
      ..color = const Color(0xFFE4E4F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    Path triangle(double x, {required bool right}) => Path()
      ..moveTo(right ? x : x + w / 2, 0)
      ..lineTo(right ? x + w / 2 : x, h / 2)
      ..lineTo(right ? x : x + w / 2, h)
      ..close();
    switch (icon) {
      case _VisIcon.previous:
        canvas.drawPath(triangle(0, right: false), fill);
        canvas.drawPath(triangle(w / 2 - 0.5, right: false), fill);
      case _VisIcon.next:
        canvas.drawPath(triangle(0, right: true), fill);
        canvas.drawPath(triangle(w / 2 - 0.5, right: true), fill);
      case _VisIcon.random:
        canvas.drawRect(Rect.fromLTWH(0.5, 0.5, w - 1, h - 1), line);
        for (final p in [
          Offset(w * 0.3, h * 0.3),
          Offset(w * 0.5, h * 0.5),
          Offset(w * 0.7, h * 0.7),
        ]) {
          canvas.drawCircle(p, 0.6, fill);
        }
      case _VisIcon.fullscreen:
        const c = 2.5;
        canvas.drawPath(
          Path()
            ..moveTo(0.5, c)
            ..lineTo(0.5, 0.5)
            ..lineTo(c, 0.5)
            ..moveTo(w - c, 0.5)
            ..lineTo(w - 0.5, 0.5)
            ..lineTo(w - 0.5, c)
            ..moveTo(w - 0.5, h - c)
            ..lineTo(w - 0.5, h - 0.5)
            ..lineTo(w - c, h - 0.5)
            ..moveTo(c, h - 0.5)
            ..lineTo(0.5, h - 0.5)
            ..lineTo(0.5, h - c),
          line,
        );
      case _VisIcon.options:
        canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.3)
            ..lineTo(w, h * 0.3)
            ..lineTo(w / 2, h * 0.9)
            ..close(),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_VisIconPainter oldDelegate) => oldDelegate.icon != icon;
}

/// The Album Art window (Alt+A), in the generic skinned frame of embedded
/// windows like the classic player's gen_classicart: resizable, docking with the
/// others.
class AlbumArtWindow extends StatelessWidget {
  const AlbumArtWindow({
    required this.host,
    required this.title,
    required this.content,
    this.showControls = true,
    super.key,
  });

  final ClassicHost host;

  /// Whether the frame has its close button (a window that only shows
  /// something, such as the notification, has none).
  final bool showControls;

  /// The title bar text ("Album Art").
  final String title;

  /// The cover, inside the frame.
  final Widget content;

  @override
  Widget build(BuildContext context) => _EmbedWindow(
    contentDragsWindow: true,
    host: host,
    window: SkinWindow.albumArt,
    title: title,
    content: content,
    showControls: showControls,
  );
}

/// The height of the visualization window's bar of buttons.
const double _visBarHeight = 20;

/// Where an embedded window's content goes inside its `gen.bmp` frame
/// (`embwnd.cpp`).
const EdgeInsets embedWindowInsets = EdgeInsets.fromLTRB(11, 20, 8, 14);

/// An embedded window (`embwnd.cpp`): the `gen.bmp` frame titled [title]
/// around [content], with a close button and a resize grip.
class _EmbedWindow extends StatelessWidget {
  const _EmbedWindow({
    required this.host,
    required this.window,
    required this.title,
    required this.content,
    this.bottomExtra = 0,
    this.showControls = true,
    this.contentDragsWindow = false,
  });

  final bool showControls;

  /// Whether pressing the content (that no control inside claims) drags the
  /// window. Off by default, so that a list or scrollbar in the content
  /// never moves the window; only the frame does.
  final bool contentDragsWindow;
  final ClassicHost host;
  final SkinWindow window;
  final String title;
  final Widget content;

  /// Room under the content, inside the frame, for something of the window's
  /// own.
  final double bottomExtra;

  @override
  Widget build(BuildContext context) {
    final skin = host.skin!;
    final gen = skin.image("gen.bmp")!;
    final size = host.baseSize(window);
    return Stack(
      children: [
        FutureBuilder<_GenFont>(
          future: _GenFont.of(gen),
          builder: (context, font) => CustomPaint(
            size: size,
            painter: _EmbedFramePainter(
              gen,
              title,
              font.data,
              active: WindowActivity.of(context),
            ),
          ),
        ),
        // The content fills the frame's inside (`embwnd.cpp`).
        Positioned(
          left: embedWindowInsets.left,
          top: embedWindowInsets.top,
          right: embedWindowInsets.right,
          bottom: embedWindowInsets.bottom + bottomExtra,
          child: contentDragsWindow
              ? content
              : SkinNoWindowDrag(child: content),
        ),
        CursorZone(
          skin: skin,
          rect: Rect.fromLTRB(0, 0, size.width, 14),
          cursor: SkinCursor.titleBar,
        ),
        if (showControls) ...[
          Positioned(
            left: size.width - 11,
            top: 3,
            child: SkinButton(
              image: gen,
              src: const Rect.fromLTWH(144, 3, 9, 9),
              pressedSrc: const Rect.fromLTWH(148, 42, 9, 9),
              cursor: skin.cursor(SkinCursor.close),
              onPressed: () => host.setOpen(window, false),
            ),
          ),
          _ResizeGrip(host: host, window: window, skin: skin, size: size),
        ],
      ],
    );
  }
}

/// A dialog drawn in the skin: the `gen.bmp` frame (as embedded windows
/// have) titled [title], around [child], with a close button. The window
/// around it has no frame of its own; dragging the title bar calls
/// [onDragStart] and [onDragUpdate] for the app to move it.
class SkinnedDialogFrame extends StatelessWidget {
  const SkinnedDialogFrame({
    required this.skin,
    required this.title,
    required this.size,
    required this.child,
    this.onClose,
    this.onDragStart,
    this.onDragUpdate,
    this.onResizeStart,
    this.onResizeUpdate,
    super.key,
  });

  final ClassicSkinData skin;
  final String title;

  /// A drag on the grip in the bottom-right corner, when the dialog can be
  /// resized: the app resizes the window.
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeUpdate;

  /// The dialog's size.
  final Size size;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final gen = skin.image("gen.bmp")!;
    return SkinButtonScope(
      child: MouseRegion(
        cursor: skin.cursor(SkinCursor.normal),
        child: Stack(
          children: [
            FutureBuilder<_GenFont>(
              future: _GenFont.of(gen),
              builder: (context, font) => CustomPaint(
                size: size,
                painter: _EmbedFramePainter(
                  gen,
                  title,
                  font.data,
                  active: WindowActivity.of(context),
                ),
              ),
            ),
            Positioned(
              left: embedWindowInsets.left,
              top: embedWindowInsets.top,
              right: embedWindowInsets.right,
              bottom: embedWindowInsets.bottom,
              child: child,
            ),
            Positioned(
              left: 0,
              top: 0,
              width: size.width - 14,
              height: 14,
              child: SkinDragTarget(
                cursor: skin.cursor(SkinCursor.titleBar),
                onStart: (_) => onDragStart?.call(),
                onUpdate: (_) => onDragUpdate?.call(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: size.width - 11,
              top: 3,
              child: SkinButton(
                image: gen,
                src: const Rect.fromLTWH(144, 3, 9, 9),
                pressedSrc: const Rect.fromLTWH(148, 42, 9, 9),
                cursor: skin.cursor(SkinCursor.close),
                onPressed: onClose,
              ),
            ),
            if (onResizeStart != null)
              Positioned(
                left: size.width - 20,
                top: size.height - 20,
                width: 20,
                height: 20,
                child: SkinDragTarget(
                  cursor: skin.cursor(SkinCursor.plSize),
                  onStart: (_) => onResizeStart?.call(),
                  onUpdate: (_) => onResizeUpdate?.call(),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bottom-right resize area of embedded windows (`embwnd.cpp` `do_size`:
/// within 20 px of both edges and 30 px of the corner, Manhattan distance).
class _ResizeGrip extends StatefulWidget {
  const _ResizeGrip({
    required this.host,
    required this.window,
    required this.skin,
    required this.size,
  });

  final ClassicHost host;
  final SkinWindow window;
  final ClassicSkinData skin;
  final Size size;

  @override
  State<_ResizeGrip> createState() => _ResizeGripState();
}

class _ResizeGripState extends State<_ResizeGrip> {
  Offset? _grab;

  Offset _pointer() {
    final origin = widget.host.windowOrigin(widget.window);
    return (widget.host.cursorPosition - origin) / widget.host.player.uiScale;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.size.width - 20,
      top: widget.size.height - 20,
      width: 20,
      height: 20,
      child: SkinDragTarget(
        cursor: widget.skin.cursor(SkinCursor.plSize),
        onStart: (_) {
          final size = widget.host.fullSize(widget.window);
          _grab = Offset(size.width, size.height) - _pointer();
        },
        onUpdate: (_) {
          final grab = _grab;
          if (grab == null) return;
          final target = _pointer() + grab;
          widget.host.resize(widget.window, Size(target.dx, target.dy));
        },
        onEnd: (_) => _grab = null,
        child: const SizedBox.expand(),
      ),
    );
  }
}

final Paint _blit = Paint()..filterQuality = FilterQuality.none;

void _draw(Canvas canvas, ui.Image image, Rect src, Rect dst) =>
    canvas.drawImageRect(image, src, dst, _blit);

/// Draws the left/right border columns from y = 20 down to [bottom], tiling
/// 29 px pieces and stretching the remainder (`draw_vw`/`draw_embed`).
void _drawSides(Canvas canvas, ui.Image image, double width, double bottom) {
  var y = 20.0;
  while (y + 29 <= bottom) {
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(127, 42, 11, 29),
      Rect.fromLTWH(0, y, 11, 29),
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(139, 42, 8, 29),
      Rect.fromLTWH(width - 8, y, 8, 29),
    );
    y += 29;
  }
  if (y < bottom) {
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(127, 42, 11, 29),
      Rect.fromLTWH(0, y, 11, bottom - y),
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(139, 42, 8, 29),
      Rect.fromLTWH(width - 8, y, 8, bottom - y),
    );
  }
}

/// Tiles a 25 px piece across [from, to), stretching the remainder.
void _tileX(
  Canvas canvas,
  ui.Image image,
  Rect src,
  double from,
  double to,
  double y,
) {
  var x = from;
  while (x + 25 <= to) {
    _draw(canvas, image, src, Rect.fromLTWH(x, y, 25, src.height));
    x += 25;
  }
  if (x < to)
    _draw(canvas, image, src, Rect.fromLTWH(x, y, to - x, src.height));
}

class _VideoFramePainter extends CustomPainter {
  const _VideoFramePainter(this.image, {required this.active});

  final ui.Image image;

  /// Whether the window is active (`draw_vw_tbar(state)`).
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    // Title bar (`draw_vw_tbar`): caps, a centered 100 px title piece, fill.
    final state = active ? 0.0 : 21.0;
    _draw(
      canvas,
      image,
      Rect.fromLTWH(0, state, 25, 20),
      const Rect.fromLTWH(0, 0, 25, 20),
    );
    final fill = (w - 150) / 2;
    _tileX(
      canvas,
      image,
      Rect.fromLTWH(127, state, 25, 20),
      25,
      25 + fill,
      0,
    );
    _draw(
      canvas,
      image,
      Rect.fromLTWH(26, state, 100, 20),
      Rect.fromLTWH(25 + fill, 0, 100, 20),
    );
    _tileX(
      canvas,
      image,
      Rect.fromLTWH(127, state, 25, 20),
      125 + fill,
      w - 25,
      0,
    );
    _draw(
      canvas,
      image,
      Rect.fromLTWH(153, state, 25, 20),
      Rect.fromLTWH(w - 25, 0, 25, 20),
    );
    _drawSides(canvas, image, w, h - 38);
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(0, 42, 125, 38),
      Rect.fromLTWH(0, h - 38, 125, 38),
    );
    _tileX(
      canvas,
      image,
      const Rect.fromLTWH(127, 81, 25, 38),
      125,
      w - 125,
      h - 38,
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(0, 81, 125, 38),
      Rect.fromLTWH(w - 125, h - 38, 125, 38),
    );
  }

  @override
  bool shouldRepaint(_VideoFramePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.active != active;
}

class _EmbedFramePainter extends CustomPainter {
  const _EmbedFramePainter(
    this.image,
    this.title,
    this.font, {
    required this.active,
  });

  final ui.Image image;
  final String title;
  final _GenFont? font;

  /// Whether the window is active (`draw_embed_tbar(state)`).
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );

    // Title bar (`draw_embed_tbar`): the text area is sized to the title,
    // rounded up to 25 px, and centered between two fills.
    final state = active ? 0.0 : 21.0;
    final textExact = font?.measure(title) ?? 0;
    var textWidth = textExact + 24;
    textWidth -= textWidth % 25;
    if (textWidth > w - 100) textWidth = w - 100;
    final fill = w - 100 - textWidth;
    _draw(
      canvas,
      image,
      Rect.fromLTWH(0, state, 25, 20),
      const Rect.fromLTWH(0, 0, 25, 20),
    );
    var x = 25.0;
    final leftFill =
        (fill / 25).floor() ~/ 2 * 25 + ((fill / 25).floor().isOdd ? 12 : 0);
    _tileX(
      canvas,
      image,
      Rect.fromLTWH(104, state, 25, 20),
      x,
      x + leftFill,
      0,
    );
    x += leftFill;
    _draw(
      canvas,
      image,
      Rect.fromLTWH(26, state, 25, 20),
      Rect.fromLTWH(x, 0, 25, 20),
    );
    x += 25;
    final textStart = x;
    _tileX(
      canvas,
      image,
      Rect.fromLTWH(52, state, 25, 20),
      x,
      x + textWidth,
      0,
    );
    x += textWidth;
    _draw(
      canvas,
      image,
      Rect.fromLTWH(78, state, 25, 20),
      Rect.fromLTWH(x, 0, 25, 20),
    );
    x += 25;
    _tileX(
      canvas,
      image,
      Rect.fromLTWH(104, state, 25, 20),
      x,
      w - 25,
      0,
    );
    _draw(
      canvas,
      image,
      Rect.fromLTWH(130, state, 25, 20),
      Rect.fromLTWH(w - 25, 0, 25, 20),
    );
    font?.draw(
      canvas,
      title,
      textStart + (textWidth - textExact) / 2 + 1,
      4,
      textWidth,
      active: active,
    );

    _drawSides(canvas, image, w, h - 38);
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(158, 42, 11, 24),
      Rect.fromLTWH(0, h - 38, 11, 24),
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(170, 42, 8, 24),
      Rect.fromLTWH(w - 8, h - 38, 8, 24),
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(0, 42, 125, 14),
      Rect.fromLTWH(0, h - 14, 125, 14),
    );
    _tileX(
      canvas,
      image,
      const Rect.fromLTWH(127, 72, 25, 14),
      125,
      w - 125,
      h - 14,
    );
    _draw(
      canvas,
      image,
      const Rect.fromLTWH(0, 57, 125, 14),
      Rect.fromLTWH(w - 125, h - 14, 125, 14),
    );
  }

  @override
  bool shouldRepaint(_EmbedFramePainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.title != title ||
      oldDelegate.font != font ||
      oldDelegate.active != active;
}

/// The title-bar letters of `gen.bmp`: A–Z laid out at y = 88 (active) and
/// y = 96 (inactive), 7 px tall, each followed by a 1 px column of the
/// background color.
class _GenFont {
  _GenFont._(this.image, this.offsets, this.widths);

  static final Expando<Future<_GenFont>> _cache = Expando();

  static Future<_GenFont> of(ui.Image image) => _cache[image] ??= _scan(image);

  static Future<_GenFont> _scan(ui.Image image) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int colorAt(int x, int y) =>
        data.getUint32((y * image.width + x) * 4, Endian.big);
    const y = 88;
    final background = colorAt(0, y);
    final offsets = <int>[];
    final widths = <int>[];
    var x = 1;
    for (var letter = 0; letter < 26; letter++) {
      var next = x;
      while (next < image.width && colorAt(next, y) != background) {
        next++;
      }
      offsets.add(x);
      widths.add(next - x);
      x = next + 1;
    }
    return _GenFont._(image, offsets, widths);
  }

  final ui.Image image;
  final List<int> offsets;
  final List<int> widths;

  static const int _unknownWidth = 5;

  int? _index(String char) {
    final code = char.toUpperCase().codeUnitAt(0) - 65;
    return code >= 0 && code < 26 && widths[code] > 0 ? code : null;
  }

  double measure(String text) {
    var width = 0;
    for (final char in text.split("")) {
      final index = _index(char);
      width += index == null ? _unknownWidth : widths[index];
    }
    return width.toDouble();
  }

  void draw(
    Canvas canvas,
    String text,
    double x,
    double y,
    double maxWidth, {
    required bool active,
  }) {
    var remaining = maxWidth;
    for (final char in text.split("")) {
      final index = _index(char);
      final width = index == null ? _unknownWidth : widths[index];
      if (width > remaining) break;
      if (index != null) {
        _draw(
          canvas,
          image,
          Rect.fromLTWH(
            offsets[index].toDouble(),
            active ? 88 : 96,
            width.toDouble(),
            7,
          ),
          Rect.fromLTWH(x, y, width.toDouble(), 7),
        );
      }
      x += width;
      remaining -= width;
    }
  }
}
