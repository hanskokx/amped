import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

import "wasabi_view_test.dart" show FakeHost;

void main() {
  testWidgets("a frame made as a second window is drawn over its window", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_companion");
    addTearDown(() => dir.deleteSync(recursive: true));
    // What Wasabi 5 skins' standardframe scripts do: ask for a second
    // container that follows the window the script's group is in.
    final source = File("${dir.path}/frame.m")
      ..writeAsStringSync(r'''
Global Container clear;

System.onScriptLoaded() {
  clear = newDynamicContainer("cont.clear");
}
''');
    File(
      "${dir.path}/frame.maki",
    ).writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="frame"><script id="s" file="frame.maki"/></groupdef>
<container id="main">
  <layout id="normal" w="40" h="30">
    <group id="frame" x="0" y="0"/>
    <component x="5" y="5" w="30" h="20" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
  </layout>
</container>
<container id="cont.clear" dynamic="1">
  <layout id="clear" w="40" h="30"/>
</container>
</WasabiXML>''');

    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);

    final main = skin.container("main")!.layout("normal")!;
    final companions = runtime.companionsOf(main);
    expect(companions, hasLength(1));
    expect(companions.single.$1.id, "cont.clear");
    expect(companions.single.$2.id, "clear");
    // Other layouts have none, and the frame is not its own companion.
    expect(runtime.companionsOf(companions.single.$2), isEmpty);
  });

  testWidgets("the frame does not take the window's content's clicks", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_companion2");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/frame.m")
      ..writeAsStringSync(r'''
Global Container clear;
System.onScriptLoaded() { clear = newDynamicContainer("cont.clear"); }
''');
    File("${dir.path}/frame.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="frame"><script id="s" file="frame.maki"/></groupdef>
<container id="main">
  <layout id="normal" w="40" h="30">
    <group id="frame" x="0" y="0"/>
    <component x="5" y="5" w="30" h="20" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
  </layout>
</container>
<container id="cont.clear" dynamic="1">
  <layout id="clear" w="40" h="30"/>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: WasabiLayoutView(
            skin: skin,
            layout: skin.container("main")!.layout("normal")!,
            host: FakeHost(),
            container: "main",
            scripts: runtime,
            components: {
              "ml": GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
            },
          ),
        ),
      ),
    );
    expect(find.byType(WasabiLayoutView), findsNWidgets(2));
    await tester.tap(find.byType(WasabiLayoutView).first);
    expect(taps, 1);
  });

  testWidgets("a window hidden under its frame leaves the frame showing", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_companion3");
    addTearDown(() => dir.deleteSync(recursive: true));
    // What the Apple-styled skin's mini mode and big album art do: hide the playlist
    // editor, keeping the player drawn over it (and shrinking it).
    final source = File("${dir.path}/frame.m")
      ..writeAsStringSync(r'''
Global Container clear;
Global Layout own;
Global Int shown;
Global Timer later;
System.onScriptLoaded() {
  clear = newDynamicContainer("cont.clear");
  own = getScriptGroup().getParentLayout();
  shown = 0;
  clear.getLayout("clear").setXMLParam("h", "10");
  later = new Timer;
  later.setDelay(10);
  later.start();
}
later.onTimer() {
  later.stop();
  own.hide();
  own.hide();
}
own.onSetVisible(Boolean visible) {
  shown = shown + 1;
  setPrivateInt("t", "events", shown);
}
''');
    File("${dir.path}/frame.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="frame"><script id="s" file="frame.maki"/></groupdef>
<container id="main">
  <layout id="normal" w="40" h="30">
    <group id="frame" x="0" y="0"/>
  </layout>
</container>
<container id="cont.clear" dynamic="1">
  <layout id="clear" w="40" h="30"/>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final host = FakeHost();
    final log = <String>[];
    final runtime = WasabiScriptRuntime(skin: skin, host: host, log: log.add)
      ..start();
    addTearDown(runtime.dispose);
    await tester.pump(const Duration(milliseconds: 100));
    final main = skin.container("main")!.layout("normal")!;
    expect(runtime.isHiddenUnderCompanions(main), isTrue);
    // The window is as big as the frame, which is all it shows.
    expect(main.size, const Size(40, 10));
    // The layout is told it is shown as the skin starts, and hiding it once
    // more is no news: two events, not three.
    expect(
      [
        for (final MapEntry(:key, :value) in host.private.entries)
          if (key.endsWith("t/events")) value,
      ],
      ["2"],
      reason: log.join("\n"),
    );
  });

  testWidgets("a skin's glass switch turns desktop alpha off and on", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_glass");
    addTearDown(() => dir.deleteSync(recursive: true));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<container id="main">
  <layout id="normal" w="40" h="30">
    <togglebutton id="glass" x="0" y="0" w="10" h="10" tooltip="Glass"
      cfgattrib="{9149C445-3C30-4E04-8433-5A518ED0FDDE};Enable desktop alpha"/>
  </layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    // The classic player starts with desktop alpha on.
    expect(runtime.desktopAlpha, isTrue);
    final glass = runtime.skinSwitches.single;
    expect(glass.label, "Glass");
    expect(glass.checked, isTrue);
    runtime.toggleSkinOption(glass);
    expect(runtime.desktopAlpha, isFalse);
    runtime.toggleSkinOption(glass);
    expect(runtime.desktopAlpha, isTrue);

    // And the button itself does it.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: skin.container("main")!.layout("normal")!,
            host: FakeHost(),
            container: "main",
            scripts: runtime,
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(runtime.desktopAlpha, isFalse);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(runtime.desktopAlpha, isTrue);
  });

  testWidgets("a frame over a window does not take the component's clicks", (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync("wasabi_companion3");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/frame.m")
      ..writeAsStringSync(r'''
Global Container clear;
System.onScriptLoaded() { clear = newDynamicContainer("cont.clear"); }
''');
    File("${dir.path}/frame.maki").writeAsBytesSync(compileMaki(source.path));
    File("${dir.path}/skin.xml").writeAsStringSync('''
<?xml version="1.0"?>
<WasabiXML version="1.2">
<groupdef id="frame"><script id="s" file="frame.maki"/></groupdef>
<container id="main">
  <layout id="normal" w="40" h="30">
    <group id="frame" x="0" y="0"/>
    <component x="5" y="5" w="30" h="20" param="guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"/>
  </layout>
</container>
<container id="cont.clear" dynamic="1">
  <layout id="clear" w="40" h="30"><layer id="cover" x="0" y="0" w="40" h="30" move="1"/></layout>
</container>
</WasabiXML>''');
    final skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory(dir.path)),
    ))!;
    final runtime = WasabiScriptRuntime(
      skin: skin,
      host: FakeHost(),
      log: (_) {},
    )..start();
    addTearDown(runtime.dispose);
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: skin.container("main")!.layout("normal")!,
            host: FakeHost(),
            container: "main",
            scripts: runtime,
            components: {
              "ml": GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
            },
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(20, 15));
    expect(taps, 1);
  });
}
