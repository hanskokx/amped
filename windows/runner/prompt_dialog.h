#ifndef RUNNER_PROMPT_DIALOG_H_
#define RUNNER_PROMPT_DIALOG_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// A small modal prompt for a line of text (e.g. "Open URL"), built from an
// in-memory dialog template so it needs no resource file.
namespace prompt_dialog
{

  struct State
  {
    std::wstring title;
    std::wstring message;
    std::wstring value;
    std::wstring confirm;
    std::wstring cancel;
    std::optional<std::wstring> result;
  };

  constexpr int kMessageId = 100;
  constexpr int kEditId = 101;

  inline INT_PTR CALLBACK Proc(HWND dialog, UINT message, WPARAM wparam,
                               LPARAM lparam)
  {
    switch (message)
    {
    case WM_INITDIALOG:
    {
      SetWindowLongPtrW(dialog, GWLP_USERDATA, lparam);
      auto *state = reinterpret_cast<State *>(lparam);
      SetDlgItemTextW(dialog, kMessageId, state->message.c_str());
      SetDlgItemTextW(dialog, kEditId, state->value.c_str());
      SendDlgItemMessageW(dialog, kEditId, EM_SETSEL, 0, -1);
      SetFocus(GetDlgItem(dialog, kEditId));
      return FALSE; // focus set above
    }
    case WM_COMMAND:
    {
      const int id = LOWORD(wparam);
      if (id == IDOK)
      {
        auto *state = reinterpret_cast<State *>(
            GetWindowLongPtrW(dialog, GWLP_USERDATA));
        const int length = GetWindowTextLengthW(GetDlgItem(dialog, kEditId));
        std::wstring text(static_cast<size_t>(length) + 1, L'\0');
        GetDlgItemTextW(dialog, kEditId, text.data(), length + 1);
        text.resize(static_cast<size_t>(length));
        state->result = text;
        EndDialog(dialog, IDOK);
        return TRUE;
      }
      if (id == IDCANCEL)
      {
        EndDialog(dialog, IDCANCEL);
        return TRUE;
      }
      break;
    }
    }
    return FALSE;
  }

  inline void Append(std::vector<uint8_t> &out, const void *data, size_t size)
  {
    const auto *bytes = static_cast<const uint8_t *>(data);
    out.insert(out.end(), bytes, bytes + size);
  }

  inline void AppendWord(std::vector<uint8_t> &out, uint16_t value)
  {
    Append(out, &value, sizeof(value));
  }

  inline void AppendString(std::vector<uint8_t> &out, const std::wstring &text)
  {
    Append(out, text.c_str(), (text.size() + 1) * sizeof(wchar_t));
  }

  inline void Align(std::vector<uint8_t> &out)
  {
    while (out.size() % 4 != 0)
      out.push_back(0);
  }

  inline void AppendItem(std::vector<uint8_t> &out, DWORD style, short x,
                         short y, short width, short height, WORD id,
                         uint16_t window_class, const std::wstring &text)
  {
    Align(out);
    DLGITEMTEMPLATE item{};
    item.style = style | WS_CHILD | WS_VISIBLE;
    item.x = x;
    item.y = y;
    item.cx = width;
    item.cy = height;
    item.id = id;
    Append(out, &item, sizeof(item));
    AppendWord(out, 0xFFFF); // predefined class follows as an ordinal
    AppendWord(out, window_class);
    AppendString(out, text);
    AppendWord(out, 0); // no creation data
  }

  // Shows the prompt; returns the entered text, or nothing when cancelled.
  inline std::optional<std::wstring> Show(HWND owner, State &state)
  {
    std::vector<uint8_t> tpl;
    DLGTEMPLATE dialog{};
    dialog.style = DS_MODALFRAME | DS_CENTER | DS_SETFONT | WS_POPUP |
                   WS_CAPTION | WS_SYSMENU;
    dialog.cdit = 4;
    dialog.cx = 220;
    dialog.cy = 76;
    Append(tpl, &dialog, sizeof(dialog));
    AppendWord(tpl, 0); // no menu
    AppendWord(tpl, 0); // default dialog class
    AppendString(tpl, state.title);
    AppendWord(tpl, 9); // font size
    AppendString(tpl, L"Segoe UI");

    // Class ordinals: 0x0080 button, 0x0081 edit, 0x0082 static.
    AppendItem(tpl, SS_LEFT, 8, 8, 204, 16, kMessageId, 0x0082, L"");
    AppendItem(tpl, WS_BORDER | WS_TABSTOP | ES_AUTOHSCROLL, 8, 26, 204, 14,
               kEditId, 0x0081, L"");
    AppendItem(tpl, WS_TABSTOP | BS_DEFPUSHBUTTON, 104, 54, 50, 14, IDOK,
               0x0080, state.confirm);
    AppendItem(tpl, WS_TABSTOP | BS_PUSHBUTTON, 162, 54, 50, 14, IDCANCEL,
               0x0080, state.cancel);

    DialogBoxIndirectParamW(GetModuleHandleW(nullptr),
                            reinterpret_cast<LPCDLGTEMPLATEW>(tpl.data()),
                            owner, Proc, reinterpret_cast<LPARAM>(&state));
    return state.result;
  }

} // namespace prompt_dialog

#endif // RUNNER_PROMPT_DIALOG_H_
