# amped_podcast

Podcast RSS feeds and iTunes search as an Amped source.

## Use

This package is part of the Amped app repository, in `packages/amped_podcast`, and the
app depends on it by path:

```yaml
dependencies:
  amped_podcast:
    path: packages/amped_podcast
```

It depends on other Amped packages:

- [amped_media_source](../amped_media_source)

## What it provides

- `RssClient` fetches and parses a podcast feed into a `Podcast` with its
  `PodcastEpisode`s.
- `ItunesSearch` searches the iTunes directory (`PodcastSearchResult`).
- `RssRemote` is the `RemoteLibrarySource` of one feed: the source's server is
  the feed URL, there is no password, and episodes are named by their audio
  URL.

## License

This package is covered by the license of the Amped repository it is part of.
