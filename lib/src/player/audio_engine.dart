import "dart:async";

import "package:amped_logging/amped_logging.dart";
import "package:amped_media_source/amped_media_source.dart";
import "package:flutter/foundation.dart";
import "package:flutter_soloud/flutter_soloud.dart";

import "equalizer.dart";
import "network_stream.dart";

/// What the playing live stream says about itself: what is on now and the
/// bitrate and sample rate the station announces.
@immutable
class StreamInfo {
  const StreamInfo(
    this.location, {
    this.title,
    this.bitrate,
    this.sampleRate,
  });

  /// The URL that is playing.
  final String location;

  /// The station's current `StreamTitle`, usually "Artist - Title"; null
  /// until it sends one.
  final String? title;

  /// kbps (`icy-br`), or null.
  final int? bitrate;

  /// Hz (`icy-sr`), or null.
  final int? sampleRate;

  StreamInfo withTitle(String? title) => StreamInfo(
    location,
    title: title,
    bitrate: bitrate,
    sampleRate: sampleRate,
  );
}

/// Plays one track at a time through SoLoud, or two while crossfading from
/// one to the next.
///
/// Local files stream from disk. A live HTTP stream (a Shoutcast or Icecast
/// station) is fed to a SoLoud buffer stream as it arrives; other URLs are
/// downloaded first.
class AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  AudioSource? _source;
  SoundHandle? _handle;
  bool _ready = false;

  /// The connection feeding the playing live stream, if one is playing.
  NetworkStream? _stream;
  StreamSubscription<Uint8List>? _streamData;

  /// The buffer stream of the last live stream started.
  AudioSource? _liveSource;

  /// What the playing live stream says about itself; null when no live
  /// stream plays.
  final ValueNotifier<StreamInfo?> streamInfo = ValueNotifier(null);

  /// The track fading out under the current one while crossfading.
  AudioSource? _outgoingSource;
  SoundHandle? _outgoingHandle;

  /// Measures the current track's fade-in, and how long it lasts, while
  /// the track is fading in.
  Stopwatch? _fadeIn;
  Duration _fadeInLength = Duration.zero;

  /// The player's volume (0..1), before the EQ preamp.
  double _volume = 1;

  /// The EQ preamp's gain while the EQ is active, else 1.
  double _preamp = 1;

  /// How many visualizations want samples ([startVisualization]).
  int _visUsers = 0;
  StreamSubscription<AudioVisualizationData>? _visSubscription;
  (Float32List, Float32List)? _visSamples;

  /// The last EQ settings, applied again once the device starts.
  ({bool enabled, int preamp, List<int> bands})? _eq;

  /// Starts the audio device. Returns whether audio is available.
  Future<bool> init() async {
    if (_ready) return true;
    try {
      await _soloud.init();
      _ready = true;
      final eq = _eq;
      if (eq != null) {
        setEqualizer(enabled: eq.enabled, preamp: eq.preamp, bands: eq.bands);
      }
      if (_visUsers > 0) _enableVisualization();
    } on Object catch (error) {
      Arcane.log(
        "Audio unavailable",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "AudioEngine",
      );
    }
    return _ready;
  }

  /// Plays [location] (a path or URL) from the start, replacing whatever was
  /// playing, and calls [onFinished] when it ends by itself. Returns the
  /// track length, or `null` when it could not be played.
  ///
  /// With a [crossfade] length, the playing track fades out over that time
  /// instead of stopping, and the new one fades in over it once loaded.
  Future<Duration?> play(
    String location, {
    required double volume,
    required double pan,
    required VoidCallback onFinished,
    Duration? crossfade,
  }) async {
    if (!await init()) return null;
    if (crossfade != null && crossfade > Duration.zero && _playing) {
      await _fadeOutCurrent(crossfade);
    } else {
      await stop();
    }
    final AudioSource source;
    NetworkStream? stream;
    try {
      // A station link is often a .pls/.m3u that names the actual stream.
      // A track of a remote source is signed just now.
      location = await SourceLocation.resolve(location);
      location = await NetworkStream.resolvePlaylist(location);
      if (NetworkStream.isHttp(location)) {
        stream = await NetworkStream.open(location);
        if (!stream.isLive) {
          // A file with a length: download it, as before.
          stream.close();
          stream = null;
        }
      }
      source = stream != null
          ? _openLiveStream(location, stream)
          : location.contains("://")
          ? await _soloud.loadUrl(location, mode: LoadMode.disk)
          : await _soloud.loadFile(location, mode: LoadMode.disk);
    } on Object catch (error) {
      stream?.close();
      Arcane.log(
        "Could not open the stream",
        level: Level.warning,
        module: "AudioEngine",
        metadata: {"location": location, "error": "$error"},
      );
      return null;
    }
    _source = source;
    unawaited(
      source.allInstancesFinished.first.then((_) {
        // Stopping clears _source first, so only a natural end gets here.
        if (identical(_source, source)) onFinished();
      }),
    );
    _volume = volume;
    if (crossfade != null && crossfade > Duration.zero) {
      final handle = _soloud.play(source, volume: 0, pan: pan);
      _handle = handle;
      _soloud.fadeVolume(handle, volume * _preamp, crossfade);
      _fadeIn = Stopwatch()..start();
      _fadeInLength = crossfade;
    } else {
      _fadeIn = null;
      _handle = _soloud.play(source, volume: volume * _preamp, pan: pan);
    }
    // A live stream has no length; the player then shows no seek position.
    return stream != null ? Duration.zero : _soloud.getLength(source);
  }

  /// A buffer stream that plays [stream] (from [location]) as it arrives.
  /// The station's metadata blocks are taken out of the audio here and go
  /// to [streamInfo]; SoLoud detects the format (MP3, AAC, Ogg). When the
  /// server closes the connection the stream ends once what was received
  /// has played.
  AudioSource _openLiveStream(String location, NetworkStream stream) {
    final source = _soloud.setBufferStream(
      bufferingType: BufferingType.released,
      format: BufferType.auto,
    );
    _stream = stream;
    _liveSource = source;
    streamInfo.value = StreamInfo(
      location,
      bitrate: stream.bitrate,
      sampleRate: stream.sampleRate,
    );
    void onMetadata(IcyMetadata metadata) {
      final info = streamInfo.value;
      if (!identical(_stream, stream) || info == null) return;
      // An empty block keeps the title; a new one replaces it.
      if (metadata.title != null && metadata.title != info.title) {
        streamInfo.value = info.withTitle(metadata.title);
      }
    }

    _streamData = stream
        .audio(onMetadata: onMetadata)
        .listen(
          (chunk) {
            if (!identical(_stream, stream)) return;
            try {
              _soloud.addAudioDataStream(source, chunk);
            } on Object catch (error) {
              Arcane.log(
                "Stream stopped",
                level: Level.warning,
                module: "AudioEngine",
                metadata: {"error": "$error"},
              );
              _endLiveStream(source, stream);
            }
          },
          onError: (Object error) {
            Arcane.log(
              "Stream connection lost",
              level: Level.warning,
              module: "AudioEngine",
              metadata: {"error": "$error"},
            );
            _endLiveStream(source, stream);
          },
          onDone: () => _endLiveStream(source, stream),
          cancelOnError: true,
        );
    return source;
  }

  /// Marks [source]'s data as complete, so it ends when it has played out.
  void _endLiveStream(AudioSource source, NetworkStream stream) {
    if (!identical(_stream, stream)) return;
    unawaited(_streamData?.cancel());
    _streamData = null;
    _stream = null;
    stream.close();
    try {
      _soloud.setDataIsEnded(source);
    } on Object {
      // Already ended (or disposed).
    }
  }

  /// Moves the current track to the outgoing slot and fades it out over
  /// [time], then releases it. An earlier outgoing track stops right away.
  Future<void> _fadeOutCurrent(Duration time) async {
    await _stopOutgoing();
    final source = _source!;
    final handle = _handle!;
    _source = null;
    _handle = null;
    _fadeIn = null;
    _outgoingSource = source;
    _outgoingHandle = handle;
    _soloud.fadeVolume(handle, 0, time);
    _soloud.scheduleStop(handle, time);
    unawaited(
      Future<void>.delayed(time + const Duration(milliseconds: 100), () {
        if (identical(_outgoingSource, source)) return _stopOutgoing();
      }),
    );
  }

  Future<void> _stopOutgoing() async {
    final source = _outgoingSource;
    final handle = _outgoingHandle;
    _outgoingSource = null;
    _outgoingHandle = null;
    if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
      await _soloud.stop(handle);
    }
    if (source != null) await _soloud.disposeSource(source);
  }

  /// Whether a track is fading out under the current one.
  bool get crossfading {
    final handle = _outgoingHandle;
    return handle != null && _soloud.getIsValidVoiceHandle(handle);
  }

  /// The time left of the current track's fade-in, zero once it is done.
  Duration get _fadeInLeft {
    final fadeIn = _fadeIn;
    if (fadeIn == null) return Duration.zero;
    final left = _fadeInLength - fadeIn.elapsed;
    if (left > Duration.zero) return left;
    _fadeIn = null;
    return Duration.zero;
  }

  /// Sets the current track's volume to the player's volume times the
  /// preamp; during its fade-in, the fade aims for it instead (setting the
  /// volume does not stop a fade).
  void _applyVolume() {
    if (!_playing) return;
    final target = _volume * _preamp;
    final left = _fadeInLeft;
    if (left > Duration.zero) {
      _soloud.fadeVolume(_handle!, target, left);
    } else {
      _soloud.setVolume(_handle!, target);
    }
  }

  bool get _playing {
    final handle = _handle;
    return handle != null && _soloud.getIsValidVoiceHandle(handle);
  }

  void setPaused(bool paused) {
    if (_playing) _soloud.setPause(_handle!, paused);
    if (crossfading) _soloud.setPause(_outgoingHandle!, paused);
  }

  /// Stops playback and releases the track (both tracks while crossfading).
  Future<void> stop() async {
    _fadeIn = null;
    await _stopOutgoing();
    final source = _source;
    final handle = _handle;
    _source = null;
    _handle = null;
    final stream = _stream;
    _stream = null;
    final data = _streamData;
    _streamData = null;
    await data?.cancel();
    stream?.close();
    streamInfo.value = null;
    if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
      await _soloud.stop(handle);
    }
    if (source != null) await _soloud.disposeSource(source);
  }

  void seek(Duration position) {
    // A live stream can't seek.
    if (_playing && !_isLiveStream) _soloud.seek(_handle!, position);
  }

  /// [volume] is 0..1.
  void setVolume(double volume) {
    _volume = volume;
    _applyVolume();
  }

  /// Applies the Equalizer window's settings (the original's slider values,
  /// see [Equalizer]) as the original does: the preamp scales the signal,
  /// the 4Front ten-band EQ shapes it (reproduced by fitting a finer
  /// parametric EQ to its response), and a limiter keeps peaks below
  /// -0.6 dB. A flat or switched-off EQ leaves the audio untouched.
  void setEqualizer({
    required bool enabled,
    required int preamp,
    required List<int> bands,
  }) {
    _eq = (enabled: enabled, preamp: preamp, bands: List.of(bands));
    if (!_ready) return;
    final filters = _soloud.filters;
    final eq = filters.parametricEqFilter;
    final limiter = filters.limiterFilter;
    final active = Equalizer.isActive(
      enabled: enabled,
      preamp: preamp,
      bands: bands,
    );
    try {
      if (!active) {
        if (eq.isActive) eq.deactivate();
        if (limiter.isActive) limiter.deactivate();
        _preamp = 1;
      } else {
        if (!eq.isActive) {
          eq.activate();
          // Fine enough frequency bins (about 11 Hz) for the 70 Hz band.
          eq.stftWindowSize.value = 4096;
          eq.numBands.value = Equalizer.fitFrequencies.length.toDouble();
          for (final (i, frequency) in Equalizer.fitFrequencies.indexed) {
            eq.bandFreq(i).value = frequency;
            eq.bandQ(i).value = Equalizer.fitQ;
          }
        }
        final bandValues = [
          for (var i = 0; i < Equalizer.frequencies.length; i++)
            i < bands.length ? bands[i] : Equalizer.neutral,
        ];
        final gains = Equalizer.fittedGains(bandValues);
        for (final (i, gain) in gains.indexed) {
          eq.bandGain(i).value = gain;
        }
        if (!limiter.isActive) {
          limiter.activate();
          limiter.threshold.value = Equalizer.limiterThresholdDb;
          limiter.outputCeiling.value = Equalizer.limiterThresholdDb;
          limiter.releaseTime.value = Equalizer.limiterRelease.inMilliseconds
              .toDouble();
        }
        _preamp = Equalizer.preampGain(preamp);
      }
    } on Object catch (error) {
      Arcane.log(
        "Could not set the equalizer",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "AudioEngine",
      );
    }
    _applyVolume();
  }

  /// [pan] is -1 (left) .. 1 (right).
  void setPan(double pan) {
    if (_playing) _soloud.setPan(_handle!, pan);
    if (crossfading) _soloud.setPan(_outgoingHandle!, pan);
  }

  /// Starts capturing what plays for visualizations; pair each call with
  /// [stopVisualization].
  void startVisualization() {
    if (_visUsers++ == 0 && _ready) _enableVisualization();
  }

  void stopVisualization() {
    if (_visUsers == 0 || --_visUsers > 0) return;
    unawaited(_visSubscription?.cancel());
    _visSubscription = null;
    _visSamples = null;
    if (_ready) _soloud.setVisualizationEnabled(false);
  }

  /// The latest [visualizationWindow] samples of the left and right
  /// channels (-1..1) as the decoder produced them: the output with the
  /// volume and preamp taken back out, as the original's visualizations get
  /// the samples before the volume control. `null` until capturing starts.
  (Float32List, Float32List)? get visualizationSamples => _visSamples;

  /// The samples per visualization packet: enough for the 576-sample
  /// waveform of the original's visualization API.
  static const int visualizationWindow = 1024;

  void _enableVisualization() {
    try {
      _soloud.setVisualizationEnabled(
        true,
        windowSize: visualizationWindow,
        kind: VisualizationKind.wave,
        channel: VisualizationChannel.all,
      );
    } on Object catch (error) {
      Arcane.log(
        "Visualization unavailable",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "AudioEngine",
      );
      return;
    }
    _visSubscription ??= _soloud.audioVisualizationEvents.listen((data) {
      final wave = data.wave;
      if (wave.isEmpty) return;
      final gain = _volume * _preamp;
      final scale = gain > 0.01 ? 1 / gain : 0.0;
      Float32List unscaled(Float32List samples) {
        final out = Float32List(samples.length);
        for (var i = 0; i < out.length; i++) {
          out[i] = samples[i] * scale;
        }
        return out;
      }

      final left = unscaled(wave.first);
      _visSamples = (left, wave.length > 1 ? unscaled(wave[1]) : left);
    });
  }

  /// The playback position, or zero when nothing is playing.
  Duration get position {
    if (!_playing) return Duration.zero;
    final source = _source;
    // A released buffer stream's position stays 0; count what has played.
    if (source != null && _isLiveStream) {
      try {
        return _soloud.getStreamTimeConsumed(source);
      } on Object {
        return Duration.zero;
      }
    }
    return _soloud.getPosition(_handle!);
  }

  /// Whether the playing source is a live stream, also after its
  /// connection has closed.
  bool get _isLiveStream =>
      _liveSource != null && identical(_liveSource, _source);
}
