import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

/// Only what the main window reads while building, plus [showAbout].
class _FakeHost extends ChangeNotifier implements ClassicHost {
  _FakeHost(this.skin, this.player);

  @override
  final ClassicSkinData skin;

  @override
  final ClassicPlayer player;

  @override
  final ValueNotifier<String?> songTitleOverride = ValueNotifier(null);

  int aboutShown = 0;

  @override
  void showAbout() => aboutShown++;

  int fileInfoShown = 0;

  @override
  void showFileInfo() => fileInfoShown++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHost host;

  setUp(() async {
    final skin = await loadBaseSkin();
    host = _FakeHost(skin, PlayerState(engine: AudioEngine()));
  });

  Future<void> pumpMainWindow(WidgetTester tester) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SkinButtonScope(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 275,
              height: 116,
              child: MainWindowView(host: host),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets("clicking the logo opens the About dialog", (tester) async {
    await pumpMainWindow(tester);
    await tester.tapAt(const Offset(259, 98));
    await tester.pump();
    expect(host.aboutShown, 1);
  });

  testWidgets("a click beside the logo does not", (tester) async {
    await pumpMainWindow(tester);
    await tester.tapAt(const Offset(250, 98));
    await tester.pump();
    expect(host.aboutShown, 0);
  });

  testWidgets("double-clicking the song title opens File Info", (tester) async {
    await pumpMainWindow(tester);
    await tester.tapAt(const Offset(150, 30));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(150, 30));
    await tester.pump();
    expect(host.fileInfoShown, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("a single click on the song title does not", (tester) async {
    await pumpMainWindow(tester);
    await tester.tapAt(const Offset(150, 30));
    await tester.pump(const Duration(seconds: 1));
    expect(host.fileInfoShown, 0);
  });
}
