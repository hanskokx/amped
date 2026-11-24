import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/foundation.dart" show listEquals;
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

import "wasabi_contrast.dart";
import "wasabi_gamma.dart";
import "wasabi_host.dart";
import "wasabi_skin_data.dart";
import "wasabi_view.dart";

/// Where the color theme chosen for each skin is kept, by skin name
/// (the classic player's `Color Themes/<skin>` private string).
const String wasabiColorThemesSection = "Color Themes";

/// The key in [wasabiColorThemesSection] of the theme chosen last for any
/// skin, which skins share while [wasabiSharesColorTheme].
const String wasabiSharedColorThemeKey = "*";

/// The key in [wasabiColorThemesSection] of whether skins share one color
/// theme ("1", the default) or each keeps its own ("0").
const String wasabiShareColorThemeKey = "*share";

/// Whether every skin that has a theme of the chosen name uses it, rather
/// than each skin remembering its own.
bool wasabiSharesColorTheme(WasabiHost host) =>
    host.readPrivate(wasabiColorThemesSection, wasabiShareColorThemeKey) != "0";

void wasabiShareColorTheme(WasabiHost host, {required bool share}) =>
    host.writePrivate(
      wasabiColorThemesSection,
      wasabiShareColorThemeKey,
      share ? "1" : "0",
    );

/// The color theme to start the skin named [skinName] with, or null when
/// none was chosen: what to give [WasabiSkinData.load]. A skin without a theme
/// of that name starts with its first.
String? wasabiSavedColorTheme(WasabiHost host, String skinName) =>
    host.readPrivate(
      wasabiColorThemesSection,
      wasabiSharesColorTheme(host) ? wasabiSharedColorThemeKey : skinName,
    ) ??
    host.readPrivate(wasabiColorThemesSection, skinName);

/// Switches [skin] to the color theme named [name] and remembers it for
/// the skin and for all skins (`SkinApi::colortheme_setColorSet`).
/// Completes when the skin's bitmaps show the theme.
Future<void> wasabiSelectColorTheme(
  WasabiSkinData skin,
  WasabiHost host,
  String name,
) {
  final set = skin.colorThemes.named(name);
  if (set == null) return skin.colorThemes.settled;
  host.writePrivate(wasabiColorThemesSection, skin.name, set.name);
  host.writePrivate(
    wasabiColorThemesSection,
    wasabiSharedColorThemeKey,
    set.name,
  );
  return skin.colorThemes.select(set.name);
}

/// Whether [object] is a color themes list (`<ColorThemes:List>`) or its
/// invisible kind (`<ColorThemes:Mgr>`), which take the `colorthemes_*`
/// actions.
bool wasabiIsColorThemesList(WasabiObject object) =>
    object.tag == "colorthemes:list" || object.tag == "colorthemes:mgr";

/// The theme selected in [list]: the row a click chose, else the theme
/// that is on.
String? wasabiSelectedColorTheme(WasabiSkinData skin, WasabiObject list) =>
    list["#selected"] ?? skin.colorThemes.current?.name;

/// Runs a button's [action] on the color themes list [list]
/// (`ColorThemesList::onAction`): `colorthemes_switch` turns on the
/// selected theme, `colorthemes_next` and `colorthemes_previous` the one
/// after and before the current one. Whether it was one of those.
bool wasabiColorThemeAction(
  WasabiSkinData skin,
  WasabiHost host,
  WasabiObject list,
  String action,
) {
  if (!wasabiIsColorThemesList(list)) return false;
  final String? name;
  switch (action.toLowerCase()) {
    case "colorthemes_switch":
      // The invisible kind has no selection to switch to.
      if (list.tag != "colorthemes:list") return false;
      name = wasabiSelectedColorTheme(skin, list);
    case "colorthemes_next":
      name = skin.colorThemes.advance(1);
    case "colorthemes_previous":
      name = skin.colorThemes.advance(-1);
    default:
      return false;
  }
  if (name != null) wasabiSelectColorTheme(skin, host, name);
  return true;
}

