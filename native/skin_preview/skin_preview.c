// See skin_preview.h. Self-contained (no zlib, no system image libraries;
// the JPEG and GIF decoders are stb_image, vendored beside it) so the same
// file builds into the Quick Look extensions, the Windows shell extension and
// the Linux thumbnailer.

#include "skin_preview.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

// JPEG and GIF (first frame) for the skins that use them; BMP and PNG have
// decoders of their own below.
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_MAX_DIMENSIONS 8192
#include "stb_image.h"

#include "bamp_map.inc"
#include "base_skin.inc"

// --- Skin files --------------------------------------------------------------

enum {
  F_MAIN,
  F_TITLEBAR,
  F_CBUTTONS,
  F_PLAYPAUS,
  F_POSBAR,
  F_VOLUME,
  F_BALANCE,
  F_MONOSTER,
  F_SHUFREP,
  F_TEXT,
  F_EQMAIN,
  F_PLEDIT,
  F_BITMAPS,  // The text files follow the bitmaps.
  F_PLEDIT_TXT = F_BITMAPS,
  F_REGION_TXT,
  F_HINTS_TXT,  // skin.hints (Audacious skins).
  F_COUNT
};

static const char* const kFileNames[F_COUNT] = {
    "main.bmp",    "titlebar.bmp", "cbuttons.bmp", "playpaus.bmp",
    "posbar.bmp",  "volume.bmp",   "balance.bmp",  "monoster.bmp",
    "shufrep.bmp", "text.bmp",     "eqmain.bmp",   "pledit.bmp",
    "pledit.txt",  "region.txt",   "skin.hints",
};

typedef struct {
  uint8_t* data;
  size_t size;
} Blob;

typedef struct {
  int width;
  int height;
  uint8_t* rgba;
} Bitmap;

static int lower(int c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }

static int name_equals(const char* a, size_t a_len, const char* b) {
  size_t i;
  for (i = 0; i < a_len; i++) {
    if (b[i] == 0 || lower((unsigned char)a[i]) != b[i]) return 0;
  }
  return b[i] == 0;
}

// --- Inflate (RFC 1951), after zlib's puff.c ---------------------------------

typedef struct {
  const uint8_t* in;
  size_t in_size;
  size_t in_pos;
  uint32_t bit_buf;
  int bit_count;
  uint8_t* out;
  size_t out_size;
  size_t out_pos;
  int error;
} Inflater;

typedef struct {
  short count[16];
  short symbol[288];
} Huffman;

static int bits(Inflater* s, int need) {
  uint32_t value = s->bit_buf;
  while (s->bit_count < need) {
    if (s->in_pos >= s->in_size) {
      s->error = 1;
      return 0;
    }
    value |= (uint32_t)s->in[s->in_pos++] << s->bit_count;
    s->bit_count += 8;
  }
  s->bit_buf = value >> need;
  s->bit_count -= need;
  return (int)(value & ((1u << need) - 1));
}

static int decode(Inflater* s, const Huffman* h) {
  int code = 0, first = 0, index = 0;
  for (int len = 1; len < 16; len++) {
    code |= bits(s, 1);
    if (s->error) return -1;
    int count = h->count[len];
    if (code - count < first) return h->symbol[index + (code - first)];
    index += count;
    first = (first + count) << 1;
    code <<= 1;
  }
  s->error = 1;
  return -1;
}

static int construct(Huffman* h, const short* length, int n) {
  short offs[16];
  memset(h->count, 0, sizeof(h->count));
  for (int symbol = 0; symbol < n; symbol++) h->count[length[symbol]]++;
  if (h->count[0] == n) return 0;
  int left = 1;
  for (int len = 1; len < 16; len++) {
    left <<= 1;
    left -= h->count[len];
    if (left < 0) return left;
  }
  offs[1] = 0;
  for (int len = 1; len < 15; len++) offs[len + 1] = offs[len] + h->count[len];
  for (int symbol = 0; symbol < n; symbol++) {
    if (length[symbol] != 0) h->symbol[offs[length[symbol]]++] = (short)symbol;
  }
  return left;
}

static int inflate_codes(Inflater* s, const Huffman* lencode,
                         const Huffman* distcode) {
  static const short kLengthBase[29] = {
      3,  4,  5,  6,  7,  8,  9,  10, 11,  13,  15,  17,  19,  23, 27,
      31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
  static const short kLengthExtra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
                                         1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                                         4, 4, 4, 4, 5, 5, 5, 5, 0};
  static const short kDistBase[30] = {
      1,    2,    3,    4,    5,    7,     9,     13,    17,  25,
      33,   49,   65,   97,   129,  193,   257,   385,   513, 769,
      1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
  static const short kDistExtra[30] = {0, 0, 0, 0, 1, 1, 2,  2,  3,  3,
                                       4, 4, 5, 5, 6, 6, 7,  7,  8,  8,
                                       9, 9, 10, 10, 11, 11, 12, 12, 13, 13};
  for (;;) {
    int symbol = decode(s, lencode);
    if (s->error) return -1;
    if (symbol < 256) {
      if (s->out_pos >= s->out_size) return -1;
      s->out[s->out_pos++] = (uint8_t)symbol;
    } else if (symbol == 256) {
      return 0;
    } else {
      symbol -= 257;
      if (symbol >= 29) return -1;
      size_t len = kLengthBase[symbol] + bits(s, kLengthExtra[symbol]);
      symbol = decode(s, distcode);
      if (s->error || symbol < 0 || symbol >= 30) return -1;
      size_t dist = kDistBase[symbol] + bits(s, kDistExtra[symbol]);
      if (s->error || dist > s->out_pos || len > s->out_size - s->out_pos) {
        return -1;
      }
      for (; len > 0; len--, s->out_pos++) {
        s->out[s->out_pos] = s->out[s->out_pos - dist];
      }
    }
  }
}

static int inflate_stored(Inflater* s) {
  s->bit_buf = 0;
  s->bit_count = 0;
  if (s->in_pos + 4 > s->in_size) return -1;
  size_t len = s->in[s->in_pos] | (s->in[s->in_pos + 1] << 8);
  size_t inverse = s->in[s->in_pos + 2] | (s->in[s->in_pos + 3] << 8);
  s->in_pos += 4;
  if (len != (~inverse & 0xffff)) return -1;
  if (len > s->in_size - s->in_pos || len > s->out_size - s->out_pos) {
    return -1;
  }
  memcpy(s->out + s->out_pos, s->in + s->in_pos, len);
  s->in_pos += len;
  s->out_pos += len;
  return 0;
}

// Built for each block rather than cached: previews render on several
// threads at once.
static int inflate_fixed(Inflater* s) {
  Huffman lencode, distcode;
  short lengths[288];
  int symbol = 0;
  for (; symbol < 144; symbol++) lengths[symbol] = 8;
  for (; symbol < 256; symbol++) lengths[symbol] = 9;
  for (; symbol < 280; symbol++) lengths[symbol] = 7;
  for (; symbol < 288; symbol++) lengths[symbol] = 8;
  construct(&lencode, lengths, 288);
  for (symbol = 0; symbol < 30; symbol++) lengths[symbol] = 5;
  construct(&distcode, lengths, 30);
  return inflate_codes(s, &lencode, &distcode);
}

static int inflate_dynamic(Inflater* s) {
  static const short kOrder[19] = {16, 17, 18, 0, 8,  7, 9,  6, 10, 5,
                                   11, 4,  12, 3, 13, 2, 14, 1, 15};
  short lengths[288 + 32];
  Huffman lencode, distcode;
  int nlen = bits(s, 5) + 257;
  int ndist = bits(s, 5) + 1;
  int ncode = bits(s, 4) + 4;
  if (s->error || nlen > 286 || ndist > 30) return -1;
  int index = 0;
  for (; index < ncode; index++) lengths[kOrder[index]] = (short)bits(s, 3);
  for (; index < 19; index++) lengths[kOrder[index]] = 0;
  if (s->error || construct(&lencode, lengths, 19) != 0) return -1;
  index = 0;
  while (index < nlen + ndist) {
    int symbol = decode(s, &lencode);
    if (s->error) return -1;
    if (symbol < 16) {
      lengths[index++] = (short)symbol;
      continue;
    }
    short len = 0;
    if (symbol == 16) {
      if (index == 0) return -1;
      len = lengths[index - 1];
      symbol = 3 + bits(s, 2);
    } else if (symbol == 17) {
      symbol = 3 + bits(s, 3);
    } else {
      symbol = 11 + bits(s, 7);
    }
    if (s->error || index + symbol > nlen + ndist) return -1;
    while (symbol--) lengths[index++] = len;
  }
  if (lengths[256] == 0) return -1;
  int err = construct(&lencode, lengths, nlen);
  if (err < 0 || (err > 0 && nlen - lencode.count[0] != 1)) return -1;
  err = construct(&distcode, lengths + nlen, ndist);
  if (err < 0 || (err > 0 && ndist - distcode.count[0] != 1)) return -1;
  return inflate_codes(s, &lencode, &distcode);
}

static int inflate_raw(const uint8_t* in, size_t in_size, uint8_t* out,
                       size_t out_size) {
  Inflater s;
  memset(&s, 0, sizeof(s));
  s.in = in;
  s.in_size = in_size;
  s.out = out;
  s.out_size = out_size;
  int last;
  do {
    last = bits(&s, 1);
    int type = bits(&s, 2);
    if (s.error) return -1;
    int result = type == 0   ? inflate_stored(&s)
                 : type == 1 ? inflate_fixed(&s)
                 : type == 2 ? inflate_dynamic(&s)
                             : -1;
    if (result != 0) return -1;
  } while (!last);
  return s.out_pos == out_size ? 0 : -1;
}

// --- Zip ---------------------------------------------------------------------

static uint32_t le16(const uint8_t* p) { return p[0] | (p[1] << 8); }
static uint32_t le32(const uint8_t* p) {
  return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
}

// Calls `visit` with each file in the archive (its path, and the offset of
// its central directory record) until it returns nonzero. Returns -1 when
// `zip` is not a zip archive.
typedef int (*ZipVisitor)(const char* name, size_t name_len, size_t central,
                          void* context);

static int zip_each(const uint8_t* zip, size_t size, ZipVisitor visit,
                    void* context) {
  if (size < 22) return -1;
  size_t eocd = size - 22;
  size_t stop = size > 22 + 0xffff ? size - 22 - 0xffff : 0;
  while (le32(zip + eocd) != 0x06054b50) {
    if (eocd == stop) return -1;
    eocd--;
  }
  uint32_t entries = le16(zip + eocd + 10);
  size_t p = le32(zip + eocd + 16);
  for (uint32_t e = 0; e < entries; e++) {
    if (p + 46 > size || le32(zip + p) != 0x02014b50) break;
    size_t name_len = le16(zip + p + 28);
    if (p + 46 + name_len > size) break;
    size_t next = p + 46 + name_len + le16(zip + p + 30) + le16(zip + p + 32);
    const char* name = (const char*)zip + p + 46;
    if (name_len == 0 || name[name_len - 1] == '/') {
      p = next;
      continue;  // A folder.
    }
    if (visit(name, name_len, p, context)) break;
    p = next;
  }
  return 0;
}

// Unpacks the file whose central directory record is at `central`.
static int zip_extract(const uint8_t* zip, size_t size, size_t central,
                       Blob* out) {
  uint32_t flags = le16(zip + central + 8);
  uint32_t method = le16(zip + central + 10);
  size_t packed = le32(zip + central + 20);
  size_t unpacked = le32(zip + central + 24);
  size_t local = le32(zip + central + 42);
  if ((flags & 1) != 0 || (method != 0 && method != 8)) return -1;
  if (unpacked > (16u << 20)) return -1;
  if (local + 30 > size || le32(zip + local) != 0x04034b50) return -1;
  size_t data = local + 30 + le16(zip + local + 26) + le16(zip + local + 28);
  if (data > size || packed > size - data) return -1;
  uint8_t* bytes = (uint8_t*)malloc(unpacked ? unpacked : 1);
  if (!bytes) return -1;
  int ok = -1;
  if (method == 8) {
    ok = inflate_raw(zip + data, packed, bytes, unpacked);
  } else if (packed == unpacked) {
    memcpy(bytes, zip + data, unpacked);
    ok = 0;
  }
  if (ok != 0) {
    free(bytes);
    return -1;
  }
  out->data = bytes;
  out->size = unpacked;
  return 0;
}

// The depth of `name` and the offset of its base name.
static int path_depth(const char* name, size_t name_len, size_t* base) {
  int depth = 0;
  *base = 0;
  for (size_t i = 0; i < name_len; i++) {
    if (name[i] == '/' || name[i] == '\\') {
      *base = i + 1;
    } else if (i == 0 || name[i - 1] == '/' || name[i - 1] == '\\') {
      depth++;
    }
  }
  return depth;
}

// Whether `name` is a macOS resource fork or a hidden file.
static int is_junk(const char* name, size_t name_len, size_t base) {
  return name[base] == '.' ||
         (name_len > 9 && name_equals(name, 9, "__macosx/"));
}

// The extensions a skin bitmap may have, in order of preference (the same
// as skinImageExtensions in skin_loader.dart).
static const char* const kImageExtensions[] = {"bmp", "png", "jpg", "jpeg",
                                               "gif"};
enum { kImageExtensionCount = 5 };

typedef struct {
  int depths[F_COUNT];
  int ranks[F_COUNT];  // Index in kImageExtensions of the file found.
  size_t centrals[F_COUNT];
  int allow_images;
} SkinFiles;

// The index in kImageExtensions of the extension `name` has once its stem is
// `file` without its `.bmp`; -1 if it is not that file.
static int image_rank_of(const char* name, size_t name_len, const char* file) {
  size_t stem = strlen(file) - 4;
  if (name_len < stem + 2 || name[stem] != '.') return -1;
  for (size_t i = 0; i < stem; i++) {
    if (lower((unsigned char)name[i]) != file[i]) return -1;
  }
  for (int rank = 0; rank < kImageExtensionCount; rank++) {
    if (name_equals(name + stem + 1, name_len - stem - 1,
                    kImageExtensions[rank])) {
      return rank;
    }
  }
  return -1;
}

static int visit_skin_file(const char* name, size_t name_len, size_t central,
                           void* context) {
  SkinFiles* found = (SkinFiles*)context;
  size_t base;
  int depth = path_depth(name, name_len, &base);
  if (is_junk(name, name_len, base)) return 0;
  for (int i = 0; i < F_COUNT; i++) {
    int rank = 0;
    if (i < F_BITMAPS && found->allow_images) {
      rank = image_rank_of(name + base, name_len - base, kFileNames[i]);
    } else if (!name_equals(name + base, name_len - base, kFileNames[i])) {
      rank = -1;
    }
    if (rank < 0) continue;
    // A BMP wins over another format, then the shallowest file.
    if (rank < found->ranks[i] ||
        (rank == found->ranks[i] && depth < found->depths[i])) {
      found->ranks[i] = rank;
      found->depths[i] = depth;
      found->centrals[i] = central;
    }
  }
  return 0;
}

// Reads the skin files out of the archive. With `allow_images`, a bitmap with
// no BMP is its PNG, JPEG or GIF (`main.png` for `main.bmp`). Files are matched by name
// wherever they are, case-insensitively; the shallowest copy wins, and macOS
// resource forks and hidden files are skipped (skinArchiveFiles in
// skin_loader.dart). Returns the number of files found, or -1 when `zip` is
// not a zip archive.
static int read_zip(const uint8_t* zip, size_t size, Blob files[F_COUNT],
                    int allow_images) {
  SkinFiles found;
  memset(&found, 0, sizeof(found));
  found.allow_images = allow_images;
  for (int i = 0; i < F_COUNT; i++) {
    found.depths[i] = 1 << 30;
    found.ranks[i] = 1 << 30;
  }
  if (zip_each(zip, size, visit_skin_file, &found) != 0) return -1;
  int count = 0;
  for (int i = 0; i < F_COUNT; i++) {
    if (found.depths[i] == 1 << 30) continue;
    if (zip_extract(zip, size, found.centrals[i], &files[i]) == 0) count++;
  }
  return count;
}

// --- Files -------------------------------------------------------------------

static FILE* open_utf8(const char* path) {
#ifdef _WIN32
  wchar_t wide[MAX_PATH * 2];
  if (!MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, MAX_PATH * 2)) {
    return NULL;
  }
  return _wfopen(wide, L"rb");
#else
  return fopen(path, "rb");
#endif
}

static int read_file(const char* path, Blob* blob) {
  FILE* file = open_utf8(path);
  if (!file) return -1;
  int result = -1;
  if (fseek(file, 0, SEEK_END) == 0) {
    long size = ftell(file);
    if (size >= 0 && size < (64l << 20) && fseek(file, 0, SEEK_SET) == 0) {
      blob->data = (uint8_t*)malloc(size ? (size_t)size : 1);
      if (blob->data && fread(blob->data, 1, (size_t)size, file) == (size_t)size) {
        blob->size = (size_t)size;
        result = 0;
      } else {
        free(blob->data);
        blob->data = NULL;
      }
    }
  }
  fclose(file);
  return result;
}

// --- BMP (bmp_decoder.dart) --------------------------------------------------

static int mask_shift(uint32_t mask) {
  int shift = 0;
  while (mask != 0 && (mask & 1) == 0) {
    shift++;
    mask >>= 1;
  }
  return shift;
}

