import "dart:ffi";
import "dart:ui";

import "package:ffi/ffi.dart";

// Win32 works in physical pixels; window_dock works in logical pixels. The
// conversion uses the system DPI, which is exact on single-DPI setups (mixed
// per-monitor DPI layouts are approximated).

final DynamicLibrary _user32 = DynamicLibrary.open("user32.dll");
final DynamicLibrary _gdi32 = DynamicLibrary.open("gdi32.dll");
final DynamicLibrary _dwmapi = DynamicLibrary.open("dwmapi.dll");

final class _Rect extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int top;

  @Int32()
  external int right;

  @Int32()
  external int bottom;
}

final class _Point extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _Margins extends Struct {
  @Int32()
  external int left;

  @Int32()
  external int right;

  @Int32()
  external int top;

  @Int32()
  external int bottom;
}

/// `ACCENT_POLICY`.
final class _AccentPolicy extends Struct {
  @Int32()
  external int accentState;

  @Int32()
  external int accentFlags;

  @Int32()
  external int gradientColor;

  @Int32()
  external int animationId;
}

/// `WINDOWCOMPOSITIONATTRIBDATA`.
final class _CompositionAttribute extends Struct {
  @Int32()
  external int attribute;

  external Pointer<Void> data;

  @Uint32()
  external int size;
}

final class _MonitorInfo extends Struct {
  @Uint32()
  external int cbSize;

  external _Rect rcMonitor;

  external _Rect rcWork;

  @Uint32()
  external int dwFlags;
}

const int swHide = 0;
const int swShowNoActivate = 4;
const int swMinimize = 6;

const int _gwlStyle = -16;
const int _wsPopup = 0x80000000;
const int _wsVisible = 0x10000000;
const int _wsMinimizeBox = 0x00020000;
const int _wsOverlappedWindow = 0x00CF0000;
const int _swpNoSize = 0x0001;
const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;

final _getWindowLongPtr = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)
    >(
      "GetWindowLongPtrW",
    );
final _setWindowLongPtr = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, IntPtr),
      int Function(Pointer<Void>, int, int)
    >("SetWindowLongPtrW");
final _setWindowPos = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(Pointer<Void>, int, int, int, int, int, int)
    >("SetWindowPos");
final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_Rect>),
      int Function(Pointer<Void>, Pointer<_Rect>)
    >("GetWindowRect");
final _showWindow = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)
    >(
      "ShowWindow",
    );
final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      "IsWindowVisible",
    );
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      "SetForegroundWindow",
    );
final _getCursorPos = _user32
    .lookupFunction<
      Int32 Function(Pointer<_Point>),
      int Function(Pointer<_Point>)
    >(
      "GetCursorPos",
    );
final _getDpiForSystem = _user32
    .lookupFunction<Uint32 Function(), int Function()>(
      "GetDpiForSystem",
    );
final _enumDisplayMonitors = _user32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<_Rect>,
        Pointer<
          NativeFunction<Int32 Function(IntPtr, IntPtr, Pointer<_Rect>, IntPtr)>
        >,
        IntPtr,
      ),
      int Function(
        Pointer<Void>,
        Pointer<_Rect>,
        Pointer<
          NativeFunction<Int32 Function(IntPtr, IntPtr, Pointer<_Rect>, IntPtr)>
        >,
        int,
      )
    >("EnumDisplayMonitors");
final _getMonitorInfo = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_MonitorInfo>),
      int Function(int, Pointer<_MonitorInfo>)
    >("GetMonitorInfoW");

final _monitorFromWindow = _user32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >("MonitorFromWindow");

const int _monitorDefaultToNearest = 2;

/// The whole rectangle of the monitor [hwnd] is mostly on (taskbar
/// included).
Rect monitorRect(Pointer<Void> hwnd) => using((arena) {
  final info = arena<_MonitorInfo>()..ref.cbSize = sizeOf<_MonitorInfo>();
  _getMonitorInfo(_monitorFromWindow(hwnd, _monitorDefaultToNearest), info);
  return _toLogical(info.ref.rcMonitor);
});

double get _scale => _getDpiForSystem() / 96.0;

Rect _toLogical(_Rect r) {
  final s = _scale;
  return Rect.fromLTRB(r.left / s, r.top / s, r.right / s, r.bottom / s);
}

void makeFrameless(Pointer<Void> hwnd) {
  final frame = windowRect(hwnd);
  var style = _getWindowLongPtr(hwnd, _gwlStyle);
  style &= ~_wsOverlappedWindow;
  style |= _wsPopup | _wsMinimizeBox | (style & _wsVisible);
  _setWindowLongPtr(hwnd, _gwlStyle, style);
  _setWindowPos(
    hwnd,
    0,
    0,
    0,
    0,
    0,
    _swpNoMove | _swpNoSize | _swpNoZOrder | _swpNoActivate | _swpFrameChanged,
  );
  setWindowRect(hwnd, frame);
}

Rect windowRect(Pointer<Void> hwnd) {
  return using((arena) {
    final rect = arena<_Rect>();
    _getWindowRect(hwnd, rect);
    return _toLogical(rect.ref);
  });
}

void setWindowRect(Pointer<Void> hwnd, Rect rect) {
  final s = _scale;
  _setWindowPos(
    hwnd,
    0,
    (rect.left * s).round(),
    (rect.top * s).round(),
    (rect.width * s).round(),
    (rect.height * s).round(),
    _swpNoZOrder | _swpNoActivate,
  );
}

