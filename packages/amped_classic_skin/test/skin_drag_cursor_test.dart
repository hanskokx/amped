import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("a drag holds its cursor until the button is released", (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SkinButtonScope(
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: SkinDragTarget(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: SizedBox(width: 20, height: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    MouseCursor? active() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await tester.pump();
    expect(active(), SystemMouseCursors.resizeDownRight);

    await mouse.down(const Offset(10, 10));
    await tester.pump();
    await mouse.moveTo(const Offset(200, 200));
    await tester.pump();
    expect(active(), SystemMouseCursors.resizeDownRight);

    await mouse.up();
    await tester.pump();
    await mouse.moveTo(const Offset(210, 210));
    await tester.pump();
    expect(active(), SystemMouseCursors.basic);
  });
}
