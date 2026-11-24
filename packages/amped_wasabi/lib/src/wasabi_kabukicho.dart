import "wasabi_gamma.dart";

/// The name of the built-in Kabukichō color theme.
const String wasabiKabukichoTheme = "Kabukichō";

/// Kabukichō, Tokyo's neon-lit nightlife district: night-blue backgrounds
/// under hot pink and cyan signs, with amber lit displays. It is made of
/// Amped Modern's gamma groups, so it is added to a skin that has color
/// themes (see [WasabiColorThemes]) next to the skin's own.
WasabiGammaSet wasabiKabukichoGammaSet() {
  final set = WasabiGammaSet(wasabiKabukichoTheme);
  void group(
    String id,
    int red,
    int green,
    int blue, {
    int gray = 0,
    bool boost = false,
  }) => set.add(
    WasabiGammaGroup(
      id: id,
      red: red,
      green: green,
      blue: blue,
      gray: gray,
      boost: boost,
    ),
  );

  // The night: near-black aubergine surfaces.
  group("Backgrounds", -3300, -3650, -3000, gray: 1);
  group("Backgrounds2", -3150, -3600, -2850, gray: 1);
  group("Menubar", -3350, -3700, -3050, gray: 1);
  group("Titlebar", -3050, -3600, -2750, gray: 1);
  group("TitlebarElements", 0, -400, -3700, gray: 1);
  group("TitlebarHover", 400, 0, -3300, gray: 1);
  group("BGOverlayDark", -3400, -3700, -3100, gray: 1);
  group("BGOverlayBright", -1400, -2300, -700, gray: 1);
  group("BG2Textoverlay", -2600, -3300, -2000, gray: 1);
  // Muted violet controls that light up teal when pointed at.
  group("Buttons", -1900, -2500, -1300, gray: 1);
  group("Buttons2", -1900, -2500, -1300, gray: 1);
  group("ButtonsHover", -3300, -400, -600, gray: 1);
  group("ButtonsHover2", -3300, -400, -600, gray: 1);
  group("ButtonGlow", -1500, 600, 2400);
  group("ButtonsActive", -3200, -500, -700, gray: 1);
  group("ButtonStatus", -2800, -600, 600, gray: 1);
  group("Scrollbar Buttons", -1900, -2500, -1300, gray: 1);
  group("Scrollbar Hover", -3300, -400, -600, gray: 1);
  group("Bolt", -800, -2600, -600, gray: 1);
  // The lit displays: cyan digits and an amber ticker on near-black.
  group("Led", -3200, 3000, 4096);
  group("Display", -3700, -3800, -3400, gray: 2);
  group("DisplaySongtickerBG", -3700, -3800, -3400, gray: 2);
  group("DisplayElements", -3000, 1800, 4096);
  group("DisplayVis", 2200, -2800, 600);
  group("DisplayBeatVis", 2200, -2800, 600);
  group("DisplaySongticker", 4096, 800, -3000, gray: 1);
  group("DisplaySongtickerShade", 2800, -400, -3000, gray: 1);
  group("ProgressBar", 1400, -2800, -300, gray: 1);
  // Text and lists: pale lavender on dark, a dark violet selection, a yellow
  // current track.
  group("Text", 800, 0, 1600, boost: true);
  group("Text Inverse", 4095, 4095, 4095, boost: true);
  group("TextDark", 2600, 2000, 3600, boost: true);
  group("ButtonText", 2600, 2000, 3600, boost: true);
  group("Button Fonts", 2600, 2000, 3600, boost: true);
  group("MenubarText", 2600, 2000, 3600, boost: true);
  group("TitlebarText", 2600, 2000, 3600, boost: true);
  group("ListText", -400, -800, 0);
  group("ListTextSelected", -400, -800, 0);
  group("ListTextCurrent", 0, -400, -3900, gray: 1);
  group("ListBackground", -3150, -3560, -2830, gray: 1);
  group("ListSelBackground", -2870, -3200, -2335, gray: 1);
  group("ListColumnText", -400, -800, 0);
  group("Tooltips Background", -3300, -3650, -2900, gray: 1);
  group("Tooltips Text", -400, -800, 0, boost: true);
  return set;
}