static int mask_channel(uint32_t value, uint32_t mask) {
  if (mask == 0) return 0;
  int shift = mask_shift(mask);
  uint32_t max = mask >> shift;
  return (int)(((value & mask) >> shift) * 255 / max);
}

// Decodes 1/4/8/16/24/32-bit BMPs, palette and RLE4/RLE8 included. Palette
// bitmaps are opaque (GDI ignores the fourth palette byte).
static int decode_bmp(const Blob* blob, Bitmap* out) {
  const uint8_t* d = blob->data;
  size_t size = blob->size;
  if (size < 26 || d[0] != 'B' || d[1] != 'M') return -1;
  size_t offset = le32(d + 10);
  uint32_t dib = le32(d + 14);
  int width, height, bpp;
  uint32_t compression = 0, colors_used = 0;
  uint32_t rmask = 0, gmask = 0, bmask = 0;
  size_t palette_entry = 4;
  if (dib >= 40 && size >= 54) {
    width = (int32_t)le32(d + 18);
    height = (int32_t)le32(d + 22);
    bpp = le16(d + 28);
    compression = le32(d + 30);
    colors_used = le32(d + 46);
    // BI_BITFIELDS masks: in the header from V2 on, else right after it.
    if (compression == 3 && size >= 66) {
      rmask = le32(d + 54);
      gmask = le32(d + 58);
      bmask = le32(d + 62);
    }
  } else if (dib == 12) {
    width = le16(d + 18);
    height = le16(d + 20);
    bpp = le16(d + 24);
    palette_entry = 3;
  } else {
    return -1;
  }
  int bottom_up = height > 0;
  if (height < 0) height = -height;
  if (width <= 0 || width > 4096 || height <= 0 || height > 4096) return -1;
  if (offset >= size) return -1;

  uint8_t palette[256][4];
  memset(palette, 0, sizeof(palette));
  if (bpp <= 8) {
    size_t max = (size_t)1 << bpp;
    size_t count = colors_used ? colors_used : max;
    size_t start = 14 + dib;
    if (offset > start && count > (offset - start) / palette_entry) {
      count = (offset - start) / palette_entry;
    }
    if (count > max) count = max;
    for (size_t i = 0; i < count; i++) {
      const uint8_t* e = d + start + i * palette_entry;
      if (e + 3 > d + size) break;
      palette[i][0] = e[2];
      palette[i][1] = e[1];
      palette[i][2] = e[0];
    }
  }
  for (int i = 0; i < 256; i++) palette[i][3] = 255;

  uint8_t* rgba = (uint8_t*)calloc((size_t)width * height, 4);
  if (!rgba) return -1;
  size_t stride = (((size_t)width * bpp + 31) >> 5) << 2;

  if (bpp <= 8 && (compression == 1 || compression == 2)) {
    // RLE8 / RLE4 into an index buffer, in stored row order.
    uint8_t* idx = (uint8_t*)calloc((size_t)width * height, 1);
    if (!idx) {
      free(rgba);
      return -1;
    }
    int rle8 = bpp == 8;
    int x = 0, y = 0;
    size_t i = offset;
    while (i < size && y < height) {
      int first = d[i++];
      if (i >= size) break;
      int second = d[i++];
      if (first == 0) {
        if (second == 0) {
          x = 0;
          y++;
        } else if (second == 1) {
          break;
        } else if (second == 2) {
          if (i + 1 >= size) break;
          x += d[i];
          y += d[i + 1];
          i += 2;
        } else if (rle8) {
          for (int n = 0; n < second && i < size; n++, i++) {
            if (x < width && y < height) idx[(size_t)y * width + x] = d[i];
            x++;
          }
          if (second & 1) i++;
        } else {
          for (int n = 0; n < second && i < size; n++) {
            int v = (n & 1) ? d[i++] & 15 : d[i] >> 4;
            if (x < width && y < height) idx[(size_t)y * width + x] = (uint8_t)v;
            x++;
          }
          if (second & 1) i++;
          if (((second + 1) >> 1) & 1) i++;
        }
      } else {
        for (int n = 0; n < first; n++) {
          int v = rle8 ? second : (n & 1) ? second & 15 : second >> 4;
          if (x < width && y < height) idx[(size_t)y * width + x] = (uint8_t)v;
          x++;
        }
      }
    }
    for (int row = 0; row < height; row++) {
      const uint8_t* src = idx + (size_t)(bottom_up ? height - 1 - row : row) * width;
      for (int col = 0; col < width; col++) {
        memcpy(rgba + ((size_t)row * width + col) * 4, palette[src[col]], 4);
      }
    }
    free(idx);
  } else if (bpp == 1 || bpp == 4 || bpp == 8 || bpp == 16 || bpp == 24 ||
             bpp == 32) {
    if (bpp == 16 && compression != 3) {
      rmask = 0x7c00;
      gmask = 0x03e0;
      bmask = 0x001f;
    } else if (bpp == 32 && (compression != 3 || rmask == 0)) {
      rmask = 0xff0000;
      gmask = 0xff00;
      bmask = 0xff;
    }
    for (int row = 0; row < height; row++) {
      size_t src = offset + (size_t)(bottom_up ? height - 1 - row : row) * stride;
      uint8_t* dst = rgba + (size_t)row * width * 4;
      for (int col = 0; col < width; col++, dst += 4) {
        size_t bit = (size_t)col * bpp;
        size_t at = src + bit / 8;
        if (at + (bpp + 7) / 8 > size) break;
        if (bpp <= 8) {
          int shift = 8 - bpp - (int)(bit % 8);
          int index = (d[at] >> shift) & ((1 << bpp) - 1);
          memcpy(dst, palette[index], 4);
        } else if (bpp == 24) {
          dst[0] = d[at + 2];
          dst[1] = d[at + 1];
          dst[2] = d[at];
          dst[3] = 255;
        } else {
          uint32_t v = bpp == 16 ? le16(d + at) : le32(d + at);
          dst[0] = (uint8_t)mask_channel(v, rmask);
          dst[1] = (uint8_t)mask_channel(v, gmask);
          dst[2] = (uint8_t)mask_channel(v, bmask);
          dst[3] = 255;
        }
      }
    }
  } else {
    free(rgba);
    return -1;
  }
  out->width = width;
  out->height = height;
  out->rgba = rgba;
  return 0;
}

// --- PNG (for Wasabi 3 skins) ------------------------------------------------

