import "dart:async";
import "dart:math" as math;

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_skin/amped_skin.dart";
import "package:amped_wasabi/amped_wasabi.dart";
import "package:flutter/services.dart";
import "package:material_ui/material_ui.dart";

import "../../../../skin/modern_preview_cache.dart";
import "../../../../skin/webamp_skin_library.dart";

/// Installs the downloaded skin archive and makes it the active skin.
typedef SkinInstallFn = Future<SkinInfo> Function(
  Uint8List bytes, {
  String? name,
  String? fileName,
});

/// What the skin browser shows and does: the skins fetched so far, the
/// search, and which skins are downloading, installed or failed.
class _SkinBrowserModel extends ChangeNotifier {
  _SkinBrowserModel(this.library, this.install)
    : previews = ModernPreviewCache(library);

  final WebampSkinLibrary library;

  /// Previews of modern skins, which the library has no screenshot for.
  final ModernPreviewCache previews;
  final SkinInstallFn install;

  final List<WebampSkin> skins = [];
  final Set<String> installed = {};
  final Set<String> installing = {};
  final Map<String, Object> failed = {};
  final Map<String, Future<Uint8List>> _shots = {};
  int total = 0;
  bool loading = false;
  Object? error;
  String query = "";

  /// Bumped per new search so a slow, superseded reply is dropped.
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => skins.length < total;

  @override
  void dispose() {
    _disposed = true;
    unawaited(previews.dispose());
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<Uint8List> screenshot(WebampSkin skin) =>
      _shots.putIfAbsent(skin.md5, () => library.screenshot(skin));

  Future<void> search(String text) {
    query = text.trim();
    return load(reset: true);
  }

  Future<void> load({required bool reset}) async {
    if (loading && !reset) return;
    if (reset) {
      _generation++;
      skins.clear();
      total = 0;
    }
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await library.browse(query: query, offset: skins.length);
      if (generation != _generation) return;
      skins.addAll(page.skins);
      total = page.total;
      loading = false;
    } on Object catch (e) {
      if (generation != _generation) return;
      error = e;
      loading = false;
    }
    notifyListeners();
  }

  Future<void> download(WebampSkin skin) async {
    if (installing.contains(skin.md5)) return;
    installing.add(skin.md5);
    failed.remove(skin.md5);
    notifyListeners();
    try {
      final bytes = await library.download(skin);
      await install(bytes, name: skin.title, fileName: skin.installFileName);
      installed.add(skin.md5);
    } on Object catch (e) {
      failed[skin.md5] = e;
    }
    installing.remove(skin.md5);
    notifyListeners();
  }
}

const double _tileHeight = 210;
const double _tileSpacing = 8;
const double _tileMaxWidth = 220;
const double _gridPadding = 12;

/// The online skin browser: a searchable grid of the Webamp skin library's
/// skins. Hovering a skin shows a download button; clicking it opens a
/// preview that the arrow keys step through.
class SkinBrowserPage extends StatefulWidget {
  const SkinBrowserPage({
    required this.library,
    required this.install,
    super.key,
  });

  final WebampSkinLibrary library;
  final SkinInstallFn install;

  @override
  State<SkinBrowserPage> createState() => _SkinBrowserPageState();
}

