/// The contract every external source (Plex, SoundCloud, Audiobookshelf...)
/// implements, and the pieces they share: track tags, source locations and
/// the browser sign-in helpers.
library;

export "src/auth_exception.dart";
export "src/browser_sign_in.dart";
export "src/json_decode.dart";
export "src/redact.dart";
export "src/remote_library_source.dart";
export "src/source_location.dart";
export "src/track_tags.dart";
