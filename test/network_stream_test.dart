import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped/src/player/network_stream.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late HttpServer server;
  late String base;
  final metadataRequests = <String?>[];

  setUp(() async {
    metadataRequests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = "http://${server.address.host}:${server.port}";
    server.listen((request) async {
      metadataRequests.add(request.headers.value("icy-metadata"));
      final response = request.response;
      switch (request.uri.path) {
        case "/station":
          // A Shoutcast station: no length, icy headers, and audio that
          // keeps coming until the listener hangs up.
          // Unbuffered, so the first chunk leaves before the response ends.
          response.bufferOutput = false;
          response.headers
            ..contentType = ContentType("audio", "mpeg")
            ..set("icy-name", "ISKC Old Men's Rock")
            ..set("icy-metaint", "4")
            ..set("icy-br", "320")
            ..set("icy-sr", "44100");
          // Four audio bytes, then a metadata block, then more audio.
          response
            ..add([1, 2, 3, 4])
            ..add(_metadataBlock("StreamTitle='AC/DC - Thunderstruck';"))
            ..add([5, 6]);
          await response.flush();
          await Future<void>.delayed(const Duration(seconds: 5));
          await response.close().catchError((_) {});
        case "/tunein-station.pls":
          response.headers.contentType = ContentType("audio", "x-scpls");
          response.write(
            "[playlist]\nnumberofentries=2\n"
            "File1=$base/station\nTitle1=Rock\nLength1=-1\n"
            "File2=$base/other\nVersion=2\n",
          );
          await response.close();
        case "/gone.pls":
          response.statusCode = HttpStatus.notFound;
          await response.close();
        case "/file.mp3":
          response.headers.contentType = ContentType("audio", "mpeg");
          response.contentLength = 3;
          response.add([1, 2, 3]);
          await response.close();
        default:
          response.statusCode = HttpStatus.notFound;
          await response.close();
      }
    });
  });

  tearDown(() => server.close(force: true));

  test("a .pls link resolves to the stream it lists", () async {
    expect(NetworkStream.isPlaylistUrl("$base/tunein-station.pls?id=1"), true);
    expect(NetworkStream.isPlaylistUrl("$base/a.M3U8"), true);
    expect(NetworkStream.isPlaylistUrl("$base/station"), false);
    expect(
      await NetworkStream.resolvePlaylist("$base/tunein-station.pls?id=1"),
      "$base/station",
    );
  });

  test("a link that is not a readable playlist is left alone", () async {
    expect(
      await NetworkStream.resolvePlaylist("$base/station"),
      "$base/station",
    );
    expect(
      await NetworkStream.resolvePlaylist("$base/gone.pls"),
      "$base/gone.pls",
    );
  });

  test("only http and https locations are fetched over HTTP", () {
    expect(NetworkStream.isHttp("http://45.85.191.114:8012/OldMenRock"), true);
    expect(NetworkStream.isHttp("HTTPS://example.com/a.mp3"), true);
    expect(NetworkStream.isHttp("/music/a.mp3"), false);
    expect(NetworkStream.isHttp("file:///music/a.mp3"), false);
  });

  test("a station is live and its audio arrives before it ends", () async {
    final stream = await NetworkStream.open("$base/station");
    addTearDown(stream.close);
    expect(metadataRequests.single, "1", reason: "asks for song titles");
    expect(stream.isLive, true);
    expect(stream.icyMetaInt, 4);
    expect(stream.stationName, "ISKC Old Men's Rock");
    expect(stream.bitrate, 320);
    expect(stream.sampleRate, 44100);
    // The audio comes while the server is still sending (waiting for the
    // whole response, as a download does, would never finish), without the
    // metadata block, whose title is reported instead.
    final titles = <String?>[];
    final audio = <int>[];
    final received = Completer<void>();
    final subscription = stream
        .audio(onMetadata: (metadata) => titles.add(metadata.title))
        .listen((chunk) {
          audio.addAll(chunk);
          if (audio.length == 6 && !received.isCompleted) received.complete();
        });
    addTearDown(subscription.cancel);
    await received.future.timeout(const Duration(seconds: 2));
    expect(audio, [1, 2, 3, 4, 5, 6]);
    expect(titles, ["AC/DC - Thunderstruck"]);
  });

  test("a file with a length is not live", () async {
    final stream = await NetworkStream.open("$base/file.mp3");
    addTearDown(stream.close);
    expect(stream.isLive, false);
    expect(stream.icyMetaInt, 0);
  });

  group("IcyDemuxer", () {
    // 3 audio bytes, a title block, 3 audio bytes, an empty block, 3 more.
    final title = _metadataBlock("StreamTitle='Guns N' Roses - Patience';");
    final whole = Uint8List.fromList([
      1, 2, 3, ...title, 4, 5, 6, 0, 7, 8, 9, //
    ]);

    test("takes the metadata out wherever the chunks split", () {
      for (var split = 0; split <= whole.length; split++) {
        final titles = <String?>[];
        final demuxer = IcyDemuxer(
          3,
          onMetadata: (metadata) => titles.add(metadata.title),
        );
        final audio = [
          for (final part in [
            Uint8List.sublistView(whole, 0, split),
            Uint8List.sublistView(whole, split),
          ])
            for (final chunk in demuxer.add(part)) ...chunk,
        ];
        expect(audio, [1, 2, 3, 4, 5, 6, 7, 8, 9], reason: "split at $split");
        expect(titles, ["Guns N' Roses - Patience"], reason: "split $split");
      }
    });

    test("passes a stream without metadata through", () {
      final demuxer = IcyDemuxer(0);
      expect(demuxer.add(whole).single, whole);
    });
  });

  group("IcyMetadata", () {
    test("reads the title and link, quotes and all", () {
      // Stations pack the fields with no space between them.
      final metadata = IcyMetadata.parse(
        [
          "StreamTitle='Sinead O'Connor - Nothing Compares 2 U';",
          "StreamUrl='http://example.com/';",
          "\u0000\u0000",
        ].join(),
      );
      expect(metadata.title, "Sinead O'Connor - Nothing Compares 2 U");
      expect(metadata.url, "http://example.com/");
    });

    test("an empty title is no title", () {
      expect(IcyMetadata.parse("StreamTitle='';").title, isNull);
    });
  });

  test("an error status fails to open", () async {
    await expectLater(
      NetworkStream.open("$base/missing"),
      throwsA(isA<HttpException>()),
    );
  });
}

/// A metadata block: its length in 16-byte units, then [text] padded with
/// zeros.
Uint8List _metadataBlock(String text) {
  final bytes = utf8.encode(text);
  final units = (bytes.length + 15) ~/ 16;
  return Uint8List(1 + units * 16)
    ..[0] = units
    ..setRange(1, 1 + bytes.length, bytes);
}
