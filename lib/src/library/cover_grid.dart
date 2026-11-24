import "dart:async";
import "dart:typed_data";

import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:flutter/widgets.dart";

/// One tile of the [CoverGrid]: an album, podcast, book, show or movie.
@immutable
class CoverItem {
  const CoverItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.picked,
    required this.onTap,
    required this.onPlay,
    required this.onMenu,
    this.imageUrl,
    this.badge,
  });

  /// Names the tile, to keep its picture while the list changes.
  final String key;
  final String title;
  final String subtitle;

  /// The track whose cover the tile shows, unless [imageUrl] says better
  /// (the picture of a show, a season or an artist).
  final String coverPath;
  final String? imageUrl;

  /// Shown at the right of the line under the title, such as a check mark
  /// for what was watched.
  final String? badge;
  final bool picked;
  final VoidCallback onTap;

  /// Called on a double-click.
  final VoidCallback onPlay;

  /// Called on a right-click.
  final VoidCallback onMenu;
}

/// A scrolling grid of covers with a title and a line under each, in the
/// list's colors; the picked ones are highlighted.
class CoverGrid extends StatefulWidget {
  const CoverGrid({
    required this.items,
    required this.colors,
    required this.controller,
    required this.scrollbar,
    required this.loader,
    this.provider,
    this.tileWidth = defaultTileWidth,
    super.key,
  });

  final List<CoverItem> items;
  final PlEditConfig colors;
  final ScrollController controller;

  /// The scrollbar beside the grid, for the controller it is given.
  final Widget Function(ScrollController controller) scrollbar;

  /// Reads the cover of the track at a path; null for tiles without covers.
  final Future<Uint8List?> Function(String path)? loader;

  /// Gives the picture at an address.
  final ImageProvider Function(String url)? provider;

  /// How wide a tile is at most; the grid fits as many as it can.
  final double tileWidth;

  /// How wide a tile is unless said otherwise, and the least and most the
  /// size can be set to.
  static const double defaultTileWidth = 116;
  static const double minTileWidth = 56;
  static const double maxTileWidth = 220;

  @override
  State<CoverGrid> createState() => _CoverGridState();
}

class _CoverGridState extends State<CoverGrid> {
  /// The pictures read, by track, shared by all grids so that going back to
  /// a view does not read them again.
  static final Map<String, Future<ImageProvider?>> _pictures = {};
  static const _kept = 600;

  Future<ImageProvider?> _picture(CoverItem item) {
    final url = item.imageUrl;
    final provider = widget.provider;
    if (url != null && provider != null) return Future.value(provider(url));
    final path = item.coverPath;
    final loader = widget.loader;
    if (loader == null) return Future.value();
    final known = _pictures.remove(path);
    if (known != null) return _pictures[path] = known;
    if (_pictures.length >= _kept) _pictures.remove(_pictures.keys.first);
    return _pictures[path] = () async {
      try {
        final bytes = await loader(path);
        if (bytes == null) return null;
        return ResizeImage(MemoryImage(bytes), width: 256);
      } on Object {
        return null;
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false, overscroll: false),
            child: GridView.builder(
              controller: widget.controller,
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: widget.tileWidth,
                mainAxisExtent: widget.tileWidth + 36,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return _Tile(
                  key: ValueKey(item.key),
                  item: item,
                  colors: colors,
                  picture: _picture(item),
                  size: widget.tileWidth - 8,
                );
              },
            ),
          ),
        ),
        SizedBox(
          width: SkinScrollbar.width,
          child: widget.scrollbar(widget.controller),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.colors,
    required this.picture,
    required this.size,
    super.key,
  });

  final CoverItem item;
  final PlEditConfig colors;
  final Future<ImageProvider?> picture;
  final double size;

  @override
  Widget build(BuildContext context) {
    final picked = item.picked;
    final text = picked ? colors.current : colors.normal;
    TextStyle style(double size, {bool bold = false}) => TextStyle(
      color: text,
      fontSize: size,
      height: 1.15,
      fontWeight: bold ? FontWeight.bold : null,
      fontFamily: colors.fontName.isEmpty ? null : colors.fontName,
      decoration: TextDecoration.none,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        onDoubleTap: item.onPlay,
        onSecondaryTap: item.onMenu,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: picked ? colors.selectedBg : null,
            border: Border.all(
              color: picked ? colors.selectedBg : const Color(0x00000000),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox.square(
                  dimension: size,
                  child: FutureBuilder<ImageProvider?>(
                    future: picture,
                    builder: (context, snapshot) {
                      final image = snapshot.data;
                      Widget placeholder() => ColoredBox(
                        color: colors.normal.withAlpha(30),
                        child: Center(
                          child: Text(
                            item.title.isEmpty
                                ? ""
                                : item.title.characters.first.toUpperCase(),
                            style: style(
                              28,
                            ).copyWith(color: colors.normal.withAlpha(120)),
                          ),
                        ),
                      );
                      if (image == null) return placeholder();
                      return Image(
                        image: image,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stack) => placeholder(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style(11, bold: true),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(10),
                      ),
                    ),
                    if (item.badge != null)
                      Text(item.badge!, maxLines: 1, style: style(10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
