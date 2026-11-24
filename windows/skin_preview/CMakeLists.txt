# The Explorer preview handler and thumbnail provider for skins,
# installed next to the executable, which registers it
# (lib/src/platform/file_types.dart).
enable_language(C)

set(SKIN_PREVIEW_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../native/skin_preview")
add_library(amped_skin_preview SHARED
  "skin_preview_shell.cpp"
  "skin_preview_shell.def"
  "${SKIN_PREVIEW_DIR}/skin_preview.c"
)
target_include_directories(amped_skin_preview PRIVATE "${SKIN_PREVIEW_DIR}")
# Explorer loads the DLL into dllhost.exe and prevhost.exe, which have neither
# the app's directory nor Visual Studio's debug runtime on their search path, so
# a DLL linked to the dynamic CRT (vcruntime140d.dll in Debug builds) fails to
# load there and Explorer silently shows plain icons. Link the CRT statically.
set_property(TARGET amped_skin_preview PROPERTY MSVC_RUNTIME_LIBRARY
  "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_compile_features(amped_skin_preview PRIVATE cxx_std_17)
target_compile_options(amped_skin_preview PRIVATE /W4 /wd4100)
target_compile_definitions(amped_skin_preview PRIVATE
  "NOMINMAX" "UNICODE" "_UNICODE" "_CRT_SECURE_NO_WARNINGS")
target_link_libraries(amped_skin_preview PRIVATE
  "shlwapi.lib" "msimg32.lib" "ole32.lib")
