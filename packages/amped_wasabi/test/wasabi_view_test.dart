import "dart:io";
import "dart:ui" as ui;

import "package:amped_vis/amped_vis.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

/// Records what the skin asks of the player.
class FakeHost extends ChangeNotifier implements WasabiHost {
  final List<WasabiAction> actions = [];
  final Map<String, double> values = {"VOLUME": 0.5, "SEEK": 0};
  final List<(String, double, bool)> moves = [];
  bool eq = false;

  String? statusText;

  @override
  double layoutScale(String container) => 1;

  @override
  String get songTitle => statusText ?? trackTitle;

  @override
  String get trackTitle => "Test Artist - Test Song";

  @override
  String songInfoText = "";

  @override
  String videoInfoText = "";

  @override
  bool videoPlaying = false;

  @override
  bool videoFullscreen = false;

  @override
  String playItemMetadata(String name) => "";

  @override
  ui.Rect viewport = const ui.Rect.fromLTWH(0, 0, 1920, 1080);

  @override
  bool appMinimized = false;

  int activations = 0;

  @override
  void activateApplication() => activations++;

  @override
  int get lengthMs => 200000;

  @override
  int get positionMs => 61000;

  @override
  bool timeRemaining = false;

  @override
  void toggleTimeRemaining() {
    timeRemaining = !timeRemaining;
    notifyListeners();
  }

  @override
  bool isActive(String action, String? param) =>
      (action == "EQ_TOGGLE" && eq) ||
      (action == "TOGGLE" && param != null && open.contains(param));

  /// The `TOGGLE` params whose windows are open.
  final Set<String> open = {};

  @override
  void runAction(WasabiAction action) => actions.add(action);

  /// Config attribute values by `cfgattrib`.
  final Map<WasabiCfgAttrib, int> config = {};

  @override
  int configValue(WasabiCfgAttrib attribute) => config[attribute] ?? 0;

  @override
  void setConfigValue(WasabiCfgAttrib attribute, int value) {
    config[attribute] = value;
    notifyListeners();
  }

  final List<WasabiMenuRequest> menus = [];

  @override
  Future<void> openMenu(WasabiMenuRequest request) async => menus.add(request);

  @override
  double? sliderValue(String action, String? param) =>
      values["$action${param ?? ""}"] ?? 0.5;

  @override
  void setSliderValue(
    String action,
    String? param,
    double value, {
    required bool done,
  }) {
    moves.add((action, value, done));
    values["$action${param ?? ""}"] = value;
    notifyListeners();
  }

  @override
  int get playbackStatus => 1;

  @override
  String get playItemLocation => "/music/test.mp3";

  @override
  ui.Image? albumArt;

  @override
  ui.Offset cursorPosition = ui.Offset.zero;

  @override
  ui.Offset? windowOrigin(String id) => null;

  @override
  ui.Image? onlineAlbumArt;

  @override
  bool albumArtLoading = false;

  int albumArtRefreshes = 0;

  @override
  void refreshAlbumArt() => albumArtRefreshes++;

  /// Right presses on an `<AlbumArt>`, its menus shown, and its folder
  /// opened.
  int albumArtPresses = 0;
  int albumArtMenus = 0;
  int albumArtFolders = 0;

  @override
  void pressAlbumArtMenu(PointerDownEvent event) => albumArtPresses++;

  @override
  void showAlbumArtMenu() => albumArtMenus++;

  @override
  void openAlbumArtFolder() => albumArtFolders++;

  /// The actions right presses ran.
  final List<String> secondaryActions = [];

  @override
  void pressSecondaryAction(WasabiAction action, PointerDownEvent event) {
    secondaryActions.add(action.action);
  }

  /// The popup a script showed and what it would answer.
  List<WasabiPopupItem>? popup;
  void Function(int id)? popupChosen;

  @override
  void showPopup(List<WasabiPopupItem> items, void Function(int id) chosen) {
    popup = items;
    popupChosen = chosen;
  }

  @override
  void seekTo(int ms) {}

  @override
  void openPath(String path, {required bool play}) {}

  /// What scripts asked the file manager to show or open.
  final List<String> revealed = [];
  final List<String> foldersOpened = [];
  final List<String> filesOpened = [];

