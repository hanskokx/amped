/// The archive container a skin ships in.
///
/// Every file type carries the suffixes it is known by, so filename matching
/// lives in one place: skin loaders, installers and the app all use [matches]
/// instead of their own extension lists. An enhanced enum keeps the suffixes
/// next to the type they describe.
enum SkinFileType {
  /// A zip archive, including the classic player's classic `.wsz` name.
  zip(".zip", [".wsz"]),

  /// An uncompressed tar archive, as used by Audacious skins.
  tar(".tar"),

  /// A gzip-compressed tar archive.
  tarGz(".tar.gz", [".tgz"]),

  /// A bzip2-compressed tar archive.
  tarBz2(".tar.bz2", [".tbz2", ".tbz"]),

  /// A Wasabi 3 / Wasabi 5 modern skin archive.
  ///
  /// Its bytes are a zip too, but it is a different skin family: modern
  /// skins are opened by `amped_wasabi`, not by the classic loader.
  wal(".wal");

  const SkinFileType(this.suffix, [this.aliases = const []]);

  /// The canonical suffix, including its leading dot.
  final String suffix;

  /// Alternative suffixes for the same container.
  final List<String> aliases;

  /// Every suffix that means this container.
  List<String> get suffixes => [suffix, ...aliases];

  /// Whether [fileName] ends in one of this container's suffixes.
  bool matches(String fileName) {
    final lower = fileName.toLowerCase();
    return suffixes.any(lower.endsWith);
  }
}
