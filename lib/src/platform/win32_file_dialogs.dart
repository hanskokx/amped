import "dart:ffi";

import "package:ffi/ffi.dart";

// The common file dialogs the original uses: GetOpenFileName and
// GetSaveFileName (with a filter list and remembered filter index), and
// SHBrowseForFolder for folders.

final DynamicLibrary _comdlg32 = DynamicLibrary.open("comdlg32.dll");
final DynamicLibrary _shell32 = DynamicLibrary.open("shell32.dll");
final DynamicLibrary _ole32 = DynamicLibrary.open("ole32.dll");

final class _OpenFileName extends Struct {
  @Uint32()
  external int lStructSize;

  external Pointer<Void> hwndOwner;

  external Pointer<Void> hInstance;

  external Pointer<Utf16> lpstrFilter;

  external Pointer<Utf16> lpstrCustomFilter;

  @Uint32()
  external int nMaxCustFilter;

  @Uint32()
  external int nFilterIndex;

  external Pointer<Utf16> lpstrFile;

  @Uint32()
  external int nMaxFile;

  external Pointer<Utf16> lpstrFileTitle;

  @Uint32()
  external int nMaxFileTitle;

  external Pointer<Utf16> lpstrInitialDir;

  external Pointer<Utf16> lpstrTitle;

  @Uint32()
  external int flags;

  @Uint16()
  external int nFileOffset;

  @Uint16()
  external int nFileExtension;

  external Pointer<Utf16> lpstrDefExt;

  @IntPtr()
  external int lCustData;

  external Pointer<Void> lpfnHook;

  external Pointer<Utf16> lpTemplateName;

  external Pointer<Void> pvReserved;

  @Uint32()
  external int dwReserved;

  @Uint32()
  external int flagsEx;
}

final class _BrowseInfo extends Struct {
  external Pointer<Void> hwndOwner;

  external Pointer<Void> pidlRoot;

  external Pointer<Utf16> pszDisplayName;

  external Pointer<Utf16> lpszTitle;

  @Uint32()
  external int ulFlags;

  external Pointer<Void> lpfn;

  @IntPtr()
  external int lParam;

  @Int32()
  external int iImage;
}

typedef _FileNameNative = Int32 Function(Pointer<_OpenFileName>);
typedef _FileName = int Function(Pointer<_OpenFileName>);

final _FileName _getOpenFileName = _comdlg32
    .lookupFunction<_FileNameNative, _FileName>("GetOpenFileNameW");
final _FileName _getSaveFileName = _comdlg32
    .lookupFunction<_FileNameNative, _FileName>("GetSaveFileNameW");

final Pointer<Void> Function(Pointer<_BrowseInfo>) _shBrowseForFolder = _shell32
    .lookupFunction<
      Pointer<Void> Function(Pointer<_BrowseInfo>),
      Pointer<Void> Function(Pointer<_BrowseInfo>)
    >("SHBrowseForFolderW");
final int Function(Pointer<Void>, Pointer<Utf16>) _shGetPathFromIDList =
    _shell32.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf16>),
      int Function(Pointer<Void>, Pointer<Utf16>)
    >("SHGetPathFromIDListW");
final void Function(Pointer<Void>) _coTaskMemFree = _ole32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      "CoTaskMemFree",
    );

const int _ofnOverwritePrompt = 0x00000002;
const int _ofnHideReadOnly = 0x00000004;
const int _ofnNoChangeDir = 0x00000008;
const int _ofnAllowMultiSelect = 0x00000200;
const int _ofnPathMustExist = 0x00000800;
const int _ofnFileMustExist = 0x00001000;
const int _ofnExplorer = 0x00080000;

const int _bifReturnOnlyFsDirs = 0x0001;
const int _bifNewDialogStyle = 0x0040;

const int _maxPath = 260;

/// A filter list in the dialogs' format: label, NUL, patterns, NUL, ...,
/// with a final extra NUL. Each type is `(label, [extensions])`.
Pointer<Utf16> _filter(
  List<(String, List<String>)> types,
  Allocator allocator,
) {
  final buffer = StringBuffer();
  for (final (label, extensions) in types) {
    buffer
      ..write(label)
      ..write("\u0000")
      ..write(
        extensions.isEmpty
            ? "*.*"
            : extensions.map((extension) => "*.$extension").join(";"),
      )
      ..write("\u0000");
  }
  buffer.write("\u0000");
  return buffer.toString().toNativeUtf16(allocator: allocator);
}

