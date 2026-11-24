# amped_audiobookshelf

Audiobookshelf as an Amped source: client and the RemoteLibrarySource.

## Use

This package is part of the Amped app repository, in `packages/amped_audiobookshelf`, and the
app depends on it by path:

```yaml
dependencies:
  amped_audiobookshelf:
    path: packages/amped_audiobookshelf
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)
- [amped_podcast](../amped_podcast)

## What it provides

- `AudiobookshelfClient` talks to an [Audiobookshelf](https://www.audiobookshelf.org)
  server.
- `AudiobookshelfRemote` is the `RemoteLibrarySource` for the server's
  podcasts (the "password" is the server's API token), built on the
  podcast types of [amped_podcast](../amped_podcast).

Passwords and tokens are not stored here: the application keeps them in the
system's secure store and hands them over when it opens the source.

## License

This package is covered by the license of the Amped repository it is part of.
