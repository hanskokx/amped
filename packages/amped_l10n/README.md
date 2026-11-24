# amped_l10n

Shared localization catalog for Amped.

The ARB catalog in `lib/l10n/app_en.arb` is the source of truth for the strings
the app owns; Flutter generates the typed API in `lib/src/generated`.

## Use

This package is part of the Amped app repository, in `packages/amped_l10n`, and the
app depends on it by path:

```yaml
dependencies:
  amped_l10n:
    path: packages/amped_l10n
```

## Changing a string

Edit `lib/l10n/app_en.arb` (every string has an `@key` entry that says where it
is shown), then regenerate the Dart API from this package's folder:

```sh
flutter gen-l10n
```

## License

This package is covered by the license of the Amped repository it is part of.
