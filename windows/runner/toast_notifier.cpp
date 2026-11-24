#include <windows.h>
#include <shellapi.h>
#include <string>

#include "resource.h"

#pragma comment(lib, "shell32.lib")

namespace
{

  std::wstring Widen(const std::string &text)
  {
    if (text.empty())
      return std::wstring();
    const int length = MultiByteToWideChar(
        CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring wide(length, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                        static_cast<int>(text.size()), wide.data(), length);
    return wide;
  }

  // Posts system notifications (a toast on current Windows). The shell only
  // shows a notification for a notification-area icon, so each one adds a
  // short-lived icon and removes it again; the persistent tray icon and its
  // menu come from the tray_manager package.
  class ToastNotifier
  {
  public:
    ~ToastNotifier()
    {
      Remove();
      if (hwnd_)
        DestroyWindow(hwnd_);
    }

    void Show(const std::string &utf8_title, const std::string &utf8_body)
    {
      if (!EnsureWindow())
        return;
      Remove();

      const std::wstring title = Widen(utf8_title);
      const std::wstring body = Widen(utf8_body);
      icon_ = {};
      icon_.cbSize = sizeof(icon_);
      icon_.hWnd = hwnd_;
      icon_.uID = 1;
      icon_.uFlags = NIF_ICON | NIF_INFO;
      icon_.hIcon = LoadIconW(GetModuleHandleW(nullptr),
                              MAKEINTRESOURCEW(IDI_APP_ICON));
      icon_.dwInfoFlags = NIIF_USER | NIIF_NOSOUND;
      lstrcpynW(icon_.szInfoTitle, title.c_str(), ARRAYSIZE(icon_.szInfoTitle));
      lstrcpynW(icon_.szInfo, body.c_str(), ARRAYSIZE(icon_.szInfo));
      added_ = Shell_NotifyIconW(NIM_ADD, &icon_) != FALSE;
      if (added_)
        SetTimer(hwnd_, kRemoveTimer, 10000, nullptr);
    }

  private:
    static constexpr UINT_PTR kRemoveTimer = 1;
    HWND hwnd_ = nullptr;
    NOTIFYICONDATAW icon_{};
    bool added_ = false;

    bool EnsureWindow()
    {
      if (hwnd_)
        return true;
      WNDCLASSW wc = {0};
      wc.lpfnWndProc = WindowProc;
      wc.hInstance = GetModuleHandle(nullptr);
      wc.lpszClassName = L"AmpedToastWindow";
      RegisterClassW(&wc);
      hwnd_ = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0,
                              HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
      if (hwnd_)
        SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
      return hwnd_ != nullptr;
    }

    void Remove()
    {
      if (!added_)
        return;
      KillTimer(hwnd_, kRemoveTimer);
      Shell_NotifyIconW(NIM_DELETE, &icon_);
      added_ = false;
    }

    static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wParam,
                                       LPARAM lParam)
    {
      if (msg == WM_TIMER && wParam == kRemoveTimer)
      {
        auto *self = reinterpret_cast<ToastNotifier *>(
            GetWindowLongPtr(hwnd, GWLP_USERDATA));
        if (self)
          self->Remove();
        return 0;
      }
      return DefWindowProc(hwnd, msg, wParam, lParam);
    }
  };

}
