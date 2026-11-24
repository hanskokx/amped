# amped_media_source

The contract external sources implement, and what they share.

## Use

This package is part of the Amped app repository, in `packages/amped_media_source`, and the
app depends on it by path:

```yaml
dependencies:
  amped_media_source:
    path: packages/amped_media_source
```

## What it provides

Plex, Jellyfin, Subsonic, SoundCloud, Audiobookshelf and podcast feeds are all
a `RemoteLibrarySource` to Amped: something that can be checked, lists its
tracks a page at a time, and signs a stream URL for one of them.

- `RemoteLibrarySource` and `SourceConnection`: the contract, and where a
  source is and who it signs in as. Mixins (`ResumesPlayback`,
  `ReportsProgress`, `HasBooks`, `HasVideoPlaylists`,
  `RefreshesCredentials`) say what else a source can do.
- `TrackTags` and `SourceLocation`: what a track is, and how an address names
  a source's item.
- `PkceSignIn`, `OAuthTokens` and `BrowserSignInException`: the browser
  sign-in helpers (OAuth with PKCE).
- `redact`: masks URLs, tokens and secrets in text (used by
  [amped_logging](../amped_logging)), JSON decoding helpers, and
  `RemoteAuthException` for a refused sign-in.

Sources: [amped_plex](../amped_plex),
[amped_jellyfin](../amped_jellyfin),
[amped_subsonic](../amped_subsonic),
[amped_soundcloud](../amped_soundcloud),
[amped_audiobookshelf](../amped_audiobookshelf),
[amped_podcast](../amped_podcast).

```sh
dart test
```

## License

This package is covered by the license of the Amped repository it is part of.
