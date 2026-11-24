# amped_bamp_skin

Bamp skin support for Amped.

## Use

This package is part of the Amped app repository, in `packages/amped_bamp_skin`, and the
app depends on it by path:

```yaml
dependencies:
  amped_bamp_skin:
    path: packages/amped_bamp_skin
```

It depends on other Amped packages:

- [amped_classic_skin](../amped_classic_skin)
- [amped_skin](../amped_skin)

## What it provides

[Bamp](https://github.com/dp-mason/bamp) skins are zips of PNG layers.
`BampSkinFormat` converts those layers into the bitmaps of a classic skin; the
archive decoding and rendering stay in
[amped_classic_skin](../amped_classic_skin).

The layer-to-bitmap table (`BampSpec`) is generated from Bamp's skin
specification into `assets/bamp/spec.json`:

```sh
ruby tool/bamp_spec_to_json.rb path/to/winamp_skin_specification.yaml
```

The app's native previews embed the same table (see its
`native/skin_preview/embed_bamp_map.rb`), so regenerate that too after
changing the file.

## Tests

```sh
flutter test
```

## License

This package is covered by the license of the Amped repository it is part of.
