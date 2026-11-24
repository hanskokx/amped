import "dart:async";

import "package:amped_skin/amped_skin.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Keeps what a skin remembers in the app's preferences.
class PrefsSkinStorage implements SkinStorage {
  PrefsSkinStorage(this._prefs);

  final SharedPreferences _prefs;

  @override
  Iterable<String> get keys => _prefs.getKeys();

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  void setBool(String key, {required bool value}) =>
      unawaited(_prefs.setBool(key, value));

  @override
  void setString(String key, String value) =>
      unawaited(_prefs.setString(key, value));

  @override
  void setStringList(String key, List<String> value) =>
      unawaited(_prefs.setStringList(key, value));

  @override
  void remove(String key) => unawaited(_prefs.remove(key));
}
