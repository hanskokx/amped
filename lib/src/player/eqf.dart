import "dart:convert";
import "dart:typed_data";

import "equalizer.dart";

/// Winamp EQ library files (`.eqf`, `.q1`): a signature, then records of a
/// 257-byte NUL-padded name, the 10 band values and the preamp
/// (`readEQfile`/`writeEQfile` in Eq.cpp).
abstract final class Eqf {
  static const String _signature = "Winamp EQ library file v1.1\x1A!--";
  static const int _nameLength = 257;
  static const int _recordLength = _nameLength + 10 + 1;

  /// The preset named [name] (case-insensitively) in [bytes] as slider
  /// values, or `null` when the file is not an EQ library or lacks it.
  static ({int preamp, List<int> bands})? read(
    Uint8List bytes, {
    String name = "Entry1",
  }) {
    final signature = latin1.encode(_signature);
    if (bytes.length < signature.length) return null;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    for (
      var offset = signature.length;
      offset + _recordLength <= bytes.length;
      offset += _recordLength
    ) {
      final nameBytes = bytes.sublist(offset, offset + _nameLength);
      final end = nameBytes.indexOf(0);
      final entry = latin1.decode(
        end < 0 ? nameBytes : nameBytes.sublist(0, end),
      );
      if (entry.toLowerCase() != name.toLowerCase()) continue;
      final values = bytes.sublist(
        offset + _nameLength,
        offset + _recordLength,
      );
      return (
        preamp: values[10].clamp(0, 63),
        bands: [for (final v in values.take(10)) v.clamp(0, 63)],
      );
    }
    return null;
  }

  /// A one-preset EQ library holding [preamp] and [bands] (slider values)
  /// as [name], as "Save > To EQF..." writes it.
  static Uint8List write({
    required int preamp,
    required List<int> bands,
    String name = "Entry1",
  }) {
    final signature = latin1.encode(_signature);
    final bytes = Uint8List(signature.length + _recordLength)
      ..setAll(0, signature);
    final nameBytes = latin1.encode(name);
    bytes.setAll(
      signature.length,
      nameBytes.take(_nameLength - 1),
    );
    final values = signature.length + _nameLength;
    for (var i = 0; i < 10; i++) {
      bytes[values + i] = (i < bands.length ? bands[i] : Equalizer.neutral)
          .clamp(0, 63);
    }
    bytes[values + 10] = preamp.clamp(0, 63);
    return bytes;
  }
}
