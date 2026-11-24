// Explorer's preview pane handler (IPreviewHandler) and thumbnail provider
// (IThumbnailProvider) for skins (.wsz, .wal), drawn by the shared
// renderer in native/skin_preview. lib/src/platform/file_types.dart registers
// the two classes for the current user.

#include <windows.h>

#include <algorithm>
#include <new>
#include <objbase.h>
#include <propsys.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <thumbcache.h>

#include <string.h>

#include "skin_preview.h"

// {F0885A9F-81E6-456B-9A0A-CD4927BF4538}
static const CLSID kPreviewHandlerClsid = {
    0xf0885a9f, 0x81e6, 0x456b,
    {0x9a, 0x0a, 0xcd, 0x49, 0x27, 0xbf, 0x45, 0x38}};
// {BCFF163F-3A50-41F1-BB4A-15B2298A603B}
static const CLSID kThumbnailProviderClsid = {
    0xbcff163f, 0x3a50, 0x41f1,
    {0xbb, 0x4a, 0x15, 0xb2, 0x29, 0x8a, 0x60, 0x3b}};

static LONG g_objects = 0;
static LONG g_locks = 0;
static HINSTANCE g_instance = nullptr;

namespace {

// Reads the whole stream (skins are a few hundred kilobytes at most).
bool ReadStream(IStream* stream, BYTE** data, ULONG* size) {
  STATSTG stat;
  if (FAILED(stream->Stat(&stat, STATFLAG_NONAME)) ||
      stat.cbSize.QuadPart > (64u << 20)) {
    return false;
  }
  ULONG length = static_cast<ULONG>(stat.cbSize.QuadPart);
  BYTE* buffer = static_cast<BYTE*>(malloc(length ? length : 1));
  if (!buffer) return false;
  LARGE_INTEGER start = {};
  stream->Seek(start, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  if (FAILED(stream->Read(buffer, length, &read)) || read != length) {
    free(buffer);
    return false;
  }
  *data = buffer;
  *size = length;
  return true;
}

// The skin's name, upper-cased for the song title display, from the
// stream's file name.
void TitleOf(IStream* stream, char* title, int size) {
  title[0] = 0;
  STATSTG stat;
  if (FAILED(stream->Stat(&stat, STATFLAG_DEFAULT)) || !stat.pwcsName) return;
  PathRemoveExtensionW(stat.pwcsName);
  for (WCHAR* c = stat.pwcsName; *c; c++) {
    if (*c == L'_') *c = L' ';
  }
  CharUpperW(stat.pwcsName);
  WideCharToMultiByte(CP_UTF8, 0, stat.pwcsName, -1, title, size, nullptr,
                      nullptr);
  CoTaskMemFree(stat.pwcsName);
}

bool Render(IStream* stream, int layout, SkinPreviewImage* image) {
  BYTE* data = nullptr;
  ULONG size = 0;
  if (!ReadStream(stream, &data, &size)) return false;
  char title[128];
  TitleOf(stream, title, static_cast<int>(sizeof(title)));
  bool ok = skin_preview_render(data, size, title, layout, image) == 0;
  free(data);
  return ok;
}

// A top-down 32-bit DIB section with premultiplied BGRA pixels.
HBITMAP CreateBitmap(const SkinPreviewImage& image) {
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = image.width;
  info.bmiHeader.biHeight = -image.height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  BYTE* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS,
                                    reinterpret_cast<void**>(&bits), nullptr, 0);
  if (!bitmap) return nullptr;
  size_t count = static_cast<size_t>(image.width) * image.height;
  for (size_t i = 0; i < count; i++) {
    const uint8_t* src = image.rgba + i * 4;
    BYTE* dst = bits + i * 4;
    dst[0] = static_cast<BYTE>(src[2] * src[3] / 255);
    dst[1] = static_cast<BYTE>(src[1] * src[3] / 255);
    dst[2] = static_cast<BYTE>(src[0] * src[3] / 255);
    dst[3] = src[3];
  }
  return bitmap;
}

// --- Thumbnail provider ------------------------------------------------------

class ThumbnailProvider : public IThumbnailProvider, public IInitializeWithStream {
 public:
  ThumbnailProvider() { InterlockedIncrement(&g_objects); }

  // IUnknown
  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    static const QITAB kInterfaces[] = {
        QITABENT(ThumbnailProvider, IThumbnailProvider),
        QITABENT(ThumbnailProvider, IInitializeWithStream),
        {nullptr, 0},
    };
    return QISearch(this, kInterfaces, riid, object);
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  IFACEMETHODIMP_(ULONG) Release() override {
    ULONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) delete this;
    return refs;
  }

  // IInitializeWithStream
  IFACEMETHODIMP Initialize(IStream* stream, DWORD) override {
    if (stream_) return HRESULT_FROM_WIN32(ERROR_ALREADY_INITIALIZED);
    stream_ = stream;
    stream_->AddRef();
    return S_OK;
  }