  @override
  void revealPath(String path) => revealed.add(path);

  @override
  void openFolder(String path) => foldersOpened.add(path);

  @override
  void openExternal(String path) => filesOpened.add(path);

  final Map<String, String> private = {};

  @override
  String? readPrivate(String section, String item) => private["$section/$item"];

  @override
  void writePrivate(String section, String item, String value) =>
      private["$section/$item"] = value;

  @override
  bool isContainerVisible(String id) => true;

  @override
  bool isContainerActive(String id) => true;

  @override
  void setContainerVisible(String id, bool visible) {}

  @override
  String? currentLayout(String id) => null;

  final List<Size> resizes = [];

  @override
  void resizeLayout(String container, WasabiLayout layout, Size size) =>
      resizes.add(size);

  List<(String, int)> playlist = [("First", 61000), ("Second", -1)];
  final Set<int> selection = {};
  int played = -1;

  @override
  int get playlistLength => playlist.length;

  @override
  String playlistTitle(int index) => playlist[index].$1;

  @override
  int playlistItemLengthMs(int index) => playlist[index].$2;

  /// The playing item's index.
  int current = 0;

  @override
  int get playlistCurrent => current;

  @override
  String playlistLocation(int index) => "song$index.mp3";

  @override
  String playlistMetadata(int index, String name) =>
      name == "title" ? playlist[index].$1 : "";

  @override
  void removePlaylistItem(int index) => playlist.removeAt(index);

  @override
  void clearPlaylist() => playlist = [];

  @override
  void movePlaylistItem(int from, int to) =>
      playlist.insert(to, playlist.removeAt(from));

  final List<String> skinSwitches = [];
  final List<String> centered = [];
  final List<String> focused = [];

  @override
  void switchSkin(String name) => skinSwitches.add(name);

  @override
  ui.Rect? appRect = const ui.Rect.fromLTWH(10, 20, 300, 150);

  @override
  void centerWindow(String container) => centered.add(container);

  @override
  void focusWindow(String container) => focused.add(container);

  @override
  bool isPlaylistSelected(int index) => selection.contains(index);

  @override
  void selectPlaylistItem(
    int index, {
    required bool extend,
    required bool toggle,
  }) {
    if (!toggle) selection.clear();
    selection.add(index);
    notifyListeners();
  }

  @override
  void playPlaylistItem(int index) => played = index;

  @override
  List<int> searchPlaylist(String query) => [
    for (var i = 0; i < playlist.length; i++)
      if (playlist[i].$1.toLowerCase().contains(query.toLowerCase())) i,
  ];

  /// The entries right-pressed (null below the last), and the menus shown.
  final List<int?> menuPresses = [];
  int menusShown = 0;

  @override
  void pressPlaylistMenu(int? index, PointerDownEvent event) =>
      menuPresses.add(index);

  @override
  void showPlaylistMenu() => menusShown++;

  @override
  ClassicVisOptions get visOptions => const ClassicVisOptions();

  int visClicks = 0;

  @override
  void clickVis() => visClicks++;

  @override
  bool get visRunning => false;

  @override
  void startVisualization() {}

  @override
  void stopVisualization() {}

  @override
  (Float32List, Float32List)? get visSamples => null;
}

