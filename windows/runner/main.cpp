#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/generated_plugin_registrant.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "media_session.h"
#include "utils.h"

#include "prompt_dialog.h"
#include "toast_notifier.cpp"

namespace
{

  using flutter::EncodableList;
  using flutter::EncodableMap;
  using flutter::EncodableValue;

  const EncodableValue *Lookup(const EncodableMap &map, const char *key)
  {
    auto it = map.find(EncodableValue(key));
    return it == map.end() ? nullptr : &it->second;
  }

  std::optional<std::string> StringAt(const EncodableMap &map,
                                      const char *key)
  {
    const EncodableValue *value = Lookup(map, key);
    const auto *text = value ? std::get_if<std::string>(value) : nullptr;
    return text ? std::optional<std::string>(*text) : std::nullopt;
  }

  std::optional<double> NumberAt(const EncodableMap &map, const char *key)
  {
    const EncodableValue *value = Lookup(map, key);
    if (!value)
      return std::nullopt;
    if (const auto *number = std::get_if<int32_t>(value))
      return *number;
    if (const auto *number = std::get_if<int64_t>(value))
    {
      return static_cast<double>(*number);
    }
    if (const auto *number = std::get_if<double>(value))
      return *number;
    return std::nullopt;
  }

  std::wstring Utf16(const std::string &text)
  {
    if (text.empty())
      return L"";
    const int length = ::MultiByteToWideChar(
        CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring wide(static_cast<size_t>(length), L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                          static_cast<int>(text.size()), wide.data(), length);
    return wide;
  }

  std::string Utf8(const std::wstring &text)
  {
    if (text.empty())
      return "";
    const int length = ::WideCharToMultiByte(
        CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0,
        nullptr, nullptr);
    std::string utf8(static_cast<size_t>(length), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                          static_cast<int>(text.size()), utf8.data(), length,
                          nullptr, nullptr);
    return utf8;
  }

  NowPlayingInfo ParseNowPlaying(const EncodableValue *arguments)
  {
    NowPlayingInfo info;
    const auto *map =
        arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
    if (!map)
      return info;
    info.state = StringAt(*map, "state").value_or("stopped");
    info.title = StringAt(*map, "title");
    info.artist = StringAt(*map, "artist");
    info.album = StringAt(*map, "album");
    info.duration = NumberAt(*map, "duration");
    info.elapsed = NumberAt(*map, "elapsed").value_or(0);
    return info;
  }

} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  auto const engine{std::make_shared<flutter::FlutterEngine>(project)};
  RegisterPlugins(engine.get());

  flutter::MethodChannel<EncodableValue> channel(
      engine->messenger(), "amped",
      &flutter::StandardMethodCodec::GetInstance());
  MediaSession media_session(
      [&channel](const std::string &command, std::optional<double> position)
      {
        EncodableMap arguments{
            {EncodableValue("command"), EncodableValue(command)}};
        if (position)
        {
          arguments[EncodableValue("position")] = EncodableValue(*position);
        }
        channel.InvokeMethod("remoteCommand",
                             std::make_unique<EncodableValue>(arguments));
      });
  ToastNotifier toast_notifier;
  channel.SetMethodCallHandler(
      [&media_session, &toast_notifier](
          const flutter::MethodCall<EncodableValue> &call,
          std::unique_ptr<flutter::MethodResult<EncodableValue>> result)
      {
        if (call.method_name() == "setNowPlaying")
        {
          media_session.SetNowPlaying(ParseNowPlaying(call.arguments()));
          result->Success();
        }
        else if (call.method_name() == "setNowPlayingArtwork")
        {
          const auto *bytes =
              call.arguments()
                  ? std::get_if<std::vector<uint8_t>>(call.arguments())
                  : nullptr;
          media_session.SetArtwork(bytes ? *bytes : std::vector<uint8_t>());
          result->Success();
        }
        else if (call.method_name() == "showNotification")
        {
          const auto *arguments =
              call.arguments()
                  ? std::get_if<EncodableMap>(call.arguments())
                  : nullptr;
          if (arguments)
          {
            const auto title = StringAt(*arguments, "title").value_or("");
            const auto body = StringAt(*arguments, "body").value_or("");
            toast_notifier.Show(title, body);
          }
          result->Success();
        }
        else if (call.method_name() == "promptText")
        {
          const auto *arguments =
              call.arguments()
                  ? std::get_if<EncodableMap>(call.arguments())
                  : nullptr;
          prompt_dialog::State state;
          if (arguments)
          {
            state.title = Utf16(StringAt(*arguments, "title").value_or(""));
            state.message =
                Utf16(StringAt(*arguments, "message").value_or(""));
            state.value = Utf16(StringAt(*arguments, "value").value_or(""));
            state.confirm =
                Utf16(StringAt(*arguments, "confirmLabel").value_or("OK"));
            state.cancel =
                Utf16(StringAt(*arguments, "cancelLabel").value_or("Cancel"));
          }
          const auto text = prompt_dialog::Show(::GetActiveWindow(), state);
          if (text)
          {
            result->Success(EncodableValue(Utf8(*text)));
          }
          else
          {
            result->Success();
          }
        }
        else
        {
          result->NotImplemented();
        }
      });

  engine->Run();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  channel.SetMethodCallHandler(nullptr);

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