static uint32_t be32(const uint8_t* p) {
  return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

static int paeth(int a, int b, int c) {
  int p = a + b - c;
  int pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

// Decodes a non-interlaced PNG of any color type and bit depth (16-bit
// samples keep their high byte), with tRNS transparency.
static int decode_png(const Blob* blob, Bitmap* out) {
  static const uint8_t kSignature[8] = {137, 'P', 'N', 'G', 13, 10, 26, 10};
  const uint8_t* d = blob->data;
  size_t size = blob->size;
  if (size < 33 || memcmp(d, kSignature, 8) != 0) return -1;
  int width = 0, height = 0, depth = 0, type = 0, interlace = 0;
  uint8_t palette[256][4];
  memset(palette, 0, sizeof(palette));
  for (int i = 0; i < 256; i++) palette[i][3] = 255;
  int key = 0;  // tRNS gives a transparent gray or RGB.
  uint16_t key_rgb[3] = {0, 0, 0};
  uint8_t* idat = NULL;
  size_t idat_size = 0;
  int result = -1;
  size_t at = 8;
  while (at + 12 <= size) {
    size_t length = be32(d + at);
    const uint8_t* type_tag = d + at + 4;
    const uint8_t* body = d + at + 8;
    if (length > size - at - 12) break;
    if (memcmp(type_tag, "IHDR", 4) == 0 && length >= 13) {
      width = (int)be32(body);
      height = (int)be32(body + 4);
      depth = body[8];
      type = body[9];
      interlace = body[12];
    } else if (memcmp(type_tag, "PLTE", 4) == 0) {
      for (size_t i = 0; i < length / 3 && i < 256; i++) {
        palette[i][0] = body[i * 3];
        palette[i][1] = body[i * 3 + 1];
        palette[i][2] = body[i * 3 + 2];
      }
    } else if (memcmp(type_tag, "tRNS", 4) == 0) {
      if (type == 3) {
        for (size_t i = 0; i < length && i < 256; i++) palette[i][3] = body[i];
      } else if (type == 0 && length >= 2) {
        key = 1;
        key_rgb[0] = key_rgb[1] = key_rgb[2] = (uint16_t)(body[0] << 8 | body[1]);
      } else if (type == 2 && length >= 6) {
        key = 1;
        for (int c = 0; c < 3; c++) {
          key_rgb[c] = (uint16_t)(body[c * 2] << 8 | body[c * 2 + 1]);
        }
      }
    } else if (memcmp(type_tag, "IDAT", 4) == 0) {
      uint8_t* grown = (uint8_t*)realloc(idat, idat_size + length + 1);
      if (!grown) goto done;
      idat = grown;
      memcpy(idat + idat_size, body, length);
      idat_size += length;
    } else if (memcmp(type_tag, "IEND", 4) == 0) {
      break;
    }
    at += length + 12;
  }
  int channels = type == 0 ? 1 : type == 2 ? 3 : type == 3 ? 1 : type == 4 ? 2
                 : type == 6 ? 4 : 0;
  if (channels == 0 || interlace > 1 || idat_size < 2) goto done;
  if (depth != 1 && depth != 2 && depth != 4 && depth != 8 && depth != 16) {
    goto done;
  }
  if (width <= 0 || width > 4096 || height <= 0 || height > 4096) goto done;
  if ((idat[0] & 0x0f) != 8 || (idat[1] & 0x20) != 0) goto done;

  size_t bits_per_pixel = (size_t)channels * depth;
  size_t step = bits_per_pixel >= 8 ? bits_per_pixel / 8 : 1;
  // An interlaced image is seven smaller images (Adam7), each filtered on
  // its own; a plain one is a single pass over everything.
  static const int kPasses[7][4] = {{0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8},
                                    {2, 0, 4, 4}, {0, 2, 2, 4}, {1, 0, 2, 2},
                                    {0, 1, 1, 2}};
  int pass_count = interlace ? 7 : 1;
  int pass_w[7], pass_h[7];
  size_t pass_stride[7], pass_at[7];
  size_t raw_size = 0;
  for (int i = 0; i < pass_count; i++) {
    int x0 = interlace ? kPasses[i][0] : 0, y0 = interlace ? kPasses[i][1] : 0;
    int dx = interlace ? kPasses[i][2] : 1, dy = interlace ? kPasses[i][3] : 1;
    pass_w[i] = (width - x0 + dx - 1) / dx;
    pass_h[i] = (height - y0 + dy - 1) / dy;
    if (pass_w[i] < 0) pass_w[i] = 0;
    if (pass_h[i] < 0) pass_h[i] = 0;
    // An empty pass has no rows and no filter bytes.
    pass_stride[i] = pass_w[i] > 0 ? ((size_t)pass_w[i] * bits_per_pixel + 7) / 8 : 0;
    pass_at[i] = raw_size;
    raw_size += pass_w[i] > 0 ? (pass_stride[i] + 1) * pass_h[i] : 0;
  }
  uint8_t* raw = (uint8_t*)malloc(raw_size);
  if (!raw) goto done;
  if (inflate_raw(idat + 2, idat_size - 2, raw, raw_size) != 0) {
    free(raw);
    goto done;
  }
  uint8_t* rgba = (uint8_t*)calloc((size_t)width * height, 4);
  if (!rgba) {
    free(raw);
    goto done;
  }
  for (int pass = 0; pass < pass_count; pass++) {
    if (pass_w[pass] == 0 || pass_h[pass] == 0) continue;
    size_t stride = pass_stride[pass];
    uint8_t* base = raw + pass_at[pass];
    // Undo the row filters in place.
    for (int y = 0; y < pass_h[pass]; y++) {
      uint8_t* row = base + y * (stride + 1);
      const uint8_t* up = y > 0 ? row - (stride + 1) + 1 : NULL;
      int filter = row[0];
      row++;
      for (size_t x = 0; x < stride; x++) {
        int a = x >= step ? row[x - step] : 0;
        int b = up ? up[x] : 0;
        int c = up && x >= step ? up[x - step] : 0;
        int v = filter == 1 ? a : filter == 2 ? b : filter == 3 ? (a + b) / 2
                : filter == 4 ? paeth(a, b, c) : 0;
        row[x] = (uint8_t)(row[x] + v);
      }
    }
    for (int y = 0; y < pass_h[pass]; y++) {
      const uint8_t* row = base + y * (stride + 1) + 1;
      int out_y = interlace ? kPasses[pass][1] + y * kPasses[pass][3] : y;
      for (int x = 0; x < pass_w[pass]; x++) {
        int out_x = interlace ? kPasses[pass][0] + x * kPasses[pass][2] : x;
        // Each sample's high byte, and the full value for the tRNS key.
        int samples[4];
        uint16_t wide[4];
        for (int c = 0; c < channels; c++) {
          size_t bit = ((size_t)x * channels + c) * depth;
          if (depth == 16) {
            wide[c] = (uint16_t)(row[bit / 8] << 8 | row[bit / 8 + 1]);
            samples[c] = row[bit / 8];
          } else if (depth == 8) {
            wide[c] = samples[c] = row[bit / 8];
          } else {
            int shift = 8 - depth - (int)(bit % 8);
            int v = (row[bit / 8] >> shift) & ((1 << depth) - 1);
            wide[c] = (uint16_t)v;
            // Gray scales up to 8 bits; palette indexes stay as they are.
            samples[c] = type == 3 ? v : v * 255 / ((1 << depth) - 1);
          }
        }
        uint8_t* px = rgba + ((size_t)out_y * width + out_x) * 4;
        if (type == 3) {
          memcpy(px, palette[samples[0]], 4);
          continue;
        }
        int gray = type == 0 || type == 4;
        px[0] = (uint8_t)samples[0];
        px[1] = (uint8_t)samples[gray ? 0 : 1];
        px[2] = (uint8_t)samples[gray ? 0 : 2];
        px[3] = type == 4 ? (uint8_t)samples[1] : type == 6 ? (uint8_t)samples[3] : 255;
        if (key && wide[0] == key_rgb[0] && (gray || (wide[1] == key_rgb[1] &&
                                                      wide[2] == key_rgb[2]))) {
          px[3] = 0;
        }
      }
    }
  }
  free(raw);
  out->width = width;
  out->height = height;
  out->rgba = rgba;
  result = 0;

done:
  free(idat);
  return result;
}

// --- Drawing -----------------------------------------------------------------

typedef struct {
  Bitmap bitmaps[F_BITMAPS];
  uint8_t list_bg[3];  // pledit.txt NormalBG.
  SkinPreviewImage canvas;
  int top;  // The window being drawn starts at this canvas row.
} Painter;

// Copies a w x h crop of bitmap `which` at (sx, sy) to (dx, dy) in the
// window, clipped to both, like the original's BitBlt calls.
static void blit(Painter* p, int which, int sx, int sy, int w, int h, int dx,
                 int dy) {
  const Bitmap* b = &p->bitmaps[which];
  if (!b->rgba) return;
  dy += p->top;
  if (sx < 0) { w += sx; dx -= sx; sx = 0; }
  if (sy < 0) { h += sy; dy -= sy; sy = 0; }
  if (dx < 0) { w += dx; sx -= dx; dx = 0; }
  if (dy < 0) { h += dy; sy -= dy; dy = 0; }
  if (sx + w > b->width) w = b->width - sx;
  if (sy + h > b->height) h = b->height - sy;
  if (dx + w > p->canvas.width) w = p->canvas.width - dx;
  if (dy + h > p->canvas.height) h = p->canvas.height - dy;
  if (w <= 0 || h <= 0) return;
  for (int row = 0; row < h; row++) {
    memcpy(p->canvas.rgba + ((size_t)(dy + row) * p->canvas.width + dx) * 4,
           b->rgba + ((size_t)(sy + row) * b->width + sx) * 4, (size_t)w * 4);
  }
}

static void fill(Painter* p, int x, int y, int w, int h, const uint8_t rgb[3]) {
  y += p->top;
  for (int row = y; row < y + h && row < p->canvas.height; row++) {
    for (int col = x; col < x + w && col < p->canvas.width; col++) {
      uint8_t* px = p->canvas.rgba + ((size_t)row * p->canvas.width + col) * 4;
      px[0] = rgb[0];
      px[1] = rgb[1];
      px[2] = rgb[2];
      px[3] = 255;
    }
  }
}

// The 5x6 text.bmp glyph for `c` (TextFont._rectFor / `getXYfromChar`).
static void glyph(int c, int* x, int* y) {
  static const char kRow1[] = "0123456789\1.:()-'!_+\\/[]~&%,=$#";
  *y = 0;
  if (c >= 'a' && c <= 'z') c -= 32;
  if (c >= 'A' && c <= 'Z') {
    *x = (c - 'A') * 5;
    return;
  }
  const char* hit = c ? strchr(kRow1, c) : NULL;
  if (c == '`') hit = strchr(kRow1, '\'');
  if (c == '{' || c == '<') hit = strchr(kRow1, '[');
  if (c == '}' || c == '>') hit = strchr(kRow1, ']');
  if (c == '^') hit = strchr(kRow1, '~');
  if (hit) {
    *x = (int)(hit - kRow1) * 5;
    *y = 6;
  } else if (c == '?' || c == '*') {
    *x = c == '?' ? 15 : 20;
    *y = 12;
  } else {
    *x = c == '"' ? 130 : c == '@' ? 135 : 150;
  }
}

static void draw_text(Painter* p, const char* text, int x, int y, int width) {
  for (int i = 0; text && text[i] && (i + 1) * 5 <= width; i++) {
    int gx, gy;
    glyph((unsigned char)text[i], &gx, &gy);
    blit(p, F_TEXT, gx, gy, 5, 6, x + i * 5, y);
  }
}

// The main window stopped, with an empty playlist (main_window.dart).
static void draw_main(Painter* p, const char* title, int docked) {
  blit(p, F_MAIN, 0, 0, 275, 116, 0, 0);
  blit(p, F_TITLEBAR, 27, 0, 275, 14, 0, 0);
  // Menu, minimize, windowshade and close.
  blit(p, F_TITLEBAR, 0, 0, 9, 9, 6, 3);
  blit(p, F_TITLEBAR, 9, 0, 9, 9, 244, 3);
  blit(p, F_TITLEBAR, 0, 18, 9, 9, 254, 3);
  blit(p, F_TITLEBAR, 18, 0, 9, 9, 264, 3);
  // The clutterbar, nothing selected.
  blit(p, F_TITLEBAR, 304, 0, 8, 43, 10, 22);
  // Stopped.
  blit(p, F_PLAYPAUS, 18, 0, 9, 9, 26, 28);
  blit(p, F_PLAYPAUS, 27, 0, 3, 9, 24, 28);
  draw_text(p, title, 111, 27, 154);
  blit(p, F_MONOSTER, 29, 12, 27, 12, 212, 41);
  blit(p, F_MONOSTER, 0, 12, 29, 12, 239, 41);
  // Volume at the default 200, balance centered, no position thumb.
  int volume = 200;
  blit(p, F_VOLUME, 0, volume * 27 / 255 * 15, 68, 13, 107, 57);
  blit(p, F_VOLUME, 15, 422, 14, 11, 107 + volume * 51 / 255, 58);
  blit(p, F_BALANCE, 9, 0, 38, 13, 177, 57);
  blit(p, F_BALANCE, 15, 422, 14, 11, 177 + 12, 58);
  blit(p, F_POSBAR, 0, 0, 248, 10, 16, 72);
  for (int i = 0; i < 5; i++) {
    blit(p, F_CBUTTONS, i * 23, 0, i == 4 ? 22 : 23, 18, 16 + i * 23, 88);
  }
  blit(p, F_CBUTTONS, 114, 0, 22, 16, 136, 89);
  blit(p, F_SHUFREP, 28, 0, 47, 15, 164, 89);
  blit(p, F_SHUFREP, 0, 0, 28, 15, 210, 89);
  // The EQ and PL toggles are lit while those windows are open.
  blit(p, F_SHUFREP, 0, docked ? 73 : 61, 23, 12, 219, 58);
  blit(p, F_SHUFREP, 23, docked ? 73 : 61, 23, 12, 242, 58);
}

// The equalizer, off, with flat bands (eq_window.dart, `draw_eq`).
static void draw_eq(Painter* p) {
  blit(p, F_EQMAIN, 0, 0, 275, 116, 0, 0);
  blit(p, F_EQMAIN, 0, 134, 275, 14, 0, 0);
  blit(p, F_EQMAIN, 10, 119, 25, 12, 14, 18);
  blit(p, F_EQMAIN, 35, 119, 33, 12, 39, 18);
  blit(p, F_EQMAIN, 224, 164, 44, 12, 217, 18);
  blit(p, F_EQMAIN, 0, 116, 9, 9, 264, 3);
  // The graph (`draw_eq_graphthingy`): the preamp line and the flat curve.
  const int neutral = 31;
  const int level = neutral * 19 / 64;
  blit(p, F_EQMAIN, 0, 294, 113, 19, 86, 17);
  blit(p, F_EQMAIN, 0, 314, 113, 1, 86, 17 - 1 + 19 - level);
  for (int x = 0; x < 109; x++) blit(p, F_EQMAIN, 115, 294 + level, 1, 1, 88 + x, 17 + level);
  // The preamp and ten band sliders (`draw_eq_slid`).
  int n = 27 - neutral * 28 / 64;
  int thumb = 63 - 12 - ((63 - neutral) * (63 - 11)) / 64;
  for (int which = 0; which <= 10; which++) {
    int left = which == 0 ? 21 : 78 + (which - 1) * 18;
    if (n < 14) {
      blit(p, F_EQMAIN, 13 + n * 15, 164, 14, 63, left, 38);
    } else {
      blit(p, F_EQMAIN, 13 + (n - 14) * 15, 229, 14, 63, left, 38);
    }
    blit(p, F_EQMAIN, 0, 164, 11, 11, left + 1, 38 + thumb);
  }
}

// The playlist editor, empty, `width` x `height` (playlist_window.dart).
static void draw_playlist(Painter* p, int width, int height) {
  static const uint8_t kBlack[3] = {0, 0, 0};
  fill(p, 0, 0, width, height, kBlack);
  // The titlebar (`draw_pe_tbar`).
  int x = 0;
  blit(p, F_PLEDIT, 0, 0, 25, 20, x, 0);
  x += 25;
  for (int side = 0; side < 2; side++) {
    int tiles = (width - 150) / 25;
    if (tiles & 1) {
      blit(p, F_PLEDIT, 127, 0, 12 + side, 20, x, 0);
      x += 12 + side;
    }
    for (tiles /= 2; tiles > 0; tiles--, x += 25) {
      blit(p, F_PLEDIT, 127, 0, 25, 20, x, 0);
    }
    if (side == 0) {
      blit(p, F_PLEDIT, 26, 0, 100, 20, x, 0);
      x += 100;
    }
  }
  int rest = (width - 150) % 25;
  blit(p, F_PLEDIT, 127, 0, rest, 20, x, 0);
  blit(p, F_PLEDIT, 153, 0, 25, 20, x + rest, 0);
  // The sides.
  int body = height - 20 - 38;
  for (int y = 0; y < body; y += 29) {
    int h = body - y < 29 ? body - y : 29;
    blit(p, F_PLEDIT, 0, 42, 12, h, 0, 20 + y);
    blit(p, F_PLEDIT, 31, 42, 5, h, width - 20, 20 + y);
    blit(p, F_PLEDIT, 44, 42, 7, h, width - 7, 20 + y);
  }
  fill(p, 12, 20, width - 20 - 12, body, p->list_bg);
  // The scrollbar, thumb at the top (`draw_pe_vslide`).
  int sx = width - 15;
  blit(p, F_PLEDIT, 52, 53, 8, 18, sx, 20);
  blit(p, F_PLEDIT, 36, 42 + 18, 8, 11, sx, 20 + 18);
  for (int y = 29; y < body; y += 29) {
    blit(p, F_PLEDIT, 36, 42, 8, body - y < 29 ? body - y : 29, sx, 20 + y);
  }
  // The bottom bar.
  int bottom = height - 38;
  blit(p, F_PLEDIT, 0, 72, 125, 38, 0, bottom);
  x = 125;
  int stretch = width - 125 - 150;
  int tiles = stretch / 25;
  int wide = tiles >= 3;
  if (wide) tiles -= 3;
  for (; tiles > 0; tiles--, x += 25) blit(p, F_PLEDIT, 179, 0, 25, 38, x, bottom);
  blit(p, F_PLEDIT, 179, 0, stretch % 25, 38, x, bottom);
  x += stretch % 25;
  if (wide) {
    blit(p, F_PLEDIT, 205, 0, 75, 38, x, bottom);
    x += 75;
  }
  blit(p, F_PLEDIT, 126, 72, 150, 38, x, bottom);
}

// --- region.txt --------------------------------------------------------------

typedef struct {
  int count;
  int* points;  // x, y pairs.
  int polygons;
  int* sizes;
} Region;

static int parse_ints(const char* s, const char* end, int* out, int max) {
  int n = 0;
  while (s < end) {
    if ((*s >= '0' && *s <= '9') || (*s == '-' && s + 1 < end && s[1] >= '0' && s[1] <= '9')) {
      int sign = *s == '-' ? -1 : 1;
      if (*s == '-') s++;
      int v = 0;
      while (s < end && *s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
      if (out && n < max) out[n] = sign * v;
      n++;
    } else {
      s++;
    }
  }
  return n;
}

// Reads the polygons of `section` ("normal", "equalizer": lower case, as
// name_equals compares) from region.txt.
static int parse_region(const Blob* text, const char* section, Region* out) {
  memset(out, 0, sizeof(*out));
  if (!text->data) return -1;
  const char* s = (const char*)text->data;
  const char* end = s + text->size;
  const char *num = NULL, *num_end = NULL, *list = NULL, *list_end = NULL;
  int in_section = 0;
  while (s < end) {
    const char* line = s;
    while (s < end && *s != '\n' && *s != '\r') s++;
    const char* line_end = s;
    while (s < end && (*s == '\n' || *s == '\r')) s++;
    while (line < line_end && (*line == ' ' || *line == '\t')) line++;
    if (line < line_end && *line == '[') {
      const char* close = memchr(line, ']', (size_t)(line_end - line));
      in_section = close && name_equals(line + 1, (size_t)(close - line - 1), section);
      continue;
    }
    if (!in_section) continue;
    const char* eq = memchr(line, '=', (size_t)(line_end - line));
    if (!eq) continue;
    const char* key_end = eq;
    while (key_end > line && (key_end[-1] == ' ' || key_end[-1] == '\t')) key_end--;
    if (name_equals(line, (size_t)(key_end - line), "numpoints")) {
      num = eq + 1;
      num_end = line_end;
    } else if (name_equals(line, (size_t)(key_end - line), "pointlist")) {
      list = eq + 1;
      list_end = line_end;
    }
  }
  if (!num || !list) return -1;
  int polygons = parse_ints(num, num_end, NULL, 0);
  int count = parse_ints(list, list_end, NULL, 0);
  if (polygons <= 0 || count < 6) return -1;
  out->sizes = (int*)malloc(sizeof(int) * polygons);
  out->points = (int*)malloc(sizeof(int) * count);
  if (!out->sizes || !out->points) {
    free(out->sizes);
    free(out->points);
    return -1;
  }
  parse_ints(num, num_end, out->sizes, polygons);
  parse_ints(list, list_end, out->points, count);
  out->polygons = polygons;
  out->count = count / 2;
  return 0;
}

// Clears the alpha of the window's pixels outside its region. Each polygon
// is filled with the winding rule and the polygons are combined, as the
// original builds the region with CreatePolyPolygonRgn(WINDING).
static void apply_region(Painter* p, const Region* region, int width,
                         int height) {
  int top = p->top;
  for (int y = 0; y < height && top + y < p->canvas.height; y++) {
    double py = y + 0.5;
    for (int x = 0; x < width && x < p->canvas.width; x++) {
      double px = x + 0.5;
      int inside = 0;
      int start = 0;
      for (int poly = 0; poly < region->polygons && !inside; poly++) {
        int n = region->sizes[poly];
        if (n <= 0 || start + n > region->count) break;
        int winding = 0;
        for (int i = 0; i < n; i++) {
          const int* a = region->points + (start + i) * 2;
          const int* b = region->points + (start + (i + 1) % n) * 2;
          if (a[1] <= py) {
            if (b[1] > py && (b[0] - a[0]) * (py - a[1]) - (px - a[0]) * (b[1] - a[1]) > 0) winding++;
          } else if (b[1] <= py && (b[0] - a[0]) * (py - a[1]) - (px - a[0]) * (b[1] - a[1]) < 0) {
            winding--;
          }
        }
        inside = winding != 0;
        start += n;
      }
      if (!inside) p->canvas.rgba[((size_t)(top + y) * p->canvas.width + x) * 4 + 3] = 0;
    }
  }
}

// The value of `key=` in a skin.hints file (keys are case-insensitive), or 0.
static int hint_value(const Blob* hints, const char* key) {
  size_t key_len = strlen(key);
  if (!hints->data) return 0;
  for (size_t i = 0; i + key_len < hints->size; i++) {
    if (i > 0 && hints->data[i - 1] != '\n' && hints->data[i - 1] != '\r') {
      continue;
    }
    size_t k = 0;
    while (k < key_len && lower(hints->data[i + k]) == lower((unsigned char)key[k])) k++;
    if (k < key_len) continue;
    size_t at = i + key_len;
    while (at < hints->size && (hints->data[at] == ' ' || hints->data[at] == '\t')) at++;
    if (at >= hints->size || hints->data[at] != '=') continue;
    at++;
    int value = 0;
    while (at < hints->size && (hints->data[at] == ' ' || hints->data[at] == '\t')) at++;
    while (at < hints->size && hints->data[at] >= '0' && hints->data[at] <= '9') {
      value = value * 10 + (hints->data[at] - '0');
      if (value > 16384) return 0;
      at++;
    }
    return value;
  }
  return 0;
}

static void free_region(Region* region) {
  free(region->sizes);
  free(region->points);
}

// --- pledit.txt --------------------------------------------------------------

static void parse_list_bg(const Blob* text, uint8_t rgb[3]) {
  if (!text->data) return;
  const char* s = (const char*)text->data;
  const char* end = s + text->size;
  while (s < end) {
    const char* line = s;
    while (s < end && *s != '\n' && *s != '\r') s++;
    const char* line_end = s;
    while (s < end && (*s == '\n' || *s == '\r')) s++;
    while (line < line_end && (*line == ' ' || *line == '\t')) line++;
    const char* eq = memchr(line, '=', (size_t)(line_end - line));
    if (!eq) continue;
    const char* key_end = eq;
    while (key_end > line && (key_end[-1] == ' ' || key_end[-1] == '\t')) key_end--;
    if (!name_equals(line, (size_t)(key_end - line), "normalbg")) continue;
    const char* v = eq + 1;
    while (v < line_end && (*v == ' ' || *v == '\t' || *v == '#')) v++;
    uint32_t color = 0;
    int digits = 0;
    for (; v < line_end && digits < 6; v++, digits++) {
      int c = lower((unsigned char)*v);
      int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
      if (d < 0) break;
      color = color << 4 | (uint32_t)d;
    }
    if (digits == 0) return;
    rgb[0] = (uint8_t)(color >> 16);
    rgb[1] = (uint8_t)(color >> 8);
    rgb[2] = (uint8_t)color;
    return;
  }
}

// --- Wasabi 3 skins ---------------------------------------------------------

typedef struct {
  int depth;
  size_t central;
  size_t base;  // The length of the folder skin.xml is in, slash included.
  char folder[512];
} SkinXml;

static int visit_skin_xml(const char* name, size_t name_len, size_t central,
                          void* context) {
  SkinXml* found = (SkinXml*)context;
  size_t base;
  int depth = path_depth(name, name_len, &base);
  if (is_junk(name, name_len, base) || base >= sizeof(found->folder)) return 0;
  if (!name_equals(name + base, name_len - base, "skin.xml")) return 0;
  if (depth < found->depth) {
    found->depth = depth;
    found->central = central;
    found->base = base;
    memcpy(found->folder, name, base);
  }
  return 0;
}

typedef struct {
  const char* path;  // Lower case, with forward slashes.
  size_t central;
  int found;
} ZipPath;

static int visit_path(const char* name, size_t name_len, size_t central,
                      void* context) {
  ZipPath* want = (ZipPath*)context;
  size_t i = 0;
  for (; i < name_len && want->path[i]; i++) {
    int c = name[i] == '\\' ? '/' : lower((unsigned char)name[i]);
    if (c != want->path[i]) return 0;
  }
  if (i != name_len || want->path[i]) return 0;
  want->central = central;
  want->found = 1;
  return 1;
}

// Unpacks `folder` + `file` (the file relative to the skin's folder),
// matching case-insensitively as Windows does.
static int read_skin_path(const uint8_t* zip, size_t size, const SkinXml* xml,
                          const char* file, size_t file_len, Blob* out) {
  char path[1024];
  size_t n = 0;
  for (size_t i = 0; i < xml->base && n + 1 < sizeof(path); i++) {
    path[n++] = (char)(xml->folder[i] == '\\' ? '/' : lower((unsigned char)xml->folder[i]));
  }
  // Paths in skin.xml may start with "./" or a slash.
  while (file_len > 0 && (*file == '/' || *file == '\\')) {
    file++;
    file_len--;
  }
  if (file_len >= 2 && file[0] == '.' && (file[1] == '/' || file[1] == '\\')) {
    file += 2;
    file_len -= 2;
  }
  for (size_t i = 0; i < file_len && n + 1 < sizeof(path); i++) {
    path[n++] = (char)(file[i] == '\\' ? '/' : lower((unsigned char)file[i]));
  }
  path[n] = 0;
  ZipPath want = {path, 0, 0};
  zip_each(zip, size, visit_path, &want);
  return want.found ? zip_extract(zip, size, want.central, out) : -1;
}

static int decode_image(const Blob* blob, Bitmap* out) {
  if (blob->size > 2 && blob->data[0] == 'B' && blob->data[1] == 'M') {
    return decode_bmp(blob, out);
  }
  if (blob->size > 8 && memcmp(blob->data, "\x89PNG", 4) == 0) {
    return decode_png(blob, out);
  }
  if (blob->size > 4 && blob->size < (size_t)INT_MAX) {
    int width, height, channels;
    uint8_t* rgba = stbi_load_from_memory(blob->data, (int)blob->size, &width,
                                          &height, &channels, 4);
    if (rgba) {
      out->width = width;
      out->height = height;
      out->rgba = rgba;
      return 0;
    }
  }
  return -1;
}

// The text between <tag> and </tag> after `from`, trimmed.
static const char* element_text(const char* from, const char* end,
                                const char* tag, size_t* length) {
  size_t tag_len = strlen(tag);
  for (const char* s = from; s + tag_len + 2 < end; s++) {
    if (*s != '<' || !name_equals(s + 1, tag_len, tag) || s[tag_len + 1] != '>') {
      continue;
    }
    const char* text = s + tag_len + 2;
    const char* close = text;
    while (close < end && *close != '<') close++;
    while (text < close && (*text == ' ' || *text == '\t' || *text == '\r' || *text == '\n')) text++;
    while (close > text && (close[-1] == ' ' || close[-1] == '\t' || close[-1] == '\r' || close[-1] == '\n')) close--;
    *length = (size_t)(close - text);
    return text;
  }
  return NULL;
}

// The next <tag ...> element after `from`, or NULL; `*tag_end` is its '>'.
static const char* find_tag(const char* from, const char* end, const char* tag,
                            const char** tag_end) {
  size_t tag_len = strlen(tag);
  for (const char* s = from; s + tag_len + 1 < end; s++) {
    if (*s != '<' || !name_equals(s + 1, tag_len, tag)) continue;
    char next = s[tag_len + 1];
    if (next != ' ' && next != '\t' && next != '\r' && next != '\n' &&
        next != '/' && next != '>') {
      continue;
    }
    const char* close = memchr(s, '>', (size_t)(end - s));
    if (!close) return NULL;
    *tag_end = close;
    return s;
  }
  return NULL;
}

// The value of attribute `name` (lower case) in the element [tag, tag_end).
static const char* attribute(const char* tag, const char* tag_end,
                             const char* name, size_t* length) {
  size_t name_len = strlen(name);
  for (const char* s = tag + 1; s + name_len < tag_end; s++) {
    if (s[-1] != ' ' && s[-1] != '\t' && s[-1] != '\r' && s[-1] != '\n') continue;
    if (!name_equals(s, name_len, name)) continue;
    const char* v = s + name_len;
    while (v < tag_end && (*v == ' ' || *v == '\t')) v++;
    if (v >= tag_end || *v != '=') continue;
    v++;
    while (v < tag_end && (*v == ' ' || *v == '\t')) v++;
    if (v >= tag_end || (*v != '"' && *v != '\'')) continue;
    const char* close = memchr(v + 1, *v, (size_t)(tag_end - v - 1));
    if (!close) return NULL;
    *length = (size_t)(close - v - 1);
    return v + 1;
  }
  return NULL;
}

static int attribute_is(const char* tag, const char* tag_end, const char* name,
                        const char* value) {
  size_t length;
  const char* v = attribute(tag, tag_end, name, &length);
  return v && name_equals(v, length, value);
}

static int attribute_int(const char* tag, const char* tag_end, const char* name,
                         int fallback) {
  size_t length;
  const char* v = attribute(tag, tag_end, name, &length);
  int n;
  return v && parse_ints(v, v + length, &n, 1) == 1 ? n : fallback;
}

typedef struct {
  char* text;
  size_t size;
} Text;

static void append(Text* out, const char* text, size_t size) {
  char* grown = (char*)realloc(out->text, out->size + size + 1);
  if (!grown) return;
  out->text = grown;
  memcpy(out->text + out->size, text, size);
  out->size += size;
  out->text[out->size] = 0;
}

// Appends `text` (from the file at `path`, relative to the skin's folder)
// with its <include file="..."/> elements replaced by the included files,
// which are relative to the including file.
static void blank_comments(char* text, size_t size);

static void expand_includes(const uint8_t* zip, size_t size, const SkinXml* xml,
                            const char* path, const char* source, size_t length,
                            int depth, Text* out) {
  // Includes inside <!-- comments --> are not expanded (their own comments
  // would end the outer one early and blank real content).
  char* copy = (char*)malloc(length ? length : 1);
  if (!copy) return;
  memcpy(copy, source, length);
  blank_comments(copy, length);
  const char* text = copy;
  const char* end = text + length;
  const char* s = text;
  const char *tag, *tag_end;
  size_t folder = 0;
  for (size_t i = 0; path[i]; i++) {
    if (path[i] == '/' || path[i] == '\\') folder = i + 1;
  }
  while ((tag = find_tag(s, end, "include", &tag_end))) {
    append(out, s, (size_t)(tag - s));
    s = tag_end + 1;
    size_t file_len;
    const char* file = attribute(tag, tag_end, "file", &file_len);
    char included[1024];
    if (!file || depth >= 16 || folder + file_len >= sizeof(included)) continue;
    memcpy(included, path, folder);
    memcpy(included + folder, file, file_len);
    included[folder + file_len] = 0;
    Blob blob = {NULL, 0};
    if (read_skin_path(zip, size, xml, included, folder + file_len, &blob) == 0) {
      expand_includes(zip, size, xml, included, (const char*)blob.data,
                      blob.size, depth + 1, out);
    }
    free(blob.data);
  }
  append(out, s, (size_t)(end - s));
  free(copy);
}

// Blanks out <!-- comments --> so commented-out elements are not read.
static void blank_comments(char* text, size_t size) {
  char* end = text + size;
  for (char* s = text; s + 4 <= end; s++) {
    if (memcmp(s, "<!--", 4) != 0) continue;
    char* e = s + 4;
    while (e + 3 <= end && memcmp(e, "-->", 3) != 0) e++;
    e = e + 3 <= end ? e + 3 : end;
    memset(s, ' ', (size_t)(e - s));
    s = e - 1;
  }
}

// The '>' ending the tag that starts at `s`, skipping quoted values.
static const char* tag_close(const char* s, const char* end) {
  char quote = 0;
  for (; s < end; s++) {
    if (quote) {
      if (*s == quote) quote = 0;
    } else if (*s == '"' || *s == '\'') {
      quote = *s;
    } else if (*s == '>') {
      return s;
    }
  }
  return NULL;
}

// An XML element: its start tag, and the content up to its end tag.
typedef struct {
  const char* tag;      // The '<' of the start tag.
  const char* tag_end;  // Its '>'.
  const char* name;
  size_t name_len;
  const char* body;  // After the start tag; NULL when self-closing.
  const char* body_end;  // The '<' of the end tag.
} Element;

// Reads the element at or after `*s` into `out` and moves `*s` past it.
// Stops (returning 0) at the parent's end tag or `end`.
static int next_element(const char** s, const char* end, Element* out) {
  const char* p = *s;
  const char* close;
  for (;;) {
    while (p < end && *p != '<') p++;
    if (p + 1 >= end || p[1] == '/') return 0;
    close = tag_close(p, end);
    if (!close) return 0;
    if (p[1] != '!' && p[1] != '?') break;
    p = close + 1;
  }
  out->tag = p;
  out->tag_end = close;
  out->name = p + 1;
  const char* n = p + 1;
  while (n < close && *n != ' ' && *n != '\t' && *n != '\r' && *n != '\n' &&
         *n != '/') {
    n++;
  }
  out->name_len = (size_t)(n - out->name);
  if (close[-1] == '/') {
    out->body = out->body_end = NULL;
    *s = close + 1;
    return 1;
  }
  out->body = close + 1;
  int depth = 1;
  for (const char* q = close + 1; q < end;) {
    while (q < end && *q != '<') q++;
    const char* c = q < end ? tag_close(q, end) : NULL;
    if (!c) break;
    if (q[1] == '/') {
      if (--depth == 0) {
        out->body_end = q;
        *s = c + 1;
        return 1;
      }
    } else if (q[1] != '!' && q[1] != '?' && c[-1] != '/') {
      depth++;
    }
    q = c + 1;
  }
  out->body_end = end;
  *s = end;
  return 1;
}

static int is_element(const Element* e, const char* name) {
  return name_equals(e->name, e->name_len, name);
}

// Whether `a` and `b` are the same id, ignoring case.
static int same_id(const char* a, size_t a_len, const char* b, size_t b_len) {
  if (a_len != b_len) return 0;
  for (size_t i = 0; i < a_len; i++) {
    if (lower((unsigned char)a[i]) != lower((unsigned char)b[i])) return 0;
  }
  return 1;
}

// The last element `name` in [from, end) whose id is `id`, as the skin
// loader lets later definitions replace earlier ones.
static int find_by_id(const char* from, const char* end, const char* name,
                      const char* id, size_t id_len, Element* out) {
  const char *tag, *tag_end;
  int found = 0;
  for (const char* s = from; (tag = find_tag(s, end, name, &tag_end));
       s = tag_end) {
    size_t length = 0;
    const char* v = attribute(tag, tag_end, "id", &length);
    if (!v || !same_id(v, length, id, id_len)) continue;
    const char* at = tag;
    found = next_element(&at, end, out);
  }
  return found;
}

typedef struct {
  char* path;  // Lower case, as the skin names it.
  Bitmap image;
} WalFile;

// A Wasabi 3 skin being drawn: its zip, skin.xml with the includes
// expanded, and the image files decoded so far.
typedef struct {
  const uint8_t* zip;
  size_t size;
  const SkinXml* xml;
  const char* text;
  const char* end;
  WalFile** files;  // Each on its own, as sprites point at their images.
  int file_count;
  Bitmap** tinted;  // Crops recolored by a gamma group, each on its own.
  int tinted_count;
} Wal;

// A `<bitmap>`: a crop of an image file.
typedef struct {
  const Bitmap* image;
  int x, y, w, h;
} Sprite;

static const Bitmap* wal_file(Wal* wal, const char* file, size_t file_len) {
  for (int i = 0; i < wal->file_count; i++) {
    WalFile* f = wal->files[i];
    if (same_id(f->path, strlen(f->path), file, file_len)) {
      return f->image.rgba ? &f->image : NULL;
    }
  }
  WalFile** grown = (WalFile**)realloc(
      wal->files, sizeof(WalFile*) * (size_t)(wal->file_count + 1));
  if (!grown) return NULL;
  wal->files = grown;
  WalFile* entry = (WalFile*)malloc(sizeof(WalFile));
  if (!entry) return NULL;
  entry->path = (char*)malloc(file_len + 1);
  if (!entry->path) {
    free(entry);
    return NULL;
  }
  wal->files[wal->file_count] = entry;
  memcpy(entry->path, file, file_len);
  entry->path[file_len] = 0;
  memset(&entry->image, 0, sizeof(entry->image));
  wal->file_count++;
  Blob blob = {NULL, 0};
  if (read_skin_path(wal->zip, wal->size, wal->xml, file, file_len, &blob) ==
          0 &&
      decode_image(&blob, &entry->image) != 0) {
    free(entry->image.rgba);
    memset(&entry->image, 0, sizeof(entry->image));
  }
  free(blob.data);
  return entry->image.rgba ? &entry->image : NULL;
}

// The `<gammagroup>` named `group` of the skin's first `<gammaset>` (its
// default color theme), as the red, green and blue multipliers of the player's
// bitmap filter (65535 leaves a channel as it is), the gray mode and boost.
// 0 when there is none or it changes nothing.
static int wal_gamma(Wal* wal, const char* group, size_t group_len, int mult[3],
                     int* gray, int* boost) {
  // The set named Default, which a skin starts with.
  const char* from = NULL;
  const char* to = NULL;
  for (const char* at = wal->text; at < wal->end; at++) {
    if (wal->end - at >= 22 &&
        memcmp(at, "<gammaset id=\"Default\"", 22) == 0) {
      from = at;
      break;
    }
  }
  if (!from) return 0;
  for (const char* at = from; at + 11 <= wal->end; at++) {
    if (memcmp(at, "</gammaset>", 11) == 0) {
      to = at;
      break;
    }
  }
  if (!to) return 0;
  Element e;
  if (!find_by_id(from, to, "gammagroup", group, group_len, &e)) return 0;
  size_t length;
  const char* value = attribute(e.tag, e.tag_end, "value", &length);
  int v[3] = {0, 0, 0};
  if (value) {
    const char* at = value;
    const char* stop = value + length;
    for (int i = 0; i < 3 && at < stop; i++) {
      char* next;
      long n = strtol(at, &next, 10);
      if (next == at) break;
      v[i] = (int)n;
      at = next;
      if (at < stop && *at == ',') at++;
    }
  }
  *gray = attribute_int(e.tag, e.tag_end, "gray", 0);
  *boost = attribute_int(e.tag, e.tag_end, "boost", 0);
  for (int i = 0; i < 3; i++) mult[i] = 65535 + v[i] * 16;
  return v[0] || v[1] || v[2] || *gray || *boost;
}

// Replaces the crop in `out` with a copy recolored by the bitmap's gamma group
// (`gammagroup="..."`), as the player does with the skin's color theme.
static void wal_tint(Wal* wal, const Element* bitmap, Sprite* out) {
  size_t group_len;
  const char* group = attribute(bitmap->tag, bitmap->tag_end, "gammagroup",
                                &group_len);
  int mult[3], gray, boost;
  if (!group || group_len == 0 ||
      !wal_gamma(wal, group, group_len, mult, &gray, &boost)) {
    return;
  }
  Bitmap* copy = (Bitmap*)calloc(1, sizeof(Bitmap));
  Bitmap** grown = (Bitmap**)realloc(
      wal->tinted, sizeof(Bitmap*) * (size_t)(wal->tinted_count + 1));
  if (!copy || !grown) {
    free(copy);
    if (grown) wal->tinted = grown;
    return;
  }
  wal->tinted = grown;
  copy->width = out->w;
  copy->height = out->h;
  copy->rgba = (uint8_t*)malloc((size_t)out->w * (size_t)out->h * 4);
  if (!copy->rgba) {
    free(copy);
    return;
  }
  wal->tinted[wal->tinted_count++] = copy;
  for (int row = 0; row < out->h; row++) {
    const uint8_t* s = out->image->rgba +
                       ((size_t)(out->y + row) * out->image->width + out->x) * 4;
    uint8_t* d = copy->rgba + (size_t)row * out->w * 4;
    for (int col = 0; col < out->w; col++, s += 4, d += 4) {
      int c[3] = {s[0], s[1], s[2]};
      if (gray == 1) {
        int top = c[0] > c[1] ? (c[0] > c[2] ? c[0] : c[2])
                              : (c[1] > c[2] ? c[1] : c[2]);
        c[0] = c[1] = c[2] = top;
      } else if (gray == 2) {
        c[0] = c[1] = c[2] = (c[0] + c[1] + c[2]) / 3;
      }
      if (boost) {
        int half = s[3] >> 1;
        for (int i = 0; i < 3; i++) c[i] = (c[i] >> 1) + half;
      }
      for (int i = 0; i < 3; i++) {
        int scaled = (int)(((int64_t)c[i] * mult[i]) >> 16);
        d[i] = (uint8_t)(scaled < 0 ? 0 : (scaled > 255 ? 255 : scaled));
      }
      d[3] = s[3];
    }
  }
  out->image = copy;
  out->x = 0;
  out->y = 0;
}

// The `<bitmap>` named `id`.
static int wal_bitmap(Wal* wal, const char* id, size_t id_len, Sprite* out) {
  if (!id || id_len == 0) return -1;
  Element bitmap;
  if (!find_by_id(wal->text, wal->end, "bitmap", id, id_len, &bitmap)) {
    // Some skins name an image file where an id belongs.
    int path = 0;
    for (size_t i = 0; i < id_len; i++) {
      if (id[i] == '.') path = 1;
    }
    const Bitmap* whole = path ? wal_file(wal, id, id_len) : NULL;
    if (!whole) return -1;
    out->image = whole;
    out->x = 0;
    out->y = 0;
    out->w = whole->width;
    out->h = whole->height;
    return 0;
  }
  size_t file_len;
  const char* file =
      attribute(bitmap.tag, bitmap.tag_end, "file", &file_len);
  const Bitmap* image = file ? wal_file(wal, file, file_len) : NULL;
  if (!image) return -1;
  // A bitmap may be a crop of its file.
  int x = attribute_int(bitmap.tag, bitmap.tag_end, "x", 0);
  int y = attribute_int(bitmap.tag, bitmap.tag_end, "y", 0);
  int w = attribute_int(bitmap.tag, bitmap.tag_end, "w", image->width - x);
  int h = attribute_int(bitmap.tag, bitmap.tag_end, "h", image->height - y);
  // A rectangle that runs past the file is clipped to it, as the classic player does
  // (the Wasabi 5 skin's display glass is 4 pixels taller than its file).
  if (x < 0 || y < 0 || w <= 0 || h <= 0 || x >= image->width ||
      y >= image->height) {
    return -1;
  }
  if (x + w > image->width) w = image->width - x;
  if (y + h > image->height) h = image->height - y;
  out->image = image;
  out->x = x;
  out->y = y;
  out->w = w;
  out->h = h;
  wal_tint(wal, &bitmap, out);
  return 0;
}

// Draws `sprite` over the rectangle (x, y, w, h) of `canvas` with `alpha`
// (0..255), stretched or tiled, blending straight alpha over straight alpha.
static void draw_sprite(Bitmap* canvas, const Sprite* sprite, int x, int y,
                        int w, int h, int alpha, int tile) {
  if (w <= 0 || h <= 0 || alpha <= 0) return;
  int top = y < 0 ? 0 : y, left = x < 0 ? 0 : x;
  int bottom = y + h < canvas->height ? y + h : canvas->height;
  int right = x + w < canvas->width ? x + w : canvas->width;
  for (int row = top; row < bottom; row++) {
    int sy = tile ? (row - y) % sprite->h : (int)((int64_t)(row - y) * sprite->h / h);
    const uint8_t* line =
        sprite->image->rgba +
        ((size_t)(sprite->y + sy) * sprite->image->width + sprite->x) * 4;
    uint8_t* d = canvas->rgba + ((size_t)row * canvas->width + left) * 4;
    for (int col = left; col < right; col++, d += 4) {
      int sx = tile ? (col - x) % sprite->w : (int)((int64_t)(col - x) * sprite->w / w);
      const uint8_t* s = line + (size_t)sx * 4;
      int sa = s[3] * alpha / 255;
      if (sa == 0) continue;
      // Both scaled by 255: the source's share and what shows of the
      // destination.
      int under = d[3] * (255 - sa);
      int total = sa * 255 + under;
      for (int c = 0; c < 3; c++) {
        d[c] = (uint8_t)((s[c] * sa * 255 + d[c] * under) / total);
      }
      d[3] = (uint8_t)((total + 127) / 255);
    }
  }
}

// A drawn object: its own element and, for a group, its `<groupdef>`,
// whose attributes the group's own override.
typedef struct {
  const Element* use;
  const Element* def;
} Object;

static const char* object_attribute(const Object* o, const char* name,
                                    size_t* length) {
  const char* v = attribute(o->use->tag, o->use->tag_end, name, length);
  if (!v && o->def) v = attribute(o->def->tag, o->def->tag_end, name, length);
  return v;
}

// Integer attribute `name`, or `fallback` when missing or not a number.
static int object_int(const Object* o, const char* name, int fallback) {
  size_t length;
  const char* v = object_attribute(o, name, &length);
  int n;
  return v && parse_ints(v, v + length, &n, 1) == 1 ? n : fallback;
}

// `x`/`y`/`w`/`h` with relat 1 "from the right/bottom" or 2 "percent".
static int place(int value, int relat, int extent) {
  return relat == 1 ? extent + value
         : relat == 2 ? extent * value / 100
                      : value;
}

static const int kUnset = -(1 << 30);  // An attribute that is not given.

static void draw_group_body(Wal* wal, Bitmap* canvas, const Element* def,
                            int x, int y, int w, int h, int depth);

// --- Sample playlist ---------------------------------------------------------

// The playlist a skin leaves to the app (the `playlistpro` group, or a
// `<component>` / `<windowholder>` holding the playlist editor) is drawn with
// made up tracks, in the skin's list colors, so the picture shows what a list
// looks like in it. The text is set in the classic skin's 5x6 font.
static Bitmap g_font;
static int g_font_tried = 0;

static const Bitmap* sample_font(void) {
  if (!g_font_tried) {
    g_font_tried = 1;
    Blob base[F_COUNT];
    memset(base, 0, sizeof(base));
    read_zip(kBaseSkin, kBaseSkinSize, base, 0);
    if (base[F_TEXT].data) decode_bmp(&base[F_TEXT], &g_font);
    for (int i = 0; i < F_COUNT; i++) free(base[i].data);
  }
  return g_font.rgba ? &g_font : NULL;
}

// The `<color id="...">` of the skin as red, green, blue; `fallback` when the
// skin has none.
static void wal_color(Wal* wal, const char* id, const uint8_t fallback[3],
                      uint8_t rgb[3]) {
  memcpy(rgb, fallback, 3);
  Element color;
  if (!find_by_id(wal->text, wal->end, "color", id, strlen(id), &color)) return;
  size_t length = 0;
  const char* v = attribute(color.tag, color.tag_end, "value", &length);
  int n[3];
  if (v && parse_ints(v, v + length, n, 3) == 3) {
    for (int c = 0; c < 3; c++) rgb[c] = (uint8_t)(n[c] < 0 ? 0 : n[c] > 255 ? 255 : n[c]);
    // The color as the skin's default color theme shows it.
    size_t group_len = 0;
    const char* group =
        attribute(color.tag, color.tag_end, "gammagroup", &group_len);
    int mult[3], gray, boost;
    if (group && group_len > 0 &&
        wal_gamma(wal, group, group_len, mult, &gray, &boost)) {
      int c3[3] = {rgb[0], rgb[1], rgb[2]};
      if (gray == 1) {
        int top = c3[0] > c3[1] ? (c3[0] > c3[2] ? c3[0] : c3[2])
                                : (c3[1] > c3[2] ? c3[1] : c3[2]);
        c3[0] = c3[1] = c3[2] = top;
      } else if (gray == 2) {
        c3[0] = c3[1] = c3[2] = (c3[0] + c3[1] + c3[2]) / 3;
      }
      if (boost) {
        for (int c = 0; c < 3; c++) c3[c] = (c3[c] >> 1) + 127;
      }
      for (int c = 0; c < 3; c++) {
        int scaled = (int)(((int64_t)c3[c] * mult[c]) >> 16);
        rgb[c] = (uint8_t)(scaled < 0 ? 0 : (scaled > 255 ? 255 : scaled));
      }
    }
  }
}

static void fill_rect(Bitmap* canvas, int x, int y, int w, int h,
                      const uint8_t rgb[3]) {
  for (int row = y < 0 ? 0 : y; row < y + h && row < canvas->height; row++) {
    for (int col = x < 0 ? 0 : x; col < x + w && col < canvas->width; col++) {
      uint8_t* d = canvas->rgba + ((size_t)row * canvas->width + col) * 4;
      d[0] = rgb[0];
      d[1] = rgb[1];
      d[2] = rgb[2];
      d[3] = 255;
    }
  }
}

// `text` in `rgb` at (x, y), clipped to `width` pixels; returns its width.
static int sample_text(Bitmap* canvas, const char* text, int x, int y, int width,
                       const uint8_t rgb[3]) {
  const Bitmap* font = sample_font();
  int drawn = 0;
  for (int i = 0; font && text[i] && (i + 1) * 5 <= width; i++, drawn += 5) {
    int gx, gy;
    glyph((unsigned char)text[i], &gx, &gy);
    for (int row = 0; row < 6; row++) {
      for (int col = 0; col < 5; col++) {
        int dx = x + i * 5 + col, dy = y + row;
        if (dx < 0 || dy < 0 || dx >= canvas->width || dy >= canvas->height) continue;
        const uint8_t* s = font->rgba + ((size_t)(gy + row) * font->width + gx + col) * 4;
        int a = s[0] > s[1] ? (s[0] > s[2] ? s[0] : s[2]) : (s[1] > s[2] ? s[1] : s[2]);
        if (a < 40 || s[3] == 0) continue;
        uint8_t* d = canvas->rgba + ((size_t)dy * canvas->width + dx) * 4;
        for (int c = 0; c < 3; c++) d[c] = (uint8_t)((rgb[c] * a + d[c] * (255 - a)) / 255);
        d[3] = 255;
      }
    }
  }
  return drawn;
}

// The list in the rectangle (x, y, w, h): a few rows of made up tracks, one
// playing and one selected.
static void draw_sample_playlist(Wal* wal, Bitmap* canvas, int x, int y, int w,
                                 int h) {
  static const char* const kTracks[][2] = {
      {"NEON HARBOR - MIDNIGHT STATIC", "3:42"},
      {"THE PAPER SATELLITES - GLASS ORCHARD", "4:05"},
      {"VELVET ARCADE - LO-FI SUNRISE", "2:58"},
      {"MARLOW AND THE ECHOES - PAPER PLANES", "3:31"},
      {"JUNIPER STATIC - GOLDEN HOUR", "4:17"},
      {"CASSETTE DREAMS - SLOW MOTION", "3:09"},
      {"ORBIT GARDEN - NIGHT BLOOM", "5:02"},
      {"THE LANTERN CLUB - WINTER LIGHTS", "3:48"},
  };
  static const uint8_t kBackground[3] = {28, 61, 125},
                       kText[3] = {255, 255, 255}, kCurrent[3] = {187, 210, 255},
                       kSelected[3] = {214, 228, 255}, kSelectedBackground[3] = {103, 136, 201};
  uint8_t background[3], alternate[3], text[3], current[3], selected[3], selected_bg[3];
  wal_color(wal, "wasabi.list.background", kBackground, background);
  // A skin without alternate rows has plain ones.
  wal_color(wal, "wasabi.list.background.alternate", background, alternate);
  wal_color(wal, "wasabi.list.text", kText, text);
  wal_color(wal, "wasabi.list.text.current", kCurrent, current);
  wal_color(wal, "wasabi.list.text.selected", kSelected, selected);
  wal_color(wal, "wasabi.list.text.selected.background", kSelectedBackground,
            selected_bg);
  if (w < 40 || h < 13) return;
  const int row_height = 13;
  fill_rect(canvas, x, y, w, h, background);
  int rows = sizeof(kTracks) / sizeof(kTracks[0]);
  for (int i = 0; i < rows && (i + 1) * row_height <= h; i++) {
    int top = y + i * row_height;
    const uint8_t* ink = text;
    if (i == 2) {
      fill_rect(canvas, x, top, w, row_height, selected_bg);
      ink = selected;
    } else if (i % 2 == 1) {
      fill_rect(canvas, x, top, w, row_height, alternate);
    }
    if (i == 1) ink = current;
    char label[96];
    snprintf(label, sizeof(label), "%d. %s", i + 1, kTracks[i][0]);
    int time_w = (int)strlen(kTracks[i][1]) * 5;
    sample_text(canvas, label, x + 4, top + 4, w - time_w - 14, ink);
    sample_text(canvas, kTracks[i][1], x + w - time_w - 4, top + 4, time_w, ink);
  }
}

// Whether `e` holds the playlist editor: the `playlistpro` group of the
// Wasabi 5 skins, or a component or window holder naming its GUID.
static int holds_playlist(const Element* e) {
  size_t length = 0;
  const char* v;
  if (is_element(e, "group")) {
    v = attribute(e->tag, e->tag_end, "id", &length);
    return v && same_id(v, length, "playlistpro", 11);
  }
  if (!is_element(e, "component") && !is_element(e, "windowholder")) return 0;
  const char* names[2] = {"param", "hold"};
  for (int k = 0; k < 2; k++) {
    v = attribute(e->tag, e->tag_end, names[k], &length);
    for (size_t i = 0; v && i + 8 <= length; i++) {
      if (name_equals(v + i, 8, "45f3f7c1")) return 1;
    }
    for (size_t i = 0; v && i + 7 <= length; i++) {
      if (name_equals(v + i, 7, "guid:pl")) return 1;
    }
  }
  return 0;
}


// The menu bar's alignment (menualign.maki): while a groupdef whose script
// lists groups in its `param` is drawn, each of those groups is placed after
// the one before, as wide as its `autowidthsource` label.
static const char* g_align = NULL;
static size_t g_align_length = 0;
static int g_align_cursor = 0;

// The title bar (titlebar.maki): while a groupdef whose script is the title
// bar's is drawn, its streaks are placed around the title text, centered in
// the window: the left one from the frame's `padtitleleft` to the text, the
// right one from the text to `padtitleright` short of the end, which leaves
// room for the buttons over it.
static const char* g_streak_left = NULL;
static size_t g_streak_left_length = 0;
static const char* g_streak_right = NULL;
static size_t g_streak_right_length = 0;
static int g_title_width = 0;  // The title text's width, 0 when unknown.
static int g_pad_left = 0, g_pad_right = 0;

// The width of `text` set in Arial Bold, 14 pixels (the Wasabi title bar's
// font), in pixels, upper-cased.
static int title_text_width(const char* text, size_t length) {
  // Arial Bold's advances for A-Z in 1/1000 em.
  static const int kLetters[26] = {722, 722, 722, 722, 667, 611, 778, 722, 278,
                                   556, 722, 611, 833, 722, 778, 667, 778, 722,
                                   667, 611, 722, 667, 944, 667, 667, 611};
  int total = 0;
  for (size_t i = 0; i < length; i++) {
    int c = lower((unsigned char)text[i]);
    total += c >= 'a' && c <= 'z' ? kLetters[c - 'a'] : c == ' ' ? 278 : 556;
  }
  return total * 14 / 1000;
}

// Whether `id` is one of the comma separated ids in g_align.
static int in_alignment(const char* id, size_t id_len) {
  if (!g_align) return 0;
  const char* end = g_align + g_align_length;
  for (const char* p = g_align; p < end;) {
    const char* comma = memchr(p, ',', (size_t)(end - p));
    size_t n = comma ? (size_t)(comma - p) : (size_t)(end - p);
    if (same_id(p, n, id, id_len)) return 1;
    p += n + 1;
  }
  return 0;
}

// The groupdef an XUI tag such as `<Wasabi:MainFrame:NoStatus>` stands for:
// the one whose `xuitag` is the element's name.
static int find_xui_def(const Wal* wal, const Element* e, Element* out) {
  const char *tag, *tag_end;
  int found = 0;
  for (const char* s = wal->text; (tag = find_tag(s, wal->end, "groupdef", &tag_end));
       s = tag_end) {
    size_t length = 0;
    const char* v = attribute(tag, tag_end, "xuitag", &length);
    if (!v || !same_id(v, length, e->name, e->name_len)) continue;
    const char* at = tag;
    found = next_element(&at, wal->end, out);
  }
  return found;
}

// Where a frame's script (standardframe.maki, `param="x,y,w,h,relatx,relaty,
// relatw,relath"`) puts the content it hosts, in a frame (w, h) big:
// rect = {x, y, w, h}. The standard frames put it at the title's height with
// the frame's own size (relath), so a skin's content hangs from the
// frame's bottom, not from the bottom of what is left under the title. The
// short form `param="left,top,right,bottom"` is the room around it. Without
// a script, the usual 18 pixel title.
static void frame_content(const Element* def, int w, int h, int rect[4]) {
  rect[0] = 0;
  rect[1] = 18;
  rect[2] = w;
  rect[3] = h - 18;
  Element child;
  for (const char* s = def->body; def->body && next_element(&s, def->body_end, &child);) {
    if (!is_element(&child, "script")) continue;
    size_t length;
    const char* v = attribute(child.tag, child.tag_end, "param", &length);
    int n[8];
    int count = v ? parse_ints(v, v + length, n, 8) : 0;
    if (count == 8) {
      rect[0] = n[4] ? w + n[0] : n[0];
      rect[1] = n[5] ? h + n[1] : n[1];
      rect[2] = n[6] ? w + n[2] : n[2];
      rect[3] = n[7] ? h + n[3] : n[3];
    } else if (count == 4) {
      rect[0] = n[0];
      rect[1] = n[1];
      rect[2] = w - n[0] - n[2];
      rect[3] = h - n[1] - n[3];
    }
  }
}

// Whether `a` and `b` give the same value for attribute `name`.
static int same_attribute(const Element* a, const Element* b, const char* name) {
  size_t la = 0, lb = 0;
  const char* va = attribute(a->tag, a->tag_end, name, &la);
  const char* vb = attribute(b->tag, b->tag_end, name, &lb);
  if (!va || !vb) return 0;
  return la == lb && memcmp(va, vb, la) == 0;
}

// Whether `a` and `b` give the same value for attribute `name`, or neither
// gives one.
static int same_or_absent(const Element* a, const Element* b, const char* name) {
  size_t la = 0, lb = 0;
  const char* va = attribute(a->tag, a->tag_end, name, &la);
  const char* vb = attribute(b->tag, b->tag_end, name, &lb);
  if (!va && !vb) return 1;
  return va && vb && la == lb && memcmp(va, vb, la) == 0;
}

// Skins stack alternate pages (a display's menu, song info, equalizer and
// options) in one place and let a script show one. Without the script, draws
// the song info page and skips the others; groups stacked for other reasons
// (no song info page among them) are all drawn.
static int skip_alternate_page(const char* body, const char* end,
                               const Element* self) {
  int count = 0;
  const char* preferred = NULL;
  Element other;
  for (const char* s = body; next_element(&s, end, &other);) {
    if (!is_element(&other, "group") || !same_attribute(self, &other, "x") ||
        !same_attribute(self, &other, "y") ||
        !same_or_absent(self, &other, "w") ||
        !same_or_absent(self, &other, "h")) {
      continue;
    }
    count++;
    size_t length = 0;
    const char* id = attribute(other.tag, other.tag_end, "id", &length);
    // Pages that give their size, as the song info page does.
    size_t size_length = 0;
    int sized = attribute(self->tag, self->tag_end, "w", &size_length) &&
                attribute(self->tag, self->tag_end, "h", &size_length);
    for (size_t i = 0; sized && id && !preferred && i + 8 <= length; i++) {
      if (name_equals(id + i, 8, "songinfo")) preferred = other.tag;
    }
    // The page a display opens on (the iPhone skin's `maingroup`).
    if (id && !preferred && !sized && length == 9 &&
        name_equals(id, 9, "maingroup")) {
      preferred = other.tag;
    }
  }
  if (count < 3 || !preferred) return 0;
  return self->tag != preferred;
}

// Whether a child of the groupdef `def` is combined with its region
// (`sysregion="AND"`), as a mask group's contents are.
static int has_and_child(const Element* def) {
  Element child;
  for (const char* c = def->body; def->body &&
                                  next_element(&c, def->body_end, &child);) {
    size_t length = 0;
    const char* v = attribute(child.tag, child.tag_end, "sysregion", &length);
    if (v && length == 3 && lower(v[0]) == 'a' && lower(v[1]) == 'n' &&
        lower(v[2]) == 'd') {
      return 1;
    }
  }
  return 0;
}

// Draws the children of a layout or groupdef in [body, body_end), XML order,
// in the parent rectangle (x, y, w, h). As the app's wasabi_view.dart:
// layers, buttons and groups, without what scripts or the player would show.
static void draw_children(Wal* wal, Bitmap* canvas, const char* body,
                          const char* body_end, int x, int y, int w, int h,
                          int depth) {
  Element e;
  for (const char* s = body; body && next_element(&s, body_end, &e);) {
    int layer = is_element(&e, "layer") || is_element(&e, "animatedlayer");
    int button = is_element(&e, "button") || is_element(&e, "togglebutton");
    int group = is_element(&e, "group");
    // The playlist is the app's: draw some tracks in its place.
    if (holds_playlist(&e)) {
      Object list = {&e, NULL};
      int lx = place(object_int(&list, "x", 0), object_int(&list, "relatx", 0), w);
      int ly = place(object_int(&list, "y", 0), object_int(&list, "relaty", 0), h);
      int lw = object_int(&list, "w", kUnset);
      int lh = object_int(&list, "h", kUnset);
      lw = lw != kUnset ? place(lw, object_int(&list, "relatw", 0), w) : w - lx;
      lh = lh != kUnset ? place(lh, object_int(&list, "relath", 0), h) : h - ly;
      draw_sample_playlist(wal, canvas, x + lx, y + ly, lw, lh);
      continue;
    }
    Element def;
    // An XUI tag is a group of the groupdef that defines it.
    int xui = !layer && !button && !group && depth < 16 &&
              find_xui_def(wal, &e, &def);
    if (!layer && !button && !group && !xui) continue;
    Object o = {&e, NULL};
    size_t length = 0;
    const char* v;
    // The Wasabi 5 player's overlay that hides the video and visualization
    // button while both are detached; its script hides it otherwise.
    if (layer) {
      v = attribute(e.tag, e.tag_end, "id", &length);
      if (v && same_id(v, length, "openclosehider", 14)) continue;
    }
    if (xui) {
      o.def = &def;
      group = 1;
    } else if (group) {
      if (skip_alternate_page(body, body_end, &e)) continue;
      v = attribute(e.tag, e.tag_end, "id", &length);
      if (!v || depth >= 16 ||
          !find_by_id(wal->text, wal->end, "groupdef", v, length, &def)) {
        continue;
      }
      o.def = &def;
    }
    if (object_int(&o, "visible", 1) == 0) continue;
    // The natural size (-1 for none): the image's, or a group's default
    // size or background.
    Sprite sprite;
    int has_sprite;
    int natural_w = -1, natural_h = -1;
    if (group) {
      v = o.def ? attribute(def.tag, def.tag_end, "background", &length) : NULL;
      has_sprite = wal_bitmap(wal, v, v ? length : 0, &sprite) == 0;
      natural_w = object_int(&o, "default_w", has_sprite ? sprite.w : -1);
      natural_h = object_int(&o, "default_h", has_sprite ? sprite.h : -1);
    } else {
      v = attribute(e.tag, e.tag_end, "image", &length);
      has_sprite = wal_bitmap(wal, v, v ? length : 0, &sprite) == 0;
      // A layer without an image only takes the mouse.
      if (!has_sprite) continue;
      natural_w = sprite.w;
      natural_h = sprite.h;
    }
    int ox = place(object_int(&o, "x", 0), object_int(&o, "relatx", 0), w);
    int oy = place(object_int(&o, "y", 0), object_int(&o, "relaty", 0), h);
    int aligned = 0;
    if (group && !xui) {
      size_t id_len = 0;
      const char* id = attribute(e.tag, e.tag_end, "id", &id_len);
      if (id && in_alignment(id, id_len)) {
        aligned = 1;
        ox = g_align_cursor;
      }
    }
    int ow = object_int(&o, "w", kUnset);
    int oh = object_int(&o, "h", kUnset);
    ow = ow != kUnset ? place(ow, object_int(&o, "relatw", 0), w)
         : natural_w >= 0 ? natural_w
                          : w - ox;
    oh = oh != kUnset ? place(oh, object_int(&o, "relath", 0), h)
         : natural_h >= 0 ? natural_h
                          : h - oy;
    if (ow < 0) ow = 0;
    if (oh < 0) oh = 0;
    if (group && !xui && g_streak_left) {
      size_t id_len = 0;
      const char* id = attribute(e.tag, e.tag_end, "instanceid", &id_len);
      int left = id && same_id(id, id_len, g_streak_left, g_streak_left_length);
      int right = id && same_id(id, id_len, g_streak_right, g_streak_right_length);
      if (g_title_width > 0 && (left || right)) {
        // Where the layout's center is, in this group's coordinates.
        int lx = (canvas->width - g_title_width) / 2 - x;
        if (left) {
          ox = g_pad_left;
          ow = lx - g_pad_left;
        } else {
          ox = lx + g_title_width + 1;
          ow = w - (lx + g_title_width + 1 + g_pad_right + 1);
        }
        if (ow < 0) ow = 0;
      }
    }
    int alpha = object_int(&o, "alpha", 255);
    // The window is drawn active: its `activealpha` is the object's alpha
    // (the title bar's inactive pieces are 0), `inactivealpha` is not used.
    alpha = object_int(&o, "activealpha", alpha);
    alpha = alpha < 0 ? 0 : alpha > 255 ? 255 : alpha;
    if (aligned) {
      // The label's width (`getAutoWidth`), as menualign.maki adds it up.
      size_t n = 0;
      const char* source = attribute(def.tag, def.tag_end, "autowidthsource", &n);
      int label = 0;
      Element child;
      for (const char* c = def.body; source && def.body &&
                                      next_element(&c, def.body_end, &child);) {
        size_t id_len = 0;
        const char* id = attribute(child.tag, child.tag_end, "id", &id_len);
        Sprite image;
        size_t image_len = 0;
        const char* name = attribute(child.tag, child.tag_end, "image", &image_len);
        if (id && same_id(id, id_len, source, n) &&
            wal_bitmap(wal, name, name ? image_len : 0, &image) == 0) {
          label = image.w;
        }
      }
      g_align_cursor += label > 0 ? label : ow;
    }
    // A group with `alpha="0"` is invisible with everything on it (Graviton
    // starts its controls and display so, and its script fades them in).
    if (group && alpha == 0) continue;
    if (group) {
      // `drawbackground="0"` keeps the background as the group's shape only.
      if (has_sprite &&
          !(o.def && attribute_is(def.tag, def.tag_end, "drawbackground", "0"))) {
        draw_sprite(canvas, &sprite, x + ox, y + oy, ow, oh, alpha, 0);
      }
      int saved_pad_left = g_pad_left, saved_pad_right = g_pad_right;
      if (xui) {
        g_pad_left = attribute_int(e.tag, e.tag_end, "padtitleleft", 0);
        g_pad_right = attribute_int(e.tag, e.tag_end, "padtitleright", 0);
      }
      if (!xui && has_sprite && o.def &&
          attribute_is(def.tag, def.tag_end, "drawbackground", "0") &&
          has_and_child(&def)) {
        // A mask group (Anexa's drawers): what it holds shows only inside its
        // own rectangle, so a panel parked outside it (`x="-140"`) is hidden.
        Bitmap mask = {canvas->width, canvas->height,
                        (uint8_t*)calloc((size_t)canvas->width * canvas->height, 4)};
        if (mask.rgba) {
          draw_group_body(wal, &mask, &def, x + ox, y + oy, ow, oh, depth + 1);
          int x0 = x + ox < 0 ? 0 : x + ox, y0 = y + oy < 0 ? 0 : y + oy;
          int x1 = x + ox + ow > canvas->width ? canvas->width : x + ox + ow;
          int y1 = y + oy + oh > canvas->height ? canvas->height : y + oy + oh;
          if (x1 > x0 && y1 > y0) {
            Sprite cut = {&mask, x0, y0, x1 - x0, y1 - y0};
            draw_sprite(canvas, &cut, x0, y0, x1 - x0, y1 - y0, 255, 0);
          }
          free(mask.rgba);
        }
      } else {
        draw_group_body(wal, canvas, &def, x + ox, y + oy, ow, oh, depth + 1);
      }
      g_pad_left = saved_pad_left;
      g_pad_right = saved_pad_right;
      v = xui ? attribute(e.tag, e.tag_end, "content", &length) : NULL;
      Element content;
      if (v && find_by_id(wal->text, wal->end, "groupdef", v, length, &content)) {
        int rect[4];
        frame_content(&def, ow, oh, rect);
        draw_group_body(wal, canvas, &content, x + ox + rect[0],
                        y + oy + rect[1], rect[2], rect[3], depth + 1);
      }
      continue;
    }
    if (is_element(&e, "animatedlayer")) {
      // Its first frame.
      // A frame is as big as the layer unless the skin says otherwise.
      int fw = object_int(&o, "framewidth", ow);
      int fh = object_int(&o, "frameheight", oh);
      if (fw > 0 && fw < sprite.w) sprite.w = fw;
      if (fh > 0 && fh < sprite.h) sprite.h = fh;
    }
    draw_sprite(canvas, &sprite, x + ox, y + oy, ow, oh,
                button ? 255 : alpha, layer && object_int(&o, "tile", 0) == 1);
  }
}

// A group's objects: those of the groupdef it inherits, then its own.
static void draw_group_body(Wal* wal, Bitmap* canvas, const Element* def,
                            int x, int y, int w, int h, int depth) {
  size_t length;
  const char* inherited =
      attribute(def->tag, def->tag_end, "inherit_group", &length);
  Element parent;
  if (inherited && depth < 16 &&
      find_by_id(wal->text, wal->end, "groupdef", inherited, length,
                 &parent) &&
      parent.tag != def->tag) {
    draw_children(wal, canvas, parent.body, parent.body_end, x, y, w, h,
                  depth + 1);
  }
  // A script that aligns groups (the menu bar's).
  const char* saved = g_align;
  size_t saved_length = g_align_length;
  int saved_cursor = g_align_cursor;
  Element child;
  for (const char* s = def->body; def->body && next_element(&s, def->body_end, &child);) {
    size_t file_len = 0;
    const char* file = is_element(&child, "script")
                           ? attribute(child.tag, child.tag_end, "file", &file_len)
                           : NULL;
    if (!file) continue;
    for (size_t i = 0; i + 9 <= file_len; i++) {
      if (name_equals(file + i, 9, "menualign")) {
        g_align = attribute(child.tag, child.tag_end, "param", &g_align_length);
        g_align_cursor = 0;
      }
    }
  }
  // The title bar's script: `param="left streak;title;right streak"`.
  const char* saved_streak_left = g_streak_left;
  size_t saved_streak_left_length = g_streak_left_length;
  const char* saved_streak_right = g_streak_right;
  size_t saved_streak_right_length = g_streak_right_length;
  for (const char* s = def->body; def->body && next_element(&s, def->body_end, &child);) {
    size_t file_len = 0;
    const char* file = is_element(&child, "script")
                           ? attribute(child.tag, child.tag_end, "file", &file_len)
                           : NULL;
    if (!file) continue;
    for (size_t i = 0; i + 8 <= file_len; i++) {
      if (!name_equals(file + i, 8, "titlebar")) continue;
      size_t param_len = 0;
      const char* param = attribute(child.tag, child.tag_end, "param", &param_len);
      const char* end = param ? param + param_len : NULL;
      const char* first = param ? memchr(param, ';', param_len) : NULL;
      const char* last = param ? memchr(first ? first + 1 : param, ';', (size_t)(end - (first ? first + 1 : param))) : NULL;
      if (first && last) {
        g_streak_left = param;
        g_streak_left_length = (size_t)(first - param);
        g_streak_right = last + 1;
        g_streak_right_length = (size_t)(end - (last + 1));
      }
    }
  }
  draw_children(wal, canvas, def->body, def->body_end, x, y, w, h, depth);
  g_streak_left = saved_streak_left;
  g_streak_left_length = saved_streak_left_length;
  g_streak_right = saved_streak_right;
  g_streak_right_length = saved_streak_right_length;
  g_align = saved;
  g_align_length = saved_length;
  g_align_cursor = saved_cursor;
}

// Draws the normal layout of the container whose id is `id_a` or `id_b`
// (`<container id="main">` → `<layout id="normal">`): its background
// (alphabackground, else background) and the objects on it, clipped to the
// window's shape, which is where `background` is not transparent. Returns
// nonzero when the skin has no such window.
static int wal_window(Wal* wal, const char* id_a, const char* id_b,
                      Bitmap* out) {
  int result = -1;
  const char *tag, *tag_end;
  Element layout = {0}, first = {0};
  int found = 0;
  for (const char* s = wal->text;
       !found && (tag = find_tag(s, wal->end, "container", &tag_end));
       s = tag_end) {
    if (!attribute_is(tag, tag_end, "id", id_a) &&
        !(id_b && attribute_is(tag, tag_end, "id", id_b))) {
      continue;
    }
    const char* at = tag;
    Element container;
    if (!next_element(&at, wal->end, &container) || !container.body) continue;
    // The "normal" layout, else the container's first (Ebonite's are "full",
    // "compact", ...).
    Element candidate;
    int have_first = 0;
    for (const char* c = container.body;
         next_element(&c, container.body_end, &candidate);) {
      if (!is_element(&candidate, "layout")) continue;
      if (attribute_is(candidate.tag, candidate.tag_end, "id", "normal")) {
        layout = candidate;
        found = 1;
        break;
      }
      if (!have_first) {
        first = candidate;
        have_first = 1;
      }
    }
    if (!found && have_first) {
      layout = first;
      found = 1;
    }
  }
  if (!found) return -1;
  size_t length = 0;
  const char* v;
  Sprite background, base;
  v = attribute(layout.tag, layout.tag_end, "alphabackground", &length);
  int alpha_given = v != NULL;
  int has_background = wal_bitmap(wal, v, v ? length : 0, &background) == 0;
  v = attribute(layout.tag, layout.tag_end, "background", &length);
  int has_base = wal_bitmap(wal, v, v ? length : 0, &base) == 0;
  if (!has_background && has_base) {
    background = base;
    has_background = 1;
  }
  if (!has_base && has_background) {
    base = background;
    has_base = 1;
  }
  // A background with next to no opaque pixels cannot be the window's shape
  // (the skin draws everything in its layers): it cuts nothing out.
  if (has_base) {
    size_t opaque = 0;
    for (int y = 0; y < base.h; y++) {
      for (int x = 0; x < base.w; x++) {
        if (base.image->rgba[((size_t)(base.y + y) * base.image->width +
                              base.x + x) * 4 + 3] != 0) {
          opaque++;
        }
      }
    }
    if (opaque * 50 < (size_t)base.w * base.h) has_base = 0;
  }
  // With an alpha background the layers show beyond the `background`'s shape
  // (a character standing on top of the player): it only takes the mouse.
  if (alpha_given) has_base = 0;
  // The title text the window shows, for the title bar to leave room for:
  // the layout's own (`default` of a `sendparams` on the title), else what
  // The classic player names the window.
  g_title_width = 0;
  {
    const char* title = NULL;
    size_t title_len = 0;
    Element child;
    for (const char* c = layout.body; layout.body && next_element(&c, layout.body_end, &child);) {
      if (!is_element(&child, "sendparams")) continue;
      size_t target_len = 0;
      const char* target = attribute(child.tag, child.tag_end, "target", &target_len);
      for (size_t i = 0; target && i + 19 <= target_len; i++) {
        if (name_equals(target + i, 19, "window.titlebar.tit")) {
          title = attribute(child.tag, child.tag_end, "default", &title_len);
        }
      }
    }
    if (!title) {
      title = attribute_is(layout.tag, layout.tag_end, "id", "normal") &&
                      id_b != NULL
                  ? "Playlist Editor"
                  : id_a[0] == 'e' ? "Equalizer" : "the classic player";
      title_len = strlen(title);
    }
    g_title_width = title_text_width(title, title_len);
  }
  Object o = {&layout, NULL};
  int w = object_int(&o, "w", object_int(&o, "default_w",
                                         has_background ? background.w : 0));
  int h = object_int(&o, "h", object_int(&o, "default_h",
                                         has_background ? background.h : 0));
  // A layout that gives no size and whose background is only a handle
  // (Lithium's drawer) is as big as the groups on it: the skin's script
  // sizes the window to them.
  if (!attribute(layout.tag, layout.tag_end, "w", &length) &&
      !attribute(layout.tag, layout.tag_end, "default_w", &length) &&
      !attribute(layout.tag, layout.tag_end, "h", &length) &&
      !attribute(layout.tag, layout.tag_end, "default_h", &length)) {
    int extent_w = 0, extent_h = 0;
    Element child;
    for (const char* c = layout.body; layout.body &&
                                      next_element(&c, layout.body_end, &child);) {
      if (!is_element(&child, "group")) continue;
      Object g = {&child, NULL};
      if (object_int(&g, "relatw", 0) || object_int(&g, "relath", 0)) continue;
      int gw = object_int(&g, "w", 0), gh = object_int(&g, "h", 0);
      if (gw <= 0 || gh <= 0) continue;
      int gx = object_int(&g, "x", 0), gy = object_int(&g, "y", 0);
      if (gx + gw > extent_w) extent_w = gx + gw;
      if (gy + gh > extent_h) extent_h = gy + gh;
    }
    if (extent_w > w * 4 && extent_h >= h && extent_w <= 4096 && extent_h <= 4096) {
      w = extent_w;
      if (extent_h > h) h = extent_h;
    }
  }
  // A background a fraction of the layout's size is a placeholder (the
  // layers draw the window), not something to stretch over it.
  if (has_background && w > 0 && h > 0 && background.w * 4 < w &&
      background.h * 4 < h) {
    has_background = 0;
    has_base = 0;
  }
  if (w > 0 && h > 0 && w <= 4096 && h <= 4096) {
    out->width = w;
    out->height = h;
    out->rgba = (uint8_t*)calloc((size_t)w * h, 4);
    if (out->rgba) {
      if (has_background) {
        draw_sprite(out, &background, 0, 0, w, h, 255, 0);
      }
      draw_children(wal, out, layout.body, layout.body_end, 0, 0, w, h, 0);
      if (has_base) {
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            int inside = x < base.w && y < base.h &&
                         base.image->rgba[((size_t)(base.y + y) *
                                               base.image->width +
                                           base.x + x) * 4 + 3] != 0;
            if (!inside) {
              memset(out->rgba + ((size_t)y * w + x) * 4, 0, 4);
            }
          }
        }
      }
      // The room a skin keeps under or beside the window for a drawer that
      // is closed is not part of the window (`snapadjustbottom` and
      // `snapadjustright`): the layout is laid out whole, and the window
      // is what is left of it.
      int cut_w = w - object_int(&o, "snapadjustright", 0);
      int cut_h = h - object_int(&o, "snapadjustbottom", 0);
      if (cut_w > 0 && cut_h > 0 && (cut_w < w || cut_h < h)) {
        uint8_t* cropped = (uint8_t*)calloc((size_t)cut_w * cut_h, 4);
        if (cropped) {
          for (int y = 0; y < cut_h; y++) {
            memcpy(cropped + (size_t)y * cut_w * 4, out->rgba + (size_t)y * w * 4,
                   (size_t)cut_w * 4);
          }
          free(out->rgba);
          out->rgba = cropped;
          out->width = cut_w;
          out->height = cut_h;
        }
      }
      result = 0;
    }
  }
  return result;
}

static void trim_transparent(Bitmap* image);

// Whether one color covers nearly all of the window's visible pixels: a
// playlist or equalizer window the layout leaves as a bare fill (its content
// is drawn by the app) is not worth a place in the picture.
static int mostly_flat(const Bitmap* image) {
  size_t count = (size_t)image->width * image->height;
  size_t visible = 0, best = 0;
  uint32_t seen[8];
  size_t seen_count[8];
  int kinds = 0;
  for (size_t i = 0; i < count; i++) {
    const uint8_t* px = image->rgba + i * 4;
    if (px[3] == 0) continue;
    visible++;
    uint32_t key = (uint32_t)(px[0] >> 4) << 8 | (uint32_t)(px[1] >> 4) << 4 |
                   (uint32_t)(px[2] >> 4);
    int k = 0;
    while (k < kinds && seen[k] != key) k++;
    if (k == kinds) {
      if (kinds == 8) continue;
      seen[kinds] = key;
      seen_count[kinds++] = 0;
    }
    if (++seen_count[k] > best) best = seen_count[k];
  }
  // Or hardly anything of it shows: a few widgets in a wide layout, a strip
  // of buttons.
  return visible == 0 || best * 10 >= visible * 9 || visible * 5 < count ||
         image->width < 24 || image->height < 24;
}

// The skin's windows drawn from their layouts: the main window alone, or
// with the equalizer and the playlist editor stacked below it (as the
// classic skins' preview does), each trimmed to what shows and left
// aligned.
static int wal_layout(const uint8_t* zip, size_t size, const SkinXml* xml,
                      const Blob* skin, int stack, Bitmap* out) {
  Text all = {NULL, 0};
  expand_includes(zip, size, xml, "skin.xml", (const char*)skin->data,
                  skin->size, 0, &all);
  if (!all.text) return -1;
  blank_comments(all.text, all.size);
  Wal wal = {zip, size, xml, all.text, all.text + all.size, NULL, 0, NULL, 0};
  Bitmap windows[3];
  memset(windows, 0, sizeof(windows));
  int count = 0;
  if (wal_window(&wal, "main", NULL, &windows[0]) == 0) {
    trim_transparent(&windows[0]);
    count = 1;
    if (stack) {
      const char* ids[2][2] = {{"eq", NULL}, {"pl", "pledit"}};
      for (int i = 0; i < 2; i++) {
        Bitmap* next = &windows[count];
        if (wal_window(&wal, ids[i][0], ids[i][1], next) != 0) continue;
        trim_transparent(next);
        // A window without anything on it is not worth showing.
        if (mostly_flat(next)) {
          free(next->rgba);
          memset(next, 0, sizeof(*next));
          continue;
        }
        count++;
      }
    }
  }
  int result = -1;
  if (count > 0) {
    int width = 0, height = 0;
    for (int i = 0; i < count; i++) {
      if (windows[i].width > width) width = windows[i].width;
      height += windows[i].height;
    }
    out->width = width;
    out->height = height;
    out->rgba = (uint8_t*)calloc((size_t)width * height, 4);
    if (out->rgba) {
      int top = 0;
      for (int i = 0; i < count; i++) {
        for (int y = 0; y < windows[i].height; y++) {
          memcpy(out->rgba + ((size_t)(top + y) * width) * 4,
                 windows[i].rgba + (size_t)y * windows[i].width * 4,
                 (size_t)windows[i].width * 4);
        }
        top += windows[i].height;
      }
      result = 0;
    }
  }
  for (int i = 0; i < 3; i++) free(windows[i].rgba);
  for (int i = 0; i < wal.file_count; i++) {
    free(wal.files[i]->path);
    free(wal.files[i]->image.rgba);
    free(wal.files[i]);
  }
  free(wal.files);
  for (int i = 0; i < wal.tinted_count; i++) {
    free(wal.tinted[i]->rgba);
    free(wal.tinted[i]);
  }
  free(wal.tinted);
  free(all.text);
  return result;
}

// Clears a backdrop baked into a screenshot (Lapis Lazuli's is black, with a
// translucent outer edge): when the corners are translucent and of one
// color, every pixel of about that color connected to the edges becomes
// transparent. Screenshots of rectangular windows have opaque corners and
// are kept as they are.
static void clear_backdrop(Bitmap* image) {
  int w = image->width, h = image->height;
  uint8_t* px = image->rgba;
  const uint8_t* corners[4] = {
      px, px + (size_t)(w - 1) * 4, px + (size_t)(h - 1) * w * 4,
      px + ((size_t)(h - 1) * w + w - 1) * 4};
  for (int i = 0; i < 4; i++) {
    if (corners[i][3] == 255 || memcmp(corners[i], corners[0], 3) != 0) return;
  }
  uint8_t color[3];
  memcpy(color, corners[0], 3);
  int* stack = (int*)malloc(sizeof(int) * (size_t)w * h);
  if (!stack) return;
  int count = 0;
  // Edge pixels first; a cleared pixel has alpha 0 and is not pushed again.
#define PUSH(x, y)                                                          \
  do {                                                                      \
    uint8_t* q = px + ((size_t)(y) * w + (x)) * 4;                          \
    if (q[3] != 0 && abs(q[0] - color[0]) + abs(q[1] - color[1]) +         \
                         abs(q[2] - color[2]) <= 24) {                      \
      q[3] = 0;                                                             \
      stack[count++] = (y) * w + (x);                                       \
    }                                                                       \
  } while (0)
  for (int x = 0; x < w; x++) {
    PUSH(x, 0);
    PUSH(x, h - 1);
  }
  for (int y = 0; y < h; y++) {
    PUSH(0, y);
    PUSH(w - 1, y);
  }
  while (count > 0) {
    int at = stack[--count];
    int x = at % w, y = at / w;
    if (x > 0) PUSH(x - 1, y);
    if (x + 1 < w) PUSH(x + 1, y);
    if (y > 0) PUSH(x, y - 1);
    if (y + 1 < h) PUSH(x, y + 1);
  }
#undef PUSH
  free(stack);
}

// Crops `image` to the pixels that are not fully transparent, as a window
// with a shaped region shows nothing outside them.
static void trim_transparent(Bitmap* image) {
  int w = image->width, h = image->height;
  int left = w, right = -1, top = h, bottom = -1;
  for (int y = 0; y < h; y++) {
    const uint8_t* row = image->rgba + (size_t)y * w * 4;
    for (int x = 0; x < w; x++) {
      if (row[x * 4 + 3] == 0) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < 0) return;  // Nothing shows; keep it as it is.
  int tw = right - left + 1, th = bottom - top + 1;
  if (tw == w && th == h) return;
  for (int y = 0; y < th; y++) {
    memmove(image->rgba + (size_t)y * tw * 4,
            image->rgba + ((size_t)(top + y) * w + left) * 4, (size_t)tw * 4);
  }
  image->width = tw;
  image->height = th;
}

// A Wasabi 3 / Wasabi 5 (.wal) skin: its windows drawn from their layouts,
// or the screenshot its skin.xml names. A screenshot is usually a thumbnail
// of the main window, so the layouts win when they come out much bigger
// than it (and when the skin has a screenshot of its own size, that shows
// what the layouts leave out: text, the visualization). Either is trimmed to
// what shows.
static int render_wal(const uint8_t* zip, size_t size, int layout,
                      SkinPreviewImage* out) {
  SkinXml xml;
  memset(&xml, 0, sizeof(xml));
  xml.depth = 1 << 30;
  zip_each(zip, size, visit_skin_xml, &xml);
  if (xml.depth == 1 << 30) return -1;
  Blob skin = {NULL, 0};
  if (zip_extract(zip, size, xml.central, &skin) != 0) return -1;
  Bitmap image = {0, 0, NULL};
  size_t length;
  const char* text = (const char*)skin.data;
  const char* screenshot = element_text(text, text + skin.size, "screenshot", &length);
  if (!screenshot) {
    screenshot = element_text(text, text + skin.size, "skinshot", &length);
  }
  if (screenshot && length > 0) {
    Blob blob = {NULL, 0};
    if (read_skin_path(zip, size, &xml, screenshot, length, &blob) == 0 &&
        decode_image(&blob, &image) == 0) {
      clear_backdrop(&image);
      trim_transparent(&image);
    }
    free(blob.data);
  }
  int stack = layout == SKIN_PREVIEW_STACK || layout == SKIN_PREVIEW_ICON;
  Bitmap drawn = {0, 0, NULL};
  int has_layout = wal_layout(zip, size, &xml, &skin, stack, &drawn) == 0;
  free(skin.data);
  if (has_layout && (!image.rgba || drawn.width * 2 >= image.width * 3 ||
                     stack)) {
    free(image.rgba);
    image = drawn;
  } else {
    free(drawn.rgba);
  }
  if (!image.rgba) return -1;
  trim_transparent(&image);
  out->width = image.width;
  out->height = image.height;
  out->rgba = image.rgba;
  return 0;
}

// --- Bamp skins ---------------------------------------------------------------

// A Bamp skin (https://github.com/dp-mason/bamp) is a stack of PNG layers
// (00.png ... 37.png, font_and_palette.png). It is turned into the files of
// a classic skin, as the Bamp converter does (bamp_skin.dart): the layers
// are composited in order and their regions copied into the bitmaps.

#define BAMP_W 275
#define BAMP_H 348

typedef struct {
  size_t centrals[BAMP_LAYER_COUNT];
  int depths[BAMP_LAYER_COUNT];
} BampLayers;

static int visit_bamp_layer(const char* name, size_t name_len, size_t central,
                            void* context) {
  BampLayers* found = (BampLayers*)context;
  size_t base;
  int depth = path_depth(name, name_len, &base);
  if (is_junk(name, name_len, base)) return 0;
  for (int i = 0; i < BAMP_LAYER_COUNT; i++) {
    if (name_equals(name + base, name_len - base, kBampLayers[i]) &&
        depth < found->depths[i]) {
      found->depths[i] = depth;
      found->centrals[i] = central;
    }
  }
  return 0;
}

// Encodes the top `rows` rows of the w-wide RGB image as a 24-bit BMP.
static int rgb_to_bmp(const uint8_t* rgb, int w, int rows, Blob* out) {
  size_t stride = ((size_t)w * 3 + 3) & ~(size_t)3;
  size_t total = 54 + stride * rows;
  uint8_t* d = (uint8_t*)calloc(total, 1);
  if (!d) return -1;
  d[0] = 'B';
  d[1] = 'M';
  uint32_t fields[][2] = {{2, (uint32_t)total}, {10, 54}, {14, 40},
                          {18, (uint32_t)w}, {22, (uint32_t)rows},
                          {34, (uint32_t)(stride * rows)}};
  for (int i = 0; i < 6; i++) {
    for (int b = 0; b < 4; b++) d[fields[i][0] + b] = (uint8_t)(fields[i][1] >> (8 * b));
  }
  d[26] = 1;
  d[28] = 24;
  for (int y = 0; y < rows; y++) {
    uint8_t* row = d + 54 + (size_t)(rows - 1 - y) * stride;
    for (int x = 0; x < w; x++) {
      const uint8_t* px = rgb + ((size_t)y * w + x) * 3;
      row[x * 3] = px[2];
      row[x * 3 + 1] = px[1];
      row[x * 3 + 2] = px[0];
    }
  }
  out->data = d;
  out->size = total;
  return 0;
}

// Fills `files` (bitmaps and pledit.txt) from a Bamp skin. Returns nonzero
// when `zip` holds no Bamp skin (it needs 00.png and font_and_palette.png).
static int read_bamp(const uint8_t* zip, size_t size, Blob files[F_COUNT]) {
  BampLayers found;
  for (int i = 0; i < BAMP_LAYER_COUNT; i++) found.depths[i] = 1 << 30;
  if (zip_each(zip, size, visit_bamp_layer, &found) != 0) return -1;
  int palette = BAMP_LAYER_COUNT - 1;
  if (found.depths[0] == 1 << 30 || found.depths[palette] == 1 << 30) return -1;

  uint8_t* out[F_BITMAPS];
  int rows[F_BITMAPS];
  int ok = 1;
  for (int f = 0; f < F_BITMAPS; f++) {
    rows[f] = kBampSizes[f][1];
    out[f] = (uint8_t*)malloc((size_t)kBampSizes[f][0] * kBampSizes[f][1] * 3);
    if (!out[f]) { ok = 0; continue; }
    for (size_t i = 0; i < (size_t)kBampSizes[f][0] * kBampSizes[f][1]; i++) {
      out[f][i * 3] = 255;
      out[f][i * 3 + 1] = 0;
      out[f][i * 3 + 2] = 255;
    }
  }
  uint8_t* stack = (uint8_t*)malloc((size_t)BAMP_W * BAMP_H * 4);
  if (!stack || !ok) {
    free(stack);
    for (int f = 0; f < F_BITMAPS; f++) free(out[f]);
    return -1;
  }
  int first = 1;
  size_t map = 0;
  const size_t map_count = sizeof(kBampMaps) / sizeof(kBampMaps[0]);
  for (int layer = 0; layer < BAMP_LAYER_COUNT; layer++) {
    Bitmap image = {0, 0, NULL};
    Blob blob = {NULL, 0};
    if (found.depths[layer] != 1 << 30 &&
        zip_extract(zip, size, found.centrals[layer], &blob) == 0) {
      if (decode_png(&blob, &image) != 0) image.rgba = NULL;
    }
    free(blob.data);
    int w = image.width < BAMP_W ? image.width : BAMP_W;
    int h = image.height < BAMP_H ? image.height : BAMP_H;
    if (!image.rgba) w = h = 0;
    if (first) {
      // Partial transparency becomes opaque, full transparency magenta.
      for (int y = 0; y < BAMP_H; y++) {
        for (int x = 0; x < BAMP_W; x++) {
          uint8_t* d = stack + ((size_t)y * BAMP_W + x) * 4;
          const uint8_t* s = x < w && y < h ? image.rgba + ((size_t)y * image.width + x) * 4 : NULL;
          if (s && s[3]) {
            memcpy(d, s, 3);
          } else {
            d[0] = 255;
            d[1] = 0;
            d[2] = 255;
          }
          d[3] = 255;
        }
      }
      first = 0;
    } else {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          const uint8_t* s = image.rgba + ((size_t)y * image.width + x) * 4;
          uint8_t* d = stack + ((size_t)y * BAMP_W + x) * 4;
          if (!s[3]) continue;
          for (int c = 0; c < 3; c++) {
            d[c] = (uint8_t)((s[c] * s[3] + d[c] * (255 - s[3]) + 127) / 255);
          }
        }
      }
    }
    for (; map < map_count && kBampMaps[map].layer == layer; map++) {
      const BampMap* m = &kBampMaps[map];
      if (m->flags & 1) {
        // A handle the artist left transparent is not drawn at all.
        int clear = 1;
        for (int y = m->y0; y < m->y1 && clear; y++) {
          for (int x = m->x0; x < m->x1; x++) {
            if (x < w && y < h && image.rgba[((size_t)y * image.width + x) * 4 + 3]) {
              clear = 0;
              break;
            }
          }
        }
        if (clear) {
          rows[m->file] = kBampSizes[m->file][2];
          continue;
        }
      }
      int scale = (m->flags & 2) ? 4 : 1;
      int dw = kBampSizes[m->file][0], dh = kBampSizes[m->file][1];
      for (int y = 0; y < (m->y1 - m->y0) / scale; y++) {
        for (int x = 0; x < (m->x1 - m->x0) / scale; x++) {
          int ox = m->dx + x, oy = m->dy + y;
          if (ox < 0 || oy < 0 || ox >= dw || oy >= dh) continue;
          unsigned sum[3] = {0, 0, 0};
          unsigned n = 0;
          for (int by = 0; by < scale; by++) {
            for (int bx = 0; bx < scale; bx++) {
              int sx = m->x0 + x * scale + bx, sy = m->y0 + y * scale + by;
              if (sx < 0 || sy < 0 || sx >= BAMP_W || sy >= BAMP_H) continue;
              const uint8_t* s = stack + ((size_t)sy * BAMP_W + sx) * 4;
              sum[0] += s[0];
              sum[1] += s[1];
              sum[2] += s[2];
              n++;
            }
          }
          if (!n) continue;
          uint8_t* d = out[m->file] + ((size_t)oy * dw + ox) * 3;
          d[0] = (uint8_t)(sum[0] / n);
          d[1] = (uint8_t)(sum[1] / n);
          d[2] = (uint8_t)(sum[2] / n);
        }
      }
    }
    free(image.rgba);
  }

  for (int f = 0; f < F_BITMAPS; f++) {
    rgb_to_bmp(out[f], kBampSizes[f][0], rows[f], &files[f]);
    free(out[f]);
  }
  // The playlist's background is the third swatch of the palette
  // (PLEDIT_START 125,80; 12 pixels each; sampled at the centre).
  const uint8_t* bg = stack + ((size_t)(80 + 6 + 12 * 2) * BAMP_W + 125 + 6) * 4;
  char text[64];
  int n = snprintf(text, sizeof(text), "[Text]\nNormalBG=#%02X%02X%02X\n", bg[0], bg[1], bg[2]);
  files[F_PLEDIT_TXT].data = (uint8_t*)malloc((size_t)n);
  if (files[F_PLEDIT_TXT].data) {
    memcpy(files[F_PLEDIT_TXT].data, text, (size_t)n);
    files[F_PLEDIT_TXT].size = (size_t)n;
  }
  free(stack);
  return 0;
}

