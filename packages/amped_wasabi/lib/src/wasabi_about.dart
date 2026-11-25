import "package:flutter/widgets.dart";

import "maki/maki_runtime.dart";
import "wasabi_host.dart";
import "wasabi_skin_data.dart";
import "wasabi_view.dart";

/// The panel a modern skin draws about itself (its `skin.about.group`),
/// which the classic player shows in its own About pages: Amped Modern's
/// animated credits. Its scripts run while it is shown.
class WasabiAboutPanel extends StatefulWidget {
  const WasabiAboutPanel({required this.skin, required this.host, super.key});

  static const String groupId = "skin.about.group";

  /// The size the panel is laid out at. The group fills whatever it is put
  /// in, and skins draw it for the room on the original's page.
  static const Size size = Size(371, 321);

  /// Whether [skin] has a panel to show.
  static bool isIn(WasabiSkinData skin) => skin.newGroup(groupId) != null;

  /// The skin, for which [isIn] is true.
  final WasabiSkinData skin;
  final WasabiHost host;

  @override
  State<WasabiAboutPanel> createState() => _WasabiAboutPanelState();
}

class _WasabiAboutPanelState extends State<WasabiAboutPanel> {
  static const String _container = WasabiAboutPanel.groupId;

  late final WasabiLayout _layout;
  late final WasabiScriptRuntime _scripts;

  @override
  void initState() {
    super.initState();
    final group = widget.skin.newGroup(WasabiAboutPanel.groupId)!;
    group.attributes
      ..remove("relatw")
      ..remove("relath")
      ..addAll({
        "x": "0",
        "y": "0",
        "w": "${WasabiAboutPanel.size.width.round()}",
        "h": "${WasabiAboutPanel.size.height.round()}",
      });
    _layout = WasabiLayout(
      id: "normal",
      root: group,
      size: WasabiAboutPanel.size,
      region: null,
    );
    _scripts = WasabiScriptRuntime(skin: widget.skin, host: widget.host)
      ..startGroup(
        WasabiContainer(
          id: _container,
          name: _container,
          layouts: [_layout],
          defaultPosition: null,
          defaultVisible: false,
          dynamic: false,
        ),
        _layout,
      );
  }

  @override
  void dispose() {
    _scripts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WasabiLayoutView(
    skin: widget.skin,
    layout: _layout,
    host: widget.host,
    container: _container,
    scripts: _scripts,
  );
}
