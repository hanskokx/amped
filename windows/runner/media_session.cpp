#include "media_session.h"

// Classic COM interfaces must be declared before C++/WinRT for interop.
#include <unknwn.h>

#include <shcore.h>
#include <shlwapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <chrono>
#include <deque>
#include <mutex>
#include <utility>

namespace {

using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::PlaybackPositionChangeRequestedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;
using winrt::Windows::Media::Playback::MediaPlayer;
using winrt::Windows::Storage::Streams::IRandomAccessStream;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

constexpr wchar_t kWindowClass[] = L"AMPED_MEDIA_SESSION";
constexpr UINT kCommandMessage = WM_APP + 1;
constexpr UINT_PTR kTimelineTimer = 1;

winrt::hstring ToHString(const std::optional<std::string>& text) {
  return text ? winrt::to_hstring(*text) : winrt::hstring();
}

TimeSpan Seconds(double seconds) {
  return std::chrono::duration_cast<TimeSpan>(
      std::chrono::duration<double>(seconds));
}

void LogError(const winrt::hresult_error& error) {
  ::OutputDebugStringW((L"Media session: " + error.message() + L"\n").c_str());
}

}  // namespace

struct MediaSession::Impl {
  CommandHandler on_command;
  HWND window = nullptr;
  // The controls of an unused MediaPlayer are how a desktop app without a
  // window of its own gets an SMTC session.
  MediaPlayer player{nullptr};
  SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token;
  winrt::event_token position_token;

  std::mutex mutex;
  std::deque<std::pair<std::string, std::optional<double>>> pending;

  NowPlayingInfo info;
  std::chrono::steady_clock::time_point sent_at;

  // Queues a command from the thread pool for the message loop's thread.
  void Post(std::string command, std::optional<double> position = {}) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      pending.emplace_back(std::move(command), position);
    }
    ::PostMessage(window, kCommandMessage, 0, 0);
  }

  void Drain() {
    std::deque<std::pair<std::string, std::optional<double>>> commands;
    {
      std::lock_guard<std::mutex> lock(mutex);
      commands.swap(pending);
    }
    for (const auto& [command, position] : commands) {
      on_command(command, position);
    }
  }

  // The controls don't advance the position on their own, so it is
  // refreshed every second while playing.
  void UpdateTimeline() {
    if (!controls) return;
    const double duration = info.duration.value_or(0);
    double position = info.elapsed;
    if (info.state == "playing") {
      position += std::chrono::duration<double>(
                      std::chrono::steady_clock::now() - sent_at)
                      .count();
    }
    if (duration > 0) position = std::min(position, duration);
    try {
      SystemMediaTransportControlsTimelineProperties timeline;
      timeline.StartTime(Seconds(0));
      timeline.MinSeekTime(Seconds(0));
      timeline.EndTime(Seconds(duration));
      timeline.MaxSeekTime(Seconds(duration));
      timeline.Position(Seconds(position));
      controls.UpdateTimelineProperties(timeline);
    } catch (const winrt::hresult_error& error) {
      LogError(error);
    }
  }

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
    auto* self =
        reinterpret_cast<Impl*>(::GetWindowLongPtr(window, GWLP_USERDATA));
    if (self && message == kCommandMessage) {
      self->Drain();
      return 0;
    }
    if (self && message == WM_TIMER && wparam == kTimelineTimer) {
      self->UpdateTimeline();
      return 0;
    }
    return ::DefWindowProc(window, message, wparam, lparam);
  }
};

