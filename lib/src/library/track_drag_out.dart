import "package:amped_skin/amped_skin.dart";
import "package:material_ui/material_ui.dart";

/// Follows a drag of tracks out of the Media Library's window. A Flutter drag
/// only reaches targets in its own window, but the pointer's moves and its
/// release keep arriving there while the button is down, so the other window
/// under the pointer is looked up here.
class TrackDragOut {
  TrackDragOut({required this.windowAt, required this.add});

  /// The window under the pointer that takes tracks for the playlist, or
  /// null.
  final SkinWindow? Function() windowAt;

  /// Adds the dropped tracks to the playlist.
  final void Function(List<String> paths) add;

  /// The window the tracks would be dropped on, to show it.
  final ValueNotifier<SkinWindow?> over = ValueNotifier(null);

  bool _outside = false;

  /// What is being dragged: noted at the start, as the list may change under
  /// the drag.
  List<String> _paths = const [];

  /// A drag of [paths] began.
  void started(List<String> paths) => _paths = paths;

  /// The drag moved; [outside] says whether it left the window it began in.
  void moved({required bool outside}) {
    _outside = outside;
    over.value = outside ? windowAt() : null;
  }

  /// The drag was let go where nothing in its own window took it.
  void released() {
    final target = _outside ? windowAt() : null;
    final paths = _paths;
    ended();
    if (target != null) add(paths);
  }

  /// The drag is over.
  void ended() {
    _paths = const [];
    _outside = false;
    over.value = null;
  }
}

/// Gives the track lists below it the [TrackDragOut] to report their drags to.
class TrackDragOutScope extends InheritedWidget {
  const TrackDragOutScope({
    required this.dragOut,
    required super.child,
    super.key,
  });

  final TrackDragOut dragOut;

  static TrackDragOut? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackDragOutScope>()?.dragOut;

  @override
  bool updateShouldNotify(TrackDragOutScope oldWidget) =>
      dragOut != oldWidget.dragOut;
}

/// Outlines [child], the content of [window], while dragged tracks are over
/// it.
class TrackDropOutline extends StatelessWidget {
  const TrackDropOutline({
    required this.dragOut,
    required this.window,
    required this.color,
    required this.child,
    super.key,
  });

  final TrackDragOut dragOut;
  final SkinWindow window;
  final Color Function() color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: dragOut.over,
    child: child,
    builder: (context, over, child) => DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: over == window ? Border.all(color: color(), width: 2) : null,
      ),
      child: child,
    ),
  );
}