// --- Rendering ---------------------------------------------------------------

// A skin made to be drawn over video has windows of the overlay color
// (#100010, as the app's isOverlayBitmap): it shows what is behind it.
static int is_overlay_pixel(const uint8_t* px) {
  return px[0] == 0x10 && px[1] == 0x00 && px[2] == 0x10;
}

static int is_overlay_skin(const Bitmap* main) {
  if (!main->rgba) return 0;
  size_t count = (size_t)main->width * main->height, overlay = 0;
  for (size_t i = 0; i < count; i++) {
    if (is_overlay_pixel(main->rgba + i * 4)) overlay++;
  }
  return overlay * 2 >= count;
}

static void clear_overlay(SkinPreviewImage* image) {
  size_t count = (size_t)image->width * image->height;
  for (size_t i = 0; i < count; i++) {
    uint8_t* px = image->rgba + i * 4;
    if (is_overlay_pixel(px)) px[3] = 0;
  }
}

// Whether `zip` ends with the record that closes a zip archive.
static int has_zip_end(const uint8_t* zip, size_t size) {
  if (size < 22) return 0;
  size_t eocd = size - 22;
  size_t stop = size > 22 + 0xffff ? size - 22 - 0xffff : 0;
  while (le32(zip + eocd) != 0x06054b50) {
    if (eocd == stop) return 0;
    eocd--;
  }
  return 1;
}

