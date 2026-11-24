#ifndef RUNNER_MEDIA_SESSION_H_
#define RUNNER_MEDIA_SESSION_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// What is playing, as Dart's NowPlaying sends it with "setNowPlaying".
struct NowPlayingInfo {
  // "playing", "paused" or "stopped".
  std::string state = "stopped";
  std::optional<std::string> title;
  std::optional<std::string> artist;
  std::optional<std::string> album;
  // In seconds.
  std::optional<double> duration;
  double elapsed = 0;
};

// The app's entry in the System Media Transport Controls: the media flyout,
// the lock screen, and the keyboard's media keys.
//
// Commands from the controls arrive on a thread pool; they are carried to
// the thread that created the session (the one running the message loop)
// before [on_command] is called with "play", "pause", "stop", "next",
// "previous", or "seek" and a position in seconds.
class MediaSession {
 public:
  using CommandHandler =
      std::function<void(const std::string& command,
                         std::optional<double> position)>;

  explicit MediaSession(CommandHandler on_command);
  ~MediaSession();

  MediaSession(const MediaSession&) = delete;
  MediaSession& operator=(const MediaSession&) = delete;

  void SetNowPlaying(const NowPlayingInfo& info);

  // The current track's cover art in any image format; empty for none.
  void SetArtwork(const std::vector<uint8_t>& bytes);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_SESSION_H_