class _SkinBrowserPageState extends State<SkinBrowserPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final _SkinBrowserModel _model = _SkinBrowserModel(
    widget.library,
    widget.install,
  );
  double _gridWidth = 0;
  Timer? _debounce;

  /// How long typing must pause before the search runs.
  static const _searchDelay = Duration(milliseconds: 400);

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, () => unawaited(_runSearch(text)));
  }

  Future<void> _runSearch(String text) async {
    _debounce?.cancel();
    // Typing and settling back on the same text is not a new search.
    if (text.trim() == _model.query) return;
    await _model.search(text);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    _model.addListener(_loadNearEnd);
    unawaited(_model.load(reset: true));
  }

  /// Loads the next page once the scroll is within a couple of screens of
  /// the end, or the loaded skins don't fill the view yet.
  void _loadNearEnd() {
    if (!_model.hasMore || _model.loading || _model.error != null) return;
    if (!_scroll.hasClients) {
      // The grid isn't built yet; look again after it lays out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNearEnd();
      });
      return;
    }
    final position = _scroll.position;
    if (position.extentAfter < position.viewportDimension) {
      unawaited(_model.load(reset: false));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _model.removeListener(_loadNearEnd);
    _search.dispose();
    _scroll.dispose();
    _model.dispose();
    super.dispose();
  }

  /// How many tiles fit in a row, as the grid lays them out.
  int get _columns => math.max(
    1,
    ((_gridWidth + _tileSpacing) / (_tileMaxWidth + _tileSpacing)).ceil(),
  );

  /// Scrolls the minimum needed to bring the tile at [index] fully in view.
  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = (index ~/ _columns) * (_tileHeight + _tileSpacing);
    final bottom = top + _tileHeight;
    final position = _scroll.position;
    final double? target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    } else {
      target = null;
    }
    if (target == null) return;
    unawaited(
      _scroll.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _openPreview(int index) async {
    final preview = _PreviewPosition(index);
    await showDialog<void>(
      context: context,
      builder: (context) => _SkinPreview(model: _model, position: preview),
    );
    if (!mounted) return;
    // The preview may have moved to a skin that is not on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(preview.index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final error = _model.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(_gridPadding),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: localizations.skinBrowserSearchHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (text) => unawaited(_runSearch(text)),
              ),
            ),
            Expanded(
              child: _model.skins.isEmpty && !_model.loading && error == null
                  ? Center(child: Text(localizations.skinBrowserNoResults))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _gridWidth = constraints.maxWidth - 2 * _gridPadding;
                        return GridView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: _gridPadding,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: _tileMaxWidth,
                                mainAxisExtent: _tileHeight,
                                mainAxisSpacing: _tileSpacing,
                                crossAxisSpacing: _tileSpacing,
                              ),
                          itemCount: _model.skins.length,
                          itemBuilder: (context, index) => _SkinTile(
                            key: ValueKey(_model.skins[index].md5),
                            model: _model,
                            skin: _model.skins[index],
                            onOpen: () => unawaited(_openPreview(index)),
                          ),
                        );
                      },
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        localizations.skinBrowserError("$error"),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        _model.load(reset: _model.skins.isEmpty),
                      ),
                      child: Text(localizations.skinBrowserRetry),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.skinBrowserCredit,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_model.loading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Where the preview currently is in the browser's list, shared with the
/// page so it can scroll there once the preview closes.
class _PreviewPosition {
  _PreviewPosition(this.index);

  int index;
}

/// A skin's screenshot, or for a modern skin its own run copy, or a
/// placeholder while it loads or when there is nothing to show.
class _SkinImage extends StatelessWidget {
  const _SkinImage({required this.model, required this.skin});

  final _SkinBrowserModel model;
  final WebampSkin skin;

  @override
  Widget build(BuildContext context) {
    if (skin.screenshotUrl == null) {
      return skin.modern
          ? _ModernPreview(key: ValueKey(skin.md5), model: model, skin: skin)
          : const _NoPreview();
    }
    return FutureBuilder<Uint8List>(
      future: model.screenshot(skin),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            errorBuilder: (context, _, _) =>
                const Icon(Icons.broken_image_outlined),
          );
        }
        if (snapshot.hasError) return const Icon(Icons.broken_image_outlined);
        return const _Loading();
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// What shows for a skin that has no preview.
class _NoPreview extends StatelessWidget {
  const _NoPreview();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.image_not_supported_outlined),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context).skinBrowserNoPreview,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// A modern skin run on its own: downloaded to a temporary folder while it
/// is on screen, and gone again once it is not.
class _ModernPreview extends StatefulWidget {
  const _ModernPreview({required this.model, required this.skin, super.key});

  final _SkinBrowserModel model;
  final WebampSkin skin;

  @override
  State<_ModernPreview> createState() => _ModernPreviewState();
}

