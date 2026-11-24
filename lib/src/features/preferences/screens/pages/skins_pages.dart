import "dart:async";
import "dart:ui" as ui;

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_dialog.dart";
import "../../../../app/amped_menus.dart";
import "../../../../app/amped_shell.dart";
import "../../../../skin/skin_previewer.dart";
import "../../../../skin/skin_views.dart";

/// The user-facing name of a skin's family, shown beside it in the list.
extension SkinFormatLabel on SkinFormat {
  String label(AppLocalizations localizations) => switch (this) {
    SkinFormat.classic => localizations.classicSkin,
    SkinFormat.wasabi => localizations.modernSkin,
    SkinFormat.bamp => localizations.bampSkin,
    SkinFormat.audacious => localizations.audaciousSkin,
  };
}

/// Preferences > Skins: which skin is on, and where the other pages are.
class SkinsOverviewPage extends StatelessWidget {
  const SkinsOverviewPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: shell.skins,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(localizations.skins, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(localizations.skinsSummary(shell.skins.active.name)),
          const SizedBox(height: 8),
          Text(
            localizations.skinsSummaryHint,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Preferences > Skins > Browser: the skins, and a preview of the one
/// selected. Selecting a skin only previews it; Apply and OK put it on,
/// Cancel leaves the skin as it was. For a modern skin a second tab has
/// its options and color themes, which can be set before the skin is on:
/// the color theme is kept when the skin is applied, and options are kept
/// as they are changed.
class SkinsBrowserPage extends StatefulWidget {
  const SkinsBrowserPage({
    required this.shell,
    required this.onAddSkin,
    super.key,
  });

  final AmpedShell shell;

  /// What the drop target does when tapped: lets the user pick skins to
  /// add. The place for another source of skins, such as an online skin
  /// browser.
  final Future<void> Function() onAddSkin;

  @override
  State<SkinsBrowserPage> createState() => _SkinsBrowserPageState();
}

/// Stands in for the settings of a skin that has none.
final ValueNotifier<int> _noChanges = ValueNotifier(0);

class _SkinsBrowserPageState extends State<SkinsBrowserPage>
    with SingleTickerProviderStateMixin {
  /// The Skins and Skin Settings tabs.
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_keepToEnabledTab);

  /// Whether the selected skin is modern, which is what Skin Settings is
  /// for.
  bool _selectedIsModern = false;

  /// Skin Settings is greyed out for a skin that has none: its tab cannot be
  /// shown.
  void _keepToEnabledTab() {
    if (_tabs.index == 1 && !_selectedIsModern) _tabs.index = 0;
  }

  /// The name of the skin picked in the list, or null for the active one.
  String? _picked;

  /// The skin that was active when the list last changed, to start over
  /// from it when another skin becomes active (one was added).
  String? _lastActive;

  /// The selected modern skin, loaded on its own to preview and set up.
  WasabiSkinPreviewController? _controller;

  AmpedShell get shell => widget.shell;

  @override
  void dispose() {
    _tabs.dispose();
    _controller?.dispose();
    super.dispose();
  }

  /// The loaded copy of [selected] while it is a modern skin, made when it
  /// is picked.
  WasabiSkinPreviewController? _controllerFor(SkinInfo selected) {
    final directory = selected.directory;
    final current = _controller;
    if (!selected.modern || directory == null) {
      _retire();
      return null;
    }
    if (current != null && current.name == selected.name) return current;
    _retire();
    final name = selected.name;
    final colorThemes = shell.skins.colorThemes;
    return _controller = WasabiSkinPreviewController(
      directory: directory,
      name: name,
      title: "Amped",
      storage: shell.wasabiHost,
      settings: () async => (
        await colorThemes.savedTheme(name),
        await colorThemes.savedCustomThemes(name),
      ),
    );
  }

  /// Lets go of the loaded skin once nothing shows it any more.
  void _retire() {
    final old = _controller;
    _controller = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  /// Puts [selected] on, with the options and color theme chosen for it.
  Future<void> _apply(SkinInfo selected) async {
    final controller = _controller;
    final skin = controller?.skin;
    if (controller != null && skin != null && controller.changed) {
      // The skin that is on takes the new options too.
      final live = shell.wasabiScripts;
      if (live != null && shell.skins.active.name == controller.name) {
        for (final MapEntry(:key, :value)
            in controller.pendingOptions.entries) {
          live.setConfigAttribute(key, value);
        }
      }
      controller.commitOptions();
      if (controller.themeDirty) {
        await shell.skins.saveColorThemes(
          controller.name,
          theme: skin.colorThemes.current?.name,
          customs: controller.customThemes,
        );
        controller.markThemesSaved();
      }
    }
    await shell.skins.apply(selected);
  }

  void _close() => shell.dialogManager.close(AmpedDialog.preferences);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: shell.skins,
      builder: (context, _) {
        final active = shell.skins.active;
        if (_lastActive != active.name) {
          _lastActive = active.name;
          _picked = null;
        }
        final selected =
            shell.skins.skins.where((s) => s.name == _picked).firstOrNull ??
            active;
        final controller = _controllerFor(selected);
        _selectedIsModern = controller != null;
        if (!_selectedIsModern && _tabs.index == 1) {
          // Back to the skins, from the settings of the skin before.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tabs.index = 0;
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                localizations.skinsInstalled,
                style: theme.textTheme.titleMedium,
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: localizations.skins),
                Tab(
                  child: Text(
                    localizations.modernSettings,
                    style: controller == null
                        ? TextStyle(color: theme.disabledColor)
                        : null,
                  ),
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  SkinListTab(
                    shell: shell,
                    selected: selected,
                    controller: controller,
                    onPick: (info) => setState(() => _picked = info.name),
                    onAddSkin: widget.onAddSkin,
                  ),
                  controller == null
                      ? const SizedBox.shrink()
                      : ModernSettingsTab(
                          shell: shell,
                          selected: selected,
                          controller: controller,
                        ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListenableBuilder(
              listenable: controller ?? _noChanges,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () {
                        unawaited(_apply(selected));
                        _close();
                      },
                      child: Text(localizations.ok),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _close,
                      child: Text(localizations.cancel),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed:
                          selected.name == active.name &&
                              !(controller?.changed ?? false)
                          ? null
                          : () => unawaited(_apply(selected)),
                      child: Text(localizations.applyAction),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The skins to choose from, with the drop target above them and the
/// preview of the selected one beside them.
class SkinListTab extends StatefulWidget {
  const SkinListTab({
    required this.shell,
    required this.selected,
    required this.controller,
    required this.onPick,
    required this.onAddSkin,
    super.key,
  });

  final AmpedShell shell;
  final SkinInfo selected;

  /// The selected skin loaded on its own, when it is a modern one.
  final WasabiSkinPreviewController? controller;
  final ValueChanged<SkinInfo> onPick;
  final Future<void> Function() onAddSkin;

  @override
  State<SkinListTab> createState() => _SkinListTabState();
}

class _SkinListTabState extends State<SkinListTab> {
  /// The skin whose remove button was pressed and awaits confirmation.
  String? _confirming;

  AmpedShell get shell => widget.shell;

  Future<void> _remove(SkinInfo info) async {
    setState(() => _confirming = null);
    await shell.skins.remove(info);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final active = shell.skins.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SkinDropTarget(
            label: localizations.skinDropTarget,
            hint: localizations.skinInstallHint,
            onTap: () => unawaited(widget.onAddSkin()),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: InkClip(
                  child: ListView(
                    children: [
                      for (final info in shell.skins.sortedSkins)
                        ListTile(
                          dense: true,
                          selected: info.name == widget.selected.name,
                          title: Text(info.name),
                          subtitle: Text(info.format.label(localizations)),
                          leading: info.name == active.name
                              ? const Icon(Icons.check, size: 18)
                              : const SizedBox(width: 18),
                          onTap: () => widget.onPick(info),
                          // Removing asks for confirmation in place.
                          trailing: info.isBundled
                              ? null
                              : _confirming == info.name
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _confirming = null),
                                      child: Text(localizations.cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () => unawaited(_remove(info)),
                                      child: Text(localizations.removeAction),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _confirming = info.name),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 300,
                child: SkinPreview(
                  previewer: shell.skinPreviewer,
                  info: widget.selected,
                  controller: widget.controller,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps what a list's tiles paint (the hover and selection highlights, which
/// go on the nearest [Material]) inside the list, not over what is beside or
/// below it.
class InkClip extends StatelessWidget {
  const InkClip({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

/// The box above the skin list: skins dropped on any Amped window are
/// installed, and tapping it lets the user find some.
class SkinDropTarget extends StatelessWidget {
  const SkinDropTarget({
    required this.label,
    required this.hint,
    required this.onTap,
    super.key,
  });

  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: hint,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The preview panel: the skin [info] loaded without putting the skin on. A
/// classic skin is the picture the file manager previews show; a modern skin
/// is [controller]'s copy, run on its own with its equalizer and playlist
/// editor.
class SkinPreview extends StatefulWidget {
  const SkinPreview({
    required this.previewer,
    required this.info,
    this.controller,
    super.key,
  });

  final SkinPreviewer previewer;
  final SkinInfo info;
  final WasabiSkinPreviewController? controller;

  @override
  State<SkinPreview> createState() => _SkinPreviewState();
}

class _SkinPreviewState extends State<SkinPreview> {
  /// The picture of a classic skin; a modern skin is run instead.
  late Future<ui.Image?> _image = widget.previewer.previewImage(widget.info);

  @override
  void didUpdateWidget(SkinPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.name != widget.info.name && !widget.info.modern) {
      _image = widget.previewer.previewImage(widget.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = widget.controller;
    final noPreview = Center(
      child: Text(
        localizations.skinNoPreview,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: controller != null
                ? ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => controller.failed
                        ? noPreview
                        : WasabiSkinPreview(controller: controller),
                  )
                : FutureBuilder<ui.Image?>(
                    future: _image,
                    builder: (context, snapshot) {
                      final image = snapshot.data;
                      if (image == null) {
                        return snapshot.connectionState == ConnectionState.done
                            ? noPreview
                            : const SizedBox.shrink();
                      }
                      return RawImage(
                        image: image,
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.medium,
                      );
                    },
                  ),
          ),
          if (controller != null)
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) =>
                  SkinComments(comment: controller.skin?.info["comment"]),
            ),
        ],
      ),
    );
  }
}

/// The comments the skin's author wrote (a modern skin's `<comment>`), below
/// its preview, which the heading folds away. Nothing shows when there are
/// none.
class SkinComments extends StatefulWidget {
  const SkinComments({required this.comment, super.key});

  final String? comment;

  @override
  State<SkinComments> createState() => _SkinCommentsState();
}

class _SkinCommentsState extends State<SkinComments> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final text = widget.comment?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).skinComments,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: SelectableText(text, style: theme.textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The settings of the selected modern skin, with its preview: the options
/// its scripts offer and its color themes. They can be set before the skin
/// is on, and take effect with Apply or OK.
class ModernSettingsTab extends StatelessWidget {
  const ModernSettingsTab({
    required this.shell,
    required this.selected,
    required this.controller,
    super.key,
  });

  final AmpedShell shell;
  final SkinInfo selected;
  final WasabiSkinPreviewController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.failed) {
          return Center(child: Text(localizations.skinNoPreview));
        }
        if (!controller.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        // The panels the skin brings of its own (Resin's "Color and
        // Opacity") are listed when it has any.
        final windows = controller.skin!.extraContainers.isNotEmpty;
        return Row(
          children: [
            Expanded(
              child: DefaultTabController(
                length: windows ? 3 : 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: localizations.modernSettingsOptions),
                        Tab(text: localizations.modernSettingsColorThemes),
                        if (windows)
                          Tab(text: localizations.modernSettingsWindows),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          ModernOptionsTab(controller: controller),
                          ColorThemesTab(controller: controller),
                          if (windows)
                            ModernWindowsTab(
                              shell: shell,
                              selected: selected,
                              controller: controller,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 300,
              child: SkinPreview(
                previewer: shell.skinPreviewer,
                info: selected,
                controller: controller,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The options the modern skin's scripts offer (Amped Modern's
/// config > options), as check boxes. Changes are kept, and shown on the
/// skin that is on, when Apply or OK is pressed.
class ModernOptionsTab extends StatelessWidget {
  const ModernOptionsTab({required this.controller, super.key});

  final WasabiSkinPreviewController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final options = controller.options;
        final switches = controller.switches;
        if (options.isEmpty && switches.isEmpty) {
          return Center(child: Text(localizations.modernSettingsNoOptions));
        }
        return InkClip(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final option in options)
                SkinOptionTile(
                  option: option,
                  onToggle: controller.toggleOption,
                ),
              if (options.isNotEmpty && switches.isNotEmpty) const Divider(),
              if (switches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    localizations.modernSettingsSkinOptions,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              for (final option in switches)
                SkinOptionTile(
                  option: option,
                  onToggle: controller.toggleOption,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The windows the skin brings of its own, which open and close like the
/// player's. They belong to the skin that is on, so they can be opened here
/// only for that one.
class ModernWindowsTab extends StatelessWidget {
  const ModernWindowsTab({
    required this.shell,
    required this.selected,
    required this.controller,
    super.key,
  });

  final AmpedShell shell;
  final SkinInfo selected;
  final WasabiSkinPreviewController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final active = shell.skins.active.name == selected.name;
    final extras =
        controller.skin?.extraContainers ?? const <WasabiContainer>[];
    final names = {
      for (final container in extras) container.id: container.name,
    };
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final windows = shell.skin.windows;
        return InkClip(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  active
                      ? localizations.skinWindowsHint
                      : localizations.skinWindowsHintInactive,
                ),
              ),
              if (active)
                for (final (window, container) in windows)
                  SwitchListTile(
                    dense: true,
                    title: Text(
                      container.name.trim().isEmpty
                          ? container.id
                          : container.name.trim(),
                    ),
                    value: shell.isOpen(window),
                    onChanged: (open) => shell.setOpen(window, open),
                  )
              else
                for (final name in names.values)
                  ListTile(
                    dense: true,
                    enabled: false,
                    title: Text(name.trim().isEmpty ? "—" : name.trim()),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// One option of a modern skin: a check box, or a group of options.
class SkinOptionTile extends StatelessWidget {
  const SkinOptionTile({
    required this.option,
    required this.onToggle,
    super.key,
  });

  final WasabiSkinOption option;
  final void Function(WasabiSkinOption option) onToggle;

  @override
  Widget build(BuildContext context) {
    if (option.separator) return const Divider();
    // Skins name their pages after the player; this one is Amped.
    final label = AmpedMenus.skinOptionLabel(
      option.label.split("\t").first,
    );
    final children = option.children;
    if (children != null) {
      return ExpansionTile(
        initiallyExpanded: true,
        dense: true,
        title: Text(label),
        children: [
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SkinOptionTile(option: child, onToggle: onToggle),
            ),
        ],
      );
    }
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: option.checked,
      title: Text(label),
      onChanged: (_) => onToggle(option),
    );
  }
}

/// The color themes of the skin of [controller]: selecting one previews it;
/// the skin is put on with it when Apply or OK is pressed. Any theme can be
/// cloned into one of the user's own, which can be edited and deleted.
class ColorThemesTab extends StatefulWidget {
  const ColorThemesTab({required this.controller, super.key});

  final WasabiSkinPreviewController controller;

  @override
  State<ColorThemesTab> createState() => _ColorThemesTabState();
}

class _ColorThemesTabState extends State<ColorThemesTab> {
  WasabiColorThemes get _themes => widget.controller.skin!.colorThemes;

  Future<void> _clone(WasabiGammaSet source) async {
    final localizations = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => ThemeNameDialog(
        title: localizations.colorThemeClone,
        label: localizations.colorThemeNewName,
        initial: _freeName(
          "${source.name} (${localizations.colorThemeCustom})",
        ),
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final clone = source.cloneAs(_freeName(name.trim()));
    _themes.add(clone);
    await _themes.select(clone.name);
  }

  /// [name], or a variant of it that no theme has.
  String _freeName(String name) {
    var candidate = name;
    for (var n = 2; _themes.named(candidate) != null; n++) {
      candidate = "$name $n";
    }
    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final names = _themes.names;
        if (names.isEmpty) {
          return Center(child: Text(localizations.colorThemeNoThemes));
        }
        final current = _themes.current;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkClip(
                child: ListView(
                  children: [
                    for (final name in names)
                      ColorThemeTile(
                        name: name,
                        custom: _themes.named(name)!.custom,
                        selected: name == current?.name,
                        onTap: () => unawaited(_themes.select(name)),
                        onClone: () => unawaited(_clone(_themes.named(name)!)),
                        onDelete: () => unawaited(_themes.remove(name)),
                      ),
                  ],
                ),
              ),
            ),
            if (current != null && current.custom) ...[
              const Divider(height: 1),
              ThemeEditor(
                key: ValueKey(current.name),
                set: current,
                onChanged: () => unawaited(_themes.reapply()),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A color theme in the list; while the pointer is over it, buttons clone
/// it and, for the user's own, delete it.
class ColorThemeTile extends StatefulWidget {
  const ColorThemeTile({
    required this.name,
    required this.custom,
    required this.selected,
    required this.onTap,
    required this.onClone,
    required this.onDelete,
    super.key,
  });

  final String name;
  final bool custom;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClone;
  final VoidCallback onDelete;

  @override
  State<ColorThemeTile> createState() => _ColorThemeTileState();
}

class _ColorThemeTileState extends State<ColorThemeTile> {
  static const double _minWidthForButtons = 200;

  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      // The buttons need room; in a tile narrower than that (a dialog
      // that is still opening) they would fill it, which a ListTile
      // refuses.
      child: LayoutBuilder(
        builder: (context, constraints) => ListTile(
          dense: true,
          selected: widget.selected,
          title: Text(widget.name),
          subtitle: widget.custom ? Text(localizations.colorThemeCustom) : null,
          onTap: widget.onTap,
          trailing: _hovering && constraints.maxWidth >= _minWidthForButtons
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: localizations.colorThemeClone,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: widget.onClone,
                    ),
                    if (widget.custom)
                      IconButton(
                        tooltip: localizations.delete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: widget.onDelete,
                      ),
                  ],
                )
              : null,
        ),
      ),
    );
  }
}

/// Asks for the name of a new color theme.
class ThemeNameDialog extends StatefulWidget {
  const ThemeNameDialog({
    required this.title,
    required this.label,
    required this.initial,
    super.key,
  });

  final String title;
  final String label;
  final String initial;

  @override
  State<ThemeNameDialog> createState() => _ThemeNameDialogState();
}

class _ThemeNameDialogState extends State<ThemeNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(localizations.ok),
        ),
      ],
    );
  }
}

/// Edits what the custom theme [set] does to all of the skin: the
/// `General` gamma group, which adds to every other group.
class ThemeEditor extends StatefulWidget {
  const ThemeEditor({required this.set, required this.onChanged, super.key});

  final WasabiGammaSet set;

  /// Called once an edit is done, after [set] has changed.
  final VoidCallback onChanged;

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<ThemeEditor> {
  late WasabiGammaGroup _group = widget.set.general;

  /// Shows [group] while a slider is dragged.
  void _show(WasabiGammaGroup group) => setState(() => _group = group);

  /// Keeps [group] in the theme.
  void _commit(WasabiGammaGroup group) {
    setState(() => _group = group);
    widget.set.general = group;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThemeChannelSlider(
            label: localizations.colorThemeRed,
            value: _group.red,
            onChanged: (value) => _show(_group.copyWith(red: value)),
            onChangeEnd: (value) => _commit(_group.copyWith(red: value)),
          ),
          ThemeChannelSlider(
            label: localizations.colorThemeGreen,
            value: _group.green,
            onChanged: (value) => _show(_group.copyWith(green: value)),
            onChangeEnd: (value) => _commit(_group.copyWith(green: value)),
          ),
          ThemeChannelSlider(
            label: localizations.colorThemeBlue,
            value: _group.blue,
            onChanged: (value) => _show(_group.copyWith(blue: value)),
            onChangeEnd: (value) => _commit(_group.copyWith(blue: value)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(localizations.colorThemeGray),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  value: _group.gray.clamp(0, 2),
                  isDense: true,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(localizations.colorThemeGrayNone),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(localizations.colorThemeGrayBrightest),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text(localizations.colorThemeGrayAverage),
                    ),
                  ],
                  onChanged: (value) =>
                      _commit(_group.copyWith(gray: value ?? 0)),
                ),
              ),
              const SizedBox(width: 16),
              FilterChip(
                label: Text(localizations.colorThemeBoost),
                selected: _group.boost,
                onSelected: (value) => _commit(_group.copyWith(boost: value)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A slider for one channel of a color theme, from -4096 to 4096.
class ThemeChannelSlider extends StatelessWidget {
  const ThemeChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                min: -4096,
                max: 4096,
                value: value.clamp(-4096, 4096).toDouble(),
                onChanged: (v) => onChanged(v.round()),
                onChangeEnd: (v) => onChangeEnd(v.round()),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              "$value",
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