// A copy of the archive `zip`, which was cut short and lost the end (the
// directory of its files, or part of it), with a directory built from the
// header in front of each file's data. Returns NULL when there is nothing
// to recover. Free with free().
static uint8_t* repair_zip(const uint8_t* zip, size_t size, size_t* fixed_size) {
  size_t end = 0, entries = 0, names = 0;
  while (end + 30 <= size && le32(zip + end) == 0x04034b50) {
    // Sizes that follow the data cannot be found without the directory.
    if (le16(zip + end + 6) & 8) break;
    size_t name_len = le16(zip + end + 26);
    size_t next = end + 30 + name_len + le16(zip + end + 28) + le32(zip + end + 18);
    if (next > size) break;
    names += name_len;
    entries++;
    end = next;
  }
  if (entries == 0 || entries > 0xffff) return NULL;
  size_t central = entries * 46 + names;
  uint8_t* fixed = (uint8_t*)calloc(end + central + 22, 1);
  if (!fixed) return NULL;
  memcpy(fixed, zip, end);
  size_t local = 0, at = end;
  for (size_t e = 0; e < entries; e++) {
    size_t name_len = le16(zip + local + 26);
    uint8_t* record = fixed + at;
    memcpy(record, "PK\1\2", 4);
    memcpy(record + 6, zip + local + 4, 2);  // Version needed.
    memcpy(record + 8, zip + local + 6, 2);    // Flags.
    memcpy(record + 10, zip + local + 8, 2);   // Method.
    memcpy(record + 16, zip + local + 14, 4);  // CRC-32.
    memcpy(record + 20, zip + local + 18, 4);  // Packed size.
    memcpy(record + 24, zip + local + 22, 4);  // Unpacked size.
    record[28] = (uint8_t)name_len;
    record[29] = (uint8_t)(name_len >> 8);
    record[30] = record[31] = record[32] = record[33] = 0;
    for (int b = 0; b < 4; b++) record[42 + b] = (uint8_t)(local >> (8 * b));
    memcpy(record + 46, zip + local + 30, name_len);
    at += 46 + name_len;
    local += 30 + name_len + le16(zip + local + 28) + le32(zip + local + 18);
  }
  uint8_t* tail = fixed + at;
  memcpy(tail, "PK\5\6", 4);
  tail[8] = tail[10] = (uint8_t)entries;
  tail[9] = tail[11] = (uint8_t)(entries >> 8);
  for (int b = 0; b < 4; b++) {
    tail[12 + b] = (uint8_t)(central >> (8 * b));
    tail[16 + b] = (uint8_t)(end >> (8 * b));
  }
  *fixed_size = at + 22;
  return fixed;
}

