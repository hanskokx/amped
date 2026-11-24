import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Amped Modern from the original source, when it is around.
final Directory _modern = ampedModern;

FakeHost _host(List<int> lengthsMs, {Set<int> selected = const {}}) {
  final host = FakeHost();
  host.playlist
    ..clear()
    ..addAll([for (final ms in lengthsMs) ("Track", ms)]);
  host.selection.addAll(selected);
  return host;
}

void main() {
  test("shows the selected and total time like the classic player", () {
    expect(wasabiPlaylistInfo(_host([])), "0:00/0:00");
    expect(wasabiPlaylistInfo(_host([61000, 125000])), "0:00/3:06");
    expect(
      wasabiPlaylistInfo(_host([61000, 125000], selected: {1})),
      "2:05/3:06",
    );
    // An hour or more gets hours.
    expect(
      wasabiPlaylistInfo(_host([3600000, 1000], selected: {0})),
      "1:00:00/1:00:01",
    );
  });

  test("marks tracks of unknown length", () {
    // Known plus unknown: "+"; only unknown: "?".
    expect(wasabiPlaylistInfo(_host([61000, -1])), "0:00/1:01+");
    expect(wasabiPlaylistInfo(_host([61000, -1], selected: {1})), "?/1:01+");
    expect(wasabiPlaylistInfo(_host([-1], selected: {0})), "?/?");
  });

  test("keeps 17 characters", () {
    final info = wasabiPlaylistInfo(
      _host([-1, 360000000, 360000000], selected: {0, 1, 2}),
    );
    expect(info, "200:00:00+/200:00");
  });

  testWidgets("Amped Modern's playlist shows PE_Info at the bottom", (
    tester,
  ) async {
    final skin = (await tester.runAsync(() => WasabiSkinData.load(_modern)))!;
    final host = _host([61000, 125000], selected: {0});
    // The frame's content group comes in through its scripts.
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: (_) {})
      ..start();
    final layout = skin.container("pledit")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            container: "pledit",
            scripts: runtime,
          ),
        ),
      ),
    );
    final texts = [
      for (final paint in tester.renderObjectList<RenderCustomPaint>(
        find.byType(CustomPaint),
      ))
        paint.painter.toString(),
    ];
    expect(texts, contains(contains("1:01/3:06")));
    runtime.dispose();
  });
}