MediaSession::MediaSession(CommandHandler on_command)
    : impl_(std::make_unique<Impl>()) {
  impl_->on_command = std::move(on_command);

  // A message-only window, to carry commands to this thread.
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = Impl::WndProc;
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.lpszClassName = kWindowClass;
  ::RegisterClassW(&window_class);
  impl_->window = ::CreateWindowW(kWindowClass, L"", 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, nullptr,
                                  window_class.hInstance, nullptr);
  if (!impl_->window) return;
  ::SetWindowLongPtr(impl_->window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(impl_.get()));

  try {
    impl_->player = MediaPlayer();
    impl_->player.CommandManager().IsEnabled(false);
    auto controls = impl_->player.SystemMediaTransportControls();
    controls.IsEnabled(true);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsStopEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    controls.PlaybackStatus(MediaPlaybackStatus::Closed);
    Impl* impl = impl_.get();
    impl_->button_token = controls.ButtonPressed(
        [impl](const SystemMediaTransportControls&,
               const SystemMediaTransportControlsButtonPressedEventArgs& args) {
          switch (args.Button()) {
            case SystemMediaTransportControlsButton::Play:
              impl->Post("play");
              break;
            case SystemMediaTransportControlsButton::Pause:
              impl->Post("pause");
              break;
            case SystemMediaTransportControlsButton::Stop:
              impl->Post("stop");
              break;
            case SystemMediaTransportControlsButton::Next:
              impl->Post("next");
              break;
            case SystemMediaTransportControlsButton::Previous:
              impl->Post("previous");
              break;
            default:
              break;
          }
        });
    impl_->position_token = controls.PlaybackPositionChangeRequested(
        [impl](const SystemMediaTransportControls&,
               const PlaybackPositionChangeRequestedEventArgs& args) {
          impl->Post("seek", std::chrono::duration<double>(
                                 args.RequestedPlaybackPosition())
                                 .count());
        });
    impl_->controls = controls;
  } catch (const winrt::hresult_error& error) {
    // E.g. Windows N without the Media Feature Pack.
    LogError(error);
  }
}

MediaSession::~MediaSession() {
  try {
    if (impl_->controls) {
      impl_->controls.ButtonPressed(impl_->button_token);
      impl_->controls.PlaybackPositionChangeRequested(impl_->position_token);
      impl_->controls.DisplayUpdater().ClearAll();
      impl_->controls.IsEnabled(false);
    }
    if (impl_->player) impl_->player.Close();
  } catch (const winrt::hresult_error& error) {
    LogError(error);
  }
  if (impl_->window) ::DestroyWindow(impl_->window);
}

void MediaSession::SetNowPlaying(const NowPlayingInfo& info) {
  impl_->info = info;
  impl_->sent_at = std::chrono::steady_clock::now();
  auto controls = impl_->controls;
  if (!controls) return;
  const bool playing = info.state == "playing";
  if (playing) {
    ::SetTimer(impl_->window, kTimelineTimer, 1000, nullptr);
  } else {
    ::KillTimer(impl_->window, kTimelineTimer);
  }
  try {
    auto updater = controls.DisplayUpdater();
    if (info.state == "stopped" && !info.title) {
      updater.ClearAll();
      updater.Update();
      controls.PlaybackStatus(MediaPlaybackStatus::Stopped);
      return;
    }
    if (updater.Type() != MediaPlaybackType::Music) {
      updater.Type(MediaPlaybackType::Music);
    }
    auto music = updater.MusicProperties();
    music.Title(ToHString(info.title));
    music.Artist(ToHString(info.artist));
    music.AlbumTitle(ToHString(info.album));
    updater.Update();
    controls.PlaybackStatus(playing ? MediaPlaybackStatus::Playing
                            : info.state == "paused"
                                ? MediaPlaybackStatus::Paused
                                : MediaPlaybackStatus::Stopped);
  } catch (const winrt::hresult_error& error) {
    LogError(error);
  }
  impl_->UpdateTimeline();
}

void MediaSession::SetArtwork(const std::vector<uint8_t>& bytes) {
  auto controls = impl_->controls;
  if (!controls) return;
  try {
    auto updater = controls.DisplayUpdater();
    if (bytes.empty()) {
      updater.Thumbnail(nullptr);
    } else {
      winrt::com_ptr<IStream> stream;
      stream.attach(::SHCreateMemStream(bytes.data(),
                                        static_cast<UINT>(bytes.size())));
      if (!stream) return;
      IRandomAccessStream random_access{nullptr};
      winrt::check_hresult(::CreateRandomAccessStreamOverStream(
          stream.get(), BSOS_DEFAULT, winrt::guid_of<IRandomAccessStream>(),
          winrt::put_abi(random_access)));
      updater.Thumbnail(
          RandomAccessStreamReference::CreateFromStream(random_access));
    }
    updater.Update();
  } catch (const winrt::hresult_error& error) {
    LogError(error);
  }
}