/// Reads the UTF-16 string at [offset] characters into [buffer].
String _stringAt(Pointer<Utf16> buffer, int offset) =>
    Pointer<Utf16>.fromAddress(buffer.address + offset * 2).toDartString();

/// GetOpenFileName: the picked files (several with [multiple]), or none.
List<String> win32OpenFiles({
  required Pointer<Void> owner,
  required String title,
  required List<(String, List<String>)> types,
  required bool multiple,
}) => using((arena) {
  const length = 0x10000;
  final file = arena<Uint16>(length).cast<Utf16>();
  final info = arena<_OpenFileName>();
  info.ref
    ..lStructSize = sizeOf<_OpenFileName>()
    ..hwndOwner = owner
    ..lpstrFilter = _filter(types, arena)
    ..nFilterIndex = 1
    ..lpstrFile = file
    ..nMaxFile = length
    ..lpstrTitle = title.toNativeUtf16(allocator: arena)
    ..flags =
        _ofnExplorer |
        _ofnHideReadOnly |
        _ofnNoChangeDir |
        _ofnPathMustExist |
        _ofnFileMustExist |
        (multiple ? _ofnAllowMultiSelect : 0);
  if (_getOpenFileName(info) == 0) return const <String>[];
  // One file: its full path. Several: the folder, then each name, each
  // NUL-terminated, ending with an empty string.
  final first = _stringAt(file, 0);
  final names = <String>[];
  var offset = first.length + 1;
  while (true) {
    final name = _stringAt(file, offset);
    if (name.isEmpty) break;
    names.add(name);
    offset += name.length + 1;
  }
  if (names.isEmpty) return [first];
  final folder = first.endsWith(r"\") ? first : "$first\\";
  return [for (final name in names) "$folder$name"];
});

/// GetSaveFileName with [types] to choose from, starting at [typeIndex]
/// (zero-based). Returns the path and the chosen type's index, or `null`
/// when cancelled.
(String, int)? win32SaveFile({
  required Pointer<Void> owner,
  required String title,
  required String name,
  required List<(String, List<String>)> types,
  required int typeIndex,
}) => using((arena) {
  final file = arena<Uint16>(_maxPath * 4).cast<Utf16>();
  final initial = name.codeUnits;
  for (var i = 0; i < initial.length && i < _maxPath; i++) {
    file.cast<Uint16>()[i] = initial[i];
  }
  final defaultExtension = types.isEmpty || types.first.$2.isEmpty
      ? null
      : types.first.$2.first;
  final info = arena<_OpenFileName>();
  info.ref
    ..lStructSize = sizeOf<_OpenFileName>()
    ..hwndOwner = owner
    ..lpstrFilter = _filter(types, arena)
    ..nFilterIndex = typeIndex + 1
    ..lpstrFile = file
    ..nMaxFile = _maxPath * 4
    ..lpstrTitle = title.toNativeUtf16(allocator: arena)
    ..lpstrDefExt = defaultExtension == null
        ? nullptr
        : defaultExtension.toNativeUtf16(allocator: arena)
    ..flags = _ofnExplorer | _ofnHideReadOnly | _ofnOverwritePrompt;
  if (_getSaveFileName(info) == 0) return null;
  final index = (info.ref.nFilterIndex - 1).clamp(0, types.length - 1);
  return (file.toDartString(), index);
});

/// SHBrowseForFolder: the picked folder, or `null`.
String? win32PickFolder({
  required Pointer<Void> owner,
  required String title,
}) => using((arena) {
  final display = arena<Uint16>(_maxPath).cast<Utf16>();
  final info = arena<_BrowseInfo>();
  info.ref
    ..hwndOwner = owner
    ..pszDisplayName = display
    ..lpszTitle = title.toNativeUtf16(allocator: arena)
    ..ulFlags = _bifReturnOnlyFsDirs | _bifNewDialogStyle;
  final list = _shBrowseForFolder(info);
  if (list == nullptr) return null;
  final path = arena<Uint16>(_maxPath * 4).cast<Utf16>();
  final found = _shGetPathFromIDList(list, path) != 0;
  _coTaskMemFree(list);
  return found ? path.toDartString() : null;
});
