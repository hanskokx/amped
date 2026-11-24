import "dart:typed_data";

import "package:amped/src/app/dialog_manager.dart";
import "package:amped/src/dialogs/artwork_page.dart";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("the size of a window that keeps its picture's shape", () {
    test("is the picture's shape plus the frame", () {
      // A 2:1 picture 300 wide: 281 of it is picture, 140.5 high.
      final wide = DialogManager.shapedSize(2, 300);
      expect(wide.width, 300);
      expect(wide.height, closeTo(140.5 + 34, 1));
      // A tall one is taller than it is wide.
      final tall = DialogManager.shapedSize(0.5, 200);
      expect(tall.width, 200);
      expect(tall.height, closeTo((200 - 19) / 0.5 + 34, 1));
      // Square.
      final square = DialogManager.shapedSize(1, 300);
      expect(square.height, closeTo(300 - 19 + 34, 1));
    });

    test("is never so small that the picture can't be seen", () {
      final narrow = DialogManager.shapedSize(1, 20);
      expect(narrow.width, greaterThanOrEqualTo(140));
      // A very wide picture is held at the least height, widening to keep
      // its shape.
      final strip = DialogManager.shapedSize(10, 300);
      expect(strip.height, greaterThanOrEqualTo(90));
      expect(
        (strip.width - 19) / (strip.height - 34),
        closeTo(10, 0.2),
      );
    });

    test("the shape holds at any width asked for", () {
      for (final aspect in [0.4, 0.75, 1.0, 1.5, 3.0]) {
        for (final width in [150.0, 250.0, 400.0, 900.0]) {
          final size = DialogManager.shapedSize(aspect, width);
          expect(
            (size.width - 19) / (size.height - 34),
            closeTo(aspect, 0.05),
            reason: "$aspect at $width",
          );
        }
      }
    });
  });

  group("the title", () {
    test("is left as it is when it fits", () {
      expect(DialogManager.fitTitle("Hard Fork", 300), "Hard Fork");
    });

    test("is cut with dots to what the title bar has room for", () {
      final cut = DialogManager.fitTitle(
        "Through Authentic Voices: The Complete Story Of Everything",
        300,
      );
      expect(cut, endsWith("..."));
      expect(cut.length, lessThanOrEqualTo((300 - 100) ~/ 6));
      // A wider window has room for more of it.
      expect(
        DialogManager.fitTitle("x" * 80, 600).length,
        greaterThan(cut.length),
      );
    });

    test("never gets shorter than a few letters", () {
      expect(DialogManager.fitTitle("Something long", 100).length, 6);
    });
  });

  testWidgets("the picture is on the skin's list background and kept to its "
      "shape", (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ArtworkPage(
          image: MemoryImage(Uint8List(0)),
          background: const Color(0xFF123456),
        ),
      ),
    );
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(box.color, const Color(0xFF123456));
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
  });

  testWidgets("with no picture there is only the background", (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ArtworkPage(image: null, background: Color(0xFF123456)),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(ColoredBox), findsOneWidget);
  });
}
