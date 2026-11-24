import "package:amped/src/app/modern_host.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/vis/vis_host.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Wasabi 5 playlist buttons open the classic playlist menus", () {
    expect(ShellWasabiHost.playlistMenuFor("PE_ADD"), ClassicMenu.playlistAdd);
    expect(
      ShellWasabiHost.playlistMenuFor("PE_REM"),
      ClassicMenu.playlistRemove,
    );
    expect(
      ShellWasabiHost.playlistMenuFor("PE_SEL"),
      ClassicMenu.playlistSelect,
    );
    expect(
      ShellWasabiHost.playlistMenuFor("PE_MISC"),
      ClassicMenu.playlistMisc,
    );
    expect(
      ShellWasabiHost.playlistMenuFor("PE_LIST"),
      ClassicMenu.playlistList,
    );
    expect(ShellWasabiHost.playlistMenuFor("PLAY"), isNull);
  });

  test("the visualization stays shown in the skin while fullscreen", () {
    final vis = VisHost(PlayerState(engine: AudioEngine()))..start();
    expect(ShellWasabiHost.visComponentVisible(vis), isTrue);
    vis.setFullscreen(true);
    expect(ShellWasabiHost.visComponentVisible(vis), isTrue);
    vis.setFullscreen(false);
    expect(ShellWasabiHost.visComponentVisible(vis), isTrue);
    vis.stop();
    expect(ShellWasabiHost.visComponentVisible(vis), isFalse);
    vis.dispose();
  });

  test("stopping while fullscreen leaves fullscreen", () {
    final vis = VisHost(PlayerState(engine: AudioEngine()))..start();
    vis.setFullscreen(true);
    vis.stop();
    expect(vis.fullscreen, isFalse);
    vis.dispose();
  });
}
