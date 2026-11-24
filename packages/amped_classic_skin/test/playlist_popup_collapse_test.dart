import "dart:ui" as ui;

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

class _FakeHost extends Fake implements ClassicHost {
  @override
  void showMenu(ClassicMenu menu, Offset? position) {}
}

void main() {
  late ui.Image image;
  late List<String> picked;

  setUp(() => picked = []);

  // Two popup buttons side by side, a "song list" and a "titlebar" area
  // above them, and a second box standing for another window.
  Future<void> pumpWindow(WidgetTester tester) async {
    await tester.runAsync(() async {
      image = await createTestImage(width: 200, height: 200);
    });
    final host = _FakeHost();
    Widget button(double left, String name) => PlPopupButton(
      image: image,
      left: left,
      height: 100,
      bar: 48,
      normalX: 0,
      pressedX: 23,
      rows: const [149, 130, 111],
      cursor: SystemMouseCursors.basic,
      host: host,
      contextMenu: ClassicMenu.playlistAdd,
      actions: [
        () => picked.add("$name 0"),
        () => picked.add("$name 1"),
        () => picked.add("$name 2"),
      ],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 10,
              child: ColoredBox(color: Colors.red, key: Key("titlebar")),
            ),
            const Positioned(
              left: 0,
              top: 10,
              width: 200,
              height: 20,
              child: ColoredBox(color: Colors.green, key: Key("songs")),
            ),
            button(14, "a"),
            button(60, "b"),
          ],
        ),
      ),
    );
  }

  // A button sits at (left, 70) with size 22x18; its column rises above it.
  Offset buttonAt(double left) => Offset(left + 11, 79);

  Future<void> clickOpen(WidgetTester tester, double left) async {
    final gesture = await tester.startGesture(buttonAt(left));
    await gesture.up();
    await tester.pump();
  }

  bool isOpen(WidgetTester tester, double left) {
    final states = tester.stateList<PlPopupButtonState>(
      find.byType(PlPopupButton),
    );
    return states.any((state) => state.isOpenForTest);
  }

  testWidgets("choosing an option still activates it", (tester) async {
    await pumpWindow(tester);
    await clickOpen(tester, 14);
    expect(isOpen(tester, 14), isTrue);
    // Column top option is 2 rows above the button.
    await tester.tapAt(const Offset(14 + 11, 79 - 36));
    await tester.pump();
    expect(picked, ["a 2"]);
    expect(isOpen(tester, 14), isFalse);
  });

  for (final target in {
    "the titlebar": const Offset(150, 5),
    "the song list": const Offset(150, 20),
    "empty space": const Offset(150, 90),
  }.entries) {
    testWidgets("clicking ${target.key} collapses the column", (tester) async {
      await pumpWindow(tester);
      await clickOpen(tester, 14);
      expect(isOpen(tester, 14), isTrue);
      await tester.tapAt(target.value);
      await tester.pump();
      expect(isOpen(tester, 14), isFalse);
      expect(picked, isEmpty);
    });
  }

  testWidgets("opening another popup button collapses the first", (
    tester,
  ) async {
    await pumpWindow(tester);
    await clickOpen(tester, 14);
    await clickOpen(tester, 60);
    final states = tester
        .stateList<PlPopupButtonState>(find.byType(PlPopupButton))
        .toList();
    expect(states[0].isOpenForTest, isFalse);
    expect(states[1].isOpenForTest, isTrue);
  });
}
