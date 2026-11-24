/// The kinds of remote source that can be added. Plex, Jellyfin and SoundCloud add
/// theirs here, with a [RemoteLibrarySource] each.
enum RemoteSourceType {
  navidrome,
  soundcloud,
  plex,
  jellyfin,
  podcast,
  audiobookshelf,
}
