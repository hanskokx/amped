# amped_jellyfin

Jellyfin as an Amped source: client and the RemoteLibrarySource.

## Use

This package is part of the Amped app repository, in `packages/amped_jellyfin`, and the
app depends on it by path:

```yaml
dependencies:
  amped_jellyfin:
    path: packages/amped_jellyfin
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

- `JellyfinClient` talks to a Jellyfin server.
- `JellyfinRemote` is the `RemoteLibrarySource`: it lists the server's music
  and signs stream URLs.
- `JellyfinException` says why a request failed.

Passwords and tokens are not stored here: the application keeps them in the
system's secure store and hands them over when it opens the source.

## License

This package is covered by the license of the Amped repository it is part of.
