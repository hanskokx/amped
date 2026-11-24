// Decodes an audio file to interleaved 16-bit PCM at its own rate and
// channel count, with miniaudio (WAV, FLAC and MP3).

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DEVICE_IO
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_GENERATION
#include "third_party/miniaudio.h"

#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32)
#define PCM_DECODER_EXPORT __declspec(dllexport)
#else
#define PCM_DECODER_EXPORT __attribute__((visibility("default")))
#endif

// Returns 0 on success, else a miniaudio result code. On success *out holds
// up to max_seconds of audio (all of it if max_seconds <= 0; free it with
// pcm_decoder_free), and *total_frames the file's whole length (0 if
// unknown).
PCM_DECODER_EXPORT int pcm_decoder_decode(const char *path, double max_seconds,
                            int16_t **out, uint64_t *frames,
                            uint64_t *total_frames, uint32_t *channels,
                            uint32_t *sample_rate) {
  *out = NULL;
  *frames = 0;
  *total_frames = 0;
  ma_decoder_config config = ma_decoder_config_init(ma_format_s16, 0, 0);
  ma_decoder decoder;
  ma_result result = ma_decoder_init_file(path, &config, &decoder);
  if (result != MA_SUCCESS) return result;
  *channels = decoder.outputChannels;
  *sample_rate = decoder.outputSampleRate;
  uint64_t max_frames = max_seconds > 0
                            ? (uint64_t)(max_seconds * decoder.outputSampleRate)
                            : UINT64_MAX;
  ma_uint64 length = 0;
  if (ma_decoder_get_length_in_pcm_frames(&decoder, &length) == MA_SUCCESS) {
    *total_frames = length;
  }

  uint64_t capacity = length > 0 && length < max_frames ? length : 1 << 20;
  if (capacity > max_frames) capacity = max_frames;
  int16_t *buffer = malloc(capacity * *channels * sizeof(int16_t));
  uint64_t count = 0;
  while (buffer != NULL && count < max_frames) {
    if (count == capacity) {
      capacity = capacity * 2 > max_frames ? max_frames : capacity * 2;
      int16_t *grown = realloc(buffer, capacity * *channels * sizeof(int16_t));
      if (grown == NULL) {
        free(buffer);
        buffer = NULL;
        break;
      }
      buffer = grown;
    }
    ma_uint64 read = 0;
    result = ma_decoder_read_pcm_frames(
        &decoder, buffer + count * *channels, capacity - count, &read);
    count += read;
    if (result != MA_SUCCESS || read == 0) break;
  }
  ma_decoder_uninit(&decoder);
  if (buffer == NULL) return MA_OUT_OF_MEMORY;
  if (result != MA_SUCCESS && result != MA_AT_END && count == 0) {
    free(buffer);
    return result;
  }
  *out = buffer;
  *frames = count;
  return 0;
}

PCM_DECODER_EXPORT void pcm_decoder_free(int16_t *samples) { free(samples); }

// Reads only the format and length. Returns 0 on success, else a miniaudio
// result code; *total_frames is 0 if the length is unknown.
PCM_DECODER_EXPORT int pcm_decoder_probe(const char *path,
                                         uint64_t *total_frames,
                                         uint32_t *channels,
                                         uint32_t *sample_rate) {
  *total_frames = 0;
  ma_decoder_config config = ma_decoder_config_init(ma_format_s16, 0, 0);
  ma_decoder decoder;
  ma_result result = ma_decoder_init_file(path, &config, &decoder);
  if (result != MA_SUCCESS) return result;
  *channels = decoder.outputChannels;
  *sample_rate = decoder.outputSampleRate;
  ma_uint64 length = 0;
  if (ma_decoder_get_length_in_pcm_frames(&decoder, &length) == MA_SUCCESS) {
    *total_frames = length;
  }
  ma_decoder_uninit(&decoder);
  return 0;
}
