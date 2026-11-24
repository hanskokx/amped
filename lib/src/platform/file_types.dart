import "dart:ffi";
import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:ffi/ffi.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

// Makes playlists and skins open in amped when double-clicked, with the
// original's document icon. macOS declares this in Info.plist; Windows and
// Linux register at runtime, as the original registers its file types
// (`config_setup_filetypes`).

/// Bumped when what [registerFileTypes] writes changes.
const int _registrationVersion = 9;

const List<String> _playlistExtensions = ["m3u", "m3u8", "pls"];
const List<String> _skinExtensions = ["wsz", "wal"];

/// Registers the file types once per executable location.
Future<void> registerFileTypes() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  final executable = Platform.resolvedExecutable;
  final marker = "$_registrationVersion $executable";
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString("amped.file_types") == marker) return;
  try {
    if (Platform.isWindows) {
      _registerWindows(executable);
    } else {
      await _registerLinux(executable);
    }
    await prefs.setString("amped.file_types", marker);
  } on Object catch (error) {
    Arcane.log(
      "Could not register file types",
      metadata: {"error": "$error"},
      level: Level.warning,
      module: "FileTypes",
    );
  }
}

// --- Windows -----------------------------------------------------------------

final DynamicLibrary _advapi32 = DynamicLibrary.open("advapi32.dll");
final DynamicLibrary _shell32 = DynamicLibrary.open("shell32.dll");

final int Function(
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  int,
)
_regSetKeyValue = _advapi32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Void>,
        Uint32,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Void>,
        int,
      )
    >("RegSetKeyValueW");

final int Function(
  Pointer<Void>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
)
_regGetValue = _advapi32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >("RegGetValueW");

final void Function(int, int, Pointer<Void>, Pointer<Void>) _shChangeNotify =
    _shell32.lookupFunction<
      Void Function(Int32, Uint32, Pointer<Void>, Pointer<Void>),
      void Function(int, int, Pointer<Void>, Pointer<Void>)
    >("SHChangeNotify");

/// `HKEY_CURRENT_USER`, sign-extended as Windows defines it.
final Pointer<Void> _hkeyCurrentUser = Pointer.fromAddress(
  0x80000001.toSigned(32),
);

/// `HKEY_LOCAL_MACHINE`.
final Pointer<Void> _hkeyLocalMachine = Pointer.fromAddress(
  0x80000002.toSigned(32),
);
const int _regNone = 0;
const int _regSz = 1;
const int _rrfRtRegSz = 0x00000002;
const int _shcneAssocChanged = 0x08000000;

/// Sets [value] (`null`: the default value) of `HKCU\Software\Classes\[key]`
/// to [data], or to an empty `REG_NONE` value when [data] is `null` (an
/// `OpenWithProgids` entry).
void _setValue(String key, String? value, String? data) =>
    _setUserValue("Software\\Classes\\$key", value, data);

/// Sets [value] of `HKCU\[key]` as [_setValue] does.
void _setUserValue(String key, String? value, String? data) => using((arena) {
  final text = data?.toNativeUtf16(allocator: arena);
  final result = _regSetKeyValue(
    _hkeyCurrentUser,
    key.toNativeUtf16(allocator: arena),
    value == null ? nullptr : value.toNativeUtf16(allocator: arena),
    text == null ? _regNone : _regSz,
    text == null ? nullptr : text.cast(),
    text == null ? 0 : (data!.length + 1) * 2,
  );
  if (result != 0) throw StateError("RegSetKeyValue($key) failed: $result");
});

/// The default value of `Software\Classes\[key]` under [root] (`HKCU` unless
/// given), if any.
String? _defaultValue(String key, [Pointer<Void>? root]) => using((arena) {
  const capacity = 512;
  final buffer = arena<Uint16>(capacity);
  final size = arena<Uint32>()..value = capacity * 2;
  final result = _regGetValue(
    root ?? _hkeyCurrentUser,
    "Software\\Classes\\$key".toNativeUtf16(allocator: arena),
    nullptr,
    _rrfRtRegSz,
    nullptr,
    buffer.cast(),
    size,
  );
  return result == 0 ? buffer.cast<Utf16>().toDartString() : null;
});

