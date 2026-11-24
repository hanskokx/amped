# pcm_decoder

Decodes audio files to interleaved 16-bit PCM at the file's own sample rate,
keeping every channel. It's a thin FFI wrapper around
[miniaudio](https://miniaud.io)'s decoder (WAV, FLAC and MP3), compiled by a
native-assets build hook, so there's nothing to install.

```dart
final audio = decodeFile(path, maxDuration: const Duration(minutes: 2));
audio.samples; // Int16List, interleaved
audio.channels;
audio.sampleRate;
audio.duration; // the whole file's
```

`decodeFile` blocks, so run it in a background isolate (`Isolate.run`).
miniaudio's symbols are hidden, so it can share a process with another copy
of miniaudio (flutter_soloud has one).

Ogg Vorbis and Opus aren't supported: miniaudio needs extra libraries for
them.

## License

miniaudio (`src/third_party/miniaudio.h`, 0.11.25) is public domain or
MIT-0, at your choice. The wrapper is under the same terms.
