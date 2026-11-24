# amped_plex

A Plex Media Server as an Amped source.

## Use

This package is part of the Amped app repository, in `packages/amped_plex`, and the
app depends on it by path:

```yaml
dependencies:
  amped_plex:
    path: packages/amped_plex
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

- `PlexClient` talks to a Plex Media Server.
- `PlexSignIn` and `PlexPin` sign in through plex.tv with the PIN flow: the
  user approves the app on the Plex website, and the token comes back, so the
  app never sees a password.
- `PlexRemote` is the `RemoteLibrarySource` (and `HasVideoPlaylists`): its
  "password" is the server's `X-Plex-Token`, and `streamUrl` signs the item's
  part key with it.

Passwords and tokens are not stored here: the application keeps them in the
system's secure store and hands them over when it opens the source.

## License

This package is covered by the license of the Amped repository it is part of.
