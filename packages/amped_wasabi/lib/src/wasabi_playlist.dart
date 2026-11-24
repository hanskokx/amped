import "dart:math" as math;

import "package:flutter/foundation.dart" show listEquals;
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "wasabi_contrast.dart";
import "wasabi_host.dart";
import "wasabi_skin_data.dart";
import "wasabi_view.dart" show WasabiPointerClaim;

/// A playlist item's [ms] length as `m:ss`, or `h:mm:ss` from an hour up;
/// empty when unknown (negative).
String formatPlaylistItemTime(int ms) {
  if (ms < 0) return "";
  final s = ms ~/ 1000;
  final ss = (s % 60).toString().padLeft(2, "0");
  if (s < 3600) return "${s ~/ 60}:$ss";
  final mm = (s ~/ 60 % 60).toString().padLeft(2, "0");
  return "${s ~/ 3600}:$mm:$ss";
}

/// The the classic player component a `<component param="...">` or
/// `<windowholder hold="...">` holds: `pl`, `ml`, `vis` or `video` (by
/// `guid:name` or the component's GUID), or null.
String? wasabiComponentName(WasabiObject object) {
  if (object.tag != "component" && object.tag != "windowholder") return null;
  final value = (object["param"] ?? object["hold"] ?? object["component"] ?? "")
      .toLowerCase();
  for (final MapEntry(key: name, value: keys) in _components.entries) {
    if (keys.any(value.contains)) return name;
  }
  return null;
}

/// The the classic player component a script names with [id] (`guid:avs`, or the
/// component's GUID as `System.showWindow` and `isNamedWindowVisible` take
/// it), or null: see [wasabiComponentName].
String? wasabiComponentOf(String id) {
  final value = id.toLowerCase();
  for (final MapEntry(key: name, value: keys) in _components.entries) {
    if (keys.any(value.contains)) return name;
  }
  return null;
}

/// The visualization component's GUID, as scripts get it in
/// `System.onGetCancelComponent`.
const String wasabiVisGuid = "{0000000A-000C-0010-FF7B-01014263450C}";

/// The video component's GUID.
const String wasabiVideoGuid = "{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}";

/// A component's GUID in braces (`WindowHolder.getGuid`): the playlist
/// editor's, the library's, the visualization's or the video's.
String? wasabiComponentGuid(String name) => switch (name) {
  "pl" => "{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}",
  "ml" => "{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}",
  "vis" => wasabiVisGuid,
  "video" => wasabiVideoGuid,
  _ => null,
};

/// A component's name as the classic player titles its window
/// (`WindowHolder.getComponentName`).
String? wasabiComponentTitle(String name) => switch (name) {
  "pl" => "Playlist Editor",
  "ml" => "Media Library",
  "vis" => "Visualization",
  "video" => "Video",
  _ => null,
};

const Map<String, List<String>> _components = {
  "pl": ["guid:pl", "45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d"],
  "ml": ["guid:ml", "6b0edf80-c9a5-11d3-9f26-00c04f39ffc6"],
  "vis": ["guid:avs", "guid:vis", "0000000a-000c-0010-ff7b-01014263450c"],
  "video": ["guid:video", "f0816d7b-fffc-4343-80f2-e8199aa15cc3"],
};

/// The playlist inside a modern skin: one row per entry, "N. Title" with the
/// length on the right, in the skin's `wasabi.list.*` colors (Wasabi 5's
/// `pledit.*` names as a fallback). Click selects, Shift extends, Cmd/Ctrl
/// toggles, a double-click plays. The mouse wheel and trackpad scroll, and
/// a scrollbar on the right shows and drags the position when the list is
/// longer than the view.
class WasabiPlaylistView extends StatefulWidget {
  const WasabiPlaylistView({
    required this.skin,
    required this.host,
    required this.object,
    super.key,
  });

  final WasabiSkinData skin;
  final WasabiHost host;
  final WasabiObject object;

  @override
  State<WasabiPlaylistView> createState() => _WasabiPlaylistViewState();
}

class _WasabiPlaylistViewState extends State<WasabiPlaylistView> {
  double _scroll = 0;

  /// The scripts' last request to show the playing track that was met.
  int _revealed = 0;
  int? _lastTapRow;
  DateTime _lastTap = DateTime(0);

