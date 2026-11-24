/// Visualizations: the classic spectrum analyzer and oscilloscope of the
/// main window, and a worker that runs visualization plug-ins (the API of
/// `amped_vis_api`, re-exported here) in an isolate.
library;

export "package:amped_vis_api/amped_vis_api.dart";

export "src/classic_vis.dart";
export "src/classic_vis_controller.dart";
export "src/vis_worker.dart";
export "src/waveform_vis.dart";
