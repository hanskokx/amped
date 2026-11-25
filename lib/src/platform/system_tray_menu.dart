import "dart:io";

import "package:amped_logging/amped_logging.dart";
import "package:tray_manager/tray_manager.dart" as tray;
import "package:window_dock/window_dock.dart";

class SystemTrayMenu {
  tray.TrayIcon? _icon;
  tray.ListenerId? _trayListenerId;
  Object? _iconImage;

  final List<tray.Menu> _menus = [];
  final List<tray.MenuItem> _menuItems = [];
  final List<_CheckBinding> _checkBindings = [];
  String _signature = "";

  void initialize(List<NativeMenuItem> definitions) {
    final icon = tray.TrayIcon.create();
    if (icon == null) {
      _log("The system could not create a tray icon", level: Level.warning);
      return;
    }
    _icon = icon;

    final iconImage = tray.ImageAsset.fromAsset(
      "assets/icons/amped_tray.png",
    );
    if (iconImage != null) {
      icon.icon = iconImage;
      _iconImage = iconImage;
    } else {
      _log("The tray icon image did not load", level: Level.warning);
    }
    icon.setTooltip("Amped");

    if (!_buildMenu(icon, definitions)) {
      _log("The tray menu could not be created", level: Level.warning);
      return;
    }
    icon.setContextMenuTrigger(
      Platform.isMacOS
          ? tray.ContextMenuTrigger.clicked
          : tray.ContextMenuTrigger.rightClicked,
    );
    // On Windows this is false when the taskbar did not accept the icon, and
    // the bounds are all zero when it cannot say where the icon is. Linux
    // registers with the panel later and never reports bounds.
    final shown = icon.setVisible(true);
    final bounds = icon.getBounds();
    _log(
      "Tray icon set up",
      metadata: {
        "shown": shown,
        "bounds":
            "${bounds.x}, ${bounds.y}, ${bounds.width} x ${bounds.height}",
      },
      level: shown ? Level.info : Level.warning,
    );
    _trayListenerId = icon.addListener((_) {});
  }

  static void _log(
    String message, {
    required Level level,
    Map<String, Object?>? metadata,
  }) => Arcane.log(message, level: level, metadata: metadata, module: "Tray");

  /// Builds the context menu of [icon] from [definitions].
  bool _buildMenu(tray.TrayIcon icon, List<NativeMenuItem> definitions) {
    final menu = tray.Menu.create();
    if (menu == null) return false;
    _menus.add(menu);
    _addItems(menu, definitions);
    _signature = _signatureOf(definitions);
    icon.setContextMenu(menu);
    return true;
  }

  /// The labels of [items] and their children, which change when skins are
  /// installed or removed and when the skin has other color themes.
  static String _signatureOf(List<NativeMenuItem> items) => [
    for (final item in items)
      item.separator ? "-" : "${item.label}(${_signatureOf(item.children)})",
  ].join("|");

  void refresh(List<NativeMenuItem> definitions) {
    final icon = _icon;
    if (icon != null && _signatureOf(definitions) != _signature) {
      _checkBindings.clear();
      icon.setContextMenu(null);
      for (final menu in _menus.reversed) {
        menu.dispose();
      }
      for (final menuItem in _menuItems) {
        menuItem.dispose();
      }
      _menus.clear();
      _menuItems.clear();
      _buildMenu(icon, definitions);
      return;
    }
    for (final binding in _checkBindings) {
      final item = _itemAtPath(definitions, binding.path);
      if (item == null) continue;
      binding.menuItem
        ..label = item.label
        ..isEnabled = item.enabled
        ..state = item.checked
            ? tray.MenuItemState.checked
            : tray.MenuItemState.unchecked;
    }
  }

  void dispose() {
    final icon = _icon;
    if (icon != null) {
      final listenerId = _trayListenerId;
      if (listenerId != null) icon.removeListener(listenerId);
      _trayListenerId = null;
      icon
        ..setVisible(false)
        ..setContextMenu(null)
        ..icon = null
        ..dispose();
      _icon = null;
    }
    for (final menu in _menus.reversed) {
      menu.dispose();
    }
    for (final menuItem in _menuItems) {
      menuItem.dispose();
    }
    _menus.clear();
    _menuItems.clear();
    _checkBindings.clear();
    if (_iconImage != null) _iconImage = null;
  }

  void _addItems(
    tray.Menu menu,
    List<NativeMenuItem> definitions, {
    List<int> path = const [],
  }) {
    for (var index = 0; index < definitions.length; index++) {
      final definition = definitions[index];
      if (definition.separator) {
        menu.addSeparator();
        continue;
      }

      final type = definition.children.isNotEmpty
          ? tray.MenuItemType.submenu
          : definition.checkable
          ? tray.MenuItemType.checkbox
          : tray.MenuItemType.normal;
      final menuItem = tray.MenuItem.createWithLabelAndType(
        definition.label,
        type,
      );
      if (menuItem == null) continue;
      _menuItems.add(menuItem);
      menuItem.isEnabled = definition.enabled;

      final itemPath = [...path, index];
      if (definition.checkable) {
        menuItem.state = definition.checked
            ? tray.MenuItemState.checked
            : tray.MenuItemState.unchecked;
        _checkBindings.add(_CheckBinding(itemPath, menuItem));
      }

      if (definition.children.isNotEmpty) {
        final submenu = tray.Menu.create();
        if (submenu != null) {
          _menus.add(submenu);
          _addItems(submenu, definition.children, path: itemPath);
          menuItem.submenu = submenu;
        }
      }

      menuItem.addListener((event) {
        if (event is tray.MenuItemClickedEvent) {
          definition.onSelected?.call();
        }
      });
      menu.addItem(menuItem);
    }
  }

  NativeMenuItem? _itemAtPath(List<NativeMenuItem> items, List<int> path) {
    var currentItems = items;
    NativeMenuItem? current;
    for (var index = 0; index < path.length; index++) {
      final itemIndex = path[index];
      if (itemIndex >= currentItems.length) return null;
      current = currentItems[itemIndex];
      if (index < path.length - 1) currentItems = current.children;
    }
    return current;
  }
}

class _CheckBinding {
  const _CheckBinding(this.path, this.menuItem);

  final List<int> path;
  final tray.MenuItem menuItem;
}