void main() {
  late WasabiSkinData skin;

  testWidgets("Amped main window: clicks on the vis reach the host", (
    tester,
  ) async {
    skin = (await tester.runAsync(
      () => WasabiSkinData.load(Directory("test/fixtures/amped")),
    ))!;
    final host = FakeHost();
    final layout = skin.container("main")!.layout("normal")!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: WasabiLayoutView(
            skin: skin,
            layout: layout,
            host: host,
            container: "main",
          ),
        ),
      ),
    );
    final vis = layout.root.children.firstWhere((c) => c.id == "vis");
    final center = wasabiObjectRect(vis, layout.size, skin).center;

    // Both clicks of a double-click go to the host, which tells a
    // double-click from a click the same way for every skin.
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    expect(host.visClicks, 2);
    await tester.pumpWidget(const SizedBox());
  });

  group("Amped title bars", () {
    Future<(FakeHost, List<int>)> pumpAmped(
      WidgetTester tester,
      String container,
      String layout,
    ) async {
      final amped = (await tester.runAsync(
        () => WasabiSkinData.load(Directory("test/fixtures/amped")),
      ))!;
      final host = FakeHost();
      // Stands in for the window's drag area, which sees every press that
      // no control claimed.
      final dragPresses = <int>[];
      final claimed = <int>{};
      WasabiPointerClaim.claim = (event) => claimed.add(event.pointer);
      addTearDown(() => WasabiPointerClaim.claim = null);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Listener(
              onPointerDown: (event) {
                if (!claimed.remove(event.pointer)) {
                  dragPresses.add(event.pointer);
                }
              },
              child: WasabiLayoutView(
                skin: amped,
                layout: amped.container(container)!.layout(layout)!,
                host: host,
                container: container,
              ),
            ),
          ),
        ),
      );
      return (host, dragPresses);
    }

    for (final container in const ["main", "eq", "pl"]) {
      testWidgets("$container: a double click toggles windowshade", (
        tester,
      ) async {
        var (host, drags) = await pumpAmped(tester, container, "normal");
        // On the title text, clear of the title-bar buttons.
        const title = Offset(180, 9);

        // A single click only drags the window.
        await tester.tapAt(title);
        await tester.pump(kDoubleTapTimeout * 2);
        expect(host.actions, isEmpty);
        expect(drags, hasLength(1));

        await tester.tapAt(title);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(title);
        expect(host.actions.single.action, "SWITCH");
        expect(host.actions.single.param, "shade");
        expect(host.actions.single.container, container);
        // Both presses still reach the window's drag area.
        expect(drags, hasLength(3));

        // A double click on the shaded window switches back. The main
        // window's shade is full of controls, so this is the gap between
        // its library button and the window buttons.
        (host, drags) = await pumpAmped(tester, container, "shade");
        const shadeGap = Offset(298, 12);
        await tester.tapAt(shadeGap);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(shadeGap);
        expect(host.actions.single.action, "SWITCH");
        expect(host.actions.single.param, "normal");
        expect(drags, hasLength(2));
      });
    }
  });

  testWidgets(
    "Amped playlist: the bottom buttons send the classic player's PE actions",
    (
      tester,
    ) async {
      final amped = (await tester.runAsync(
        () => WasabiSkinData.load(Directory("test/fixtures/amped")),
      ))!;
      final host = FakeHost();
      final layout = amped.container("pl")!.layout("normal")!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: amped,
              layout: layout,
              host: host,
              container: "pl",
            ),
          ),
        ),
      );
      for (final (id, action) in const [
        ("add", "PE_ADD"),
        ("rem", "PE_REM"),
        ("sel", "PE_SEL"),
        ("misc", "PE_MISC"),
        ("listmenu", "PE_LIST"),
      ]) {
        final button = layout.root.children.firstWhere((c) => c.id == id);
        await tester.tapAt(
          wasabiObjectRect(button, layout.size, amped).center,
        );
        expect(host.actions.last.action, action, reason: id);
        expect(host.actions.last.container, "pl");
      }
      expect(host.actions, hasLength(5));
    },
  );

  group("Amped playlist scrolling", () {
    /// The built-in Amped skin's playlist window with [count] entries,
    /// and the playlist's rect on screen.
    Future<(FakeHost, Rect)> pumpPlaylist(
      WidgetTester tester, {
      int count = 50,
    }) async {
      final amped = (await tester.runAsync(
        () => WasabiSkinData.load(Directory("test/fixtures/amped")),
      ))!;
      final host = FakeHost()
        ..playlist = [for (var i = 0; i < count; i++) ("Track $i", 60000)];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: WasabiLayoutView(
              skin: amped,
              layout: amped.container("pl")!.layout("normal")!,
              host: host,
              container: "pl",
            ),
          ),
        ),
      );
      return (host, tester.getRect(find.byType(WasabiPlaylistView)));
    }

    /// The row a click near the top of the list selects.
    Future<int> topRow(WidgetTester tester, FakeHost host, Rect list) async {
      host.selection.clear();
      await tester.tapAt(list.topLeft + const Offset(20, 6));
      await tester.pump(const Duration(seconds: 1));
      return host.selection.single;
    }

    final scrollbar = find.byKey(const ValueKey("wasabi.playlist.scrollbar"));

    testWidgets("the search box narrows the playlist to its matches", (
      tester,
    ) async {
      final (host, list) = await pumpPlaylist(tester, count: 40);
      final skin = tester
          .widget<WasabiPlaylistView>(find.byType(WasabiPlaylistView))
          .skin;

      skin.playlistFilter.value = "track 3";
      await tester.pump();
      // Track 3 and Track 30 to 39: eleven rows, the first being Track 3.
      await tester.tapAt(list.topLeft + const Offset(20, 6 + 14.0));
      await tester.pump(const Duration(seconds: 1));
      expect(host.selection.single, 30);

      // The list is short enough to need no scrollbar any more.
      expect(scrollbar, findsNothing);

      skin.playlistFilter.value = "";
      await tester.pump();
      expect(await topRow(tester, host, list), 0);
    });

    testWidgets(
      "a script's request scrolls the playlist to the playing track",
      (
        tester,
      ) async {
        final (host, list) = await pumpPlaylist(tester, count: 80);
        host.current = 60;
        final skin = tester
            .widget<WasabiPlaylistView>(find.byType(WasabiPlaylistView))
            .skin;
        expect(await topRow(tester, host, list), 0);

        skin.playlistReveal.value++;
        await tester.pump();
        // The playing track is in the view, and the list moved down to it.
        final top = await topRow(tester, host, list);
        final rows = (list.height / 14).floor();
        expect(top, lessThanOrEqualTo(60));
        expect(top + rows, greaterThan(60));
        expect(top, greaterThan(30));
      },
    );

    testWidgets("a right-click asks for the playlist's item menu", (
      tester,
    ) async {
      final (host, list) = await pumpPlaylist(tester, count: 3);
      // On the second row: pressed, then the menu on release.
      final second = list.topLeft + const Offset(20, 6 + 14.0);
      final gesture = await tester.startGesture(
        second,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      expect(host.menuPresses, [1]);
      expect(host.menusShown, 0);
      await gesture.up();
      expect(host.menusShown, 1);
      // A left click doesn't open it.
      await tester.tapAt(second);
      expect(host.menusShown, 1);
      // Below the last entry: no entry, but still the menu.
      final below = await tester.startGesture(
        list.bottomLeft + const Offset(20, -4),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await below.up();
      expect(host.menuPresses, [1, null]);
      expect(host.menusShown, 2);
    });

    testWidgets("the mouse wheel scrolls", (tester) async {
      final (host, list) = await pumpPlaylist(tester);
      expect(await topRow(tester, host, list), 0);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      mouse.hover(list.center);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 140)));
      await tester.pump();
      expect(await topRow(tester, host, list), 10);
    });

    testWidgets("a trackpad pan scrolls", (tester) async {
      final (host, list) = await pumpPlaylist(tester);
      final pad = TestPointer(2, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.panZoomStart(list.center));
      // Fingers moving up reveal later rows.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(list.center, pan: const Offset(0, -140)),
      );
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pump();
      expect(await topRow(tester, host, list), 10);
    });

    testWidgets("the scrollbar drags and pages", (tester) async {
      final (host, list) = await pumpPlaylist(tester);
      expect(scrollbar, findsOneWidget);
      final bar = tester.getRect(scrollbar);
      // Dragging the thumb to the bottom shows the last rows.
      final drag = await tester.startGesture(
        bar.topCenter + const Offset(0, 2),
      );
      await drag.moveBy(Offset(0, bar.height));
      await drag.up();
      await tester.pump();
      final bottom = await topRow(tester, host, list);
      expect(bottom, greaterThan(35));
      // Pressing the track above the thumb pages back up.
      await tester.tapAt(bar.topCenter + const Offset(0, 2));
      await tester.pump(const Duration(seconds: 1));
      expect(await topRow(tester, host, list), lessThan(bottom));
    });

    testWidgets("a short list has no scrollbar", (tester) async {
      await pumpPlaylist(tester, count: 3);
      expect(scrollbar, findsNothing);
    });
  });
}
