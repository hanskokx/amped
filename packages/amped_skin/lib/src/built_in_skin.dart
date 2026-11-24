import "dart:typed_data";

import "skin_format.dart";

/// A skin shipped with the app, discovered by a skin package's asset loader.
///
/// Keeping the [format] alongside the archive bytes means the composition
/// root does not have to guess which family an asset belongs to after its
/// bytes have been converted to a classic file set.
class BuiltInSkin {
  const BuiltInSkin({required this.bytes, required this.format});

  /// The archive bytes, read from the application's asset bundle.
  final Uint8List bytes;

  /// The skin family the archive belongs to.
  final SkinFormat format;
}
