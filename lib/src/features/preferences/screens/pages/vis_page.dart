import "package:amped_l10n/amped_l10n.dart";
import "package:amped_vis/amped_vis.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_shell.dart";
import "../../../../vis/vis_host.dart";

/// Preferences > Plug-ins > Visualization: the plug-ins, the selected
/// one's modules, and Start/Stop.
class VisPage extends StatelessWidget {
  const VisPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final VisHost vis = shell.vis;
    return ListenableBuilder(
      listenable: vis,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.visualizationPlugins,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButton<VisPlugin>(
              value: vis.plugin,
              isExpanded: true,
              items: [
                for (final plugin in vis.plugins)
                  DropdownMenuItem(
                    value: plugin,
                    child: Text(plugin.description),
                  ),
              ],
              onChanged: (plugin) {
                if (plugin != null) vis.select(plugin, 0);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RadioGroup<int>(
                groupValue: vis.moduleIndex,
                onChanged: (index) {
                  if (index != null) vis.select(vis.plugin, index);
                },
                child: ListView(
                  children: [
                    for (final (index, module) in vis.plugin.modules.indexed)
                      RadioListTile<int>(
                        dense: true,
                        value: index,
                        title: Text(module.description),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: shell.configureVisPlugin,
                  child: Text(localizations.configureActivePlugin),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: vis.toggle,
                  child: Text(
                    vis.isRunning ? localizations.stop : localizations.start,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
