import "package:amped/src/app/amped_dialog.dart";
import "package:amped/src/app/dialog_manager.dart";
import "package:amped/src/app/vis_controller.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/vis/vis_host.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:window_dock/window_dock.dart";

/// No dialog is ever open: the visualization stays out of fullscreen.
class _NoDialogs implements DialogManager {
  @override
  Map<AmpedDialog, Never> get windows => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VisHost vis;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    vis = VisHost(PlayerState(engine: AudioEngine()));
  });

  VisController controller({required bool slotsOnly}) => VisController(
    vis: vis,
    dialogs: _NoDialogs(),
    dock: DockManager<SkinWindow>(
      primary: SkinWindow.main,
      workAreas: () => const <Rect>[],
    ),
    scripts: () => null,
    slotsOnly: () => slotsOnly,
    playerChanged: () {},
  );

  test("a skin with only slots gets no window, and closing the slot stops "
      "the plug-in", () {
    final visualization = controller(slotsOnly: true);
    visualization.setRunning(true);
    expect(visualization.isOpen, isTrue);
    expect(visualization.windowShows, isFalse);
    visualization.attachSlot();
    expect(visualization.isOpen, isTrue);
    visualization.detachSlot();
    expect(vis.isRunning, isFalse);
    expect(visualization.isOpen, isFalse);
  });

  test("a plug-in the user started goes back to the skin's own window", () {
    final visualization = controller(slotsOnly: false);
    visualization.setRunning(true);
    visualization.attachSlot();
    expect(visualization.isOpen, isFalse);
    visualization.detachSlot();
    expect(vis.isRunning, isTrue);
    expect(visualization.isOpen, isTrue);
  });
}
