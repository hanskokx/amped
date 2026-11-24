import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late List<String> fired;
  late Map<String, bool> pressed;

  Widget button(String name, double left) {
    return Positioned(
      left: left,
      top: 0,
      child: SkinButton(
        size: const Size(20, 20),
        onPressed: () => fired.add(name),
        builder: (context, isPressed) {
          pressed[name] = isPressed;
          return const SizedBox.expand();
        },
      ),
    );
  }

  Future<void> pumpButtons(WidgetTester tester) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SkinButtonScope(
          child: Stack(children: [button("a", 0), button("b", 40)]),
        ),
      ),
    );
  }

  setUp(() {
    fired = [];
    pressed = {};
  });

  testWidgets("releasing over the pressed button fires it", (tester) async {
    await pumpButtons(tester);
    final gesture = await tester.startGesture(const Offset(10, 10));
    await tester.pump();
    expect(pressed["a"], isTrue);
    await gesture.up();
    await tester.pump();
    expect(fired, ["a"]);
    expect(pressed["a"], isFalse);
  });

  testWidgets("sliding to another button and releasing fires that one", (
    tester,
  ) async {
    await pumpButtons(tester);
    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.moveTo(const Offset(50, 10));
    await tester.pump();
    expect(pressed["a"], isFalse);
    expect(pressed["b"], isTrue);
    await gesture.up();
    expect(fired, ["b"]);
  });

  testWidgets("sliding off every button and releasing fires nothing", (
    tester,
  ) async {
    await pumpButtons(tester);
    final gesture = await tester.startGesture(const Offset(10, 10));
    await gesture.moveTo(const Offset(30, 100));
    await tester.pump();
    expect(pressed["a"], isFalse);
    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(pressed["a"], isTrue, reason: "re-entering re-presses");
    await gesture.moveTo(const Offset(30, 100));
    await gesture.up();
    expect(fired, isEmpty);
  });

  testWidgets("a press that starts outside the buttons never fires them", (
    tester,
  ) async {
    await pumpButtons(tester);
    final gesture = await tester.startGesture(const Offset(30, 10));
    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(pressed["a"], isFalse);
    await gesture.up();
    expect(fired, isEmpty);
  });
}
