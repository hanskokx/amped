// Renders a picture of a skin (.wsz, .wal) without the Flutter
// engine, for the file-manager previews and thumbnails on macOS (Quick
// Look), Windows (Explorer preview handler and thumbnail provider) and Linux
// (freedesktop thumbnailer).
//
// The layout mirrors the amped_classic_skin package and lib/src/main_window: the main
// window as the original draws it with nothing playing, optionally with the
// equalizer and playlist editor docked below it (the classic player's default layout).
// Files the skin leaves out come from the base skin built into the renderer
// (base_skin.inc), as the original's `draw_LBitmap` falls back to its own.
//
// A Bamp skin (https://github.com/dp-mason/bamp, a zip of PNG layers) is
// converted to a classic skin and drawn the same way.
//
// A Wasabi 3 / Wasabi 5 skin (.wal) is drawn from its windows' layouts at
// their own size: the main window, and for the stacked layouts the equalizer
// and playlist windows below it, each as the app places its objects before
// any script runs (frames such as <Wasabi:MainFrame:NoStatus> with the
// content they host, the menu bar's labels). Text, the time and the
// visualization need the app, so a skin whose screenshot is about the size of
// its layout shows the screenshot instead of the main window. Each window is
// trimmed to its visible pixels. `title` does not apply.

#ifndef AMPED_SKIN_PREVIEW_H_
#define AMPED_SKIN_PREVIEW_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The main window alone (275x116).
#define SKIN_PREVIEW_MAIN 0
// The main window, equalizer and playlist editor stacked, in the classic player's
// default sizes (275x464).
#define SKIN_PREVIEW_STACK 1
// The same with the playlist editor at its smallest, for icons (275x348).
#define SKIN_PREVIEW_ICON 2

// Straight (not premultiplied) RGBA, 4 bytes a pixel, rows top-down.
// Pixels outside a skin's region.txt shape are transparent.
typedef struct {
  int width;
  int height;
  uint8_t* rgba;
} SkinPreviewImage;

// Renders the skin in the zip archive `wsz` (`size` bytes). `title` is
// shown in the song title display (may be NULL). Returns 0 and fills `out`
// on success; nonzero when `wsz` is not a zip holding a skin.
int skin_preview_render(const uint8_t* wsz, size_t size, const char* title,
                        int layout, SkinPreviewImage* out);

// Renders the skin in the file at `path` (UTF-8).
int skin_preview_render_file(const char* path, const char* title, int layout,
                             SkinPreviewImage* out);

// Returns `image` scaled to fill `max_size` x `max_size`, keeping its aspect
// ratio. Enlarging repeats pixels by the next whole factor and then shrinks
// by area averaging, so the skin's pixels stay sharp. Returns 0 on success.
int skin_preview_fit(const SkinPreviewImage* image, int max_size,
                     SkinPreviewImage* out);

// Encodes `image` as a PNG. Returns 0 and sets `*png`/`*png_size` (free
// with free()) on success.
int skin_preview_encode_png(const SkinPreviewImage* image, uint8_t** png,
                            size_t* png_size);

void skin_preview_free(SkinPreviewImage* image);

#ifdef __cplusplus
}
#endif

#endif  // AMPED_SKIN_PREVIEW_H_
