/// Where a skin keeps what the user changed in it between runs (layouts it
/// was switched to, the sizes it was dragged to, which of its windows were
/// left open). The app decides where that is.
///
/// Reads are immediate; writes happen in their own time.
abstract interface class SkinStorage {
  /// Every key that is kept.
  Iterable<String> get keys;

  bool? getBool(String key);
  String? getString(String key);
  List<String>? getStringList(String key);

  void setBool(String key, {required bool value});
  void setString(String key, String value);
  void setStringList(String key, List<String> value);

  void remove(String key);
}
