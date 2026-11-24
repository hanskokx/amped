import "dart:async";
import "dart:collection";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "../player/eq_presets.dart";
import "../player/player_state.dart";

/// The EQ preset dialog mode, mirroring the original `IDD_LOADPRESET` /
/// `IDD_SAVEPRESET` dialogs (Eq.cpp): load/delete share one listbox dialog and
/// save adds a name field.
enum PresetsMode { load, save, delete }

/// The Equalizer presets dialog window.
///
/// A dialog (opened from the EQ presets button) with a mode switcher for
/// Load/Save/Delete, a preset list, a name field for Save, and a Default reset.
/// Loads/Defaults apply the preset to [player]; Save stores [player]'s current
/// Equalizer settings via [EqPresets].
class PresetsWindow extends StatefulWidget {
  const PresetsWindow({
    required this.mode,
    required this.skin,
    this.autoLoad = false,
    this.player,
    this.onClose,
    super.key,
  });

  final PresetsMode mode;

  /// The skin the window is drawn in (its playlist colours and font).
  final ClassicSkinData skin;

  /// Whether this works on the auto-load library (presets named after the
  /// files they load for) instead of the presets.
  final bool autoLoad;

  /// The Equalizer state presets are applied to and saved from.
  final PlayerState? player;

  /// Closes the dialog window.
  final VoidCallback? onClose;

  @override
  State<PresetsWindow> createState() => _PresetsWindowState();
}

