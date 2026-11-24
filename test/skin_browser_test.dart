import "dart:convert";
import "dart:io";

import "package:amped/src/features/preferences/screens/pages/skin_browser_page.dart";
import "package:amped/src/skin/modern_preview_cache.dart";
import "package:amped/src/skin/webamp_skin_library.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

class _FakeLibrary extends WebampSkinLibrary {
  _FakeLibrary(this.pages);

  final Map<String, List<WebampSkin>> pages;
  final List<String> queries = [];
  final List<int> offsets = [];
  final List<String> downloaded = [];

  @override
  Future<WebampSkinPage> browse({String query = "", int offset = 0}) async {
    queries.add(query);
    offsets.add(offset);
    final list = pages[query] ?? const [];
    final end = (offset + WebampSkinLibrary.pageSize).clamp(0, list.length);
    return WebampSkinPage(list.sublist(offset.clamp(0, end), end), list.length);
  }

  @override
  Future<Uint8List> screenshot(WebampSkin skin) async =>
      Future.error("no preview");

  @override
  Future<Uint8List> download(WebampSkin skin) async {
    downloaded.add(skin.md5);
    return Uint8List.fromList([1, 2, 3]);
  }
}

WebampSkin _skin(String md5, String file) => WebampSkin(
  md5: md5,
  fileName: file,
  screenshotUrl: "",
  downloadUrl: "https://example.test/$md5.wsz",
);

void main() {
  group("modern preview cache", previewCacheTests);

  test("WebampSkin names the install after the upload", () {
    final skin = _skin("a", "Dark4.zip");
    expect(skin.title, "Dark4");
    expect(skin.installFileName, "Dark4.wsz");
  });

  test("modern skins have no preview and install as .wal", () {
    final skin = WebampSkin.fromJson({
      "md5": "m",
      "filename": "Godsend_Wasabi5_Skin.wal",
      "screenshot_url": null,
      "download_url": "https://example.test/m.wal",
      "nsfw": null,
    });
    expect(skin.screenshotUrl, isNull);
    expect(skin.installFileName, "Godsend_Wasabi5_Skin.wal");
  });

  test("browse parses the library's reply and hides NSFW skins", () async {
    // The test binding stubs HTTP out; this one talks to a local server.
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            "data": {
              "skins": {
                "count": 2,
                "nodes": [
                  {
                    "md5": "a",
                    "filename": "A.wsz",
                    "screenshot_url": "s",
                    "download_url": "d",
                    "nsfw": false,
                  },
                  {
                    "md5": "b",
                    "filename": "B.wsz",
                    "screenshot_url": "s",
                    "download_url": "d",
                    "nsfw": true,
                  },
                ],
              },
            },
          }),
        );
      await request.response.close();
    });
    final client = HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(server.address, server.port);
    final library = WebampSkinLibrary(clientFactory: () => client);
    final page = await library.browse();
    expect(page.total, 2);
    expect(page.skins.map((s) => s.md5), ["a"]);
  });

  Future<_FakeLibrary> pump(
    WidgetTester tester,
    _FakeLibrary library,
    List<String?> installs,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SkinBrowserPage(
            library: library,
            install: (bytes, {name, fileName}) async {
              installs.add(fileName);
              throw UnimplementedError();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return library;
  }

  testWidgets("searches, and downloads from the hover button", (tester) async {
    final library = _FakeLibrary({
      "": [_skin("a", "Alpha.wsz")],
      "dark": [_skin("b", "Dark4.zip")],
    });
    final installs = <String?>[];
    await pump(tester, library, installs);
    expect(find.text("Alpha"), findsOneWidget);

    await tester.enterText(find.byType(TextField), "dark");
    // No Enter: the search waits for a pause in typing, then runs once.
    await tester.pump(const Duration(milliseconds: 200));
    expect(library.queries, [""]);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(library.queries, ["", "dark"]);
    expect(find.text("Alpha"), findsNothing);

    // The download button only shows while hovering the tile.
    expect(find.byIcon(Icons.download).hitTestable(), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text("Dark4")));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
    expect(library.downloaded, ["b"]);
    expect(installs, ["Dark4.wsz"]);
  });

  testWidgets("loads more as the grid scrolls near its end", (tester) async {
    final library = _FakeLibrary({
      "": [for (var i = 0; i < 60; i++) _skin("s$i", "Skin$i.wsz")],
    });
    await pump(tester, library, []);
    // The first page is not enough to be done; scrolling brings the rest.
    final grid = find.byType(GridView);
    for (var i = 0; i < 6; i++) {
      await tester.drag(grid, const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    expect(library.offsets.last, greaterThanOrEqualTo(48));
    expect(find.text("Load more"), findsNothing);
  });

  testWidgets("previews, steps with the arrow keys, and scrolls back", (
    tester,
  ) async {
    final library = _FakeLibrary({
      "": [for (var i = 0; i < 24; i++) _skin("s$i", "Skin$i.wsz")],
    });
    await pump(tester, library, []);
    await tester.tap(find.text("Skin0"));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text("Skin1")),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text("Skin0")),
      findsOneWidget,
    );

    // Step far down, then close: the grid scrolls to that skin.
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text("Skin20").hitTestable(), findsOneWidget);
  });
}

class _CountingLibrary extends WebampSkinLibrary {
  int downloads = 0;

  @override
  Future<Uint8List> download(WebampSkin skin) async {
    downloads++;
    return Uint8List.fromList([1]);
  }
}

void previewCacheTests() {
  WebampSkin wal(String md5) => WebampSkin(
    md5: md5,
    fileName: "$md5.wal",
    downloadUrl: "https://example.test/$md5.wal",
  );

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync("amped_cache_"));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ModernPreviewCache cacheOf(_CountingLibrary library) => ModernPreviewCache(
    library,
    root: root,
    unpack: (bytes, target) async {
      File("${target.path}/skin.xml").writeAsStringSync("<x/>");
      return true;
    },
  );

  List<FileSystemEntity> unpacked() => root.listSync();

  test(
    "a preview is shared, and its folder goes with the last release",
    () async {
      final library = _CountingLibrary();
      final cache = cacheOf(library);
      final skin = wal("a");
      final first = await cache.acquire(skin);
      final second = await cache.acquire(skin);
      expect(second, same(first));
      expect(library.downloads, 1);
      expect(unpacked(), hasLength(1));

      cache.release(skin);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(unpacked(), hasLength(1));
      cache.release(skin);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(unpacked(), isEmpty);
    },
  );

  test("a skin released before its turn is never downloaded", () async {
    final library = _CountingLibrary();
    final cache = ModernPreviewCache(
      library,
      root: root,
      maxConcurrent: 1,
      unpack: (bytes, target) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return true;
      },
    );
    final held = wal("a");
    final skipped = wal("b");
    final heldPreview = cache.acquire(held);
    final skippedPreview = cache.acquire(skipped);
    cache.release(skipped);
    expect(await skippedPreview, isNull);
    await heldPreview;
    expect(library.downloads, 1);
    await cache.dispose();
  });

  test(
    "dispose deletes every folder, and purgeStale clears leftovers",
    () async {
      final library = _CountingLibrary();
      final cache = cacheOf(library);
      await cache.acquire(wal("a"));
      await cache.acquire(wal("b"));
      expect(unpacked(), hasLength(2));
      await cache.dispose();
      expect(unpacked(), isEmpty);

      Directory("${root.path}/left/over").createSync(recursive: true);
      await ModernPreviewCache.purgeStale(root: root);
      expect(root.existsSync(), isFalse);
    },
  );
}