void setWindowPosition(Pointer<Void> hwnd, Offset topLeft) {
  final s = _scale;
  _setWindowPos(
    hwnd,
    0,
    (topLeft.dx * s).round(),
    (topLeft.dy * s).round(),
    0,
    0,
    _swpNoSize | _swpNoZOrder | _swpNoActivate,
  );
}

void setTopmost(Pointer<Void> hwnd, bool topmost) {
  _setWindowPos(
    hwnd,
    topmost ? -1 : -2, // HWND_TOPMOST / HWND_NOTOPMOST
    0,
    0,
    0,
    0,
    _swpNoMove | _swpNoSize | _swpNoActivate,
  );
}

bool isVisible(Pointer<Void> hwnd) => _isWindowVisible(hwnd) != 0;

void showWindow(Pointer<Void> hwnd, int command) => _showWindow(hwnd, command);

void focus(Pointer<Void> hwnd) {
  _showWindow(hwnd, 5); // SW_SHOW
  _setForegroundWindow(hwnd);
}

Offset cursorPosition() {
  return using((arena) {
    final point = arena<_Point>();
    _getCursorPos(point);
    final s = _scale;
    return Offset(point.ref.x / s, point.ref.y / s);
  });
}

final List<Rect> _collected = [];

int _monitorCallback(int monitor, int hdc, Pointer<_Rect> rect, int data) {
  using((arena) {
    final info = arena<_MonitorInfo>()..ref.cbSize = sizeOf<_MonitorInfo>();
    if (_getMonitorInfo(monitor, info) != 0) {
      _collected.add(_toLogical(info.ref.rcWork));
    }
  });
  return 1;
}

List<Rect> workAreas() {
  _collected.clear();
  final callback =
      NativeCallable<
        Int32 Function(IntPtr, IntPtr, Pointer<_Rect>, IntPtr)
      >.isolateLocal(
        _monitorCallback,
        exceptionalReturn: 0,
      );
  _enumDisplayMonitors(nullptr, nullptr, callback.nativeFunction, 0);
  callback.close();
  return List.of(_collected);
}

final _dwmExtendFrameIntoClientArea = _dwmapi
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_Margins>),
      int Function(Pointer<Void>, Pointer<_Margins>)
    >("DwmExtendFrameIntoClientArea");
final _setWindowCompositionAttribute = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<_CompositionAttribute>),
      int Function(Pointer<Void>, Pointer<_CompositionAttribute>)
    >("SetWindowCompositionAttribute");
final _createPolygonRgn = _gdi32
    .lookupFunction<
      Pointer<Void> Function(Pointer<_Point>, Int32, Int32),
      Pointer<Void> Function(Pointer<_Point>, int, int)
    >("CreatePolygonRgn");
final _combineRgn = _gdi32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Int32),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, int)
    >("CombineRgn");
final _createRectRgn = _gdi32
    .lookupFunction<
      Pointer<Void> Function(Int32, Int32, Int32, Int32),
      Pointer<Void> Function(int, int, int, int)
    >("CreateRectRgn");
final _deleteObject = _gdi32
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      "DeleteObject",
    );
final _setWindowRgn = _user32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Int32),
      int Function(Pointer<Void>, Pointer<Void>, int)
    >("SetWindowRgn");

const int _wcaAccentPolicy = 19;
const int _accentEnableTransparentGradient = 2;
const int _polyFillWinding = 2;
const int _rgnOr = 2;

/// Lets what the window's content leaves transparent show the desktop: the
/// frame is extended over the whole window (as `flutter_acrylic` does) and
/// the window gets a fully transparent accent.
void makeTransparent(Pointer<Void> hwnd) => using((arena) {
  final margins = arena<_Margins>()
    ..ref.left = -1
    ..ref.right = -1
    ..ref.top = -1
    ..ref.bottom = -1;
  _dwmExtendFrameIntoClientArea(hwnd, margins);
  final accent = arena<_AccentPolicy>()
    ..ref.accentState = _accentEnableTransparentGradient
    ..ref.accentFlags = 2
    ..ref.gradientColor = 0
    ..ref.animationId = 0;
  final data = arena<_CompositionAttribute>()
    ..ref.attribute = _wcaAccentPolicy
    ..ref.data = accent.cast()
    ..ref.size = sizeOf<_AccentPolicy>();
  _setWindowCompositionAttribute(hwnd, data);
});

/// Cuts the window to [polygons] (logical pixels from its top-left corner,
/// combined with the nonzero rule), or back to its full rectangle for
/// `null`: `SetWindowRgn`.
void setShape(Pointer<Void> hwnd, List<List<Offset>>? polygons) {
  if (polygons == null || polygons.every((p) => p.length < 3)) {
    _setWindowRgn(hwnd, nullptr, 1);
    return;
  }
  final s = _scale;
  final region = _createRectRgn(0, 0, 0, 0);
  for (final polygon in polygons) {
    if (polygon.length < 3) continue;
    using((arena) {
      final points = arena<_Point>(polygon.length);
      for (final (i, point) in polygon.indexed) {
        points[i]
          ..x = (point.dx * s).round()
          ..y = (point.dy * s).round();
      }
      final piece = _createPolygonRgn(points, polygon.length, _polyFillWinding);
      if (piece != nullptr) {
        _combineRgn(region, region, piece, _rgnOr);
        _deleteObject(piece);
      }
    });
  }
  // The window owns the region from here on.
  if (_setWindowRgn(hwnd, region, 1) == 0) _deleteObject(region);
}
