import "dart:ui";

/// The non-skinned dialog windows (native frame).
enum AmpedDialog {
  presets(Size(275, 190)),
  preferences(Size(620, 460)),
  about(Size(400, 300)),
  vis(Size(640, 480)),

  /// The playing video, filling the screen.
  video(Size(640, 480)),
  visConfig(Size(420, 560)),

  /// File Info (Alt+3), `IDD_FILEINFO`.
  fileInfo(Size(600, 440)),

  /// Edit metadata for selection (Shift+E), `IDD_EDIT_INFO`.
  editMetadata(Size(520, 600)),

  /// The name and password of a network share.
  remoteLogin(Size(440, 300)),

  /// Whether to continue an episode where it was left off.
  resume(Size(420, 170)),

  /// A new release of Amped, with its release notes.
  update(Size(460, 380)),

  /// A picture from the Media Library, in a window like the Album Art
  /// window's but of its own. Drawn in the skin.
  artwork(Size(300, 320)),

  /// Jump to file (J): searches the playlist. Drawn in the skin.
  searchPlaylist(Size(275, 190));

  const AmpedDialog(this.size);

  /// Whether the dialog is drawn in the skin, frame and all, in a window
  /// with no frame of its own.
  bool get skinned =>
      this == presets || this == searchPlaylist || this == artwork;

  final Size size;

  /// The least size the user can resize the window to, for the dialogs
  /// whose forms stop fitting below it; null where any size will do.
  Size? get minSize => switch (this) {
    fileInfo || editMetadata => size,
    _ => null,
  };
}
