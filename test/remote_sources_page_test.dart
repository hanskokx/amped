import "package:amped/src/features/preferences/screens/pages/library_preferences_page.dart";
import "package:amped/src/features/remote_source/classes/remote_source_type.dart";
import "package:amped/src/library/library_source_manager.dart";
import "package:amped/src/library/media_library.dart";
import "package:amped/src/remote/remote_credentials.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";
import "package:shared_preferences/shared_preferences.dart";

/// A server that is reachable unless [failure] says why not.
class _Remote implements RemoteLibrarySource {
  _Remote(this.failure);

  final String? failure;

  @override
  Future<void> check() async {
    if (failure != null) throw RemoteAuthException(failure!);
  }

  @override
  Future<void> load(
    void Function(List<TrackTags> tracks) add,
    bool Function() isCancelled,
  ) async {}

  @override
  Future<void> loadVideos(
    void Function(List<TrackTags> videos) add,
    bool Function() isCancelled,
  ) async {}

  @override
  String? coverUrl(String id) => null;

  @override
  String streamUrl(String id) => id;

  @override
  void close() {}
}

class _MemoryStore implements RemoteCredentialStore {
  final Map<String, RemoteLogin> logins = {};

  @override
  Future<RemoteLogin?> read(String server) async => logins[server];

  @override
  Future<void> write(String server, RemoteLogin login) async =>
      logins[server] = login;

  @override
  Future<void> delete(String server) async => logins.remove(server);
}

void main() {
  late _MemoryStore store;
  late LibrarySourceManager sources;
  String? failure;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    failure = null;
    store = _MemoryStore();
    sources = LibrarySourceManager(
      local: MediaLibrary(readTags: (files) async => const []),
      credentials: store,
      remoteFactory: (config, password) => _Remote(failure),
    );
  });

  tearDown(() => sources.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: RemoteSourcesView(sources: sources)),
    ),
  );

  Future<void> addServer() => sources.addNavidrome(
    name: "Home",
    server: "https://music.example.com",
    user: "alice",
    password: "secret",
  );

  Finder field(String label) => find.widgetWithText(TextField, label);

  bool enabled(WidgetTester tester, String label) => tester
      .widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      )
      .enabled;

  testWidgets("with no sources, the kinds to add are offered at once", (
    tester,
  ) async {
    await pump(tester);

    expect(find.text("No remote sources added."), findsOneWidget);
    for (final type in RemoteSourceType.values) {
      expect(find.byKey(ValueKey(type)), findsOneWidget);
    }
    expect(find.text("Add source"), findsNothing);
  });

  testWidgets("a source is picked, filled in and added", (tester) async {
    await addServer();
    await pump(tester);

    await tester.tap(find.text("Add source"));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey(RemoteSourceType.jellyfin)));
    await tester.pump();
    expect(find.text("Add Jellyfin"), findsOneWidget);
    expect(enabled(tester, "Connect"), isFalse);

    await tester.enterText(field("Server address"), "http://media.local:8096");
    await tester.enterText(field("Username"), "bob");
    await tester.enterText(field("Password"), "pw");
    await tester.pump();
    expect(enabled(tester, "Connect"), isTrue);

    await tester.tap(find.text("Connect"));
    await tester.pumpAndSettle();

    expect(sources.remotes.map((r) => r.type), [
      RemoteSourceType.navidrome,
      RemoteSourceType.jellyfin,
    ]);
    expect(find.text("Remote sources"), findsOneWidget);
  });

  testWidgets("going back from a new source returns to the kinds", (
    tester,
  ) async {
    await addServer();
    await pump(tester);
    await tester.tap(find.text("Add source"));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey(RemoteSourceType.plex)));
    await tester.pump();

    await tester.tap(find.byTooltip("Back"));
    await tester.pump();
    expect(find.text("Choose what to add"), findsOneWidget);

    await tester.tap(find.byTooltip("Back"));
    await tester.pump();
    expect(find.text("Home"), findsOneWidget);
  });

  testWidgets("a failure keeps the form open and says why", (tester) async {
    await addServer();
    failure = "Wrong username or password.";
    await pump(tester);

    await tester.tap(find.text("Home"));
    await tester.pump();
    expect(find.text("Edit Home"), findsOneWidget);
    await tester.enterText(field("Password"), "wrong");
    await tester.pump();
    await tester.tap(find.text("Save"));
    await tester.pumpAndSettle();

    expect(
      find.text("Could not connect: Wrong username or password."),
      findsOneWidget,
    );
    expect(find.text("Edit Home"), findsOneWidget);
  });

  testWidgets("Escape leaves the form without saving", (tester) async {
    await addServer();
    await pump(tester);
    await tester.tap(find.byTooltip("Edit"));
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text("Edit Home"), findsNothing);
    expect(find.text("Home"), findsOneWidget);
  });

  testWidgets("removing a source asks first", (tester) async {
    await addServer();
    await pump(tester);

    await tester.tap(find.byTooltip("Remove"));
    await tester.pump();
    await tester.tap(find.text("Cancel"));
    await tester.pump();
    expect(sources.remotes, hasLength(1));

    await tester.tap(find.byTooltip("Remove"));
    await tester.pump();
    expect(
      find.text("Remove Home? Its saved sign-in is forgotten."),
      findsOneWidget,
    );
    await tester.tap(find.text("Remove"));
    await tester.pumpAndSettle();

    expect(sources.remotes, isEmpty);
    expect(store.logins, isEmpty);
    expect(find.text("No remote sources added."), findsOneWidget);
  });
}
