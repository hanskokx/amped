import "package:amped_l10n/amped_l10n.dart";
import "package:amped_vis/amped_vis.dart";
import "package:material_ui/material_ui.dart";

/// A plug-in module's configuration dialog (Visualization > Configure
/// plug-in..., Alt+K), laid out from the settings it describes, grouped in
/// boxes as the original dialogs are.
class VisConfigPage extends StatefulWidget {
  const VisConfigPage({
    required this.module,
    required this.onClose,
    super.key,
  });

  final VisModule module;
  final VoidCallback onClose;

  @override
  State<VisConfigPage> createState() => _VisConfigPageState();
}

class _VisConfigPageState extends State<VisConfigPage> {
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final settings = widget.module.settings;
    // Settings in order, consecutive ones of a group in one box.
    final sections = <(String?, List<VisSetting>)>[];
    for (final setting in settings) {
      if (sections.isNotEmpty &&
          sections.last.$1 != null &&
          sections.last.$1 == setting.group) {
        sections.last.$2.add(setting);
      } else {
        sections.add((setting.group, [setting]));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: settings.isEmpty
              ? Center(
                  child: Text(localizations.pluginNoConfiguration),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final (group, items) in sections)
                      _SettingsBox(
                        title: group,
                        settings: items,
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: widget.onClose,
                child: Text(localizations.ok),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsBox extends StatelessWidget {
  const _SettingsBox({
    required this.title,
    required this.settings,
    required this.onChanged,
  });

  final String? title;
  final List<VisSetting> settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final setting in settings)
          _SettingRow(setting: setting, onChanged: onChanged),
      ],
    );
    if (title == null) return rows;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: rows,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.setting, required this.onChanged});

  final VisSetting setting;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final small = Theme.of(context).textTheme.bodySmall;
    final setting = this.setting;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: switch (setting) {
        VisSliderSetting() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(setting.label),
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(setting.minLabel ?? "", style: small),
                ),
                Expanded(
                  child: Slider(
                    min: setting.min.toDouble(),
                    max: setting.max.toDouble(),
                    value: setting
                        .value()
                        .clamp(setting.min, setting.max)
                        .toDouble(),
                    label: "${setting.value()}",
                    onChanged: (v) {
                      setting.onChanged(v.round());
                      onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    setting.maxLabel ?? "",
                    style: small,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
        VisToggleSetting() => CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(setting.label),
          value: setting.value(),
          onChanged: (v) {
            setting.onChanged(v ?? false);
            onChanged();
          },
        ),
        VisChoiceSetting() => Row(
          children: [
            Expanded(child: Text(setting.label)),
            DropdownButton<int>(
              value: setting.value(),
              items: [
                for (final (i, option) in setting.options.indexed)
                  DropdownMenuItem(value: i, child: Text(option)),
              ],
              onChanged: (i) {
                if (i == null) return;
                setting.onChanged(i);
                onChanged();
              },
            ),
          ],
        ),
        VisNumberSetting() => Row(
          children: [
            Expanded(child: Text(setting.label)),
            SizedBox(
              width: 64,
              child: TextFormField(
                initialValue: "${setting.value()}",
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                decoration: const InputDecoration(isDense: true),
                onChanged: (text) {
                  final value = int.tryParse(text);
                  if (value == null) return;
                  setting.onChanged(value.clamp(setting.min, setting.max));
                },
              ),
            ),
          ],
        ),
        VisColorsSetting() => Row(
          children: [
            Expanded(child: Text(setting.label)),
            for (final (i, color) in setting.colors().indexed)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _Swatch(
                  color: color,
                  onPicked: (picked) {
                    setting.onChanged(i, picked);
                    onChanged();
                  },
                ),
              ),
            if (setting.onDefaults != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(
                  onPressed: () {
                    setting.onDefaults!();
                    onChanged();
                  },
                  child: Text(localizations.defaults),
                ),
              ),
          ],
        ),
      },
    );
  }
}

/// A colour swatch that opens a picker (the original's `ChooseColor`).
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onPicked});

  final int color;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        // A DialogRoute, not showDialog: with windowing on, showDialog opens
        // a native window that macOS leaves at 0x0, an invisible modal.
        final picked = await Navigator.of(context).push(
          DialogRoute<int>(
            context: context,
            builder: (context) => _ColorPickerDialog(initial: color),
          ),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        width: 22,
        height: 18,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | color),
          border: Border.all(color: const Color(0xFF808080)),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final int initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final List<int> _rgb = [
    widget.initial >> 16 & 0xff,
    widget.initial >> 8 & 0xff,
    widget.initial & 0xff,
  ];

  int get _value => _rgb[0] << 16 | _rgb[1] << 8 | _rgb[2];

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.color),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 32, color: Color(0xFF000000 | _value)),
            for (final (i, name) in [
              localizations.red,
              localizations.green,
              localizations.blue,
            ].indexed)
              Row(
                children: [
                  SizedBox(width: 48, child: Text(name)),
                  Expanded(
                    child: Slider(
                      max: 255,
                      value: _rgb[i].toDouble(),
                      onChanged: (v) => setState(() => _rgb[i] = v.round()),
                    ),
                  ),
                  SizedBox(width: 32, child: Text("${_rgb[i]}")),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: Text(localizations.ok),
        ),
      ],
    );
  }
}
