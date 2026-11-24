import "dart:io";
import "dart:typed_data";

import "package:pcm_decoder/pcm_decoder.dart";
import "package:test/test.dart";

/// The fixtures are one second of a 440 Hz tone on the left and 660 Hz on
/// the right, at 44.1 kHz, made with ffmpeg.
Int16List wavSamples() {
  final bytes = File("test/fixtures/stereo.wav").readAsBytesSync();
  // ffmpeg writes a plain 44-byte header here... but find "data" anyway.
  var i = 12;
  final data = ByteData.sublistView(bytes);
  while (String.fromCharCodes(bytes.sublist(i, i + 4)) != "data") {
    i += 8 + data.getUint32(i + 4, Endian.little);
  }
  final length = data.getUint32(i + 4, Endian.little);
  return Int16List.fromList(
    Int16List.sublistView(
      Uint8List.fromList(bytes.sublist(i + 8, i + 8 + length)),
    ),
  );
}

void main() {
  test("WAV decodes to its own samples, both channels", () {
    final audio = decodeFile("test/fixtures/stereo.wav");
    expect(audio.channels, 2);
    expect(audio.sampleRate, 44100);
    expect(audio.totalFrames, 44100);
    expect(audio.duration, const Duration(seconds: 1));
    expect(audio.samples, wavSamples());
    // The channels really differ.
    expect(audio.samples[201], isNot(audio.samples[200]));
  });

  test("FLAC is lossless, so it gives the same samples", () {
    final audio = decodeFile("test/fixtures/stereo.flac");
    expect(audio.channels, 2);
    expect(audio.samples, wavSamples());
  });

  test("MP3 decodes to roughly the same signal", () {
    final audio = decodeFile("test/fixtures/stereo.mp3");
    expect(audio.channels, 2);
    expect(audio.sampleRate, 44100);
    expect(audio.duration.inMilliseconds, closeTo(1000, 60));
    expect(audio.samples.any((s) => s.abs() > 2000), isTrue);
  });

  test("decoding stops at maxDuration", () {
    final audio = decodeFile(
      "test/fixtures/stereo.wav",
      maxDuration: const Duration(milliseconds: 250),
    );
    expect(audio.samples.length, 11025 * 2);
    expect(audio.totalFrames, 44100);
  });

  test("probing reads the length without decoding", () {
    final audio = probeFile("test/fixtures/stereo.flac");
    expect(audio.samples, isEmpty);
    expect(audio.channels, 2);
    expect(audio.sampleRate, 44100);
    expect(audio.duration, const Duration(seconds: 1));
  });

  test("a file that isn't audio is an error", () {
    expect(
      () => decodeFile("pubspec.yaml"),
      throwsA(isA<DecodeException>()),
    );
    expect(() => probeFile("pubspec.yaml"), throwsA(isA<DecodeException>()));
    expect(
      () => decodeFile("test/fixtures/missing.wav"),
      throwsA(isA<DecodeException>()),
    );
  });
}
