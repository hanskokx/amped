/// Bamp skin support for amped.
///
/// Bamp skins are zips of PNG layers. `BampSkinFormat` converts those layers
/// into the bitmaps of a classic skin; the archive decoding and rendering stay
/// in `amped_classic_skin`.
library;

export "src/bamp_format.dart";
export "src/bamp_skin.dart";
