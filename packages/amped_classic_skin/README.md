# amped_classic_skin

Classic skin loading, decoding and rendering for Amped.

## Use

This package is part of the Amped app repository, in `packages/amped_classic_skin`, and the
app depends on it by path:

```yaml
dependencies:
  amped_classic_skin:
    path: packages/amped_classic_skin
```

It depends on other Amped packages:

- [amped_skin](../amped_skin)
- [amped_vis](../amped_vis)

## What it provides

Loads classic bitmap skins (`.wsz`) and draws the player windows from them the
way the original GDI code did, pixel for pixel:

- `ClassicSkinData` and `ClassicSkin`: the skin's bitmaps, regions, colors and
  cursors, with files a skin leaves out falling back to the base skin.
- `decodeBmp`: a self-contained BMP decoder (1 to 32 bits, palettes, RLE8 and
  RLE4, bottom-up and top-down), as skins ship RLE-compressed bitmaps that
  other packages do not decode.
- Skin archives in several image formats: BMP, PNG, WebP, JPEG and GIF.
- `AmpedClassicSkinLoader`: loads the skins bundled in the application's
  `assets/skins`. The base skin is the archive there whose file name starts
  with `base`; it is the fallback beneath every other skin, so an app using
  this package has to ship one.
- Widgets that blit crops of skin bitmaps (`SkinImage`, `SkinSlider`,
  `SkinText`) and the player windows built from them (`MainWindowView`,
  `EqWindow`, `PlaylistWindow`, ...), driven through the `ClassicHost`
  interface.

Audacious and Bamp skins are converted into this file set by
[amped_audacious_skin](../amped_audacious_skin) and
[amped_bamp_skin](../amped_bamp_skin).

## Tests

```sh
flutter test
```

`test/fixtures/base.wsz` is the base skin the tests load through a fake asset
bundle.

## License

This package is covered by the license of the Amped repository it is part of.
