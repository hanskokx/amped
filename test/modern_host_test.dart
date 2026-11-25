import "package:amped/src/app/amped_shell.dart";
import "package:amped/src/app/modern_host.dart";
import "package:amped/src/app/shell_classic_host.dart";
import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped/src/vis/vis_host.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

class _FakeClassicHost implements ShellClassicHost {
  int aboutShown = 0;

  @override
  void showAbout() => aboutShown++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only what running the logo's action reads.
class _FakeShell implements AmpedShell {
  @override
  final _FakeClassicHost classic = _FakeClassicHost();

  @override
  final PlayerState player = PlayerState(engine: AudioEngine());

  @override
  final Skin skin = _FakeSkin();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Not a modern skin, so no container of its own is looked up.
final class _FakeSkin extends Skin {
  _FakeSkin() : super(const SkinInfo(name: "Fake"));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("Amped Modern's logo opens the About dialog", () {
    final shell = _FakeShell();
    ShellWasabiHost(shell).runAction(
      const WasabiAction(
        "TOGGLE",
        "guid:{D6201408-476A-4308-BF1B-7BACA1124B12}",
        container: "main",
      ),
    );
    expect(shell.classic.aboutShown, 1);
  });

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
