import "package:amped_vis/amped_vis.dart";
import "package:tiny_fullscreen_vis/tiny_fullscreen_vis.dart";

/// The visualization plug-ins. The app and the isolate of a [VisWorker] each
/// build their own, so this is a top-level function.
///
/// [WaveformVis] is always there. To build without `tiny_fullscreen_vis`,
/// remove that dependency from `pubspec.yaml` and the import and the
/// [TinyFullscreen] line here.
List<VisPlugin> createVisPlugins() => [TinyFullscreen(), WaveformVis()];
