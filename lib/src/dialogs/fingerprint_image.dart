import "dart:typed_data";

import "package:chromaprint_dart/chromaprint_dart.dart";
import "package:material_ui/material_ui.dart";

/// The fingerprint a raw tag item holds, or null if it holds none: Vorbis
/// and APE `ACOUSTID_FINGERPRINT`, ID3 `TXXX` "Acoustid Fingerprint" (read
/// as "Acoustid Fingerprint: <value>"), MP4 `----:...:Acoustid Fingerprint`.
String? fingerprintOfTagEntry(String name, String value) {
  final lower = name.toLowerCase();
  if (lower == "acoustid_fingerprint" ||
      lower.endsWith(":acoustid fingerprint")) {
    return value.trim();
  }
  const prefix = "acoustid fingerprint: ";
  if (lower == "txxx" && value.toLowerCase().startsWith(prefix)) {
    return value.substring(prefix.length).trim();
  }
  return null;
}

/// A PNG of [fingerprint] from `Fingerprint.png`, or null if it doesn't
/// decode.
Uint8List? fingerprintPngOrNull(String fingerprint) {
  if (fingerprint.isEmpty) return null;
  try {
    final decoded = Fingerprint(fingerprint);
    return decoded.raw.isEmpty ? null : decoded.png;
  } on FormatException {
    return null;
  }
}

/// A fingerprint image from `Fingerprint.png`, stretched to the width it's
/// given and 64 pixels high (2 per bit, as acoustid.org shows it),
/// unsmoothed so each bit stays a crisp block.
class FingerprintImage extends StatelessWidget {
  const FingerprintImage({
    required this.png,
    required this.semanticLabel,
    super.key,
  });

  final Uint8List png;

  /// Read out instead of the picture: the fingerprint's text.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Image.memory(
    png,
    semanticLabel: semanticLabel,
    width: double.infinity,
    height: 64,
    fit: BoxFit.fill,
    filterQuality: FilterQuality.none,
    gaplessPlayback: true,
  );
}