  static const double _padding = 2;

  /// The entries shown while the search box holds a query (indices in
  /// playlist order), or null for all of them. Searched again when the
  /// query or the playlist's length changes.
  List<int>? _rows;
  String _rowsQuery = "";
  int _rowsLength = -1;

  List<int>? _visibleRows() {
    final query = widget.skin.playlistFilter.value.trim();
    if (query.isEmpty) {
      _rows = null;
      _rowsQuery = "";
      return null;
    }
    final length = widget.host.playlistLength;
    if (query != _rowsQuery || length != _rowsLength || _rows == null) {
      _rows = widget.host.searchPlaylist(query);
      _rowsQuery = query;
      _rowsLength = length;
    }
    return _rows;
  }

  int get _rowCount => _rows?.length ?? widget.host.playlistLength;

  double get _fontSize =>
      (widget.object.intAttr("fontsize", 14) * 72 / 96).toDouble();
  double get _rowHeight => (_fontSize + 4).roundToDouble();

  Color _color(List<String> ids, Color fallback) {
    for (final id in ids) {
      final color = widget.skin.color(id);
      if (color != null) return color;
    }
    return fallback;
  }

  /// The scrollbar's width, in layout pixels.
  static const double _barWidth = 8;

  double _contentHeight() => _rowCount * _rowHeight + 2 * _padding;

  double _maxScroll(double viewHeight) =>
      math.max(0.0, _contentHeight() - viewHeight);

  void _scrollTo(double value, double viewHeight) {
    final next = value.clamp(0.0, _maxScroll(viewHeight));
    if (next != _scroll) setState(() => _scroll = next);
  }

  /// Scrolls the playing track to the middle of the view when a script has
  /// asked for it since the last time.
  void _revealPlaying(double viewHeight) {
    final requested = widget.skin.playlistReveal.value;
    if (requested == _revealed) return;
    _revealed = requested;
    final current = widget.host.playlistCurrent;
    final row = _rows == null ? current : _rows!.indexOf(current);
    if (current < 0 || row < 0) return;
    final middle = _padding + row * _rowHeight - (viewHeight - _rowHeight) / 2;
    _scroll = middle.clamp(0.0, _maxScroll(viewHeight));
  }

  void _scrollBy(double delta, double viewHeight) =>
      _scrollTo(_scroll + delta, viewHeight);

  /// The pointer of a right-button press, until it is released.
  int? _menuPointer;

  int _rowAt(Offset local) =>
      ((local.dy - _padding + _scroll) / _rowHeight).floor();

  void _rightPress(PointerDownEvent event) {
    final row = _rowAt(event.localPosition);
    final onRow = row >= 0 && row < _rowCount;
    _menuPointer = event.pointer;
    widget.host.pressPlaylistMenu(onRow ? _entryAt(row) : null, event);
  }

  /// The playlist index of row [row].
  int _entryAt(int row) => _rows?[row] ?? row;

