import "dart:ffi";

import "package:ffi/ffi.dart";

typedef FDDropCallbackNative = Void Function(Int64 token, Pointer<Utf8> path);

@Native<
  Void Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Int32,
    Pointer<NativeFunction<FDDropCallbackNative>>,
    Int64,
  )
>(symbol: "fd_enable_file_drop")
external void fdEnableFileDrop(
  Pointer<Void> handle,
  Pointer<Utf8> extensions,
  int directories,
  Pointer<NativeFunction<FDDropCallbackNative>> callback,
  int token,
);
