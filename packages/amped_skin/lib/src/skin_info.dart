import "dart:io";

import "skin_format.dart";

/// Describes an installed skin.
///
/// The bundled base skin has a null [directory]; imported skins point at the
/// directory their extracted files live in. The [format] records which skin
/// package the artwork came from, even after its files were converted into a
/// classic file set.
class SkinInfo {
  const SkinInfo({
    required this.name,
    this.directory,
    this.format = SkinFormat.classic,
    this.builtIn = false,
  });

  /// Display name shown in skin lists.
  final String name;

  /// Directory containing the skin's files, or null for the bundled base.
  final Directory? directory;

  /// The family of skin: classic, Wasabi, Bamp or Audacious.
  final SkinFormat format;

  /// Whether the app installed this skin itself, so it cannot be removed.
  final bool builtIn;

  /// Whether this is a Wasabi 3 / Wasabi 5 modern skin (`.wal`).
  ///
  /// Kept as a convenience for the renderer; [format] is the source of truth.
  bool get modern => format == SkinFormat.wasabi;

  /// Whether this skin ships with the app (the base skin or a built-in one)
  /// rather than being a user import.
  bool get isBundled => directory == null || builtIn;
}
