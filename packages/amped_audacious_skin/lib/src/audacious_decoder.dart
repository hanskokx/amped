import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";

/// Opens the tarballs Audacious skins are distributed as.
///
/// The container is told from the bytes, not the file name. Zip archives are
/// left to the classic decoder in [SkinFormats].
final class AudaciousSkinDecoder implements SkinArchiveDecoder {
  const AudaciousSkinDecoder();

  @override
  Set<SkinFileType> get fileTypes => const {
    SkinFileType.tar,
    SkinFileType.tarGz,
    SkinFileType.tarBz2,
  };

  @override
  SkinFormat get format => SkinFormat.audacious;

  @override
  Archive? tryDecode(Uint8List bytes) {
    try {
      if (_startsWith(bytes, const [0x1F, 0x8B])) {
        return TarDecoder().decodeBytes(
          const GZipDecoder().decodeBytes(bytes),
        );
      }
      if (_startsWith(bytes, const [0x42, 0x5A, 0x68])) {
        return TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
      }
      // A plain tar has "ustar" at offset 257.
      if (bytes.length > 262 &&
          String.fromCharCodes(bytes.sublist(257, 262)) == "ustar") {
        return TarDecoder().decodeBytes(bytes);
      }
    } on Object {
      // Not a readable tarball after all.
    }
    return null;
  }
}

bool _startsWith(List<int> bytes, List<int> magic) =>
    bytes.length >= magic.length &&
    [for (var i = 0; i < magic.length; i++) bytes[i] == magic[i]].every(
      (same) => same,
    );