  void _tap(Offset local) {
    final host = widget.host;
    final row = _rowAt(local);
    if (row < 0 || row >= _rowCount) return;
    final now = DateTime.now();
    final double =
        row == _lastTapRow &&
        now.difference(_lastTap) < const Duration(milliseconds: 400);
    _lastTapRow = double ? null : row;
    _lastTap = now;
    if (double) {
      host.playPlaylistItem(_entryAt(row));
      return;
    }
    final keys = HardwareKeyboard.instance;
    // A range would take in the entries the search hides.
    final searching = _rows != null;
    host.selectPlaylistItem(
      _entryAt(row),
      extend: keys.isShiftPressed && !searching,
      toggle:
          keys.isMetaPressed ||
          keys.isControlPressed ||
          (keys.isShiftPressed && searching),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.skin.playlistFilter,
        widget.skin.playlistReveal,
        widget.host,
      ]),
      builder: (context, _) {
        _visibleRows();
        return _buildList(context);
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final host = widget.host;
    final family = widget.skin.fontFamily(widget.object["font"]);
    final background = _color([
      "wasabi.list.background",
      "pledit.background",
      "studio.list.background",
      // A Wasabi 3 palette without a list background: the LCD's, which its
      // list text colour is made for.
      if (widget.skin.color("studio.list.text") != null)
        "studio.textBar.background",
    ], const Color(0xFF000000));
    final selected = _color([
      "wasabi.list.text.selected.background",
      "pledit.text.selected.background",
      "studio.list.item.selected",
    ], const Color(0xFF0000C6));
    // The skin's own colours can be too close to read in a list this size.
    final colors = _PlaylistColors(
      background: background,
      text: wasabiLegible(
        _color([
          "wasabi.list.text",
          "pledit.text",
          "studio.list.text",
        ], const Color(0xFF00FF00)),
        background,
      ),
      current: wasabiLegible(
        _color([
          "wasabi.list.text.current",
          "pledit.text.current",
        ], const Color(0xFFFFFFFF)),
        background,
      ),
      selected: selected,
      selectedText: wasabiLegible(
        _color([
          "wasabi.list.text.selected",
          "studio.list.item.selected.fg",
          "wasabi.list.text",
        ], const Color(0xFF00FF00)),
        selected,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight;
        final max = _maxScroll(viewHeight);
        // The list can shrink or the window grow under the current scroll;
        // keep the field in range too, so clicks hit the rows shown.
        _scroll = math.min(_scroll, max);
        _revealPlaying(viewHeight);
        final scroll = _scroll;
        // No bar in a list too narrow to hold it (a component window that is
        // still collapsed to a pixel).
        final showBar = max > 0 && constraints.maxWidth > _barWidth;
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _scrollBy(event.scrollDelta.dy, viewHeight);
            }
          },
          // macOS trackpads scroll with pan gestures, not scroll signals;
          // fingers moving up reveal later rows.
          onPointerPanZoomUpdate: (event) =>
              _scrollBy(-event.localPanDelta.dy, viewHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Listener(
                  onPointerDown: (event) {
                    if (event.buttons == kPrimaryButton) {
                      // The list and its scrollbar keep their presses: a
                      // drag on them does not move the window.
                      WasabiPointerClaim.claim?.call(event);
                      _tap(event.localPosition);
                    } else if (event.buttons == kSecondaryButton) {
                      _rightPress(event);
                    }
                  },
                  onPointerUp: (event) {
                    if (event.pointer != _menuPointer) return;
                    _menuPointer = null;
                    host.showPlaylistMenu();
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _menuPointer) _menuPointer = null;
                  },
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _PlaylistPainter(
                        host: host,
                        colors: colors,
                        fontFamily: family,
                        fontSize: _fontSize,
                        rowHeight: _rowHeight,
                        scroll: scroll,
                        padding: _padding,
                        rows: _rows,
                      ),
                    ),
                  ),
                ),
              ),
              if (showBar)
                SizedBox(
                  width: _barWidth,
                  child: _PlaylistScrollbar(
                    key: const ValueKey("wasabi.playlist.scrollbar"),
                    scroll: scroll,
                    maxScroll: max,
                    viewHeight: viewHeight,
                    colors: colors,
                    onScrollTo: (value) => _scrollTo(value, viewHeight),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A vertical scrollbar beside the playlist: dragging the thumb scrolls,
/// pressing the track above or below it pages (Wasabi's ScrollBar).
class _PlaylistScrollbar extends StatefulWidget {
  const _PlaylistScrollbar({
    required this.scroll,
    required this.maxScroll,
    required this.viewHeight,
    required this.colors,
    required this.onScrollTo,
    super.key,
  });

  final double scroll;
  final double maxScroll;
  final double viewHeight;
  final _PlaylistColors colors;
  final ValueChanged<double> onScrollTo;

  @override
  State<_PlaylistScrollbar> createState() => _PlaylistScrollbarState();
}

class _PlaylistScrollbarState extends State<_PlaylistScrollbar> {
  /// The pointer's offset from the thumb's top while dragging it.
  double? _grab;

  static const double _minThumb = 12;

  double get _thumbHeight {
    final content = widget.maxScroll + widget.viewHeight;
    if (content <= 0) return widget.viewHeight;
    return (widget.viewHeight * widget.viewHeight / content).clamp(
      math.min(_minThumb, widget.viewHeight),
      widget.viewHeight,
    );
  }

  double get _travel => math.max(0.0, widget.viewHeight - _thumbHeight);

  double get _thumbTop =>
      widget.maxScroll <= 0 ? 0 : widget.scroll / widget.maxScroll * _travel;

  void _dragTo(double y) {
    final grab = _grab;
    if (grab == null || _travel <= 0) return;
    final top = (y - grab).clamp(0.0, _travel);
    widget.onScrollTo(top / _travel * widget.maxScroll);
  }

  @override
  Widget build(BuildContext context) {
    final top = _thumbTop;
    final height = _thumbHeight;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        WasabiPointerClaim.claim?.call(event);
        final y = event.localPosition.dy;
        if (y < top) {
          widget.onScrollTo(widget.scroll - widget.viewHeight);
        } else if (y > top + height) {
          widget.onScrollTo(widget.scroll + widget.viewHeight);
        } else {
          _grab = y - top;
        }
      },
      onPointerMove: (event) => _dragTo(event.localPosition.dy),
      onPointerUp: (_) => _grab = null,
      onPointerCancel: (_) => _grab = null,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScrollbarPainter(
          thumbTop: top,
          thumbHeight: height,
          track: widget.colors.background,
          thumb: widget.colors.text,
        ),
      ),
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter({
    required this.thumbTop,
    required this.thumbHeight,
    required this.track,
    required this.thumb,
  });

  final double thumbTop;
  final double thumbHeight;
  final Color track;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = thumb.withValues(alpha: 0.15),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, thumbTop + 1, size.width - 2, thumbHeight - 2),
        const Radius.circular(2),
      ),
      Paint()..color = thumb.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_ScrollbarPainter oldDelegate) =>
      oldDelegate.thumbTop != thumbTop ||
      oldDelegate.thumbHeight != thumbHeight ||
      oldDelegate.track != track ||
      oldDelegate.thumb != thumb;
}

