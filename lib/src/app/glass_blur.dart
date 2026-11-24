import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:amped_skin/amped_skin.dart";
import "package:flutter/foundation.dart" show compute, visibleForTesting;
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";

import "amped_shell.dart";

class GlassBlur extends StatefulWidget {
  const GlassBlur({
    required this.shell,
    required this.window,
    required this.child,
    super.key,
  });

  final AmpedShell shell;
  final SkinWindow window;
  final Widget child;

  /// Whether the platform can blur behind a window (macOS for now).
  static bool get supported => Platform.isMacOS;

  /// The mask of the glass in [rgba] (a [width] by [height] image): 255
  /// where the pixel is glass, 0 elsewhere, cropped or padded to [outWidth]
  /// by [outHeight]. A pixel is glass when it is neither (nearly) opaque nor
  /// (nearly) clear and so are the pixels around it, which keeps the soft
  /// edges of opaque shapes from counting. Null when nothing is glass.
  @visibleForTesting
  static Uint8List? maskOf(
    Uint8List rgba,
    int width,
    int height,
    int outWidth,
    int outHeight,
  ) {
    final w = outWidth;
    final h = outHeight;
    var mask = Uint8List(w * h);
    var any = false;
    int alphaAt(int x, int y) {
      if (x < 0 || y < 0 || x >= width || y >= height) return 0;
      return rgba[(y * width + x) * 4 + 3];
    }

    for (var y = 0; y < h && y < height; y++) {
      for (var x = 0; x < w && x < width; x++) {
        final a = alphaAt(x, y);
        // Mostly opaque (Ebonite's 80%) is not glass: the blur and its
        // material would hide what it lets through.
        if (a < 24 || a > 185) continue;
        // Shadows and glows fall off; glass is even. Anything whose alpha
        // changes quickly nearby is not glass.
        var even = true;
        for (final d in const [(3, 0), (-3, 0), (0, 3), (0, -3)]) {
          if ((alphaAt(x + d.$1, y + d.$2) - a).abs() > 24) {
            even = false;
            break;
          }
        }
        if (!even) continue;
        mask[y * w + x] = 255;
        any = true;
      }
    }
    if (!any) return null;
    // Two passes of a 3x3 erosion.
    for (var pass = 0; pass < 2; pass++) {
      final eroded = Uint8List(w * h);
      var left = false;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (mask[i] == 0) continue;
          if (mask[i - 1] != 0 &&
              mask[i + 1] != 0 &&
              mask[i - w] != 0 &&
              mask[i + w] != 0 &&
              mask[i - w - 1] != 0 &&
              mask[i - w + 1] != 0 &&
              mask[i + w - 1] != 0 &&
              mask[i + w + 1] != 0) {
            eroded[i] = 255;
            left = true;
          }
        }
      }
      mask = eroded;
      if (!left) return null;
    }
    // Soften the rim: a box blur of radius 3, horizontally then vertically.
    for (final horizontal in const [true, false]) {
      final soft = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var sum = 0;
          for (var k = -3; k <= 3; k++) {
            final xx = horizontal ? x + k : x;
            final yy = horizontal ? y : y + k;
            if (xx >= 0 && yy >= 0 && xx < w && yy < h)
              sum += mask[yy * w + xx];
          }
          soft[y * w + x] = sum ~/ 7;
        }
      }
      mask = soft;
    }
    return mask;
  }

  @override
  State<GlassBlur> createState() => _GlassBlurState();
}

class _GlassBlurState extends State<GlassBlur> {
  final GlobalKey _boundary = GlobalKey();
  Timer? _timer;
  bool _glassy = false;
  bool _busy = false;
  bool _applied = false;
  int _looks = 0;

  @override
  void initState() {
    super.initState();
    if (GlassBlur.supported) _next(const Duration(seconds: 1));
  }

  @override
  void didUpdateWidget(GlassBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Not on every rebuild (a skin's windows rebuild all the time): only for
    // another window.
    if (GlassBlur.supported && oldWidget.window != widget.window) {
      _looks = 0;
      _next(const Duration(seconds: 1));
    }
  }

  void _next(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _look);
  }

  /// Looks a few times as the window comes up and scripts settle it, then
  /// seldom: a window with glass is looked at every few seconds (its parts
  /// fade), one without hardly ever. Looking costs a picture of the window
  /// and a pass over its pixels, so it must not happen all the time.
  Future<void> _look() async {
    if (!mounted || _busy) return;
    _busy = true;
    try {
      _glassy = await _capture();
    } on Object {
      // The window went away or is not drawn yet: try again later.
    } finally {
      _busy = false;
      _looks++;
      if (mounted) {
        _next(
          _looks < 3
              ? const Duration(seconds: 2)
              : _glassy
              ? const Duration(seconds: 4)
              : const Duration(seconds: 30),
        );
      }
    }
  }

  /// Looks at the window and blurs behind its glass; whether it has any.
  Future<bool> _capture() async {
    final shell = widget.shell;
    final window = widget.window;
    final native = shell.dock.nativeWindowOf(window);
    final size = shell.dock.rectOf(window)?.size;
    final object = _boundary.currentContext?.findRenderObject();
    if (native == null || size == null || object is! RenderRepaintBoundary) {
      return false;
    }
    if (!object.attached || object.debugNeedsPaint) return _glassy;
    // One pixel per logical pixel: the mask is made at the window's size.
    final image = await object.toImage();
    final data = await image.toByteData();
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (data == null || !mounted) return false;
    final w = size.width.round();
    final h = size.height.round();
    final rgba = data.buffer.asUint8List();
    // Off the UI thread: it is a pass over every pixel, twice.
    final mask = await compute(_maskOf, (rgba, width, height, w, h));
    if (!mounted) return false;
    if (mask == null) {
      if (_applied) native.setBlurMask(null, 0, 0);
      _applied = false;
      return false;
    }
    native.setBlurMask(mask, w, h);
    _applied = true;
    return true;
  }

  /// Blurs what is behind the translucent glass of a modern skin's window, the
  /// way the window manager's backdrop would.
  ///
  /// Where the glass is comes from what the window draws: the pixels that are
  /// neither opaque nor clear. A window is looked at again every so often
  /// while it has glass (and now and then while it has not), since scripts
  /// can fade and move its parts.
  Uint8List? _maskOf((Uint8List, int, int, int, int) args) => GlassBlur.maskOf(
    args.$1,
    args.$2,
    args.$3,
    args.$4,
    args.$5,
  );

  @override
  void dispose() {
    _timer?.cancel();
    if (_applied) {
      widget.shell.dock.nativeWindowOf(widget.window)?.setBlurMask(null, 0, 0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _boundary,
    child: widget.child,
  );
}