class _PresetsWindowState extends State<PresetsWindow> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  /// The width of the buttons beside the list: room for "DEFAULT".
  static const double _buttonWidth = 52;

  /// A row's height.
  static const double _rowHeight = 13;
  late PresetsMode _mode;
  Map<String, EqPreset> _presets = const {};
  String? _selected;
  bool _busy = false;
  String? _message;

  String _presetLabel(String name, AppLocalizations localizations) =>
      switch (name) {
        "Classical" => localizations.eqPresetClassical,
        "Club" => localizations.eqPresetClub,
        "Dance" => localizations.eqPresetDance,
        "Flat" => localizations.eqPresetFlat,
        "Laptop speakers/headphones" => localizations.eqPresetLaptop,
        "Large hall" => localizations.eqPresetLargeHall,
        "Party" => localizations.eqPresetParty,
        "Pop" => localizations.eqPresetPop,
        "Reggae" => localizations.eqPresetReggae,
        "Rock" => localizations.eqPresetRock,
        "Soft" => localizations.eqPresetSoft,
        "Ska" => localizations.eqPresetSka,
        "Full Bass" => localizations.eqPresetFullBass,
        "Soft Rock" => localizations.eqPresetSoftRock,
        "Full Treble" => localizations.eqPresetFullTreble,
        "Full Bass & Treble" => localizations.eqPresetFullBassTreble,
        "Live" => localizations.eqPresetLive,
        "Techno" => localizations.eqPresetTechno,
        "Hall" => localizations.eqPresetHall,
        "Room" => localizations.eqPresetRoom,
        "Arena" => localizations.eqPresetArena,
        "Studio" => localizations.eqPresetStudio,
        "Stadium" => localizations.eqPresetStadium,
        "Space" => localizations.eqPresetSpace,
        _ => name,
      };

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    unawaited(_initPresets());
  }

  @override
  void didUpdateWidget(covariant PresetsWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != _mode) {
      setState(() => _mode = widget.mode);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initPresets() async {
    final loaded = await EqPresets.load(autoLoad: widget.autoLoad);
    // Saving an auto-load preset suggests the playing file's name.
    final file = widget.player?.playlist.currentEntry;
    if (widget.autoLoad && file != null && !file.isUrl) {
      _nameController.text = file.location.split(RegExp(r"[/\\]")).last;
    }
    var selected = widget.autoLoad
        ? _nameController.text
        : await EqPresets.lastPreset();
    final sorted = _sorted(loaded);
    if (selected != null && !sorted.containsKey(selected)) {
      selected = sorted.isEmpty ? null : sorted.keys.first;
    }
    if (mounted) {
      setState(() {
        _presets = sorted;
        _selected = selected;
      });
    }
  }

  static SplayTreeMap<String, EqPreset> _sorted(Map<String, EqPreset> presets) {
    return SplayTreeMap<String, EqPreset>(
      (a, b) {
        final byCase = a.toLowerCase().compareTo(b.toLowerCase());
        return byCase != 0 ? byCase : a.compareTo(b);
      },
    )..addAll(presets);
  }

  Future<void> _reloadPresets({String? select}) async {
    final loaded = await EqPresets.load(autoLoad: widget.autoLoad);
    final sorted = _sorted(loaded);
    final current = _selected;
    final selection =
        select ??
        (current != null && sorted.containsKey(current) ? current : null);
    if (mounted) {
      setState(() {
        _presets = sorted;
        _selected = selection;
        _message = null;
      });
    }
  }

  Future<void> _load() async {
    final name = _selected;
    if (name == null) return;
    final preset = await EqPresets.byName(name, autoLoad: widget.autoLoad);
    if (preset == null) return;
    await _applyPreset(preset);
  }

  Future<void> _applyDefault() async {
    final stored = await EqPresets.byName("Default");
    await _applyPreset(stored ?? EqPresets.defaultPreset);
  }

  Future<void> _applyPreset(EqPreset preset) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    widget.player?.applyEq(preset.preamp, preset.bands);
    if (!widget.autoLoad) await EqPresets.setLastPreset(preset.name);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => _message = AppLocalizations.of(context).enterPresetName,
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final player = widget.player;
    await EqPresets.save(
      EqPreset(
        name: name,
        preamp: player?.preamp ?? 31,
        bands: List.of(player?.eqBands ?? List.filled(10, 31)),
      ),
      autoLoad: widget.autoLoad,
    );
    if (!widget.autoLoad) await EqPresets.setLastPreset(name);
    _nameController.clear();
    await _reloadPresets(select: name);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final name = _selected;
    if (name == null) return;
    await EqPresets.remove(name, autoLoad: widget.autoLoad);
    if (mounted) setState(() => _selected = null);
    await _reloadPresets();
  }

  /// Scrolls the list [rows] rows, to a whole row.
  void _scrollRows(int rows) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final row = (position.pixels / _rowHeight).round() + rows;
    _scroll.jumpTo((row * _rowHeight).clamp(0, position.maxScrollExtent));
  }

  Future<void> _close() async => widget.onClose?.call();

  String _actionLabel(AppLocalizations localizations) => switch (_mode) {
    PresetsMode.load => localizations.load,
    PresetsMode.save => localizations.save,
    PresetsMode.delete => localizations.delete,
  };

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = widget.skin.pledit;
    final mode = _mode;
    final hasSelection = _selected != null;
    final canAct = switch (mode) {
      PresetsMode.load || PresetsMode.delete => hasSelection,
      PresetsMode.save => true,
    };
    final action = switch (mode) {
      PresetsMode.load => () => unawaited(_load()),
      PresetsMode.save => () => unawaited(_save()),
      PresetsMode.delete => () => unawaited(_delete()),
    };
    final style = TextStyle(
      fontFamily: colors.fontName.isEmpty ? "Arial" : colors.fontName,
      fontSize: 12,
      height: 1.1,
      color: colors.normal,
      decoration: TextDecoration.none,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_close()),
      },
      // In Save the name field has the focus; otherwise this does, so that
      // Escape has somewhere to come from.
      // TODO(any): Break this widget up into smaller ones, so we collapse the widget tree depth in the file.
      child: Focus(
        autofocus: mode != PresetsMode.save,
        child: DefaultTextStyle(
          style: style,
          child: ColoredBox(
            color: colors.normalBg,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ColoredBox(
                            color: colors.normalBg,
                            child: _presets.isEmpty
                                ? Center(child: Text(localizations.noPresets))
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: SkinWheelScroll(
                                          // A line at a time.
                                          rowsPerNotch: 1,
                                          onScroll: _scrollRows,
                                          child: ScrollConfiguration(
                                            // No stretch or glow at the ends.
                                            behavior:
                                                ScrollConfiguration.of(
                                                  context,
                                                ).copyWith(
                                                  overscroll: false,
                                                  scrollbars: false,
                                                ),
                                            child: ListView.builder(
                                              controller: _scroll,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: _presets.length,
                                              itemExtent: _rowHeight,
                                              itemBuilder: (context, index) {
                                                final name = _presets.keys
                                                    .elementAt(
                                                      index,
                                                    );
                                                final isSelected =
                                                    name == _selected;
                                                return GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () => setState(() {
                                                    _selected = name;
                                                    _message = null;
                                                  }),
                                                  onDoubleTap:
                                                      mode == PresetsMode.load
                                                      ? () => unawaited(_load())
                                                      : null,
                                                  child: ColoredBox(
                                                    color: isSelected
                                                        ? colors.selectedBg
                                                        : colors.normalBg,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                          ),
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          _presetLabel(
                                                            name,
                                                            localizations,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: style.copyWith(
                                                            color: isSelected
                                                                ? colors.current
                                                                : colors.normal,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: SkinScrollbar.width,
                                        child: SkinScrollbar(
                                          skin: widget.skin,
                                          controller: _scroll,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (mode == PresetsMode.save) ...[
                          const SizedBox(height: 4),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.normal),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Stack(
                                children: [
                                  if (_nameController.text.isEmpty)
                                    IgnorePointer(
                                      child: Text(
                                        localizations.presetName,
                                        style: style.copyWith(
                                          color: colors.normal.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  EditableText(
                                    controller: _nameController,
                                    focusNode: _nameFocus,
                                    autofocus: true,
                                    readOnly: _busy,
                                    style: style.copyWith(
                                      color: colors.current,
                                    ),
                                    cursorColor: colors.current,
                                    backgroundCursorColor: colors.normal,
                                    selectionColor: colors.selectedBg,
                                    maxLines: 1,
                                    onSubmitted: (_) => unawaited(_save()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (_message != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              _message!,
                              style: style.copyWith(color: colors.current),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // The buttons stand in a column at the right, so the list
                  // gets the height.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkinTextButton(
                        skin: widget.skin,
                        label: _actionLabel(localizations),
                        width: _buttonWidth,
                        onPressed: _busy || !canAct ? null : action,
                      ),
                      const SizedBox(height: 3),
                      SkinTextButton(
                        skin: widget.skin,
                        label: localizations.defaultPreset,
                        width: _buttonWidth,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_applyDefault()),
                      ),
                      const SizedBox(height: 3),
                      SkinTextButton(
                        skin: widget.skin,
                        label: localizations.close,
                        width: _buttonWidth,
                        onPressed: _busy ? null : () => unawaited(_close()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A button in the skin: the playlist's colours with a bevel, and the label in the skin's bitmap font (`text.bmp`), which has capitals
/// only.
class SkinTextButton extends StatefulWidget {
  const SkinTextButton({
    required this.skin,
    required this.label,
    required this.onPressed,
    this.width,
    super.key,
  });

  final ClassicSkinData skin;
  final String label;

  /// The button's width; as wide as its label when null.
  final double? width;
  final VoidCallback? onPressed;

  @override
  State<SkinTextButton> createState() => SkinTextButtonState();
}

class SkinTextButtonState extends State<SkinTextButton> {
  bool _pressed = false;

  static const double _height = 14;

  @override
  Widget build(BuildContext context) {
    final label = widget.label.toUpperCase();
    final enabled = widget.onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: CustomPaint(
        size: Size(
          widget.width ?? label.length * TextFont.charWidth + 12,
          _height,
        ),
        painter: _SkinTextButtonPainter(
          colors: widget.skin.pledit,
          font: TextFont(widget.skin.image("text.bmp")!),
          label: label,
          pressed: _pressed && enabled,
          enabled: enabled,
        ),
      ),
    );
  }
}

class _SkinTextButtonPainter extends CustomPainter {
  const _SkinTextButtonPainter({
    required this.colors,
    required this.font,
    required this.label,
    required this.pressed,
    required this.enabled,
  });

  final PlEditConfig colors;
  final TextFont font;
  final String label;
  final bool pressed;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    // The playlist's colours: its background for the face (lit like a
    // selected row while pressed), the text colour as the bevel.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = pressed ? colors.selectedBg : colors.normalBg,
    );
    final light = Paint()..color = colors.normal.withValues(alpha: 0.9);
    final dark = Paint()..color = colors.normal.withValues(alpha: 0.35);
    final top = pressed ? dark : light;
    final bottom = pressed ? light : dark;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, 1), top)
      ..drawRect(Rect.fromLTWH(0, 0, 1, size.height), top)
      ..drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), bottom)
      ..drawRect(Rect.fromLTWH(size.width - 1, 0, 1, size.height), bottom);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, enabled ? 1 : 0.4);
    final shift = pressed ? 1.0 : 0.0;
    var x =
        ((size.width - label.length * TextFont.charWidth) / 2).floorToDouble() +
        shift;
    final y = (size.height - TextFont.charHeight) / 2 + shift;
    for (var i = 0; i < label.length; i++) {
      canvas.drawImageRect(
        font.image,
        font.glyphRect(label[i]),
        Rect.fromLTWH(x, y, TextFont.charWidth, TextFont.charHeight),
        paint,
      );
      x += TextFont.charWidth;
    }
  }

  @override
  bool shouldRepaint(_SkinTextButtonPainter old) =>
      old.pressed != pressed || old.label != label || old.enabled != enabled;
}
