import "package:amped/src/player/audio_engine.dart";
import "package:amped/src/player/player_state.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

/// Only what the Album Art window reads while building, and its closing.
class _FakeHost extends ChangeNotifier implements ClassicHost {
  _FakeHost(this.skin, this.player);

  @override
  final ClassicSkinData skin;

  @override
  final ClassicPlayer player;

  final List<(SkinWindow, bool)> opened = [];

  @override
  Size baseSize(SkinWindow window) => const Size(275, 290);

  @override
  void setOpen(SkinWindow window, bool open) => opened.add((window, open));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHost host;

  setUp(() async {
    final skin = await loadBaseSkin();
    host = _FakeHost(skin, PlayerState(engine: AudioEngine()));
  });

  testWidgets("the cover fills the frame's inside; the close button closes", (
    tester,
  ) async {
    const content = Key("cover");
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SkinButtonScope(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 275,
              height: 290,
              child: AlbumArtWindow(
                host: host,
                title: "Album Art",
                content: const SizedBox.expand(key: content),
              ),
            ),
          ),
        ),
      ),
    );
    // A 256×256 picture in the default window (`embwnd.cpp` insets).
    expect(
      tester.getRect(find.byKey(content)),
      const Rect.fromLTWH(11, 20, 256, 256),
    );
    await tester.tapAt(const Offset(268, 7));
    await tester.pump();
    expect(host.opened, [(SkinWindow.albumArt, false)]);
  });
}