/// Whether [progId] is registered: a description or an open command, in
/// either hive. A program that was uninstalled can leave an extension
/// pointing at a program ID that no longer exists, which Explorer shows by
/// name with a blank icon.
bool _progIdExists(String progId) {
  for (final root in [_hkeyCurrentUser, _hkeyLocalMachine]) {
    for (final key in [progId, "$progId\\shell\\open\\command"]) {
      final value = _defaultValue(key, root);
      if (value != null && value.isNotEmpty) return true;
    }
  }
  return false;
}

void _registerWindows(String executable) {
  final exe = '"$executable"';
  // The document icon is resource IDI_DOCUMENT (102) of the executable.
  final icon = "$exe,-102";

  const playlist = "Amped.Playlist";
  _setValue(playlist, null, "Amped playlist file");
  _setValue("$playlist\\DefaultIcon", null, icon);
  _setValue("$playlist\\shell", null, "Play");
  _setValue("$playlist\\shell\\open\\command", null, '$exe "%1"');
  _setValue("$playlist\\shell\\Play", null, "&Play in Amped");
  _setValue("$playlist\\shell\\Play\\command", null, '$exe "%1"');
  _setValue("$playlist\\shell\\Enqueue", null, "&Enqueue in Amped");
  _setValue("$playlist\\shell\\Enqueue\\command", null, '$exe /ADD "%1"');

  const skin = "Amped.Skin";
  _setValue(skin, null, "skin file");
  _setValue("$skin\\DefaultIcon", null, icon);
  _setValue("$skin\\shell", null, "Install");
  _setValue("$skin\\shell\\open\\command", null, '$exe "%1"');
  _setValue("$skin\\shell\\Install", null, "&Install in Amped");
  _setValue("$skin\\shell\\Install\\command", null, '$exe "%1"');

  for (final (extensions, progId) in [
    (_playlistExtensions, playlist),
    (_skinExtensions, skin),
  ]) {
    for (final extension in extensions) {
      _setValue(".$extension\\OpenWithProgids", progId, null);
      // Claim the type unless another program already has (Windows keeps
      // the user's own choice apart, under UserChoice), or the program that
      // had is gone.
      final current = _defaultValue(".$extension");
      if (current == null ||
          current.isEmpty ||
          current == progId ||
          !_progIdExists(current)) {
        _setValue(".$extension", null, progId);
      }
    }
  }
  _registerSkinPreviews(executable);
  _shChangeNotify(_shcneAssocChanged, 0, nullptr, nullptr);
}

/// Registers the Explorer preview handler and thumbnail provider for
/// skins, `amped_skin_preview.dll` next to the executable
/// (`windows/skin_preview`).
void _registerSkinPreviews(String executable) {
  final dll = "${File(executable).parent.path}\\amped_skin_preview.dll";
  if (!File(dll).existsSync()) return;
  const previewHandler = "{F0885A9F-81E6-456B-9A0A-CD4927BF4538}";
  const thumbnailProvider = "{BCFF163F-3A50-41F1-BB4A-15B2298A603B}";
  const previewHandlerName = "Amped skin preview handler";
  for (final (clsid, name) in [
    (previewHandler, previewHandlerName),
    (thumbnailProvider, "Amped skin thumbnail provider"),
  ]) {
    _setValue("CLSID\\$clsid", null, name);
    _setValue("CLSID\\$clsid\\InprocServer32", null, dll);
    _setValue("CLSID\\$clsid\\InprocServer32", "ThreadingModel", "Apartment");
  }
  // Preview handlers run in prevhost.exe, the 64-bit one under this AppID.
  _setValue(
    "CLSID\\$previewHandler",
    "AppID",
    "{6d2b5079-2f0b-48dd-ab7f-97cec514d30b}",
  );
  _setValue("CLSID\\$previewHandler", "DisplayName", previewHandlerName);
  _setUserValue(
    "Software\\Microsoft\\Windows\\CurrentVersion\\PreviewHandlers",
    previewHandler,
    previewHandlerName,
  );
  // IPreviewHandler and IThumbnailProvider.
  for (final extension in _skinExtensions) {
    _setValue(
      ".$extension\\ShellEx\\{8895b1c6-b41f-4c1c-a562-0d564250836f}",
      null,
      previewHandler,
    );
    _setValue(
      ".$extension\\ShellEx\\{e357fccd-a995-4576-b01f-234630154e96}",
      null,
      thumbnailProvider,
    );
  }
}

// --- Linux -------------------------------------------------------------------

