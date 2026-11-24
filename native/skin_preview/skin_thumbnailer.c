// amped-skin-thumbnailer: the freedesktop thumbnailer for skins
// (installed with a .thumbnailer file by lib/src/platform/file_types.dart).
//
//   amped-skin-thumbnailer [-s SIZE] [--main | --stack] INPUT OUTPUT.png
//
// INPUT is a path or a file:// URI. SIZE is the largest side in pixels
// (default 256). The picture is the main window, equalizer and a short
// playlist editor; --main draws the main window alone and --stack the
// playlist editor at its default height. A Wasabi 3 skin (.wal) is its
// screenshot, else its main window.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "skin_preview.h"

static int hex(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

// A file:// URI as a path (percent-decoded in place); anything else as is.
static char* to_path(char* arg) {
  if (strncmp(arg, "file://", 7) != 0) return arg;
  char* path = strchr(arg + 7, '/');
  if (!path) return arg;
  char* out = path;
  for (char* in = path; *in; in++) {
    if (*in == '%' && hex(in[1]) >= 0 && hex(in[2]) >= 0) {
      *out++ = (char)(hex(in[1]) << 4 | hex(in[2]));
      in += 2;
    } else {
      *out++ = *in;
    }
  }
  *out = 0;
  return path;
}

// The skin's name, upper-cased for the song title display: the file name
// without its folder and extension.
static void title_of(const char* path, char* title, size_t size) {
  const char* name = strrchr(path, '/');
  name = name ? name + 1 : path;
  const char* dot = strrchr(name, '.');
  size_t len = dot && dot != name ? (size_t)(dot - name) : strlen(name);
  if (len >= size) len = size - 1;
  for (size_t i = 0; i < len; i++) {
    char c = name[i];
    title[i] = c >= 'a' && c <= 'z' ? (char)(c - 32) : c == '_' ? ' ' : c;
  }
  title[len] = 0;
}

int main(int argc, char** argv) {
  int size = 256;
  int layout = SKIN_PREVIEW_ICON;
  const char* paths[2] = {NULL, NULL};
  int count = 0;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
      size = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--main") == 0) {
      layout = SKIN_PREVIEW_MAIN;
    } else if (strcmp(argv[i], "--stack") == 0) {
      layout = SKIN_PREVIEW_STACK;
    } else if (count < 2) {
      paths[count++] = to_path(argv[i]);
    }
  }
  if (count != 2 || size <= 0) {
    fprintf(stderr, "usage: %s [-s SIZE] [--main | --stack] INPUT OUTPUT.png\n",
            argv[0]);
    return 2;
  }

  char title[64];
  title_of(paths[0], title, sizeof(title));
  SkinPreviewImage image, fitted;
  if (skin_preview_render_file(paths[0], title, layout, &image) != 0) {
    fprintf(stderr, "%s: not a skin\n", paths[0]);
    return 1;
  }
  int failed = skin_preview_fit(&image, size, &fitted);
  skin_preview_free(&image);
  uint8_t* png = NULL;
  size_t png_size = 0;
  if (failed || skin_preview_encode_png(&fitted, &png, &png_size) != 0) {
    skin_preview_free(&fitted);
    return 1;
  }
  skin_preview_free(&fitted);
  FILE* out = fopen(paths[1], "wb");
  failed = !out || fwrite(png, 1, png_size, out) != png_size;
  if (out && fclose(out) != 0) failed = 1;
  free(png);
  if (failed) {
    fprintf(stderr, "%s: could not write\n", paths[1]);
    return 1;
  }
  return 0;
}
