# Changelog

## 0.1.3

- Tracks can be dragged from the Media Library onto the playlist when they're
  in separate windows. The window under the pointer is outlined, and letting go
  adds the tracks to the end of the playlist. Dropping on the main window adds
  them too, without replacing the playlist.
- **Skin Browser...**, **Online Skin Browser...**, **Media Library
  Preferences...** and the visualization's **Select plug-in...** now open
  Preferences on their own page, also when it's already open. It's no longer
  closed and opened again, so what you were filling in is kept.
- The Preferences window can no longer be made so small that its pages break. It
  also opens larger, so the skin list under **Skins > Installed** has room for
  the names.
- With the Amped Classic skin, Preferences and the app's other windows now use
  the app icon's plum and mauve colors. So do the accents of skins that give no
  accent color, which could turn these windows pink.
- Under **Skins > Installed**, the drop area now asks for a skin archive.
- **Preferences > Remote sources** has a new look. Each source is a card showing
  its logo and kind, its address and whether it failed to load. **Add source**
  opens a list that says what each kind of source brings.
- Removing a remote source now asks first.
- The forms that add and edit a source keep **Cancel** and the save button in
  view, and the save button stays unavailable until the needed fields are filled
  in. Background refresh settings are tucked away until you open them, and
  <kbd>Esc</kbd> leaves the form.
- The tray icon can now appear when Amped is installed as a Flatpak.
- The log now says whether the tray icon was set up, to help find out why it's
  missing on some systems.
- In ClassicPro skins, opening the visualizer now makes a compact player taller
  so there is room for it, and the visualizer stays in the skin's own tab
  instead of also opening an invisible window.
- The visualizer in ClassicPro skins' VIS tab no longer shows a black screen
  or a single large square.
- In modern skins that draw their window with click-through artwork, such as
  ClassicPro's compact strip, clicking the artwork no longer goes through to
  the window behind.
- ClassicPro skins' tabs now open their panels in a player that started as the
  compact strip. Before, only the highlighted tab changed.
- The ClassicPro Widgets Manager now opens wide enough to read, and lists the
  widgets.
- Modern skins' flat color images now show. This fixes skins whose beat
  visualizers, such as D-Reliction's, stayed blank.

## 0.1.2

- In the Amped Modern skin, clicking the lightning bolt in the main window's
  bottom right corner now opens the About window, like the logo in a classic
  skin.
- With a modern skin that has a panel about itself, like Amped Modern's
  animated credits, the About window shows it on a **Skin** tab.
- The About window has a fixed size that fits everything in it.

## 0.1.1

- Added a **Report a bug** button to the About window. It opens a new issue on
  the GitHub issue tracker with your Amped version, system and the latest log
  lines filled in, and puts the whole log on your clipboard to paste in. Nothing
  is sent until you submit the issue.
- The About window links to the website, <https://www.amped-player.com/>.
- The website now uses the Amped logo as its icon.
- Linux builds for arm64 (deb, rpm, AppImage and Flatpak), and the Flatpak shows
  its name, author and version in software centers.

## 0.1.0

- The first release.
