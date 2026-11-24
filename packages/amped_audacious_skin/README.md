# amped_audacious_skin

Audacious skin support for Amped.

## Use

This package is part of the Amped app repository, in `packages/amped_audacious_skin`, and the
app depends on it by path:

```yaml
dependencies:
  amped_audacious_skin:
    path: packages/amped_audacious_skin
```

It depends on other Amped packages:

- [amped_classic_skin](../amped_classic_skin)
- [amped_skin](../amped_skin)

## What it provides

Audacious skins arrive as tarballs (`.tar`, `.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz2`)
or plain zips, may use PNG or JPEG bitmaps, and may carry a `skin.hints` file.
This package turns them into the classic file set that
[amped_classic_skin](../amped_classic_skin) renders:

- `AudaciousSkinDecoder` opens the archives (including the tarballs, and the
  manifest of an old Audacious install).
- `AudaciousSkinConverter` converts the bitmaps.
- `SkinHintsParser` reads `skin.hints`: `key=value` pairs, case-insensitive,
  that move the main window's controls and give it its own size.

```sh
flutter test
```

## License

This package is covered by the license of the Amped repository it is part of.