/// The desktop entry's name; matches the application ID GTK reports.
const String _desktopId = "org.hadak.amped";

const String _mimeInfo = """
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-amped-skin">
    <comment>skin</comment>
    <sub-class-of type="application/zip"/>
    <icon name="amped-skin"/>
    <glob pattern="*.wsz"/>
    <glob pattern="*.wal"/>
  </mime-type>
  <mime-type type="audio/x-mpegurl">
    <icon name="amped-playlist"/>
    <glob pattern="*.m3u"/>
    <glob pattern="*.m3u8"/>
  </mime-type>
  <mime-type type="audio/x-scpls">
    <icon name="amped-playlist"/>
    <glob pattern="*.pls"/>
  </mime-type>
</mime-info>
""";

const List<String> _playlistTypes = [
  "audio/x-mpegurl",
  "application/vnd.apple.mpegurl",
  "audio/x-scpls",
];
const String _skinType = "application/x-amped-skin";
const List<String> _audioTypes = [
  "audio/mpeg",
  "audio/x-wav",
  "audio/flac",
  "audio/ogg",
  "audio/x-vorbis+ogg",
  "audio/opus",
  "audio/x-ape",
  "audio/x-musepack",
  "audio/x-wavpack",
  "audio/x-tta",
  "audio/x-speex+ogg",
];
const List<String> _videoTypes = [
  "video/mp4",
  "video/x-matroska",
  "video/webm",
  "video/x-msvideo",
  "video/mpeg",
  "video/quicktime",
  "video/x-ms-wmv",
  "video/x-flv",
  "video/ogg",
];

Future<void> _registerLinux(String executable) async {
  final data =
      Platform.environment["XDG_DATA_HOME"] ??
      "${Platform.environment["HOME"]}/.local/share";

  for (final size in ["48", "256"]) {
    final bytes = await rootBundle.load("assets/icons/document_$size.png");
    final folder = Directory("$data/icons/hicolor/${size}x$size/mimetypes");
    await folder.create(recursive: true);
    for (final name in ["amped-playlist", "amped-skin"]) {
      await File("${folder.path}/$name.png").writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }
  }

  final mime = Directory("$data/mime/packages");
  await mime.create(recursive: true);
  await File("${mime.path}/amped.xml").writeAsString(_mimeInfo);

  final applications = Directory("$data/applications");
  await applications.create(recursive: true);
  final quoted = '"${executable.replaceAll('"', r'\"')}"';
  await File("${applications.path}/$_desktopId.desktop").writeAsString("""
[Desktop Entry]
Type=Application
Name=Amped
GenericName=Media Player
Comment=Crank it up.
Exec=$quoted %F
Terminal=false
Categories=AudioVideo;Audio;Video;Player;
MimeType=${[..._playlistTypes, _skinType, ..._audioTypes, ..._videoTypes].join(";")};
Actions=Enqueue;

[Desktop Action Enqueue]
Name=Enqueue in Amped
Exec=$quoted /ADD %F
""");

  Future<String> run(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments);
      return "${result.stdout}".trim();
    } on ProcessException {
      return ""; // The tool is not installed.
    }
  }

  // Skin thumbnails, from the thumbnailer next to the executable
  // (native/skin_preview/skin_thumbnailer.c).
  final thumbnailer = File(
    "${File(executable).parent.path}/amped-skin-thumbnailer",
  );
  if (await thumbnailer.exists()) {
    final thumbnailers = Directory("$data/thumbnailers");
    await thumbnailers.create(recursive: true);
    final command = '"${thumbnailer.path.replaceAll('"', r'\"')}"';
    await File("${thumbnailers.path}/amped.thumbnailer").writeAsString("""
[Thumbnailer Entry]
TryExec=$command
Exec=$command -s %s %i %o
MimeType=$_skinType;application/zip;
""");
  }

  await run("update-mime-database", ["$data/mime"]);
  await run("update-desktop-database", [applications.path]);
  await run("gtk-update-icon-cache", ["-f", "-t", "$data/icons/hicolor"]);
  // Skins are ours; playlists only when nothing else claims them.
  const desktop = "$_desktopId.desktop";
  await run("xdg-mime", ["default", desktop, _skinType]);
  for (final type in _playlistTypes) {
    if ((await run("xdg-mime", ["query", "default", type])).isEmpty) {
      await run("xdg-mime", ["default", desktop, type]);
    }
  }
}