  // IThumbnailProvider: the main window, equalizer and a short playlist
  // editor, filling `cx` x `cx`.
  IFACEMETHODIMP GetThumbnail(UINT cx, HBITMAP* bitmap,
                              WTS_ALPHATYPE* alpha) override {
    if (!stream_) return E_UNEXPECTED;
    SkinPreviewImage image, fitted;
    if (!Render(stream_, SKIN_PREVIEW_ICON, &image)) return E_FAIL;
    int failed = skin_preview_fit(&image, static_cast<int>(cx), &fitted);
    skin_preview_free(&image);
    if (failed) return E_OUTOFMEMORY;
    *bitmap = CreateBitmap(fitted);
    skin_preview_free(&fitted);
    if (!*bitmap) return E_OUTOFMEMORY;
    *alpha = WTSAT_ARGB;
    return S_OK;
  }

 private:
  ~ThumbnailProvider() {
    if (stream_) stream_->Release();
    InterlockedDecrement(&g_objects);
  }

  LONG refs_ = 1;
  IStream* stream_ = nullptr;
};

// --- Preview handler ---------------------------------------------------------

class PreviewHandler : public IPreviewHandler,
                       public IInitializeWithStream,
                       public IObjectWithSite,
                       public IOleWindow {
 public:
  PreviewHandler() { InterlockedIncrement(&g_objects); }

  // IUnknown
  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    static const QITAB kInterfaces[] = {
        QITABENT(PreviewHandler, IPreviewHandler),
        QITABENT(PreviewHandler, IInitializeWithStream),
        QITABENT(PreviewHandler, IObjectWithSite),
        QITABENT(PreviewHandler, IOleWindow),
        {nullptr, 0},
    };
    return QISearch(this, kInterfaces, riid, object);
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  IFACEMETHODIMP_(ULONG) Release() override {
    ULONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) delete this;
    return refs;
  }

  // IInitializeWithStream
  IFACEMETHODIMP Initialize(IStream* stream, DWORD) override {
    if (stream_) return HRESULT_FROM_WIN32(ERROR_ALREADY_INITIALIZED);
    stream_ = stream;
    stream_->AddRef();
    return S_OK;
  }

  // IObjectWithSite
  IFACEMETHODIMP SetSite(IUnknown* site) override {
    if (site_) site_->Release();
    site_ = site;
    if (site_) site_->AddRef();
    return S_OK;
  }
  IFACEMETHODIMP GetSite(REFIID riid, void** site) override {
    *site = nullptr;
    return site_ ? site_->QueryInterface(riid, site) : E_FAIL;
  }

  // IOleWindow
  IFACEMETHODIMP GetWindow(HWND* window) override {
    *window = window_;
    return window_ ? S_OK : E_FAIL;
  }
  IFACEMETHODIMP ContextSensitiveHelp(BOOL) override { return E_NOTIMPL; }

  // IPreviewHandler
  IFACEMETHODIMP SetWindow(HWND parent, const RECT* rect) override {
    parent_ = parent;
    rect_ = *rect;
    if (window_) {
      SetParent(window_, parent_);
      MoveWindow(window_, rect_.left, rect_.top, rect_.right - rect_.left,
                 rect_.bottom - rect_.top, TRUE);
    }
    return S_OK;
  }
  IFACEMETHODIMP SetRect(const RECT* rect) override {
    rect_ = *rect;
    if (window_) {
      MoveWindow(window_, rect_.left, rect_.top, rect_.right - rect_.left,
                 rect_.bottom - rect_.top, TRUE);
    }
    return S_OK;
  }
  IFACEMETHODIMP DoPreview() override {
    if (window_ || !stream_) return E_UNEXPECTED;
    if (!Render(stream_, SKIN_PREVIEW_STACK, &image_)) return E_FAIL;
    RegisterWindowClass();
    window_ = CreateWindowExW(
        0, kWindowClass, nullptr, WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        rect_.left, rect_.top, rect_.right - rect_.left,
        rect_.bottom - rect_.top, parent_, nullptr, g_instance, this);
    return window_ ? S_OK : HRESULT_FROM_WIN32(GetLastError());
  }
  IFACEMETHODIMP Unload() override {
    if (window_) {
      DestroyWindow(window_);
      window_ = nullptr;
    }
    if (stream_) {
      stream_->Release();
      stream_ = nullptr;
    }
    skin_preview_free(&image_);
    return S_OK;
  }
  IFACEMETHODIMP SetFocus() override { return S_FALSE; }
  IFACEMETHODIMP QueryFocus(HWND* window) override {
    *window = GetFocus();
    return *window ? S_OK : HRESULT_FROM_WIN32(GetLastError());
  }
  IFACEMETHODIMP TranslateAccelerator(MSG* message) override {
    IPreviewHandlerFrame* frame = nullptr;
    if (!site_ || FAILED(site_->QueryInterface(IID_PPV_ARGS(&frame)))) {
      return S_FALSE;
    }
    HRESULT result = frame->TranslateAccelerator(message);
    frame->Release();
    return result;
  }

  static const wchar_t kWindowClass[];

 private:
  // Registered once per process; later calls fail harmlessly.
  static void RegisterWindowClass() {
    WNDCLASSW window_class = {};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = g_instance;
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClass;
    RegisterClassW(&window_class);
  }

  ~PreviewHandler() {
    Unload();
    SetSite(nullptr);
    InterlockedDecrement(&g_objects);
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    if (message == WM_NCCREATE) {
      auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto self = reinterpret_cast<PreviewHandler*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (self && message == WM_PAINT) {
      self->Paint(window);
      return 0;
    }
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_SIZE) InvalidateRect(window, nullptr, FALSE);
    return DefWindowProcW(window, message, wparam, lparam);
  }

  // Centers the skin, enlarged by whole factors while it fits (the classic player's
  // double size mode), or shrunk to fit a small pane.
  void Paint(HWND window) {
    PAINTSTRUCT paint;
    HDC dc = BeginPaint(window, &paint);
    RECT client;
    GetClientRect(window, &client);
    int width = client.right, height = client.bottom;
    HDC buffer = CreateCompatibleDC(dc);
    HBITMAP canvas = CreateCompatibleBitmap(dc, width, height);
    HGDIOBJ old_canvas = SelectObject(buffer, canvas);
    FillRect(buffer, &client, GetSysColorBrush(COLOR_WINDOW));
    if (image_.rgba && width > 0 && height > 0) {
      int longest = std::max(image_.width, image_.height);
      int factor = std::min(width / image_.width, height / image_.height);
      int size = factor >= 1
                     ? longest * factor
                     : static_cast<int>(
                           longest *
                           std::min(static_cast<double>(width) / image_.width,
                                    static_cast<double>(height) / image_.height));
      SkinPreviewImage fitted = {};
      HBITMAP bitmap = nullptr;
      if (skin_preview_fit(&image_, std::max(1, size), &fitted) == 0) {
        bitmap = CreateBitmap(fitted);
      }
      if (bitmap) {
        HDC source = CreateCompatibleDC(dc);
        HGDIOBJ old_source = SelectObject(source, bitmap);
        BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
        AlphaBlend(buffer, (width - fitted.width) / 2,
                   (height - fitted.height) / 2, fitted.width, fitted.height,
                   source, 0, 0, fitted.width, fitted.height, blend);
        SelectObject(source, old_source);
        DeleteDC(source);
        DeleteObject(bitmap);
      }
      skin_preview_free(&fitted);
    }
    BitBlt(dc, 0, 0, width, height, buffer, 0, 0, SRCCOPY);
    SelectObject(buffer, old_canvas);
    DeleteObject(canvas);
    DeleteDC(buffer);
    EndPaint(window, &paint);
  }

  LONG refs_ = 1;
  IStream* stream_ = nullptr;
  IUnknown* site_ = nullptr;
  HWND parent_ = nullptr;
  HWND window_ = nullptr;
  RECT rect_ = {};
  SkinPreviewImage image_ = {};
};