/// A `<ColorThemes:List>`: the skin's color themes by name, sorted, in the
/// skin's `wasabi.list.*` colors with its `wasabi.scrollbar.*` scrollbar.
/// The theme that is on is bold. A click selects a theme and a
/// double-click switches to it (`ColorThemesList::onDoubleClick`); the
/// mouse wheel, the trackpad and the scrollbar scroll.
class WasabiColorThemesView extends StatefulWidget {
  const WasabiColorThemesView({
    required this.skin,
    required this.host,
    required this.object,
    super.key,
  });

  final WasabiSkinData skin;
  final WasabiHost host;
  final WasabiObject object;

  @override
  State<WasabiColorThemesView> createState() => _WasabiColorThemesViewState();
}

class _WasabiColorThemesViewState extends State<WasabiColorThemesView> {
  static const double _rowHeight = 18;
  static const double _fontSize = 13;

  /// The scrollbar's width when the skin has no bitmaps for it.
  static const double _plainBarWidth = 13;

  double _scroll = 0;

  /// The current theme the list last made sure was in view.
  String? _shown;

  String? _lastTapName;
  DateTime _lastTap = DateTime(0);

  /// The pointer's offset from the thumb's top while dragging it.
  double? _grab;

  WasabiColorThemes get _themes => widget.skin.colorThemes;

  double _maxScroll(double viewHeight) =>
      math.max(0.0, _themes.names.length * _rowHeight - viewHeight);

  void _scrollTo(double value, double viewHeight) {
    final next = value.clamp(0.0, _maxScroll(viewHeight));
    if (next != _scroll) setState(() => _scroll = next);
  }

  void _tapRow(double y) {
    final names = _themes.names;
    final row = ((y + _scroll) / _rowHeight).floor();
    if (row < 0 || row >= names.length) return;
    final name = names[row];
    final now = DateTime.now();
    final double =
        name == _lastTapName &&
        now.difference(_lastTap) < const Duration(milliseconds: 400);
    _lastTapName = double ? null : name;
    _lastTap = now;
    setState(() => widget.object.attributes["#selected"] = name);
    // A click only selects; a double-click or the skin's switch button
    // turns the theme on, as in the classic player.
    if (double) wasabiSelectColorTheme(widget.skin, widget.host, name);
  }

  void _pressBar(double y, _BarGeometry bar, double viewHeight) {
    if (y < bar.upHeight) {
      _scrollTo(_scroll - _rowHeight, viewHeight);
    } else if (y >= viewHeight - bar.downHeight) {
      _scrollTo(_scroll + _rowHeight, viewHeight);
    } else if (y < bar.thumbTop) {
      _scrollTo(_scroll - viewHeight, viewHeight);
    } else if (y >= bar.thumbTop + bar.thumbHeight) {
      _scrollTo(_scroll + viewHeight, viewHeight);
    } else {
      _grab = y - bar.thumbTop;
    }
  }

  void _dragBar(double y, _BarGeometry bar, double viewHeight) {
    final grab = _grab;
    if (grab == null || bar.travel <= 0) return;
    final top = (y - grab - bar.upHeight).clamp(0.0, bar.travel);
    _scrollTo(top / bar.travel * _maxScroll(viewHeight), viewHeight);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The list shows the theme that is on, in that theme's colors.
    listenable: _themes,
    builder: (context, _) => _buildList(context),
  );

  Color _color(List<String> ids, ui.Color fallback) {
    for (final id in ids) {
      final color = widget.skin.color(id);
      if (color != null) return color;
    }
    return fallback;
  }

