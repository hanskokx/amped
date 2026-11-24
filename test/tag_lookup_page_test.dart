import "package:amped/src/dialogs/file_info_page.dart";
import "package:amped/src/dialogs/tag_lookup_dialog.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:amped/src/tags/tag_lookup.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  const tags = FileTags(
    format: TagFormat.wav,
    tagTypes: ["RIFF INFO"],
    fields: {TagField.title: "track01", TagField.comment: "ripped"},
    raw: [TagEntry("INAM", "track01")],
    // WAV INFO can't store the album artist.
    editable: {
      TagField.title,
      TagField.artist,
      TagField.album,
      TagField.year,
      TagField.track,
      TagField.comment,
      TagField.acoustIdFingerprint,
    },
  );

  TagLookupResult found(List<TagCandidate> candidates) => TagLookupResult(
    candidates,
    const AudioFingerprint(duration: 290, fingerprint: "AQADnew"),
  );

  const candidates = [
    TagCandidate(
      fields: {
        TagField.title: "Here Comes The Sun",
        TagField.artist: "The Beatles",
        TagField.album: "Abbey Road",
        TagField.albumArtist: "The Beatles",
        TagField.year: "1969",
        TagField.track: "7/17",
      },
      score: 0.97,
      recordingId: "r1",
      releaseId: "a",
      releaseStatus: "Official",
      releaseType: "Album",
      date: "1969-09-26",
    ),
    TagCandidate(
      fields: {
        TagField.title: "Here Comes the Sun",
        TagField.artist: "The Beatles",
        TagField.album: "1967–1970",
      },
      score: 0.97,
      recordingId: "r1",
      releaseId: "b",
    ),
  ];

  Future<(List<Map<TagField, String>>, List<String>)> pump(
    WidgetTester tester,
    TagLookupFn lookup, {
    FileTags fileTags = tags,
    List<(String, String)>? downloads,
  }) async {
    final saved = <Map<TagField, String>>[];
    final events = <String>[];
    tester.view.physicalSize = const Size(600, 410);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FileInfoPage(
            path: "/music/a.wav",
            read: (_) async => fileTags,
            readPictures: (_) async => const FilePictures([], editable: true),
            save: (path, changes, {pictures, id3}) async => saved.add(changes),
            openImage: () async => null,
            downloadImage: ({required artist, required album}) async {
              downloads?.add((artist, album));
              return null;
            },
            exportImage: (_) async {},
            onClose: ({required ok}) => events.add("closed $ok"),
            lookup: lookup,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (saved, events);
  }

  String text(WidgetTester tester, TagField field) =>
      tester.widget<TextField>(find.byKey(ValueKey(field))).controller!.text;

  testWidgets("a picked match fills the fields; only OK writes them", (
    tester,
  ) async {
    final looked = <String>[];
    final downloads = <(String, String)>[];
    final (saved, events) = await pump(downloads: downloads, tester, (
      path, {
      cachedFingerprint = "",
    }) async {
      looked.add("$path [$cachedFingerprint]");
      return found(candidates);
    });

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    // The file has no fingerprint cached yet.
    expect(looked, ["/music/a.wav []"]);
    // The file being looked up is shown on the dialog.
    expect(
      find.descendant(
        of: find.byType(TagLookupDialog),
        matching: find.text("/music/a.wav"),
      ),
      findsOneWidget,
    );
    expect(find.text("The Beatles - Here Comes The Sun"), findsOneWidget);
    expect(find.text("Album: Abbey Road"), findsOneWidget);
    expect(
      find.text("Track 7 of 17 · Released Sep 26, 1969", findRichText: true),
      findsOneWidget,
    );
    expect(find.text("97%"), findsWidgets);
    expect(find.textContaining("Official"), findsNothing);

    await tester.tap(find.text("Use these tags"));
    await tester.pumpAndSettle();
    expect(text(tester, TagField.title), "Here Comes The Sun");
    expect(text(tester, TagField.album), "Abbey Road");
    expect(text(tester, TagField.track), "7/17");
    // The cover of the picked album is fetched at once.
    expect(downloads, [("The Beatles", "Abbey Road")]);
    // What the match doesn't have is kept, and nothing is written yet.
    expect(text(tester, TagField.comment), "ripped");
    expect(saved, isEmpty);
    expect(find.textContaining("Press OK to save"), findsOneWidget);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(saved, [
      {
        TagField.title: "Here Comes The Sun",
        TagField.artist: "The Beatles",
        TagField.album: "Abbey Road",
        TagField.year: "1969",
        TagField.track: "7/17",
        // Cached with the rest, and only on OK.
        TagField.acoustIdFingerprint: "AQADnew",
      },
    ]);
    expect(events, ["closed true"]);
  });

  testWidgets("another release can be picked, or none", (tester) async {
    final (saved, _) = await pump(
      tester,
      (_, {cachedFingerprint = ""}) async => found(candidates),
    );

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cancel").last);
    await tester.pumpAndSettle();
    expect(text(tester, TagField.title), "track01");

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    // The list scrolls in a window as small as File Info's.
    await tester.scrollUntilVisible(
      find.textContaining("1967–1970"),
      50,
      scrollable: find.descendant(
        of: find.byType(TagLookupDialog),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining("1967–1970"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Use these tags"));
    await tester.pumpAndSettle();
    expect(text(tester, TagField.title), "Here Comes the Sun");
    expect(text(tester, TagField.album), "1967–1970");
    expect(saved, isEmpty);
  });

  testWidgets("a build without an API key says so", (tester) async {
    final (saved, _) = await pump(
      tester,
      (_, {cachedFingerprint = ""}) async =>
          throw const TagLookupException(TagLookupFailure.missingApiKey),
    );

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    expect(find.textContaining("has no AcoustID API key"), findsOneWidget);
    expect(find.text("Use these tags"), findsNothing);
    expect(find.text("Retry"), findsNothing);

    await tester.tap(find.text("Cancel").last);
    await tester.pumpAndSettle();
    expect(text(tester, TagField.title), "track01");
    expect(saved, isEmpty);
  });

  testWidgets("a service failure can be retried", (tester) async {
    var calls = 0;
    await pump(tester, (_, {cachedFingerprint = ""}) async {
      if (++calls == 1) {
        throw const TagLookupException(
          TagLookupFailure.network,
          "musicbrainz.org: HTTP 503",
        );
      }
      return found(candidates);
    });

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    expect(find.textContaining("service is busy"), findsOneWidget);
    // The technical reason stays, in small print.
    expect(find.text("musicbrainz.org: HTTP 503"), findsOneWidget);
    expect(find.text("Use these tags"), findsNothing);

    await tester.tap(find.text("Retry"));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text("Use these tags"), findsOneWidget);
  });

  testWidgets("a fingerprint already in the tags is reused", (tester) async {
    final cached = <String>[];
    const tagged = FileTags(
      format: TagFormat.flac,
      tagTypes: ["Vorbis comment"],
      fields: {TagField.acoustIdFingerprint: "AQADold"},
      raw: [TagEntry("ACOUSTID_FINGERPRINT", "AQADold")],
      editable: {TagField.title, TagField.acoustIdFingerprint},
    );
    final (saved, _) = await pump(tester, (
      _, {
      cachedFingerprint = "",
    }) async {
      cached.add(cachedFingerprint);
      return TagLookupResult(
        candidates,
        AudioFingerprint(duration: 290, fingerprint: cachedFingerprint),
      );
    }, fileTags: tagged);

    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    expect(cached, ["AQADold"]);
    await tester.tap(find.text("Use these tags"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    // The fingerprint didn't change, so only the title is written.
    expect(saved, [
      {TagField.title: "Here Comes The Sun"},
    ]);
  });

  testWidgets("no match is said plainly", (tester) async {
    await pump(tester, (_, {cachedFingerprint = ""}) async => found(const []));
    await tester.tap(find.text("Look up tags..."));
    await tester.pumpAndSettle();
    expect(find.textContaining("doesn't know this recording"), findsOneWidget);
  });

  // The box must lay out even when nothing above gives it a size, as in a
  // window sized to its content.
  testWidgets("the lookup box has a size of its own", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UnconstrainedBox(
          child: TagLookupDialog(
            path: "/music/a.wav",
            lookup: (_, {cachedFingerprint = ""}) async => found(candidates),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining("Here Comes The Sun"), findsWidgets);
    final size = tester.getSize(find.byType(TagLookupDialog));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });
}