class _PlaylistColors {
  const _PlaylistColors({
    required this.background,
    required this.text,
    required this.current,
    required this.selected,
    required this.selectedText,
  });

  final Color background;
  final Color text;
  final Color current;
  final Color selected;
  final Color selectedText;
}

class _PlaylistPainter extends CustomPainter {
  _PlaylistPainter({
    required this.host,
    required this.colors,
    required this.fontFamily,
    required this.fontSize,
    required this.rowHeight,
    required this.scroll,
    required this.padding,
    this.rows,
  }) : super(repaint: host);

  /// The playlist indices shown, or null for all of them.
  final List<int>? rows;

  final WasabiHost host;
  final _PlaylistColors colors;
  final String? fontFamily;
  final double fontSize;
  final double rowHeight;
  final double scroll;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);
    final count = rows?.length ?? host.playlistLength;
    final first = math.max(0, ((scroll - padding) / rowHeight).floor());
    final last = math.min(
      count - 1,
      ((scroll + size.height) / rowHeight).ceil(),
    );
    for (var row = first; row <= last; row++) {
      final i = rows?[row] ?? row;
      final top = padding + row * rowHeight - scroll;
      final selected = host.isPlaylistSelected(i);
      if (selected) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, rowHeight),
          Paint()..color = colors.selected,
        );
      }
      final color = i == host.playlistCurrent
          ? colors.current
          : (selected ? colors.selectedText : colors.text);
      final style = TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        color: color,
        height: 1,
      );
      final time = TextPainter(
        text: TextSpan(
          text: formatPlaylistItemTime(host.playlistItemLengthMs(i)),
          style: style,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final title = TextPainter(
        text: TextSpan(
          text: "${i + 1}. ${host.playlistTitle(i)}",
          style: style,
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…",
      )..layout(maxWidth: math.max(0, size.width - time.width - 12));
      final y = top + (rowHeight - title.height) / 2;
      title.paint(canvas, Offset(4, y));
      time.paint(canvas, Offset(size.width - time.width - 4, y));
    }
  }

  @override
  bool shouldRepaint(_PlaylistPainter oldDelegate) =>
      oldDelegate.scroll != scroll ||
      !listEquals(oldDelegate.rows, rows) ||
      oldDelegate.colors != colors ||
      oldDelegate.host != host;
}
