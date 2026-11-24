# dart_cast (vendored)

[dart_cast](https://pub.dev/packages/dart_cast) 0.7.4 by AbdelazizMahdy (MIT,
see `LICENSE`), copied here with one change:

- `CastMedia.contentType` (optional) is the MIME type a Chromecast is told the
  media has. The package hard-codes `video/mp4` for MP4, which makes the
  default receiver show its video layout for a music track, with no cover art.

Only the Chromecast side is used by Amped. Remove this copy and go back to
`dart_cast: ^x` once upstream can set the content type.
