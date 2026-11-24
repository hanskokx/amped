import "dart:async";
import "dart:io";

import "package:amped_audacious_skin/amped_audacious_skin.dart";
import "package:amped_bamp_skin/amped_bamp_skin.dart";
import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_logging/amped_logging.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../player/player_state.dart";
import "prefs_skin_storage.dart";
import "skin_color_themes.dart";
import "skin_views.dart";

/// Owns the installed skins, the active selection, and the loaded [Skin].
///
/// A [ModernSkin] carries the classic base skin that draws the windows the
/// modern skin has no look for. The active skin is persisted across launches
/// and broadcast to the Equalizer/Playlist sub-windows by whoever owns the
/// manager.
class SkinManager extends ChangeNotifier {
  SkinManager._(this._registry, this._formats, this._current);

  /// The skin families the app supports, wired up in one place.
  ///
  /// Classic zip skins need no extra setup; Bamp archives are ordinary zips
  /// whose files need converting, and Audacious skins arrive as tarballs.
  static const SkinFormats defaultFormats = SkinFormats(
    decoders: {AudaciousSkinDecoder()},
    converters: {BampSkinFormat(), AudaciousSkinConverter()},
  );

  /// Resolves the directory holding the extracted skins, creating it on first
  /// use. Lives under the app-support folder so imported skins never touch the
  /// original files.
  static Future<Directory> skinsDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory("${support.path}/amped/skins");
  }

  final SkinRegistry _registry;
  final SkinFormats _formats;
  Skin _current;
  final SkinColorThemes _colorThemes = const SkinColorThemes();
  bool Function(SkinWindow window) _isShaded = (_) => false;

  /// The installed skins, base first, in scan order.
  List<SkinInfo> get skins => _registry.skins;

  /// The installed skins by name, as the menus list them.
  List<SkinInfo> get sortedSkins =>
      [..._registry.skins]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The currently selected skin.
  SkinInfo get active => _current.info;

  /// The skin on show: a [ModernSkin] while a modern skin is active, else a
  /// [ClassicSkin].
  Skin get current => _current;

  /// Persists and applies modern skin color themes.
  SkinColorThemes get colorThemes => _colorThemes;

  /// Tells the skins whether the player has a window in windowshade mode.
  void followShades(bool Function(SkinWindow window) isShaded) {
    _isShaded = isShaded;
    _current.followShades(isShaded);
  }

  /// Scans the skins directory and activates the saved skin (defaults to the
  /// first built-in skin).
  static Future<SkinManager> load() async {
    final skinsDir = await skinsDirectory();
    await _mountClassicPro();
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        "ClassicPro",
      ], await rootBundle.loadString("assets/plugins/ClassicPro-LICENSE.txt"));
    });
    final registry = await SkinRegistry.load(skinsDir);
    final repaired = await registry.migrateFormats(
      (names) => defaultFormats.identifyNames(names, SkinFormat.classic),
    );
    if (repaired > 0) {
      Arcane.log(
        "Recovered the format of installed skins",
        metadata: {"repaired": repaired},
        level: Level.info,
        module: "SkinManager",
      );
    }

    final skins = <String, BuiltInSkin>{
      ...await AmpedModernSkinLoader.loadAssets(),
      ...await AmpedClassicSkinLoader.loadAssets(formats: defaultFormats),
    };

    await _installBuiltIn(registry, skins, defaultFormats);

    final saved = await PlayerState.loadActiveSkin();
    final savedInfo = saved == null ? null : registry.byName(saved);

    SkinInfo? defaultSkin;
    for (final name in skins.keys) {
      defaultSkin = registry.byName(name);
      if (defaultSkin != null) break;
    }
    final active = savedInfo ?? defaultSkin ?? registry.skins.first;
    final current = await _resolveSkin(
      registry: registry,
      formats: defaultFormats,
      active: active,
    );

    final manager = SkinManager._(registry, defaultFormats, current);
    manager._current.followShades(manager._isShaded);
    return manager;
  }

  /// Hands the ClassicPro plugin (BSD-licensed, bundled with its licence) to
  /// the modern skin engine, which keeps it in memory as an original install's
  /// `Plugins/ClassicPro` for the cPro skins. Nothing is written to disk.
  static Future<void> _mountClassicPro() async {
    try {
      final data = await rootBundle.load("assets/plugins/ClassicPro.zip");
      WasabiSkinData.mountPlugins(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not load the ClassicPro plugin",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "SkinManager",
      );
    }
  }

  static Future<Skin> _resolveSkin({
    required SkinRegistry registry,
    required SkinFormats formats,
    required SkinInfo active,
  }) async {
    try {
      final directory = active.directory;
      final modern = active.modern && directory != null
          ? await WasabiSkinData.load(
              directory,
              name: active.name,
              colorTheme: await const SkinColorThemes().savedTheme(active.name),
              customThemes: await const SkinColorThemes().savedCustomThemes(
                active.name,
              ),
            )
          : null;
      final base = await registry.loadSkin(active, formats: formats);
      final classic = ClassicSkin(active, base);
      if (modern == null) return classic;
      return ModernSkin(
        active,
        modern,
        classic,
        PrefsSkinStorage(await SharedPreferences.getInstance()),
      );
    } catch (error) {
      Arcane.log(
        "Could not load the skin",
        metadata: {"name": active.name, "error": "$error"},
        level: Level.warning,
        module: "SkinManager",
      );
      final fallback = registry.skins.first;
      final base = await loadBaseSkin(formats: formats);
      return ClassicSkin(fallback, base);
    }
  }

  Future<void> _reload(SkinInfo active) async {
    _current = await _resolveSkin(
      registry: _registry,
      formats: _formats,
      active: active,
    );
    _current.followShades(_isShaded);
    notifyListeners();
  }

  /// Installs the built-in skins, each again whenever the app ships a
  /// different one. The [BuiltInSkin] carries its own [SkinFormat], so no
  /// guessing from the archive bytes is needed here.
  static Future<void> _installBuiltIn(
    SkinRegistry registry,
    Map<String, BuiltInSkin> skins,
    SkinFormats formats,
  ) async {
    // Built-in skins this app no longer ships (the old Amped skins).
    for (final info in [...registry.skins]) {
      if (info.builtIn && !skins.containsKey(info.name)) {
        try {
          final directory = info.directory;
          if (directory != null && await directory.exists()) {
            await directory.delete(recursive: true);
          }
          registry.forget(info);
        } on Object catch (error) {
          Arcane.log(
            "Could not remove the old built-in skin",
            metadata: {"name": info.name, "error": "$error"},
            level: Level.warning,
            module: "SkinManager",
          );
        }
      }
    }
    for (final MapEntry(:key, :value) in skins.entries) {
      try {
        final name = key;
        final bytes = value.bytes;
        final format = value.format;
        final version = _archiveVersion(bytes);

        if (registry.builtInVersion(name) == version) continue;

        if (format == SkinFormat.wasabi) {
          final wal = WasabiArchive.tryOpen(bytes);
          if (wal == null) continue;
          await registry.installFolder(
            name,
            wal.extractTo,
            format: SkinFormat.wasabi,
            builtInVersion: version,
          );
          Arcane.log(
            "Installed modern skin",
            metadata: {"name": name},
            level: Level.info,
            module: "SkinManager",
          );
          continue;
        }

        final contents = await openSkinArchive(
          bytes,
          formats: formats,
          fileName: name,
        );
        if (!isSkinArchive(contents.archive, formats: formats)) continue;
        await registry.installFolder(
          name,
          (target) => extractSkinFiles(
            contents.archive,
            target,
            formats: formats,
          ),
          format: format,
          builtInVersion: version,
        );
        Arcane.log(
          "Installed skin",
          metadata: {"name": name, "format": format.name},
          level: Level.info,
          module: "SkinManager",
        );
      } on Object catch (error) {
        Arcane.log(
          "Unable to install skin",
          metadata: {"error": "$error"},
          level: Level.warning,
          module: "SkinManager",
        );
      }
    }
  }

  /// An FNV-1a of [bytes], which changes whenever the shipped skin does.
  static String _archiveVersion(Uint8List bytes) {
    int hash = 0x811C9DC5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return "${bytes.length}-${hash.toRadixString(16)}";
  }

  /// Keeps [theme] as the color theme of the modern skin [skinName], with the
  /// user's own themes [customs] for it, and puts them on the skin if it is
  /// the one that is on.
  Future<void> saveColorThemes(
    String skinName, {
    required String? theme,
    required List<WasabiGammaSet> customs,
  }) async {
    await _colorThemes.persist(skinName, theme: theme, customs: customs);
    final live = _current.modern?.data;
    if (live == null || live.name != skinName) return;
    final themes = live.colorThemes;
    final keep = {for (final set in customs) set.name};
    for (final set in [...themes.sets]) {
      if (set.custom && !keep.contains(set.name)) {
        await themes.remove(set.name);
      }
    }
    for (final set in customs) {
      themes.add(set.cloneAs(set.name));
    }
    await themes.select(theme);
  }

  /// Selects [info] as the active skin, persists it, and reloads.
  Future<void> apply(SkinInfo info) async {
    if (info.name == _current.info.name) return;
    await PlayerState.saveActiveSkin(info.name);
    await _reload(info);
  }

  /// Deletes the imported skin [info]. Removing the active skin switches back
  /// to the bundled base skin first.
  Future<void> remove(SkinInfo info) async {
    if (info.isBundled) return;
    if (info.name == _current.info.name) {
      await apply(_registry.skins.first);
    }
    await _registry.remove(info);
    notifyListeners();
  }

  /// Imports a skin archive and applies it immediately. Throws a
  /// [FormatException] when the archive is not a skin that can be loaded;
  /// nothing is installed then.
  Future<SkinInfo> importArchive(
    Uint8List bytes, {
    String? name,
    String? fileName,
  }) async {
    final wal = WasabiArchive.tryOpen(bytes);
    final info = wal == null
        ? await _registry.importArchive(
            bytes,
            name: name,
            fileName: fileName,
            formats: _formats,
          )
        : await _registry.installFolder(
            _notBuiltIn(name ?? wal.displayName ?? _labelFrom(fileName)),
            wal.extractTo,
            format: SkinFormat.wasabi,
          );
    if (wal != null) {
      // A zip with a skin.xml that is no skin must not stay installed.
      final directory = info.directory;
      try {
        if (directory == null) throw const FormatException("No skin folder");
        await WasabiSkinData.load(directory, name: info.name);
      } on Object {
        await _registry.remove(info);
        throw const FormatException("Not a skin");
      }
    }
    await apply(info);
    return info;
  }

  /// [name], or a variant of it when a built-in skin has that name, so an
  /// import never replaces a skin that ships with the app.
  String _notBuiltIn(String name) {
    var candidate = name;
    for (var n = 2; _registry.byName(candidate)?.isBundled ?? false; n++) {
      candidate = "$name ($n)";
    }
    return candidate;
  }

  /// [fileName] without its skin archive suffix, using the one list of
  /// suffixes every skin loader matches against.
  static String _labelFrom(String? fileName) {
    if (fileName == null) return "Imported Skin";
    final file = fileName.split(RegExp(r"[\\/]")).last;
    for (final type in SkinFileType.values) {
      for (final suffix in type.suffixes) {
        if (file.toLowerCase().endsWith(suffix)) {
          return file.substring(0, file.length - suffix.length);
        }
      }
    }
    return file;
  }
}
