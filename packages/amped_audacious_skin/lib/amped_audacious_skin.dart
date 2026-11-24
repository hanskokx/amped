/// Audacious skin support for amped.
///
/// Audacious skins arrive as tarballs and may use PNG or JPEG bitmaps and a
/// `skin.hints` file. This package turns those into the classic file set that
/// `amped_classic_skin` renders.
library;

export "src/audacious_converter.dart";
export "src/audacious_decoder.dart";
export "src/skin_hints_parser.dart";
