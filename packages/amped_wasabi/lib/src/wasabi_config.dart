import "wasabi_skin_data.dart";

/// A player setting a skin can bind a control to with `cfgattrib`.
enum AmpedSetting {
  /// The Playlist Editor's `Shuffle` (a boolean).
  shuffle,

  /// The Playlist Editor's `Repeat`: 0 off, above 0 the playlist, below 0
  /// the track (Core::setRepeat).
  repeat,

  /// The Audio options' `Enable crossfading` (a boolean).
  crossfade,

  /// The classic player's `Always on top` (a boolean).
  alwaysOnTop,

  /// The UI options' `Enable tooltips` (a boolean, on until turned off).
  tooltips,
}

/// The Wasabi config attribute a control is bound to with
/// `cfgattrib="{item guid};attribute name"` (GuiObject's CFGATTRIB): a
/// toggle button shows it and sets it (ToggleButton::onToggle,
/// `guiobject_setCfgInt`).
class WasabiCfgAttrib {
  const WasabiCfgAttrib(this.item, this.name);

  /// The config item: a GUID in braces, upper-cased, or an item name.
  final String item;

  /// The attribute's name within the item.
  final String name;

  /// Parses a `cfgattrib` value; null when it is missing or has no
  /// attribute name.
  static WasabiCfgAttrib? parse(String? value) {
    if (value == null) return null;
    final split = value.indexOf(";");
    if (split < 0) return null;
    final item = value.substring(0, split).trim();
    final name = value.substring(split + 1).trim();
    if (item.isEmpty || name.isEmpty) return null;
    return WasabiCfgAttrib(
      item.startsWith("{") ? item.toUpperCase() : item,
      name,
    );
  }

  /// The Playlist Editor's config item (`pleditWndGuid` in gen_ff), with
  /// `Shuffle` and `Repeat` (wa2cfgitems.cpp).
  static const String playlistEditor = "{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}";

  /// The classic player's own config item, with `Always on top`.
  static const String player = "{280876CF-48C0-40BC-8E86-73CE6BB462E5}";

  /// The "Skins and UI Tweaks" config item (`uioptions_guid`), with
  /// `Enable tooltips` among others.
  static const String uiOptions = "{9149C445-3C30-4E04-8433-5A518ED0FDDE}";

  /// The Audio options' config item (`audio_options_guid`), with
  /// `Enable crossfading` (options.cpp).
  static const String audioOptions = "{FC3EAF78-C66E-4ED2-A0AA-1494DFCC13FF}";

  /// The the classic player setting this attribute is, or null for one of a skin's own
  /// or one amped does not know.
  AmpedSetting? get setting {
    final item = this.item.toLowerCase();
    final name = this.name.toLowerCase();
    if (item == playlistEditor.toLowerCase() || item == "playlist editor") {
      return switch (name) {
        "shuffle" => AmpedSetting.shuffle,
        "repeat" => AmpedSetting.repeat,
        _ => null,
      };
    }
    if (item == audioOptions.toLowerCase() || item == "audio options") {
      return name == "enable crossfading" ? AmpedSetting.crossfade : null;
    }
    if (item == player.toLowerCase() || item == "winamp") {
      return name == "always on top" ? AmpedSetting.alwaysOnTop : null;
    }
    if (item == uiOptions.toLowerCase() || item == "skins and ui tweaks") {
      return name == "enable tooltips" ? AmpedSetting.tooltips : null;
    }
    return null;
  }

  /// A key naming this attribute, for storing its value.
  String get key => "$item;$name";

  @override
  bool operator ==(Object other) =>
      other is WasabiCfgAttrib &&
      other.item.toLowerCase() == item.toLowerCase() &&
      other.name.toLowerCase() == name.toLowerCase();

  @override
  int get hashCode => Object.hash(item.toLowerCase(), name.toLowerCase());

  @override
  String toString() => "WasabiCfgAttrib($item;$name)";
}

/// The states of an `<NStatesButton>` (NStatesTgButton): `nstates` of
/// them, each click moving on to the next. State n shows `image`n,
/// `downimage`n and `hoverimage`n unless `autoelements` is 0, and stores
/// the nth of `cfgvals` (or n) in the button's `cfgattrib`.
class WasabiNStates {
  WasabiNStates(WasabiObject object)
    : count = object.intAttr("nstates", 1),
      oneVisualState = object.optInt("autoelements") == 0,
      _cfgvals = object["cfgvals"]
          ?.split(RegExp("[;,]"))
          .map((value) => value.trim())
          .toList();

  /// How many states there are; with fewer than 2 the button is a plain
  /// toggle button.
  final int count;

  /// Whether every state shows the same images (`autoelements="0"`).
  final bool oneVisualState;

  final List<String>? _cfgvals;

  /// The config value [state] stores (NStatesTgButton::getCurCfgVal).
  int cfgValue(int state) {
    final cfgvals = _cfgvals;
    if (cfgvals == null) return state;
    if (state < 0 || state >= cfgvals.length) return 0;
    return int.tryParse(cfgvals[state]) ?? 0;
  }

  /// The state showing config [value], or null when no state stores it
  /// (NStatesTgButton::setActivatedButton).
  int? stateOf(int value) {
    final cfgvals = _cfgvals;
    if (cfgvals == null) return value >= 0 && value < count ? value : null;
    final index = cfgvals.indexOf("$value");
    return index < 0 ? null : index;
  }

  /// The state after [state] (NStatesTgButton::autoToggle).
  int next(int state) => (state + 1) % count;

  /// The bitmap [base] names in [state] (NStatesTgButton::setupBitmaps).
  String? image(String? base, int state) =>
      base == null || oneVisualState ? base : "$base$state";
}
