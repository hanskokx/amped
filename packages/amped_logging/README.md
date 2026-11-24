# amped_logging

Amped's logging: Arcane's logger with a console that masks tokens and secrets.

## Use

This package is part of the Amped app repository, in `packages/amped_logging`, and the
app depends on it by path:

```yaml
dependencies:
  amped_logging:
    path: packages/amped_logging
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

Amped logs with `Arcane.log` from
[arcane_framework](https://pub.dev/packages/arcane_framework). This package
only decides where the messages go:

```dart
import "package:amped_logging/amped_logging.dart";

await AppLogging.init();

Arcane.log(
  "Signed in",
  metadata: {"server": "https://music.example.com"},
  level: Level.info,
  module: "Example",
);
```

- `ConsoleInterface` prints to the console.
- `redactingInterceptor` masks tokens, passwords and secret URLs in every
  event before any interface sees it (using `redact` from
  [amped_media_source](../amped_media_source)).
- `AppLogging.init` registers both and routes `debugPrint` and unhandled
  errors through `Arcane.log`.

Messages are fixed text; the values they are about go in `metadata`, so logs
can be searched and secrets masked.

```sh
flutter test
```

## License

This package is covered by the license of the Amped repository it is part of.
