# amped_subsonic

Navidrome and other Subsonic API servers as an Amped source.

## Use

This package is part of the Amped app repository, in `packages/amped_subsonic`, and the
app depends on it by path:

```yaml
dependencies:
  amped_subsonic:
    path: packages/amped_subsonic
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

- `SubsonicClient` talks to a Subsonic-API server (Navidrome, Subsonic,
  Airsonic, ...), signing requests with the salted token scheme so the password
  is never sent.
- `SubsonicRemote` is the `RemoteLibrarySource`: it lists the server's music
  and signs stream URLs.

Passwords and tokens are not stored here: the application keeps them in the
system's secure store and hands them over when it opens the source.

## License

This package is covered by the license of the Amped repository it is part of.
