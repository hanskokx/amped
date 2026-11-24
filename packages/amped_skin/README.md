# amped_skin

What the skin packages and the app share: the windows a skin draws, the installed skins, and what every kind of skin can be asked.

## Use

This package is part of the Amped app repository, in `packages/amped_skin`, and the
app depends on it by path:

```yaml
dependencies:
  amped_skin:
    path: packages/amped_skin
```

## What it provides

Amped draws its windows from skins of several formats (classic `.wsz`, Audacious
and Bamp archives, modern `.wal`). This package holds what does not depend on
the format, so the packages that read a format and the app that shows the
result can all talk about a skin the same way:

- `Skin`, `SkinInfo` and `SkinFormat`: a loaded skin, its metadata, and what a
  format must provide to open one.
- `SkinWindow`: the top-level windows a skin draws (player, equalizer,
  playlist, and the extra windows a modern skin defines).
- `SkinRegistry` and `SkinStorage`: the installed skins, and the interface the
  app implements to keep what is remembered about them (the skin switched to,
  the sizes windows were dragged to, which windows were left open).
- `SkinFileType` and `BuiltInSkin`: which files are skin archives, and the
  skins bundled with the app.

It has no dependencies besides Flutter.

```dart
import "package:amped_skin/amped_skin.dart";

final isModern = SkinFileType.wal.matches("Amped-Modern.wal");
```

Format packages build on it: [amped_classic_skin](../amped_classic_skin),
[amped_wasabi](../amped_wasabi),
[amped_bamp_skin](../amped_bamp_skin) and
[amped_audacious_skin](../amped_audacious_skin).

## License

This package is covered by the license of the Amped repository it is part of.
