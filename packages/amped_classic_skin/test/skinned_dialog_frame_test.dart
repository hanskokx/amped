import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("dragging the corner grip asks for a resize", (tester) async {
    final skin = (await tester.runAsync(loadBaseSkin))!;
    final events = <String>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 275,
            height: 190,
            child: SkinnedDialogFrame(
              skin: skin,
              title: "Test",
              size: const Size(275, 190),
              onResizeStart: () => events.add("start"),
              onResizeUpdate: () => events.add("update"),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    // The grip is the bottom-right 20x20.
    final gesture = await tester.startGesture(const Offset(265, 180));
    await gesture.moveBy(const Offset(20, 10));
    await gesture.up();

    expect(events.first, "start");
    expect(events, contains("update"));
  });

  testWidgets("without resize callbacks there is no grip", (tester) async {
    final skin = (await tester.runAsync(loadBaseSkin))!;
    var moved = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 275,
            height: 190,
            child: SkinnedDialogFrame(
              skin: skin,
              title: "Test",
              size: const Size(275, 190),
              onDragUpdate: () => moved = true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(265, 180));
    await gesture.moveBy(const Offset(20, 10));
    await gesture.up();
    expect(moved, isFalse);
  });
}