  /// The skin's list colors, with the fallbacks a playlist has: a skin
  /// without `wasabi.list.*` names its own.
  ({
    ui.Color background,
    ui.Color text,
    ui.Color selected,
    ui.Color selectedText,
  })
  _listColors() {
    final background = _color([
      "wasabi.list.background",
      "pledit.background",
      "studio.list.background",
      if (widget.skin.color("studio.list.text") != null)
        "studio.textBar.background",
    ], const ui.Color(0xFF000000));
    final selected = _color([
      "wasabi.list.text.selected.background",
      "pledit.text.selected.background",
      "studio.list.item.selected",
    ], const ui.Color(0xFF0000C6));
    return (
      background: background,
      text: wasabiLegible(
        _color([
          "wasabi.list.text",
          "pledit.text",
          "studio.list.text",
        ], const ui.Color(0xFF00FF00)),
        background,
      ),
      selected: selected,
      selectedText: wasabiLegible(
        _color([
          "wasabi.list.text.selected",
          "studio.list.item.selected.fg",
          "wasabi.list.text",
        ], const ui.Color(0xFF00FF00)),
        selected,
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final skin = widget.skin;
    final themes = _themes;
    final names = themes.names;
    final current = themes.current?.name;
    final selected = wasabiSelectedColorTheme(skin, widget.object);
    final up = skin.bitmap("wasabi.scrollbar.vertical.left");
    final down = skin.bitmap("wasabi.scrollbar.vertical.right");
    final thumb = skin.bitmap("wasabi.scrollbar.vertical.button");
    final track = skin.bitmap("wasabi.scrollbar.vertical.background.middle");
    final barWidth = up?.width ?? thumb?.width ?? _plainBarWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight;
        final max = _maxScroll(viewHeight);
        // A theme turned on elsewhere (Next, Previous) scrolls into view,
        // as does the current one when the list first shows.
        if (current != _shown) {
          _shown = current;
          final row = current == null ? -1 : names.indexOf(current);
          if (row >= 0) {
            final top = row * _rowHeight;
            if (top < _scroll) _scroll = top;
            if (top + _rowHeight > _scroll + viewHeight) {
              _scroll = top + _rowHeight - viewHeight;
            }
          }
        }
        _scroll = _scroll.clamp(0.0, max);
        final bar = _BarGeometry(
          viewHeight: viewHeight,
          upHeight: up?.height ?? 0,
          downHeight: down?.height ?? 0,
          thumbHeight: thumb?.height ?? 16,
          fraction: max <= 0 ? 0 : _scroll / max,
        );
        final colors = _listColors();
        final listWidth = constraints.maxWidth - barWidth;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _scrollTo(_scroll + event.scrollDelta.dy, viewHeight);
            }
          },
          // macOS trackpads scroll with pan gestures, not scroll signals.
          onPointerPanZoomUpdate: (event) =>
              _scrollTo(_scroll - event.localPanDelta.dy, viewHeight),
          onPointerDown: (event) {
            if (event.buttons != kPrimaryButton) return;
            WasabiPointerClaim.claim?.call(event);
            final at = event.localPosition;
            if (at.dx < listWidth) {
              _tapRow(at.dy);
            } else {
              _pressBar(at.dy, bar, viewHeight);
            }
          },
          onPointerMove: (event) =>
              _dragBar(event.localPosition.dy, bar, viewHeight),
          onPointerUp: (_) => _grab = null,
          onPointerCancel: (_) => _grab = null,
          child: ClipRect(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ThemesPainter(
                names: names,
                current: current,
                selected: selected,
                scroll: _scroll,
                rowHeight: _rowHeight,
                fontSize: _fontSize,
                fontFamily: skin.fontFamily(widget.object["font"]),
                background: colors.background,
                text: colors.text,
                selectedText: colors.selectedText,
                selectedBackground: colors.selected,
                barWidth: barWidth,
                bar: bar,
                bitmaps: [track, up, down, thumb],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where the parts of the list's scrollbar are, from the top of the list:
/// an up button, a thumb that travels, and a down button.
@immutable
class _BarGeometry {
  const _BarGeometry({
    required this.viewHeight,
    required this.upHeight,
    required this.downHeight,
    required this.thumbHeight,
    required this.fraction,
  });

  final double viewHeight;
  final double upHeight;
  final double downHeight;
  final double thumbHeight;

  /// How far the list is scrolled, 0 (top) to 1 (bottom).
  final double fraction;

  /// How far the thumb can move.
  double get travel =>
      math.max(0.0, viewHeight - upHeight - downHeight - thumbHeight);

  double get thumbTop => upHeight + fraction * travel;

  @override
  bool operator ==(Object other) =>
      other is _BarGeometry &&
      other.viewHeight == viewHeight &&
      other.upHeight == upHeight &&
      other.downHeight == downHeight &&
      other.thumbHeight == thumbHeight &&
      other.fraction == fraction;

  @override
  int get hashCode =>
      Object.hash(viewHeight, upHeight, downHeight, thumbHeight, fraction);
}

class _ThemesPainter extends CustomPainter {
  _ThemesPainter({
    required this.names,
    required this.current,
    required this.selected,
    required this.scroll,
    required this.rowHeight,
    required this.fontSize,
    required this.fontFamily,
    required this.background,
    required this.text,
    required this.selectedText,
    required this.selectedBackground,
    required this.barWidth,
    required this.bar,
    required this.bitmaps,
  }) : images = [for (final bitmap in bitmaps) bitmap?.image];

  final List<String> names;
  final String? current;
  final String? selected;
  final double scroll;
  final double rowHeight;
  final double fontSize;
  final String? fontFamily;
  final Color background;
  final Color text;
  final Color selectedText;
  final Color selectedBackground;
  final double barWidth;
  final _BarGeometry bar;

  /// The scrollbar's track, up button, down button and thumb.
  final List<WasabiBitmap?> bitmaps;

  /// The pictures of [bitmaps] in the color theme they are painted in.
  final List<ui.Image?> images;

  @override
  void paint(Canvas canvas, Size size) {
    final listWidth = size.width - barWidth;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, listWidth, size.height),
      Paint()..color = background,
    );
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, listWidth, size.height));
    final first = math.max(0, (scroll / rowHeight).floor());
    final last = math.min(
      names.length - 1,
      ((scroll + size.height) / rowHeight).ceil(),
    );
    for (var i = first; i <= last; i++) {
      final name = names[i];
      final top = i * rowHeight - scroll;
      final isSelected = name == selected;
      if (isSelected) {
        canvas.drawRect(
          Rect.fromLTWH(2, top, listWidth - 2, rowHeight),
          Paint()..color = selectedBackground,
        );
      }
      final label = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: fontSize,
            // The theme that is on (ColorThemesList::getTextBold).
            fontWeight: name == current ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? selectedText : text,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: math.max(0, listWidth - 8));
      label.paint(canvas, Offset(5, top + (rowHeight - label.height) / 2));
    }
    canvas.restore();
    _paintBar(canvas, Rect.fromLTWH(listWidth, 0, barWidth, size.height));
  }

  void _paintBar(Canvas canvas, Rect area) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    void draw(int index, Rect dest) {
      final bitmap = bitmaps[index];
      final image = images[index];
      if (bitmap == null || image == null) return;
      canvas.drawImageRect(image, bitmap.src, dest, paint);
    }

    if (images.every((image) => image == null)) {
      // No scrollbar bitmaps: a plain track and thumb.
      canvas
        ..drawRect(area, Paint()..color = background)
        ..drawRect(
          Rect.fromLTWH(
            area.left + 2,
            bar.thumbTop,
            area.width - 4,
            bar.thumbHeight,
          ),
          Paint()..color = text.withValues(alpha: 0.6),
        );
      return;
    }
    draw(0, area);
    draw(1, Rect.fromLTWH(area.left, 0, area.width, bar.upHeight));
    draw(
      2,
      Rect.fromLTWH(
        area.left,
        area.bottom - bar.downHeight,
        area.width,
        bar.downHeight,
      ),
    );
    draw(
      3,
      Rect.fromLTWH(area.left, bar.thumbTop, area.width, bar.thumbHeight),
    );
  }

  @override
  bool shouldRepaint(_ThemesPainter oldDelegate) =>
      !listEquals(oldDelegate.names, names) ||
      oldDelegate.current != current ||
      oldDelegate.selected != selected ||
      oldDelegate.scroll != scroll ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.background != background ||
      oldDelegate.text != text ||
      oldDelegate.selectedText != selectedText ||
      oldDelegate.selectedBackground != selectedBackground ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.bar != bar ||
      !listEquals(oldDelegate.images, images);
}