static int render_zip(const uint8_t* wsz, size_t size, const char* title,
                      int layout, SkinPreviewImage* out);

int skin_preview_render(const uint8_t* wsz, size_t size, const char* title,
                        int layout, SkinPreviewImage* out) {
  if (has_zip_end(wsz, size)) return render_zip(wsz, size, title, layout, out);
  size_t fixed_size = 0;
  uint8_t* fixed = repair_zip(wsz, size, &fixed_size);
  if (!fixed) return render_zip(wsz, size, title, layout, out);
  int result = render_zip(fixed, fixed_size, title, layout, out);
  free(fixed);
  return result;
}

static int render_zip(const uint8_t* wsz, size_t size, const char* title,
                      int layout, SkinPreviewImage* out) {
  Blob files[F_COUNT];
  memset(files, 0, sizeof(files));
  memset(out, 0, sizeof(*out));
  // Another format may stand in for a BMP, unless the skin is a Wasabi 3 one (its
  // skin.xml names its images).
  SkinXml xml;
  memset(&xml, 0, sizeof(xml));
  xml.depth = 1 << 30;
  zip_each(wsz, size, visit_skin_xml, &xml);
  int found = read_zip(wsz, size, files, xml.depth == 1 << 30);
  int result = -1;
  Painter p;
  memset(&p, 0, sizeof(p));
  if (found < 0) goto done;
  // A Bamp skin becomes the files of a classic one.
  if (!files[F_MAIN].data && read_bamp(wsz, size, files) == 0) {
    // drawn like any classic skin
  } else if (!files[F_MAIN].data) {
    // Wasabi 3 (.wal) skins are zips too, under the same file type.
    result = render_wal(wsz, size, layout, out);
    goto done;
  }

  // A missing or broken bitmap falls back to the base skin's.
  Blob base[F_COUNT];
  memset(base, 0, sizeof(base));
  read_zip(kBaseSkin, kBaseSkinSize, base, 0);
  // A skin without its own balance.bmp draws the balance slider from its
  // volume.bmp (skin_loader.dart).
  if (!files[F_BALANCE].data && files[F_VOLUME].data) {
    files[F_BALANCE].data = (uint8_t*)malloc(files[F_VOLUME].size);
    if (files[F_BALANCE].data) {
      memcpy(files[F_BALANCE].data, files[F_VOLUME].data, files[F_VOLUME].size);
      files[F_BALANCE].size = files[F_VOLUME].size;
    }
  }
  for (int i = 0; i < F_BITMAPS; i++) {
    if (files[i].data && decode_image(&files[i], &p.bitmaps[i]) == 0) continue;
    if (base[i].data) decode_bmp(&base[i], &p.bitmaps[i]);
  }
  for (int i = 0; i < F_COUNT; i++) free(base[i].data);
  parse_list_bg(&files[F_PLEDIT_TXT], p.list_bg);

  int stacked = layout == SKIN_PREVIEW_STACK || layout == SKIN_PREVIEW_ICON;
  int playlist = layout == SKIN_PREVIEW_ICON ? 116 : 232;
  // An Audacious skin may give the main window a size of its own
  // (skin.hints); its controls are placed by the hints, so it is drawn as its
  // main.bmp alone.
  int main_w = hint_value(&files[F_HINTS_TXT], "mainwinWidth");
  int main_h = hint_value(&files[F_HINTS_TXT], "mainwinHeight");
  int hinted = main_w > 0 && main_h > 0 && (main_w != 275 || main_h != 116);
  if (!hinted) {
    main_w = 275;
    main_h = 116;
  }
  p.canvas.width = main_w > 275 ? main_w : 275;
  p.canvas.height = stacked ? main_h + 116 + playlist : main_h;
  p.canvas.rgba = (uint8_t*)calloc((size_t)p.canvas.width * p.canvas.height, 4);
  if (!p.canvas.rgba) goto done;

  Region region;
  if (hinted) {
    blit(&p, F_MAIN, 0, 0, main_w, main_h, 0, 0);
  } else {
    draw_main(&p, title, stacked);
  }
  if (parse_region(&files[F_REGION_TXT], "normal", &region) == 0) {
    apply_region(&p, &region, main_w, main_h);
    free_region(&region);
  }
  if (stacked) {
    p.top = main_h;
    draw_eq(&p);
    if (parse_region(&files[F_REGION_TXT], "equalizer", &region) == 0) {
      apply_region(&p, &region, 275, 116);
      free_region(&region);
    }
    p.top = main_h + 116;
    draw_playlist(&p, 275, playlist);
  }
  if (is_overlay_skin(&p.bitmaps[F_MAIN])) clear_overlay(&p.canvas);
  *out = p.canvas;
  result = 0;

done:
  for (int i = 0; i < F_COUNT; i++) free(files[i].data);
  for (int i = 0; i < F_BITMAPS; i++) free(p.bitmaps[i].rgba);
  return result;
}

