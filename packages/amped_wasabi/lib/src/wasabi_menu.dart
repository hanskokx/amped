import "dart:ui" show Rect;

import "wasabi_skin_data.dart";

/// How a skin [WasabiMenu] looks: which of its buttons shows.
enum WasabiMenuLook { normal, hover, down }

/// A `<Menu>` object of a modern skin (Wasabi's `MenuButton`, used by
/// Amped Modern's menu bars): an invisible area over a label that opens
/// the classic player menu [menu] (`WA5:File`, `WA5:PE_Sort`, ...) when pressed, and
/// shows one of the objects [normal], [hover] or [down] beside it, by id,
/// for its state.
class WasabiMenu {
  const WasabiMenu({
    required this.menu,
    this.menuGroup,
    this.next,
    this.prev,
    this.normal,
    this.hover,
    this.down,
  });

  /// The menu [object] declares, or null when it is not a `<Menu>` or names
  /// no menu.
  static WasabiMenu? of(WasabiObject object) {
    if (object.tag != "menu") return null;
    final menu = object["menu"]?.trim();
    if (menu == null || menu.isEmpty) return null;
    String? id(String name) {
      final value = object[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return WasabiMenu(
      menu: menu,
      menuGroup: id("menugroup"),
      next: id("next"),
      prev: id("prev"),
      normal: id("normal"),
      hover: id("hover"),
      down: id("down"),
    );
  }

  /// The the classic player menu to open, as the skin names it (`WA5:File`).
  final String menu;

  /// The menu bar the menu belongs to (`main`, `pl`, `ml`).
  final String? menuGroup;

  /// The ids of the neighbouring `<Menu>` objects in the bar.
  final String? next;
  final String? prev;

  /// The ids of the objects shown at rest, under the mouse, and while the
  /// menu is pressed or open.
  final String? normal;
  final String? hover;
  final String? down;

  /// Whether the object with [id] shows when the menu looks like [look], or
  /// null when the menu does not control it. Of the [normal], [hover] and
  /// [down] objects only the one for [look] shows; a missing one falls back
  /// to the [normal] object.
  bool? showsButton(String id, WasabiMenuLook look) {
    final key = id.toLowerCase();
    bool same(String? other) => other != null && other.toLowerCase() == key;
    if (!same(normal) && !same(hover) && !same(down)) return null;
    final shown =
        switch (look) {
          WasabiMenuLook.normal => normal,
          WasabiMenuLook.hover => hover,
          WasabiMenuLook.down => down,
        } ??
        normal;
    return same(shown);
  }
}

/// A request from a skin to open one of the player's menus.
class WasabiMenuRequest {
  const WasabiMenuRequest({
    required this.menu,
    required this.container,
    required this.anchor,
  });

  /// The menu's name as the skin gives it (`WA5:File`, `WA5:PE_Playlist`).
  final String menu;

  /// The id of the container the menu's window shows.
  final String container;

  /// Where the menu object is, in layout pixels; the menu opens below it.
  final Rect anchor;

  @override
  String toString() => "WasabiMenuRequest($menu, $container, $anchor)";
}
