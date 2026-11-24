# amped_soundcloud

SoundCloud as an Amped source: API client, credentials and the RemoteLibrarySource.

## Use

This package is part of the Amped app repository, in `packages/amped_soundcloud`, and the
app depends on it by path:

```yaml
dependencies:
  amped_soundcloud:
    path: packages/amped_soundcloud
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

- `SoundCloudClient` talks to the SoundCloud API.
- `SoundCloudCredentials` holds the application key it is used with.
- `SoundCloudRemote` is the `RemoteLibrarySource` for a profile, reached with
  the user's own SoundCloud application key: the source's server is the
  profile URL, its user the client id and its password the client secret.

Passwords and tokens are not stored here: the application keeps them in the
system's secure store and hands them over when it opens the source.

## License

This package is covered by the license of the Amped repository it is part of.