class _ModernPreviewState extends State<_ModernPreview> {
  late final Future<WasabiSkinPreviewController?> _preview = widget
      .model
      .previews
      .acquire(widget.skin);

  @override
  void dispose() {
    widget.model.previews.release(widget.skin);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<WasabiSkinPreviewController?>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _Loading();
          }
          final controller = snapshot.data;
          if (controller == null) return const _NoPreview();
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.failed
                ? const _NoPreview()
                : WasabiSkinPreview(
                    controller: controller,
                    placeholder: const _Loading(),
                  ),
          );
        },
      );
}

/// The download button of a skin: a spinner while downloading, a check once
/// installed, a retry icon after a failure.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.model, required this.skin});

  final _SkinBrowserModel model;
  final WebampSkin skin;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (model.installing.contains(skin.md5)) {
          return const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final failure = model.failed[skin.md5];
        final installed = model.installed.contains(skin.md5);
        return IconButton.filledTonal(
          tooltip: failure != null
              ? localizations.skinBrowserError("$failure")
              : installed
              ? localizations.skinBrowserInstalled
              : localizations.skinBrowserInstall,
          icon: Icon(
            failure != null
                ? Icons.refresh
                : installed
                ? Icons.check
                : Icons.download,
          ),
          onPressed: installed ? null : () => unawaited(model.download(skin)),
        );
      },
    );
  }
}

class _SkinTile extends StatefulWidget {
  const _SkinTile({
    required this.model,
    required this.skin,
    required this.onOpen,
    super.key,
  });

  final _SkinBrowserModel model;
  final WebampSkin skin;
  final VoidCallback onOpen;

  @override
  State<_SkinTile> createState() => _SkinTileState();
}

class _SkinTileState extends State<_SkinTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final skin = widget.skin;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(
                onTap: widget.onOpen,
                // A magnifier: clicking opens the larger preview.
                mouseCursor: SystemMouseCursors.zoomIn,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SkinImage(model: model, skin: skin),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        skin.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Shown on hover, and always for a skin that is busy, done or
            // failed, so its state is never hidden.
            ListenableBuilder(
              listenable: model,
              builder: (context, _) {
                final stateful =
                    model.installing.contains(skin.md5) ||
                    model.installed.contains(skin.md5) ||
                    model.failed.containsKey(skin.md5);
                return Positioned(
                  top: 2,
                  right: 2,
                  child: Visibility(
                    visible: _hovered || stateful,
                    child: _DownloadButton(model: model, skin: skin),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The large preview of a skin. Left/Right (keys or buttons) step through
/// the browser's skins, loading more when it runs off the end; Escape closes.
class _SkinPreview extends StatefulWidget {
  const _SkinPreview({required this.model, required this.position});

  final _SkinBrowserModel model;
  final _PreviewPosition position;

  @override
  State<_SkinPreview> createState() => _SkinPreviewState();
}

class _SkinPreviewState extends State<_SkinPreview> {
  int get _index => widget.position.index;

  bool _canStep(int delta) {
    final next = _index + delta;
    if (next < 0) return false;
    return next < widget.model.skins.length || widget.model.hasMore;
  }

  Future<void> _step(int delta) async {
    final model = widget.model;
    final next = _index + delta;
    if (next < 0) return;
    if (next >= model.skins.length) {
      if (!model.hasMore) return;
      await model.load(reset: false);
      if (!mounted || next >= model.skins.length) return;
    }
    setState(() => widget.position.index = next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_step(-1));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_step(1));
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final skin = model.skins[math.min(_index, model.skins.length - 1)];
        return Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
              child: Row(
                children: [
                  IconButton(
                    tooltip: localizations.skinBrowserPrevious,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _canStep(-1) ? () => unawaited(_step(-1)) : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            skin.title,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _SkinImage(model: model, skin: skin),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Center(
                            child: _DownloadButton(model: model, skin: skin),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: localizations.skinBrowserNext,
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _canStep(1) ? () => unawaited(_step(1)) : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
