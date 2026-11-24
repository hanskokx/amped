import "dart:typed_data";

import "package:amped_skin/amped_skin.dart";
import "package:archive/archive.dart";

import "classic_skin_data.dart";

/// Opens one kind of skin archive.
///
/// A package that supports a container (for example Audacious tarballs)
/// implements this and is handed to [SkinFormats]. Zip decoding is built in,
/// so only other containers need a decoder.
abstract interface class SkinArchiveDecoder {
  /// The file types this decoder opens.
  Set<SkinFileType> get fileTypes;

  /// The family of skin this decoder produces, when no converter claims it.
  SkinFormat get format;

  /// Decodes [bytes], or returns null when they are not this container.
  Archive? tryDecode(Uint8List bytes);
}

/// Converts the files of a foreign skin into a classic skin's file set.
///
/// Bamp and Audacious skins are both converted this way, so everything
/// downstream of the conversion only ever sees classic bitmaps.
abstract interface class SkinFileConverter {
  /// The family of skin this converter produces.
  SkinFormat get format;

  /// Whether [names] (lower-case file names) are this kind of skin.
  ///
  /// Installed skins keep only the names after conversion, so detection has
  /// to work from names alone as well as from an archive's bytes.
  bool appliesToNames(Set<String> names);

  /// Whether [files] (keyed by lower-case file name) are this kind of skin.
  ///
  /// Converters that only look at names can delegate to [appliesToNames].
  bool appliesTo(Map<String, List<int>> files);

  /// Returns [files] converted to a classic skin's file set.
  Future<Map<String, List<int>>> convert(Map<String, List<int>> files);

  /// Layout hints the skin carries, or null when it has none.
  SkinHints? hints(Map<String, List<int>> files);
}

/// The result of opening a skin archive: its converted files and metadata.
class SkinArchiveContents {
  const SkinArchiveContents({
    required this.archive,
    required this.files,
    required this.format,
    required this.hints,
    this.displayName,
  });

  /// The decoded archive, for writing the skin's files to disk.
  final Archive archive;

  /// Skin files keyed by lower-case name, after conversion.
  final Map<String, List<int>> files;

  /// The archive's declared display name, when it has one.
  final String? displayName;

  /// The family the archive belongs to.
  final SkinFormat format;

  /// Layout hints from the skin, or empty when it carries none.
  final SkinHints hints;
}

/// The skin formats the app knows about.
///
/// Classic zip skins work with the empty instance. A composition root adds
/// decoders and converters from the other skin packages, and passes the same
/// object to the loaders and registry so every step treats a skin alike.
class SkinFormats {
  const SkinFormats({this.decoders = const [], this.converters = const []});

  /// Decoders for archives that are not zips.
  final Iterable<SkinArchiveDecoder> decoders;

  /// Converters for foreign skin file sets, tried in order.
  final Iterable<SkinFileConverter> converters;

  /// All archive containers this set of formats can open.
  Iterable<SkinFileType> get fileTypes => [
    SkinFileType.zip,
    ...decoders.expand((decoder) => decoder.fileTypes),
  ];

  /// Whether [fileName] looks like one of the supported skin archives.
  bool matchesFile(String fileName) =>
      fileTypes.any((fileType) => fileType.matches(fileName));

  /// The decoder that claims [bytes], or null when they are a zip.
  SkinArchiveDecoder? decoderFor(Uint8List bytes) {
    for (final decoder in decoders) {
      if (decoder.tryDecode(bytes) != null) return decoder;
    }
    return null;
  }

  /// Opens [bytes] as a skin archive.
  ///
  /// Throws a [FormatException] when no decoder recognises the bytes.
  Archive decode(Uint8List bytes) {
    for (final decoder in decoders) {
      final archive = decoder.tryDecode(bytes);
      if (archive != null) return archive;
    }
    if (_startsWith(bytes, const [0x50, 0x4B])) {
      try {
        return ZipDecoder().decodeBytes(bytes, verify: false);
      } on Object {
        // fall through to the error below
      }
    }
    throw const FormatException("Not a skin archive");
  }

  /// Converts [files] with the first converter that claims them.
  Future<Map<String, List<int>>> convert(
    Map<String, List<int>> files,
  ) async {
    for (final converter in converters) {
      if (converter.appliesTo(files)) return converter.convert(files);
    }
    return files;
  }

  /// The layout hints [files] carry, or empty hints when none apply.
  SkinHints hints(Map<String, List<int>> files) {
    for (final converter in converters) {
      final hints = converter.hints(files);
      if (hints != null) return hints;
    }
    return const SkinHints();
  }

  /// The family [files] belong to, falling back to [fallback] when no
  /// converter claims them.
  SkinFormat identify(Map<String, List<int>> files, SkinFormat fallback) =>
      identifyNames(files.keys, fallback);

  /// The family [fileNames] belong to, falling back to [fallback] when no
  /// converter claims them.
  ///
  /// Names are matched case-insensitively; folders copied in by hand need
  /// this because their archive is long gone.
  SkinFormat identifyNames(
    Iterable<String> fileNames,
    SkinFormat fallback,
  ) {
    final names = {for (final name in fileNames) name.toLowerCase()};
    for (final converter in converters) {
      if (converter.appliesToNames(names)) return converter.format;
    }
    return fallback;
  }
}

bool _startsWith(List<int> bytes, List<int> magic) =>
    bytes.length >= magic.length &&
    [for (var i = 0; i < magic.length; i++) bytes[i] == magic[i]].every(
      (same) => same,
    );