int skin_preview_render_file(const char* path, const char* title, int layout,
                             SkinPreviewImage* out) {
  Blob blob = {NULL, 0};
  memset(out, 0, sizeof(*out));
  if (read_file(path, &blob) != 0) return -1;
  int result = skin_preview_render(blob.data, blob.size, title, layout, out);
  free(blob.data);
  return result;
}

// Area-averages `image` down to `ow` x `oh`, in premultiplied space so
// transparent pixels add no color.
static int shrink(const SkinPreviewImage* image, int ow, int oh,
                  SkinPreviewImage* out) {
  int w = image->width, h = image->height;
  out->rgba = (uint8_t*)malloc((size_t)ow * oh * 4);
  if (!out->rgba) return -1;
  out->width = ow;
  out->height = oh;
  for (int y = 0; y < oh; y++) {
    int y0 = (int)((long long)y * h / oh);
    int y1 = (int)((long long)(y + 1) * h / oh);
    if (y1 <= y0) y1 = y0 + 1;
    for (int x = 0; x < ow; x++) {
      int x0 = (int)((long long)x * w / ow);
      int x1 = (int)((long long)(x + 1) * w / ow);
      if (x1 <= x0) x1 = x0 + 1;
      unsigned long sum[4] = {0, 0, 0, 0};
      for (int sy = y0; sy < y1; sy++) {
        for (int sx = x0; sx < x1; sx++) {
          const uint8_t* px = image->rgba + ((size_t)sy * w + sx) * 4;
          sum[0] += px[0] * px[3];
          sum[1] += px[1] * px[3];
          sum[2] += px[2] * px[3];
          sum[3] += px[3];
        }
      }
      unsigned long count = (unsigned long)(x1 - x0) * (y1 - y0);
      uint8_t* dst = out->rgba + ((size_t)y * ow + x) * 4;
      dst[3] = (uint8_t)(sum[3] / count);
      for (int c = 0; c < 3; c++) {
        dst[c] = sum[3] ? (uint8_t)(sum[c] / sum[3]) : 0;
      }
    }
  }
  return 0;
}

