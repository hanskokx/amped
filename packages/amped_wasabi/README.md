# amped_wasabi

Modern (Wasabi 3 / Wasabi 5, `.wal`) skin support for Amped.

## Use

This package is part of the Amped app repository, in `packages/amped_wasabi`, and the
app depends on it by path:

```yaml
dependencies:
  amped_wasabi:
    path: packages/amped_wasabi
```

It depends on other Amped packages:

- [amped_logging](../amped_logging)
- [amped_maki](https://git.hadak.org/Amped/amped_maki) (its own repository)
- [amped_skin](../amped_skin)
- [amped_vis](../amped_vis)

## What it provides

Loads `.wal` skins and renders their layouts as Flutter widgets:

- `WasabiSkinData` loads an extracted skin: its XML, bitmaps, fonts,
  containers and layouts. `WasabiArchive` installs one.
- `WasabiLayoutView` renders a layout and wires it to the player through a
  `WasabiHost`, which the application implements.
- `MakiVm` and the script runtime run the skin's MAKI scripts (compiled with
  [amped_maki](https://git.hadak.org/Amped/amped_maki)), so buttons, drawers, menus and the color
  themes behave as the skin's author scripted them.
- Plugin files that skins pull in through path variables (such as ClassicPro)
  can be mounted from a zip with `WasabiSkinData.mountPlugins`.
- `AmpedModernSkinLoader` loads the `.wal` skins bundled in the application's
  `assets/skins`.

## Tests

```sh
flutter test
```


## License

This package is covered by the license of the Amped repository it is part of.
