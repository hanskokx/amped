import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

import "../player/playlist.dart";
import "../player/playlist_search.dart";

/// Jump to file, drawn in the skin: type to narrow the playlist to the
/// entries whose title, tags or file name match (see [PlaylistSearch]), best
/// first. Up and Down move through the matches, Enter or a double-click
/// plays one, and Escape closes.
///
/// This is only the inside of the window: the frame comes from
/// [SkinnedDialogFrame].
class PlaylistSearchPage extends StatefulWidget {
  const PlaylistSearchPage({
    required this.playlist,
    required this.skin,
    required this.onPlay,
    required this.onClose,
    super.key,
  });

  final Playlist playlist;
  final ClassicSkinData skin;

  /// Plays the entry at an index of [playlist].
  final void Function(int index) onPlay;
  final VoidCallback onClose;

  @override
  State<PlaylistSearchPage> createState() => _PlaylistSearchPageState();
}

class _PlaylistSearchPageState extends State<PlaylistSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  int _highlight = 0;

  /// A row's height, as the playlist's.
  static const double _rowHeight = 13;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the list [rows] rows, to a whole row.
  void _scrollRows(int rows) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final row = (position.pixels / _rowHeight).round() + rows;
    _scroll.jumpTo((row * _rowHeight).clamp(0, position.maxScrollExtent));
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    final row = (_highlight + delta).clamp(0, count - 1);
    setState(() => _highlight = row);
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = row * _rowHeight;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (top + _rowHeight - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _play(int index) {
    widget.playlist.select({index});
    widget.onPlay(index);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = widget.skin.pledit;
    final style = TextStyle(
      fontFamily: colors.fontName.isEmpty ? "Arial" : colors.fontName,
      fontSize: 12,
      height: 1.1,
      color: colors.normal,
      decoration: TextDecoration.none,
    );
    return DefaultTextStyle(
      style: style,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.playlist, _controller]),
        builder: (context, _) {
          final matches = PlaylistSearch.search(
            widget.playlist,
            _controller.text,
          );
          final entries = widget.playlist.entries;
          final highlight = matches.isEmpty
              ? 0
              : _highlight.clamp(0, matches.length - 1);
          final searching = _controller.text.trim().isNotEmpty;
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1, matches.length),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1, matches.length),
              const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                  _move(8, matches.length),
              const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                  _move(-8, matches.length),
            },
            child: ColoredBox(
              color: colors.normalBg,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                            if (_controller.text.isEmpty)
                              IgnorePointer(
                                child: Text(
                                  localizations.jumpToFileHint,
                                  style: style.copyWith(
                                    color: colors.normal.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            EditableText(
                              controller: _controller,
                              focusNode: _focus,
                              autofocus: true,
                              style: style.copyWith(color: colors.current),
                              cursorColor: colors.current,
                              backgroundCursorColor: colors.normal,
                              selectionColor: colors.selectedBg,
                              maxLines: 1,
                              onChanged: (_) => _highlight = 0,
                              onSubmitted: (_) {
                                if (matches.isNotEmpty) {
                                  _play(matches[highlight].index);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: !searching
                          ? const SizedBox.shrink()
                          : matches.isEmpty
                          ? Center(
                              child: Text(localizations.jumpToFileNoMatches),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: SkinWheelScroll(
                                    // A line at a time.
                                    rowsPerNotch: 1,
                                    onScroll: _scrollRows,
                                    child: ScrollConfiguration(
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
                                        itemExtent: _rowHeight,
                                        itemCount: matches.length,
                                        itemBuilder: (context, row) =>
                                            _MatchRow(
                                              entry:
                                                  entries[matches[row].index],
                                              number: matches[row].index + 1,
                                              highlighted: row == highlight,
                                              colors: colors,
                                              style: style,
                                              onTap: () => setState(
                                                () => _highlight = row,
                                              ),
                                              onPlay: () =>
                                                  _play(matches[row].index),
                                            ),
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One match: "N. Title" and the length, as the playlist shows it.
class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.entry,
    required this.number,
    required this.highlighted,
    required this.colors,
    required this.style,
    required this.onTap,
    required this.onPlay,
  });

  final PlaylistEntry entry;
  final int number;
  final bool highlighted;
  final PlEditConfig colors;
  final TextStyle style;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final duration = entry.duration;
    final seconds = duration?.inSeconds;
    final rowStyle = style.copyWith(
      color: highlighted ? colors.current : colors.normal,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onPlay,
      child: ColoredBox(
        color: highlighted ? colors.selectedBg : colors.normalBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "$number. ${entry.title}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: rowStyle,
                ),
              ),
              if (seconds != null)
                Text(formatPlaylistTime(seconds), style: rowStyle),
            ],
          ),
        ),
      ),
    );
  }
}
