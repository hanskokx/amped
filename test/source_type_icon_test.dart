import "dart:ui" as ui;

import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/features/remote_source/widgets/source_type_icon.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  testWidgets("the Plex lettering is the theme's text color", (tester) async {
    // Neither black nor white, on a light and on a dark theme.
    for (final (brightness, text) in [
      (Brightness.dark, const Color(0xFF40E0D0)),
      (Brightness.light, const Color(0xFF800080)),
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: brightness,
            ).copyWith(onSurface: text),
          ),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: const SourceTypeIcon(RemoteSourceType.plex),
            ),
          ),
        ),
      );
      // The theme change is animated, and the logo loads off the test clock.
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      final colors = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 4);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        final bytes = data!.buffer.asUint8List();
        return {
          for (var i = 0; i < bytes.length; i += 4)
            Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]),
        };
      });

      expect(colors, contains(text), reason: "$brightness");
      // The chevron keeps Plex's gold.
      expect(colors, contains(const Color(0xFFEBAF00)), reason: "$brightness");
    }
  });
}