int skin_preview_fit(const SkinPreviewImage* image, int max_size,
                     SkinPreviewImage* out) {
  memset(out, 0, sizeof(*out));
  int w = image->width, h = image->height;
  int longest = w > h ? w : h;
  if (max_size <= 0 || longest <= 0) return -1;
  int ow = (int)((long long)w * max_size / longest);
  int oh = (int)((long long)h * max_size / longest);
  if (ow < 1) ow = 1;
  if (oh < 1) oh = 1;
  if (longest >= max_size) return shrink(image, ow, oh, out);
  // Repeat each pixel `factor` times, then shrink the rest of the way.
  int factor = (max_size + longest - 1) / longest;
  SkinPreviewImage big;
  big.width = w * factor;
  big.height = h * factor;
  big.rgba = (uint8_t*)malloc((size_t)big.width * big.height * 4);
  if (!big.rgba) return -1;
  for (int y = 0; y < big.height; y++) {
    const uint8_t* src = image->rgba + (size_t)(y / factor) * w * 4;
    uint8_t* dst = big.rgba + (size_t)y * big.width * 4;
    for (int x = 0; x < big.width; x++) memcpy(dst + x * 4, src + (x / factor) * 4, 4);
  }
  if (big.width == ow && big.height == oh) {
    *out = big;
    return 0;
  }
  int result = shrink(&big, ow, oh, out);
  free(big.rgba);
  return result;
}

// --- PNG ---------------------------------------------------------------------

static uint32_t crc32(const uint8_t* data, size_t size) {
  uint32_t crc = 0xffffffffu;
  for (size_t i = 0; i < size; i++) {
    crc ^= data[i];
    for (int k = 0; k < 8; k++) crc = crc & 1 ? 0xedb88320u ^ (crc >> 1) : crc >> 1;
  }
  return ~crc;
}

static uint8_t* put32(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
  return p + 4;
}

static uint8_t* chunk(uint8_t* p, const char* type, const uint8_t* data,
                      size_t size) {
  p = put32(p, (uint32_t)size);
  uint8_t* start = p;
  memcpy(p, type, 4);
  p += 4;
  if (size) memcpy(p, data, size);
  p += size;
  return put32(p, crc32(start, size + 4));
}

// Stores the pixels uncompressed in zlib "stored" blocks: previews are small
// and written once, so size matters less than keeping this short.
int skin_preview_encode_png(const SkinPreviewImage* image, uint8_t** png,
                            size_t* png_size) {
  size_t row = (size_t)image->width * 4 + 1;
  size_t raw_size = row * image->height;
  uint8_t* raw = (uint8_t*)malloc(raw_size);
  if (!raw) return -1;
  for (int y = 0; y < image->height; y++) {
    raw[y * row] = 0;
    memcpy(raw + y * row + 1, image->rgba + (size_t)y * image->width * 4, row - 1);
  }
  size_t blocks = raw_size / 65535 + 1;
  size_t zsize = 2 + raw_size + blocks * 5 + 4;
  uint8_t* z = (uint8_t*)malloc(zsize);
  uint8_t* out = (uint8_t*)malloc(8 + 25 + 12 + zsize + 12);
  if (!z || !out) {
    free(raw);
    free(z);
    free(out);
    return -1;
  }
  uint8_t* q = z;
  *q++ = 0x78;
  *q++ = 0x01;
  size_t at = 0;
  uint32_t a = 1, b = 0;
  do {
    size_t n = raw_size - at < 65535 ? raw_size - at : 65535;
    *q++ = at + n == raw_size ? 1 : 0;
    *q++ = (uint8_t)n;
    *q++ = (uint8_t)(n >> 8);
    *q++ = (uint8_t)~n;
    *q++ = (uint8_t)(~n >> 8);
    memcpy(q, raw + at, n);
    for (size_t i = 0; i < n; i++) {
      a = (a + raw[at + i]) % 65521;
      b = (b + a) % 65521;
    }
    q += n;
    at += n;
  } while (at < raw_size);
  q = put32(q, b << 16 | a);

  uint8_t header[13];
  put32(header, (uint32_t)image->width);
  put32(header + 4, (uint32_t)image->height);
  header[8] = 8;   // Bit depth.
  header[9] = 6;   // RGBA.
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;
  static const uint8_t kSignature[8] = {137, 'P', 'N', 'G', '\r', '\n', 26, '\n'};
  uint8_t* p = out;
  memcpy(p, kSignature, 8);
  p = chunk(p + 8, "IHDR", header, 13);
  p = chunk(p, "IDAT", z, (size_t)(q - z));
  p = chunk(p, "IEND", NULL, 0);
  free(raw);
  free(z);
  *png = out;
  *png_size = (size_t)(p - out);
  return 0;
}

void skin_preview_free(SkinPreviewImage* image) {
  free(image->rgba);
  image->rgba = NULL;
  image->width = image->height = 0;
}