const wchar_t PreviewHandler::kWindowClass[] = L"AmpedSkinPreview";

// --- Class factory -----------------------------------------------------------

template <typename T>
class ClassFactory : public IClassFactory {
 public:
  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    static const QITAB kInterfaces[] = {
        QITABENT(ClassFactory, IClassFactory),
        {nullptr, 0},
    };
    return QISearch(this, kInterfaces, riid, object);
  }
  // The factories are static.
  IFACEMETHODIMP_(ULONG) AddRef() override { return 2; }
  IFACEMETHODIMP_(ULONG) Release() override { return 1; }

  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID riid,
                                void** object) override {
    *object = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    T* instance = new (std::nothrow) T();
    if (!instance) return E_OUTOFMEMORY;
    HRESULT result = instance->QueryInterface(riid, object);
    instance->Release();
    return result;
  }
  IFACEMETHODIMP LockServer(BOOL lock) override {
    if (lock) {
      InterlockedIncrement(&g_locks);
    } else {
      InterlockedDecrement(&g_locks);
    }
    return S_OK;
  }
};

ClassFactory<PreviewHandler> g_preview_factory;
ClassFactory<ThumbnailProvider> g_thumbnail_factory;

}  // namespace

BOOL APIENTRY DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_instance = instance;
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** object) {
  if (IsEqualCLSID(clsid, kPreviewHandlerClsid)) {
    return g_preview_factory.QueryInterface(riid, object);
  }
  if (IsEqualCLSID(clsid, kThumbnailProviderClsid)) {
    return g_thumbnail_factory.QueryInterface(riid, object);
  }
  *object = nullptr;
  return CLASS_E_CLASSNOTAVAILABLE;
}

STDAPI DllCanUnloadNow() {
  return g_objects == 0 && g_locks == 0 ? S_OK : S_FALSE;
}
