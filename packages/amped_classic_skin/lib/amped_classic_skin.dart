/// Classic skin support for amped.
///
/// Provides the [ClassicSkinData] data model, BMP decoding, `.wsz`/base-skin
/// loading, and the small skin-rendering widgets ([SkinImage], [SkinSlider],
/// [SkinText]) that blit crops of skin bitmaps the way the original GDI code
/// did.
library;

export "package:custom_cursor/custom_cursor.dart" show CustomMouseCursor;

export "src/bmp_decoder.dart";
export "src/built_in_skin.dart";
export "src/classic_host.dart";
export "src/classic_skin.dart";
export "src/classic_skin_data.dart";
export "src/classic_skin_registry.dart";
export "src/gen_frame.dart";
export "src/skin_controls.dart";
export "src/skin_cursors.dart";
export "src/skin_formats.dart";
export "src/skin_image.dart";
export "src/skin_loader.dart";
export "src/skin_slider.dart";
export "src/text_font.dart";
export "src/windows/classic_vis_view.dart";
export "src/windows/cursor_zone.dart";
export "src/windows/eq_window.dart";
export "src/windows/frame_windows.dart";
export "src/windows/main_window.dart";
export "src/windows/playlist_window.dart";
