import "dart:ffi";

import "package:ffi/ffi.dart";

/// `SkinPreviewImage`: straight RGBA, 4 bytes a pixel, rows top-down.
final class SkinPreviewImage extends Struct {
  @Int32()
  external int width;

  @Int32()
  external int height;

  external Pointer<Uint8> rgba;
}

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Pointer<Utf8>,
    Int32,
    Pointer<SkinPreviewImage>,
  )
>(symbol: "skin_preview_render")
external int skinPreviewRender(
  Pointer<Uint8> archive,
  int size,
  Pointer<Utf8> title,
  int layout,
  Pointer<SkinPreviewImage> out,
);

@Native<
  Int32 Function(
    Pointer<SkinPreviewImage>,
    Int32,
    Pointer<SkinPreviewImage>,
  )
>(symbol: "skin_preview_fit")
external int skinPreviewFit(
  Pointer<SkinPreviewImage> image,
  int maxSize,
  Pointer<SkinPreviewImage> out,
);

@Native<Void Function(Pointer<SkinPreviewImage>)>(symbol: "skin_preview_free")
external void skinPreviewFree(Pointer<SkinPreviewImage> image);
