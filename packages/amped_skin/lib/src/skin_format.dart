/// The skin family an installed skin belongs to.
///
/// Unlike [SkinFileType], which describes how a skin is packaged, this is the
/// origin of the skin's artwork and is shown in the preferences list. It is
/// stored in each installed skin's manifest because converting a skin to a
/// classic file set loses the information about where its files came from.
enum SkinFormat {
  /// An original bitmap skin (`.wsz`), including the bundled base.
  classic,

  /// A Wasabi 3 / Wasabi 5 modern skin (`.wal`).
  wasabi,

  /// A skin made for Bamp, converted to classic bitmaps on import.
  bamp,

  /// A skin made for Audacious, converted to classic bitmaps on import.
  audacious,
}
