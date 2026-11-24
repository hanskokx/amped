import "dart:async";
import "dart:io";
import "dart:isolate";
import "dart:ui" as ui;

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/foundation.dart";
import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

/// Draws a modern skin the way the app does, off screen, as a PNG for the
/// file manager previews (which cannot run the skin's scripts themselves).
///
/// The picture is what the skin's preview in Preferences shows: the main
/// window with the equalizer and playlist editor below, trimmed to what they
/// draw, with the window shapes left transparent.
abstract final class SkinPreviewRenderer {
  /// How many times larger than its layout the picture is drawn.
  static const double scale = 2;

  /// How long the skin gets to load and run its scripts before it is looked
  /// at: long enough for the intro some skins play (Smallville's lasts about
  /// six seconds) to give way to the player.
  static const Duration settle = Duration(seconds: 9);

  /// The PNG of the skin unpacked in [directory], or null when it cannot be
  /// drawn. The skin's scripts and drawing run on the UI thread, so each step
  /// of it waits for [whenIdle] (the person using the app) and for a gap
  /// between frames.
  static Future<Uint8List?> render(
    Directory directory, {
    String? name,
    Future<void> Function()? whenIdle,
  }) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return null;
    final controller = WasabiSkinPreviewController(
      directory: directory,
      name: name ?? directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      title: "Amped - Crank it up",
      settings: () async => (null, const <WasabiGammaSet>[]),
    );
    final boundary = RenderRepaintBoundary();
    final pipeline = PipelineOwner();
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
      configuration: const ViewConfiguration(
        logicalConstraints: BoxConstraints(maxWidth: 4000, maxHeight: 4000),
        physicalConstraints: BoxConstraints(maxWidth: 4000, maxHeight: 4000),
      ),
    );
    pipeline.rootNode = renderView;
    renderView.prepareInitialFrame();
    final owner = BuildOwner(focusManager: FocusManager());
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: WasabiSkinPreview(controller: controller),
          ),
        ),
      ),
    ).attachToRenderTree(owner);
    void pump() {
      owner.buildScope(element);
      pipeline
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();
      owner.finalizeTree();
    }

    try {
      final stop = DateTime.now().add(const Duration(seconds: 20));
      while (!controller.loaded && !controller.failed) {
        if (DateTime.now().isAfter(stop)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (controller.failed) return null;
      // Scripts lay things out as they start; give them time to finish.
      const step = Duration(milliseconds: 300);
      for (var i = 0; i < settle.inMilliseconds ~/ step.inMilliseconds; i++) {
        await whenIdle?.call();
        await SchedulerBinding.instance.scheduleTask(pump, Priority.idle);
        await Future<void>.delayed(step);
      }
      await whenIdle?.call();
      await SchedulerBinding.instance.scheduleTask(pump, Priority.idle);
      final image = await boundary.toImage(pixelRatio: scale);
      final data = await image.toByteData();
      final trimmed = data == null
          ? null
          : await _trim(data, image.width, image.height);
      image.dispose();
      return trimmed;
    } finally {
      controller.dispose();
      owner.finalizeTree();
      pipeline.rootNode = null;
    }
  }

  /// The left, top, right and bottom pixel of the picture that shows (an alpha
  /// above 8) in [rgba], a [width] by [height] image; null when none does.
  /// Static and plain so it can run in another isolate.
  @visibleForTesting
  static List<int>? bounds(Uint8List rgba, int width, int height) {
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (rgba[(y * width + x) * 4 + 3] > 8) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    if (right < left || bottom < top) return null;
    return [left, top, right, bottom];
  }

  /// [rgba] (a [width] by [height] image) cut to the pixels that show, as a
  /// PNG; null for a picture with nothing in it.
  static Future<Uint8List?> _trim(ByteData rgba, int width, int height) async {
    final bytes = rgba.buffer.asUint8List();
    // The scan of millions of pixels is not done on the UI thread.
    final transfer = TransferableTypedData.fromList([bytes]);
    final found = await Isolate.run(
      () => bounds(transfer.materialize().asUint8List(), width, height),
    );
    if (found == null) return null;
    final [left, top, right, bottom] = found;
    final w = right - left + 1;
    final h = bottom - top + 1;
    final cropped = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final from = ((top + y) * width + left) * 4;
      cropped.setRange(y * w * 4, (y + 1) * w * 4, bytes, from);
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      cropped,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png?.buffer.asUint8List();
  }
}
