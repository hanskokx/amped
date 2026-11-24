import "package:amped_logging/amped_logging.dart";
import "package:amped_youtube/amped_youtube.dart";

/// What the app asks about YouTube links, unless a test supplies its own.
final YouTubeResolver sharedYouTube = YtDlpResolver(
  log: (message, {metadata}) => Arcane.log(
    message,
    level: Level.info,
    module: "SharedYoutube",
    metadata: metadata,
  ),
);
