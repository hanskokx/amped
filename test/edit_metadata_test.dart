import "dart:io";

import "package:amped/src/dialogs/edit_metadata_page.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

FileTags tagged(Map<TagField, String> fields, {Set<TagField>? editable}) =>
    FileTags(
      format: TagFormat.mp3,
      tagTypes: const ["ID3v2.3"],
      fields: fields,
      raw: const [],
      editable: editable ?? TagField.values.toSet(),
    );

const Set<TagField> wavInfo = {
  TagField.title,
  TagField.artist,
  TagField.album,
  TagField.year,
  TagField.genre,
  TagField.comment,
  TagField.track,
};

void main() {
  group("shareFields", () {
    final files = [
      tagged({
        TagField.artist: "Band",
        TagField.album: "LP",
        TagField.title: "One",
        TagField.track: "1",
      }),
      tagged({
        TagField.artist: "Band",
        TagField.title: "Two",
        TagField.track: "2",
      }),
      tagged({
        TagField.artist: "Band",
        TagField.album: "LP",
        TagField.title: "Three",
      }, editable: wavInfo),
    ];
    final shared = shareFields(files);

    test("fills in what the files agree on", () {
      expect(shared[TagField.artist]!.value, "Band");
      expect(shared[TagField.artist]!.varies, isFalse);
      expect(shared[TagField.artist]!.partial, isFalse);
    });

    test("leaves out what differs, counting the values", () {
      expect(shared[TagField.title]!.value, "");
      expect(shared[TagField.title]!.varies, isTrue);
      expect(shared[TagField.title]!.distinct, 3);
      expect(shared[TagField.track]!.varies, isTrue);
    });

    test("files without a value don't count as disagreeing", () {
      expect(shared[TagField.album]!.value, "LP");
      expect(shared[TagField.album]!.partial, isTrue);
      expect(shared[TagField.album]!.filled, 2);
    });

    test("counts the files that can store a field", () {
      expect(shared[TagField.albumArtist]!.supported, 2);
      expect(shared[TagField.albumArtist]!.unsupported, isFalse);
      expect(
        shareFields([files[2]])[TagField.albumArtist]!.unsupported,
        isTrue,
      );
    });

    test("changesFor skips unstorable and unchanged fields", () {
      final values = {TagField.album: "LP", TagField.albumArtist: "VA"};
      expect(changesFor(files[0], values), {TagField.albumArtist: "VA"});
      expect(changesFor(files[1], values), {
        TagField.album: "LP",
        TagField.albumArtist: "VA",
      });
      expect(changesFor(files[2], values), isEmpty);
    });
  });

  group("EditMetadataPage", () {
    Future<(List<(String, Map<TagField, String>)>, List<bool>)> pump(
      WidgetTester tester,
      List<FileTags> files,
    ) async {
      final saved = <(String, Map<TagField, String>)>[];
      final closed = <bool>[];
      tester.view.physicalSize = const Size(520, 570);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EditMetadataPage(
              paths: [for (var i = 0; i < files.length; i++) "/m/$i.mp3"],
              read: (_) async => files,
              save: (path, changes) async => saved.add((path, changes)),
              onClose: () => closed.add(true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (saved, closed);
    }

    TextField field(WidgetTester tester, TagField f) =>
        tester.widget<TextField>(find.byKey(ValueKey(f)));

    final files = [
      tagged({TagField.artist: "Band", TagField.title: "One"}),
      tagged({TagField.artist: "Band", TagField.title: "Two"}),
    ];

    testWidgets("prefills shared fields and flags differing ones", (
      tester,
    ) async {
      await pump(tester, files);
      expect(find.text("2 items selected"), findsOneWidget);
      expect(field(tester, TagField.artist).controller!.text, "Band");
      expect(field(tester, TagField.title).controller!.text, "");
      expect(
        field(tester, TagField.title).decoration!.hintText,
        "2 different values, kept unless ticked",
      );
      // Nothing ticked yet: Update is off.
      final update = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, "Update"),
      );
      expect(update.onPressed, isNull);
    });

    testWidgets("typing ticks a field; only ticked fields are written", (
      tester,
    ) async {
      final (saved, closed) = await pump(tester, files);
      await tester.enterText(
        find.byKey(const ValueKey(TagField.genre)),
        "Rock",
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, "Update"));
      await tester.pumpAndSettle();

      expect([for (final (path, _) in saved) path], ["/m/0.mp3", "/m/1.mp3"]);
      for (final (_, changes) in saved) {
        expect(changes, {TagField.genre: "Rock"});
      }
      expect(closed, [true]);
    });

    testWidgets("unticking undoes the edit", (tester) async {
      final (saved, _) = await pump(tester, files);
      await tester.enterText(
        find.byKey(const ValueKey(TagField.artist)),
        "Other",
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey(("tick", TagField.artist))));
      await tester.pump();
      expect(field(tester, TagField.artist).controller!.text, "Band");
      expect(saved, isEmpty);
    });

    testWidgets("fields no file can store are disabled", (tester) async {
      await pump(tester, [
        tagged({TagField.title: "A"}, editable: wavInfo),
        tagged({TagField.title: "B"}, editable: wavInfo),
      ]);
      expect(field(tester, TagField.albumArtist).enabled, isFalse);
      expect(field(tester, TagField.genre).enabled, isTrue);
    });
  });

  final hasFfmpeg = Process.runSync("which", ["ffmpeg"]).exitCode == 0;
  test("writes the ticked fields to real files of mixed formats", () async {
    final dir = Directory.systemTemp.createTempSync("edit_metadata_test");
    addTearDown(() => dir.deleteSync(recursive: true));
    String encode(String name, List<String> codec, String title) {
      final path = "${dir.path}/$name";
      final result = Process.runSync("ffmpeg", [
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "sine=duration=1",
        ...codec,
        "-metadata",
        "title=$title",
        path,
      ]);
      expect(result.exitCode, 0, reason: "${result.stderr}");
      return path;
    }

    final paths = [
      encode("a.mp3", ["-c:a", "libmp3lame"], "A"),
      encode("b.flac", ["-c:a", "flac"], "B"),
      encode("c.wav", ["-c:a", "pcm_s16le"], "C"),
    ];
    final files = await readAllFileTagsInBackground(paths);
    final values = {TagField.album: "Shared", TagField.albumArtist: "VA"};
    for (final (i, file) in files.indexed) {
      writeFileTags(paths[i], changesFor(file, values));
    }
    final after = [for (final path in paths) readFileTags(path)];
    expect(
      [for (final t in after) t[TagField.album]],
      [
        "Shared",
        "Shared",
        "Shared",
      ],
    );
    // WAV's INFO chunk has no album artist; the others got it.
    expect([for (final t in after) t[TagField.albumArtist]], ["VA", "VA", ""]);
    // Titles untouched.
    expect([for (final t in after) t[TagField.title]], ["A", "B", "C"]);
  }, skip: hasFfmpeg ? false : "ffmpeg not installed");
}
