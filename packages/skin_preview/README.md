# skin_preview

Pictures of skins, drawn by the native renderer the file manager previews use.

## Use

```yaml
dependencies:
  skin_preview:
    path: packages/skin_preview
```

## What it provides

Renders a picture of a skin (classic, Audacious or Bamp, or a modern `.wal`),
without drawing it through Flutter: it is the same C renderer that makes the
previews in Quick Look, Explorer and freedesktop thumbnails. It is compiled by
a native-assets build hook (`hook/build.dart`), so a C compiler is needed.

```dart
import "package:skin_preview/skin_preview.dart";

// The skin extracted in a folder (null: the built-in base skin).
final picture = await renderSkinPicture(
  Directory("path/to/skin"),
  title: "Song title",
  size: 600,
  layout: SkinPictureLayout.stack, // or .main: the main window alone
);
// picture?.rgba: straight RGBA, 4 bytes a pixel, rows top-down; null when
// the skin cannot be drawn. The work is done in another isolate.
```

## The native source

This package is not a repository of its own: it lives in the Amped app's
`packages/` folder, because the renderer it compiles is the app's
`native/skin_preview`, which the Quick Look, Explorer and thumbnailer targets
build too.

## License

It is part of the app and follows its license.
