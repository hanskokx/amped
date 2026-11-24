import "dart:io";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";
import "wasabi_view_test.dart" show FakeHost;

/// Wasabi 5's own modern skin, from the original source tree when it is
/// around.
final Directory _modern = ampedModern;

void main() {
  test("Amped Modern's scripts find every object they look for", () async {
    final skin = await WasabiSkinData.load(_modern);

    // Defined inside the main container (playlistpro.xml), with no size.
    expect(skin.container("searchresults"), isNotNull);

    final logs = <String>[];
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: logs.add,
    )..start();
    addTearDown(scripts.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // mainmenu.m, plmenu.m and mlmenu.m look for the menu bar beside their
    // group; playlistpro.m opens the search results container.
    expect(logs.where((l) => l.contains("null object")), isEmpty);

    // Wasabi's findObject searches outward from the object, up to the
    // layout.
    final layout = skin.container("main")!.layout("normal")!;
    final content = scripts.find(layout.root, "player.content.group")!;
    expect(scripts.find(content, "wasabi.menubar"), isNull);
    expect(scripts.findNear(content, "wasabi.menubar")?.id, "wasabi.menubar");
    expect(scripts.findNear(content, "player.content.group"), content);
  });

  test("clicking Amped Modern's playlist search box opens its edit", () async {
    final skin = await WasabiSkinData.load(_modern);
    final scripts = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(scripts.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final layout = skin.container("Pledit")!.layout("normal")!;
    final box = scripts.find(layout.root, "pl.search.edit.rect")!;
    final edit = scripts.find(layout.root, "wasabi.edit.box")!;
    final hint = scripts.find(layout.root, "pl.search.edit.searchhelp")!;
    expect(edit.visible, isFalse);

    // playlistpro.m shows the edit and hides the hint.
    scripts.pointer(box, "onLeftButtonDown", Offset.zero);
    expect(edit.visible, isTrue);
    expect(hint.visible, isFalse);

    // What is typed filters the playlist; Escape (the clear button) puts
    // the box and the playlist back.
    scripts.editChanged(edit, "abc");
    expect(skin.playlistFilter.value, "abc");
    scripts.editCancelled(edit);
    expect(edit.visible, isFalse);
    expect(hint.visible, isTrue);
    expect(skin.playlistFilter.value, "");
  });
}
