# YouTube-free stand-ins

When the `YOUTUBE_ENABLED` repository variable is `false`, the release
workflow runs `dart run tool/strip_youtube.dart`, which swaps the
`amped_youtube` and `amped_ytdlp` dependencies for these packages. They have
the same API as the real ones but never recognize a YouTube link and never
run `yt-dlp`, so the app builds without the feature and without the bundled
program.
