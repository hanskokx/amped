import "dart:convert";
import "dart:typed_data";

import "package:amped/src/dialogs/file_info_page.dart";
import "package:amped/src/dialogs/fingerprint_image.dart";
import "package:amped/src/tags/tag_io.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:chromaprint_dart/chromaprint_dart.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart";

void main() {
  const tags = FileTags(
    format: TagFormat.wav,
    tagTypes: ["RIFF INFO"],
    fields: {TagField.title: "Old", TagField.artist: "Band"},
    raw: [TagEntry("INAM", "Old"), TagEntry("IART", "Band")],
    editable: {TagField.title, TagField.artist, TagField.comment},
    stream: StreamInfo(fileSize: 1234, sampleRate: 44100, channels: 2),
  );

  final png = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwAD"
    "hgGAWjR9awAAAABJRU5ErkJggg==",
  );
  final front = EmbeddedPicture(
    type: ArtworkType.frontCover,
    mimeType: "image/png",
    data: png,
  );

  /// The pictures each save passed (null: left alone).
  late List<List<EmbeddedPicture>?> savedPictures;
  late List<EmbeddedPicture> exported;
  late List<Id3Edit?> savedId3;

  Future<(List<Map<TagField, String>>, List<bool>)> pump(
    WidgetTester tester, {
    FileTags fileTags = tags,
    FilePictures pictures = const FilePictures([], editable: true),
    List<Uint8List?> opened = const [],
    Future<Uint8List?> Function({
      required String artist,
      required String album,
    })?
    download,
  }) async {
    final saved = <Map<TagField, String>>[];
    final closed = <bool>[];
    savedPictures = [];
    savedId3 = [];
    exported = [];
    final toOpen = [...opened];
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
            readPictures: (_) async => pictures,
            save: (path, changes, {pictures, id3}) async {
              saved.add(changes);
              savedPictures.add(pictures);
              savedId3.add(id3);
            },
            openImage: () async => toOpen.removeAt(0),
            downloadImage:
                download ?? ({required artist, required album}) async => null,
            makeFileIcon: (cover) async => Uint8List.fromList([...cover, 0]),
            exportImage: (picture) async => exported.add(picture),
            onClose: ({required ok}) => closed.add(ok),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (saved, closed);
  }

  TextField field(WidgetTester tester, TagField f) =>
      tester.widget<TextField>(find.byKey(ValueKey(f)));

  testWidgets("shows the tags and saves only what changed", (tester) async {
    final (saved, closed) = await pump(tester);

    expect(field(tester, TagField.title).controller!.text, "Old");
    expect(field(tester, TagField.artist).controller!.text, "Band");
    expect(find.textContaining("Size: 1234 bytes"), findsOneWidget);
    expect(find.textContaining("Stereo"), findsOneWidget);
    // WAV INFO has no album artist field.
    expect(field(tester, TagField.albumArtist).enabled, isFalse);
    expect(field(tester, TagField.title).enabled, isTrue);

    await tester.enterText(find.byKey(const ValueKey(TagField.title)), "New");
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();

    expect(saved, [
      {TagField.title: "New"},
    ]);
    expect(closed, [true]);
  });

  testWidgets("OK without changes saves nothing; Esc cancels", (
    tester,
  ) async {
    final (saved, closed) = await pump(tester);
    await tester.tap(find.text("OK"));
    await tester.pump();
    expect(saved, isEmpty);
    expect(closed, [true]);

    await tester.tap(find.byKey(const ValueKey(TagField.title)));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, [true, false]);
  });

  testWidgets("the Advanced tab lists the raw tags", (tester) async {
    await pump(tester);
    await tester.tap(find.text("Advanced"));
    await tester.pumpAndSettle();
    expect(find.text("INAM"), findsOneWidget);
    expect(find.text("IART"), findsOneWidget);
  });

  testWidgets("the Advanced tab draws an AcoustID fingerprint", (
    tester,
  ) async {
    // About 2 minutes: far wider than the window, one pixel per column.
    const sampleRate = 11025;
    final samples = Int16List(sampleRate * 120);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (i * 2654435761) & 0xffff;
    }
    final fingerprint = Chromaprint()
        .fingerprint(samples, sampleRate: sampleRate)
        .toString();
    await pump(
      tester,
      fileTags: FileTags(
        format: TagFormat.mp3,
        tagTypes: const ["ID3v2.4"],
        fields: const {},
        raw: [
          TagEntry("TXXX", "Acoustid Fingerprint: $fingerprint"),
          TagEntry("ACOUSTID_FINGERPRINT", fingerprint),
          // Not a fingerprint after all: shown as text.
          const TagEntry("ACOUSTID_FINGERPRINT", "garbage!"),
          const TagEntry("TXXX", "MusicBrainz Album Id: x"),
        ],
        editable: const {},
      ),
    );
    await tester.tap(find.text("Advanced"));
    await tester.pumpAndSettle();

    final images = tester.widgetList<FingerprintImage>(
      find.byType(FingerprintImage),
    );
    expect(images, hasLength(2));
    for (final image in images) {
      expect(image.png, Fingerprint(fingerprint).png);
      expect(image.semanticLabel, fingerprint);
    }
    // Stretched to its cell, never past the 600-pixel window.
    final pictures = find.descendant(
      of: find.byType(FingerprintImage),
      matching: find.byType(RawImage),
    );
    expect(pictures, findsNWidgets(2));
    for (final element in pictures.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.height, 64);
      expect(rect.left, greaterThan(0));
      expect(rect.right, lessThanOrEqualTo(600));
    }
    expect(find.text("AcoustID Fingerprint"), findsNWidgets(2));
    expect(find.textContaining(fingerprint), findsNothing);
    expect(find.text("garbage!"), findsOneWidget);
    expect(find.text("MusicBrainz Album Id: x"), findsOneWidget);
  });

  test("fingerprint tag items are recognised in every format", () {
    expect(fingerprintOfTagEntry("ACOUSTID_FINGERPRINT", "AQA"), "AQA");
    expect(fingerprintOfTagEntry("acoustid_fingerprint", "AQA "), "AQA");
    expect(fingerprintOfTagEntry("TXXX", "Acoustid Fingerprint: AQA"), "AQA");
    expect(
      fingerprintOfTagEntry(
        "----:com.apple.iTunes:Acoustid Fingerprint",
        "AQA",
      ),
      "AQA",
    );
    expect(fingerprintOfTagEntry("TXXX", "Acoustid Id: x"), isNull);
    expect(fingerprintOfTagEntry("TIT2", "AQA"), isNull);
    expect(fingerprintPngOrNull(""), isNull);
    expect(fingerprintPngOrNull("AQ"), isNull);
  });

  Future<void> openArtwork(WidgetTester tester) async {
    await tester.tap(find.text("Artwork"));
    await tester.pumpAndSettle();
  }

  testWidgets("the Artwork tab shows the file's pictures", (tester) async {
    await pump(
      tester,
      pictures: FilePictures([
        EmbeddedPicture(
          type: ArtworkType.backCover,
          mimeType: "image/jpeg",
          data: Uint8List(4),
        ),
        front,
      ], editable: true),
    );
    await openArtwork(tester);
    expect(find.text("Back cover"), findsOneWidget);
    // The front cover is selected first.
    expect(
      find.text("Front cover: 1x1, origin: embedded, type: png"),
      findsOneWidget,
    );
    await tester.tap(find.text("Back cover"));
    await tester.pump();
    expect(
      find.text("Back cover: ?x?, origin: embedded, type: jpeg"),
      findsOneWidget,
    );
    await tester.tap(find.text("Save As..."));
    await tester.pump();
    expect(exported.single.type, ArtworkType.backCover);

    // Nothing changed: OK leaves the pictures alone.
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(savedPictures, isEmpty);
  });

  testWidgets("loads, replaces and deletes pictures, saved on OK", (
    tester,
  ) async {
    final (saved, closed) = await pump(
      tester,
      opened: [png, Uint8List.fromList(utf8.encode("not an image")), png],
    );
    await openArtwork(tester);
    expect(find.text("(no image)"), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "Delete"))
          .onPressed,
      isNull,
    );

    // A front cover (the default type).
    await tester.tap(find.text("Choose..."));
    await tester.pumpAndSettle();
    expect(find.textContaining("Front cover: 1x1"), findsOneWidget);

    // Not an image: nothing added.
    await tester.tap(find.text("Choose..."));
    await tester.pumpAndSettle();
    expect(
      find.text("That file isn't an image amped can embed."),
      findsOneWidget,
    );

    // A back cover.
    await tester.tap(find.byKey(const ValueKey("artworkType")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Back cover").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Choose..."));
    await tester.pumpAndSettle();
    expect(find.textContaining("Back cover: 1x1"), findsOneWidget);
    // In the list and in the type box.
    expect(find.text("Back cover"), findsWidgets);

    // Delete it again.
    await tester.tap(find.text("Delete"));
    await tester.pumpAndSettle();
    // The selection moves to the file icon made from the front cover.
    expect(find.textContaining("File icon (32x32 PNG):"), findsOneWidget);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(saved, [<TagField, String>{}]);
    // The first front cover also became the missing file icon.
    expect(savedPictures.single!.map((p) => p.type), [
      ArtworkType.frontCover,
      ArtworkType.fileIcon,
    ]);
    expect(savedPictures.single!.first.data, png);
    expect(savedPictures.single!.last.data, [...png, 0]);
    expect(closed, [true]);
  });

  testWidgets("a new front cover replaces an existing file icon", (
    tester,
  ) async {
    await pump(
      tester,
      pictures: FilePictures([
        EmbeddedPicture(
          type: ArtworkType.fileIcon,
          mimeType: "image/png",
          data: Uint8List.fromList([1, 2, 3]),
        ),
      ], editable: true),
      opened: [png],
    );
    await openArtwork(tester);
    await tester.tap(find.text("Choose..."));
    await tester.pumpAndSettle();
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(savedPictures.single!.map((p) => p.type), [
      ArtworkType.fileIcon,
      ArtworkType.frontCover,
    ]);
    expect(savedPictures.single!.first.data, [...png, 0]);
  });

  testWidgets("Download fetches the cover for the Artist and Album fields", (
    tester,
  ) async {
    final asked = <(String, String)>[];
    await pump(
      tester,
      fileTags: const FileTags(
        format: TagFormat.flac,
        tagTypes: ["Vorbis"],
        fields: {TagField.artist: "Band"},
        raw: [],
        editable: {TagField.artist, TagField.album},
      ),
      download: ({required artist, required album}) async {
        asked.add((artist, album));
        return artist == "Band" && album == "Disc" ? png : null;
      },
    );
    await tester.enterText(find.byKey(const ValueKey(TagField.album)), "Disc");
    await openArtwork(tester);
    await tester.tap(find.text("Download"));
    await tester.pumpAndSettle();
    expect(asked, [("Band", "Disc")]);
    expect(find.textContaining("Front cover: 1x1"), findsOneWidget);

    // Nothing found: said so, and the picture stays.
    await tester.tap(find.byKey(const ValueKey("artworkType")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Back cover").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Basic Info"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey(TagField.album)), "x");
    await openArtwork(tester);
    await tester.tap(find.text("Download"));
    await tester.pumpAndSettle();
    expect(find.textContaining("No artwork found"), findsOneWidget);
  });

  testWidgets("deleting the only picture saves none; Cancel saves nothing", (
    tester,
  ) async {
    var (saved, closed) = await pump(
      tester,
      pictures: FilePictures([front], editable: true),
    );
    await openArtwork(tester);
    await tester.tap(find.text("Delete"));
    await tester.pumpAndSettle();
    expect(find.text("(no image)"), findsOneWidget);
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(closed, [false]);

    (saved, closed) = await pump(
      tester,
      pictures: FilePictures([front], editable: true),
    );
    await openArtwork(tester);
    await tester.tap(find.text("Delete"));
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(savedPictures, [<EmbeddedPicture>[]]);
  });

  testWidgets("a file that can't hold pictures", (tester) async {
    await pump(
      tester,
      pictures: FilePictures([front], editable: false),
    );
    await openArtwork(tester);
    expect(find.text("Pictures can't be stored in this file."), findsOneWidget);
    for (final label in ["Choose...", "Change...", "Delete"]) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
        reason: label,
      );
    }
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, "Save As..."),
          )
          .onPressed,
      isNotNull,
    );
  });

  const mp3 = FileTags(
    format: TagFormat.mp3,
    tagTypes: ["ID3v1", "ID3v2.3"],
    fields: {TagField.title: "Long title", TagField.artist: "Band"},
    raw: [],
    editable: {...TagField.values},
    id3v1: {TagField.title: "Short", TagField.artist: "Band"},
    id3v2: {TagField.title: "Long title", TagField.artist: "Band"},
  );

  testWidgets("an MP3's ID3v1 and ID3v2 tabs are edited apart", (
    tester,
  ) async {
    final (saved, _) = await pump(tester, fileTags: mp3);
    await tester.tap(find.text("ID3v1"));
    await tester.pumpAndSettle();
    TextField v1(String name) =>
        tester.widget<TextField>(find.byKey(ValueKey("id3v1.$name")));
    expect(v1("title").controller!.text, "Short");

    await tester.enterText(find.byKey(const ValueKey("id3v1.title")), "Tiny");
    await tester.tap(find.text("ID3v2"));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey("id3v2.title")))
          .controller!
          .text,
      "Long title",
    );
    // Untick ID3v2.
    await tester.tap(find.byKey(const ValueKey("id3v2.include")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();

    expect(saved, [<TagField, String>{}]);
    final edit = savedId3.single!;
    expect(edit.v1, {TagField.title: "Tiny"});
    expect(edit.v2, isEmpty);
    expect(edit.includeV1, isNull);
    expect(edit.includeV2, false);
  });

  testWidgets("Copy to ID3v2 fills the ID3v2 tab from ID3v1", (tester) async {
    await pump(tester, fileTags: mp3);
    await tester.tap(find.text("ID3v1"));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey("id3v1.copy")));
    await tester.tap(find.byKey(const ValueKey("id3v1.copy")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("ID3v2"));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey("id3v2.title")))
          .controller!
          .text,
      "Short",
    );
  });

  testWidgets("other formats have no ID3 tabs", (tester) async {
    await pump(tester);
    expect(find.text("ID3v1"), findsNothing);
    expect(find.text("ID3v2"), findsNothing);
  });
}
