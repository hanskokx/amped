/// Decodes audio files to interleaved 16-bit PCM, keeping every channel.
library;

import "dart:ffi";
import "dart:typed_data";

import "package:ffi/ffi.dart";

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Double,
    Pointer<Pointer<Int16>>,
    Pointer<Uint64>,
    Pointer<Uint64>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
>(symbol: "pcm_decoder_decode")
external int _decode(
  Pointer<Utf8> path,
  double maxSeconds,
  Pointer<Pointer<Int16>> out,
  Pointer<Uint64> frames,
  Pointer<Uint64> totalFrames,
  Pointer<Uint32> channels,
  Pointer<Uint32> sampleRate,
);

@Native<Void Function(Pointer<Int16>)>(symbol: "pcm_decoder_free")
external void _free(Pointer<Int16> samples);

@Native<
  Int32 Function(
    Pointer<Utf8>,
    Pointer<Uint64>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
>(symbol: "pcm_decoder_probe")
external int _probe(
  Pointer<Utf8> path,
  Pointer<Uint64> totalFrames,
  Pointer<Uint32> channels,
  Pointer<Uint32> sampleRate,
);

/// Decoded audio: interleaved [samples] at the file's own rate.
class DecodedAudio {
  const DecodedAudio({
    required this.samples,
    required this.channels,
    required this.sampleRate,
    required this.totalFrames,
  });

  final Int16List samples;
  final int channels;
  final int sampleRate;

  /// The whole file's length in frames, which may be more than [samples]
  /// holds; 0 if the decoder can't tell.
  final int totalFrames;

  /// The whole file's length.
  Duration get duration => Duration(
    microseconds:
        (totalFrames > 0 ? totalFrames : samples.length ~/ channels) *
        1000000 ~/
        sampleRate,
  );
}

/// Thrown when a file can't be opened or decoded. [code] is miniaudio's.
class DecodeException implements Exception {
  const DecodeException(this.path, this.code);

  final String path;
  final int code;

  @override
  String toString() => "Can't decode $path (miniaudio error $code)";
}

/// Decodes up to [maxDuration] of [path] (WAV, FLAC or MP3). It blocks, so
/// call it from a background isolate.
DecodedAudio decodeFile(String path, {Duration? maxDuration}) => using((arena) {
  final out = arena<Pointer<Int16>>();
  final frames = arena<Uint64>();
  final total = arena<Uint64>();
  final channels = arena<Uint32>();
  final rate = arena<Uint32>();
  final code = _decode(
    path.toNativeUtf8(allocator: arena),
    (maxDuration?.inMicroseconds ?? 0) / 1000000,
    out,
    frames,
    total,
    channels,
    rate,
  );
  if (code != 0) throw DecodeException(path, code);
  try {
    final count = frames.value * channels.value;
    final samples = Int16List.fromList(out.value.asTypedList(count));
    return DecodedAudio(
      samples: samples,
      channels: channels.value,
      sampleRate: rate.value,
      totalFrames: total.value,
    );
  } finally {
    _free(out.value);
  }
});

/// Reads [path]'s format and length without decoding it: [DecodedAudio]
/// with no samples. It blocks, like [decodeFile].
DecodedAudio probeFile(String path) => using((arena) {
  final total = arena<Uint64>();
  final channels = arena<Uint32>();
  final rate = arena<Uint32>();
  final code = _probe(
    path.toNativeUtf8(allocator: arena),
    total,
    channels,
    rate,
  );
  if (code != 0) throw DecodeException(path, code);
  return DecodedAudio(
    samples: Int16List(0),
    channels: channels.value,
    sampleRate: rate.value,
    totalFrames: total.value,
  );
});
