import "dart:async";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_vis/amped_vis.dart";
import "package:flutter/widgets.dart";

/// The main window's classic visualization (76×16, or 38×5 in window
/// shade), drawn from what is playing with the skin's `viscolor.txt`
/// [colors].
///
/// Like the original's visualization thread (`bivis_thread`), it runs a
/// 16 ms cycle while playing, unpaused, with a mode on, and draws every
/// `refresh` cycles; otherwise the skin's own background shows through.
class ClassicVisView extends StatefulWidget {
  const ClassicVisView({
    required this.player,
    required this.colors,
    required this.windowShade,
    super.key,
  });

  final ClassicPlayer player;
  final List<int> colors;
  final bool windowShade;

  @override
  State<ClassicVisView> createState() => _ClassicVisViewState();
}

class _ClassicVisViewState extends State<ClassicVisView> {
  final ClassicVisController _controller = ClassicVisController();
  Timer? _timer;

  ClassicPlayer get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _player.startVisualization();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.stopVisualization();
    _controller.dispose();
    super.dispose();
  }

  void _tick() {
    final options = _player.classicVis;
    final samples = _player.visualizationSamples;
    _controller.tick(
      running:
          _player.playing &&
          !_player.paused &&
          options.mode != ClassicVisMode.off,
      // Paused keeps the last picture; stopped or off blanks it.
      keepPicture: _player.paused && options.mode != ClassicVisMode.off,
      options: options,
      windowShade: widget.windowShade,
      left: samples?.$1,
      right: samples?.$2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => CustomPaint(
        size: widget.windowShade ? const Size(38, 5) : const Size(76, 16),
        painter: _controller.showing
            ? _ClassicVisPainter(
                picture: _controller.picture!,
                colors: widget.colors,
                windowShade: widget.windowShade,
                frame: _controller.frame,
              )
            : null,
      ),
    );
  }
}

class _ClassicVisPainter extends CustomPainter {
  const _ClassicVisPainter({
    required this.picture,
    required this.colors,
    required this.windowShade,
    required this.frame,
  });

  final ClassicVisPicture picture;
  final List<int> colors;
  final bool windowShade;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    // One path per colour.
    final paths = <int, Path>{};
    final width = windowShade ? 38 : 76;
    final height = windowShade ? 5 : 16;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = picture.pixelAt(x, y);
        if (index >= colors.length) continue;
        (paths[index] ??= Path()).addRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        );
      }
    }
    for (final MapEntry(key: index, value: path) in paths.entries) {
      canvas.drawPath(path, Paint()..color = Color(colors[index]));
    }
  }

  @override
  bool shouldRepaint(_ClassicVisPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.colors != colors;
}
