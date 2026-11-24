import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:amped_vis/amped_vis.dart";
import "package:flutter/foundation.dart" show listEquals;
import "package:flutter/gestures.dart";
import "package:flutter/rendering.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart"
    show HardwareKeyboard, KeyUpEvent, LogicalKeyboardKey;
import "package:flutter/widgets.dart";

import "maki/maki_runtime.dart";
import "playlist_info.dart";
import "skin_region.dart";
import "wasabi_color_themes.dart";
import "wasabi_config.dart";
import "wasabi_contrast.dart";
import "wasabi_host.dart";
import "wasabi_keys.dart";
import "wasabi_menu.dart";
import "wasabi_playlist.dart";
import "wasabi_skin_data.dart";
import "wasabi_thinger.dart";

/// Lets a skin control keep the window from being dragged by a press that
/// starts on it. Set once by the app (e.g. to `WindowDragArea.claimPointer`).
abstract final class WasabiPointerClaim {
  static void Function(PointerDownEvent event)? claim;
}

/// Renders one layout of a modern skin at its native size: the background,
/// then every object in XML order (later objects on top), the way Wasabi
/// paints a layout's children.
class WasabiLayoutView extends StatelessWidget {
  const WasabiLayoutView({
    required this.skin,
    required this.layout,
    required this.host,
    required this.container,
    this.scripts,
    this.components = const {},
    this.active = true,
    this.overlay = false,
    super.key,
  });

  /// Whether this layout is drawn over another window's (a companion): its
  /// bare area leaves the mouse to what is under it.
  final bool overlay;

  /// Whether the window showing the layout has focus; objects paint with
  /// their `inactivealpha` while it does not.
  final bool active;

  /// What the app shows for components the skin holds (`vis`, `video`,
  /// `ml`); the playlist (`pl`) is built in.
  final Map<String, Widget> components;

  final WasabiSkinData skin;
  final WasabiLayout layout;
  final WasabiHost host;

  /// The id of the container this layout belongs to.
  final String container;

  /// The skin's running scripts, which get the layout's events and change
  /// its objects.
  final WasabiScriptRuntime? scripts;

  @override
  Widget build(BuildContext context) {
    final scripts = this.scripts;
    return _WasabiScope(
      skin: skin,
      host: host,
      container: container,
      layout: layout,
      scripts: scripts,
      components: components,
      active: active,
      child: _BucketTextHolder(
        child: ListenableBuilder(
          // A color theme changes what everything looks like.
          listenable: Listenable.merge([host, skin.colorThemes, ?scripts]),
          builder: (context, _) {
            // Frames the layout's scripts drew as windows of their own,
            // which follow this one: over it, at its size.
            final companions = scripts?.companionsOf(layout) ?? const [];
            return _EnsureOverlay(
              size: layout.size,
              child: SizedBox.fromSize(
                size: layout.size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hidden by a script, the window shows only the frames
                    // drawn over it.
                    if (layout.root["#hidden"] != "1")
                      Positioned.fill(
                        child: ClipPath(
                          clipper: _RegionClipper(
                            // A window with desktop alpha is drawn as it is: its
                            // pixels carry the shape (OrbFace's background has
                            // nothing in the middle of its orb, which its
                            // overlay fills).
                            // With desktop alpha switched off the window
                            // is shaped by its region instead.
                            layout.root["desktopalpha"]?.trim() == "1" &&
                                    (scripts?.desktopAlpha ?? true)
                                ? null
                                : wasabiLayoutRegion(skin, layout),
                            wasabiRegionCutouts(skin, layout),
                          ),
                          // Hard edges: the region is a set of abutting pixel
                          // rectangles.
                          clipBehavior: Clip.hardEdge,
                          child: _LayoutContent(
                            layout: layout,
                            scripts: scripts,
                            overlay: overlay,
                            child: _GroupBody(
                              group: layout.root,
                              size: layout.size,
                            ),
                          ),
                        ),
                      ),
                    for (final (companion, companionLayout) in companions)
                      if (companionLayout.root.visible)
                        Positioned.fill(
                          // Where the window holds a component (the library, the
                          // playlist), the mouse is the component's, not the
                          // frame's drawn over it.
                          child: _HoleHitTest(
                            holes: _componentRects(skin, layout),
                            child: WasabiLayoutView(
                              skin: skin,
                              layout: companionLayout,
                              host: host,
                              container: companion.id,
                              scripts: scripts,
                              active: active,
                              overlay: true,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Gives [child] an [Overlay] when its window has none, so a drop-down
/// list has somewhere to open (a skin's own windows are bare).
class _EnsureOverlay extends StatefulWidget {
  const _EnsureOverlay({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  State<_EnsureOverlay> createState() => _EnsureOverlayState();
}

class _EnsureOverlayState extends State<_EnsureOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_EnsureOverlay old) {
    super.didUpdateWidget(old);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    // The Overlay it is in goes with this state and lets go of it.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) != null) return widget.child;
    return SizedBox.fromSize(
      size: widget.size,
      child: Overlay(clipBehavior: Clip.none, initialEntries: [_entry]),
    );
  }
}

/// A layout's body with its own alpha (a layout that fades, such as the classic player
/// Modern's notifier) and the mouse events its scripts listen to
/// (`Layout.onLeftButtonDown`, ...).
class _LayoutContent extends StatelessWidget {
  const _LayoutContent({
    required this.layout,
    required this.scripts,
    required this.child,
    this.overlay = false,
  });

  final bool overlay;
  final WasabiLayout layout;
  final WasabiScriptRuntime? scripts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scripts = this.scripts;
    final root = layout.root;
    Widget body = child;
    if (scripts != null && scripts.scriptObjectOf(root) != null) {
      body = _ScriptMouse(
        object: root,
        scripts: scripts,
        bare: overlay,
        child: body,
      );
    }
    final alpha = root.alpha;
    if (alpha >= 255) return body;
    return Opacity(opacity: alpha / 255, child: body);
  }
}

/// Holds the text `display="componentbucket"` texts show: the name of the
/// Thinger button under the pointer (`ComponentBucket2::setText`).
class _BucketTextHolder extends StatefulWidget {
  const _BucketTextHolder({required this.child});

  final Widget child;

  @override
  State<_BucketTextHolder> createState() => _BucketTextHolderState();
}

class _BucketTextHolderState extends State<_BucketTextHolder> {
  final ValueNotifier<String?> _text = ValueNotifier(null);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BucketText(notifier: _text, child: widget.child);
}

class _BucketText extends InheritedNotifier<ValueNotifier<String?>> {
  const _BucketText({required super.notifier, required super.child});

  /// The notifier of the enclosing layout, or null outside one.
  static ValueNotifier<String?>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BucketText>()?.notifier;
}

/// Clips a layout to its window region minus [cutouts]; no clip for a
/// rectangular window without cutouts.
class _RegionClipper extends CustomClipper<Path> {
  _RegionClipper(this.region, this.cutouts);

  final List<List<Offset>>? region;

  /// What subtracting layers remove from the region, in layout pixels.
  final List<Rect> cutouts;

  @override
  Path getClip(Size size) {
    final region = this.region;
    final path = Path();
    if (region == null) {
      path.addRect(Offset.zero & size);
    } else {
      for (final polygon in region) {
        path.addPolygon(polygon, true);
      }
    }
    if (cutouts.isEmpty) return path;
    final holes = Path();
    for (final rect in cutouts) {
      holes.addRect(rect);
    }
    return Path.combine(PathOperation.difference, path, holes);
  }

  @override
  bool shouldReclip(_RegionClipper oldClipper) =>
      oldClipper.region != region || !listEquals(oldClipper.cutouts, cutouts);
}

/// The parts of [layout] its visible `sub2` layers cut out of the window
/// region ([WasabiObject.subtractsFromWindow]), in layout pixels.
///
/// The original paints these layers like any other and then clips the
/// window to its composed region (`BaseWnd::computeComposedRegion`), so
/// their opaque pixels (black in Wasabi 5's frame corners) never show.
/// `sub` layers only cut their own group ([wasabiGroupCutouts]).
///
/// Only for layouts without a shaped background: [wasabiLayoutRegion]
/// already composes the cutters into theirs.
List<Rect> wasabiRegionCutouts(WasabiSkinData skin, WasabiLayout layout) {
  if (skin.regionMasks.isEmpty || layout.region != null) return const [];
  final cutouts = <Rect>[];
  void visit(WasabiObject group, Rect area) {
    for (final child in group.children) {
      if (!child.visible) continue;
      final isGroup = child.tag == "group";
      if (!isGroup && !child.subtractsFromWindow) continue;
      final rect = wasabiObjectRect(child, area.size, skin).shift(area.topLeft);
      if (isGroup) {
        visit(child, rect);
      } else if (child.subtractsFromWindow) {
        _addMask(skin, child, rect, cutouts);
      }
    }
  }

  visit(layout.root, Offset.zero & layout.size);
  return cutouts;
}

/// The parts of [group] (laid out at [size]) its visible `sub` layers cut
/// out of the group's own region, in group pixels. The original removes
/// them from the group's composed region only, so whatever else in the
/// window covers those pixels still shows: Wasabi 5's config drawer cuts
/// its sides this way while it sits behind the main window's body.
List<Rect> wasabiGroupCutouts(
  WasabiSkinData skin,
  WasabiObject group,
  Size size,
) {
  if (skin.regionMasks.isEmpty) return const [];
  final cutouts = <Rect>[];
  for (final child in group.children) {
    if (!child.visible ||
        child.tag == "group" ||
        !child.subtractsRegion ||
        child.subtractsFromWindow) {
      continue;
    }
    _addMask(skin, child, wasabiObjectRect(child, size, skin), cutouts);
  }
  return cutouts;
}

/// Adds the region mask of layer [object], placed at [rect], to [cutouts].
void _addMask(
  WasabiSkinData skin,
  WasabiObject object,
  Rect rect,
  List<Rect> cutouts,
) {
  final mask = skin.regionMasks[object["image"]?.toLowerCase()];
  if (mask == null) return;
  // A layer given a size other than its image's stretches it (Smallville's
  // frame cuts its top edge with a 15 pixel strip made 183 wide).
  final image = skin.bitmap(object["image"]);
  final stretch =
      image != null &&
      image.width > 0 &&
      image.height > 0 &&
      object["tile"]?.trim() != "1";
  final scaleX = stretch ? rect.width / image.width : 1.0;
  final scaleY = stretch ? rect.height / image.height : 1.0;
  for (final part in mask) {
    final scaled = Rect.fromLTRB(
      part.left * scaleX,
      part.top * scaleY,
      part.right * scaleX,
      part.bottom * scaleY,
    );
    final cut = scaled.shift(rect.topLeft).intersect(rect);
    if (cut.width > 0 && cut.height > 0) cutouts.add(cut);
  }
}

class _WasabiScope extends InheritedWidget {
  const _WasabiScope({
    required this.skin,
    required this.host,
    required this.container,
    required this.layout,
    required this.scripts,
    required this.components,
    required this.active,
    required super.child,
  });

  final Map<String, Widget> components;
  final bool active;

  final WasabiSkinData skin;
  final WasabiHost host;
  final String container;
  final WasabiLayout layout;
  final WasabiScriptRuntime? scripts;

  static _WasabiScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WasabiScope>()!;

  @override
  bool updateShouldNotify(_WasabiScope oldWidget) =>
      skin != oldWidget.skin ||
      host != oldWidget.host ||
      container != oldWidget.container ||
      layout != oldWidget.layout ||
      scripts != oldWidget.scripts ||
      components != oldWidget.components ||
      active != oldWidget.active;

  /// The alpha [object] paints with in this window right now.
  int alphaOf(WasabiObject object) => object.paintingAlpha(active: active);
}

/// Where [object] goes inside a parent of [parent] size
/// (`Group::updatePos`): `x`/`y`/`w`/`h` with `relatx`.. `relath` 1
/// meaning "from the right/bottom edge" and 2 "percent of the parent".
/// Missing sizes fall back to the object's natural size.
Rect wasabiObjectRect(WasabiObject object, Size parent, WasabiSkinData skin) {
  double place(int value, int relat, double extent) => switch (relat) {
    1 => extent + value,
    2 => extent * value / 100,
    _ => value.toDouble(),
  };

  final natural = _naturalSize(object, skin);
  // `fitparent="1"` fills the parent, less what `x`, `y`, `w` and `h` say (a
  // notifier's text and frame groups, whose layout is as wide as its script
  // makes it; the script moves the text aside for a cover with x and w).
  if (object["fitparent"]?.trim() == "1") {
    final fx = object.intAttr("x").toDouble();
    final fy = object.intAttr("y").toDouble();
    return Rect.fromLTWH(
      fx,
      fy,
      math.max(0, parent.width + (object.optInt("w") ?? 0)),
      math.max(0, parent.height + (object.optInt("h") ?? 0)),
    );
  }
  final x = place(object.intAttr("x"), object.intAttr("relatx"), parent.width);
  final y = place(object.intAttr("y"), object.intAttr("relaty"), parent.height);
  final w = object.optInt("w");
  final h = object.optInt("h");
  // A NaN natural extent means "no preference" on that axis.
  final naturalWidth = natural?.width;
  final naturalHeight = natural?.height;
  final width = w == null
      ? (naturalWidth == null || naturalWidth.isNaN
            ? math.max(0.0, parent.width - x)
            : naturalWidth)
      : place(w, object.intAttr("relatw"), parent.width);
  final height = h == null
      ? (naturalHeight == null || naturalHeight.isNaN
            ? math.max(0.0, parent.height - y)
            : naturalHeight)
      : place(h, object.intAttr("relath"), parent.height);
  return Rect.fromLTWH(x, y, math.max(0, width), math.max(0, height));
}

/// The window shape of [layout] in layout pixels: its background's region
/// when it has one (Layout::desktopAlpha_autoTurnOn), else the rectangles
/// of everything visible that draws and takes the mouse. Per-pixel alpha
/// windows let clicks through where nothing is drawn, which this
/// approximates for layouts without a background (Amped Modern's main
/// window leaves room below for its drawer that way). Null for no shape.
List<List<Offset>>? wasabiWindowShape(
  WasabiSkinData skin,
  WasabiLayout layout, {
  List<WasabiLayout> companions = const [],
}) {
  // Hidden by a script, the window is only the frames drawn over it.
  if (layout.root["#hidden"] == "1" && companions.isNotEmpty) {
    return [
      for (final companion in companions)
        ...?wasabiWindowShape(skin, companion),
    ];
  }
  final region = wasabiLayoutRegion(skin, layout);
  if (region != null && layout.root["desktopalpha"]?.trim() == "1") {
    // A window with desktop alpha is also as big as the ghost layers it
    // draws (OrbFace's overlay fills its orb, which its background leaves
    // empty).
    final drawn = <List<Offset>>[];
    void visitLayers(WasabiObject group, Rect area) {
      for (final child in group.children) {
        if (!child.visible) continue;
        final rect = wasabiObjectRect(
          child,
          area.size,
          skin,
        ).shift(area.topLeft);
        if ((child.tag == "layer" || child.tag == "animatedlayer") &&
            child.ghost &&
            skin.bitmap(child["image"]) != null &&
            !child.subtractsRegion) {
          final r = rect.intersect(Offset.zero & layout.size);
          if (!r.isEmpty) {
            drawn.add([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
          }
        }
        if (child.tag == "group") visitLayers(child, rect);
      }
    }

    visitLayers(layout.root, Offset.zero & layout.size);
    return [
      ...region,
      ...drawn,
      for (final companion in companions)
        ...?wasabiWindowShape(skin, companion),
    ];
  }
  if (region != null) {
    return [
      ...region,
      for (final companion in companions)
        ...?wasabiWindowShape(skin, companion),
    ];
  }
  final bounds = Offset.zero & layout.size;
  final rects = <Rect>[];
  void visit(WasabiObject group, Rect area) {
    for (final child in group.children) {
      if (!child.visible || child.ghost) continue;
      final rect = wasabiObjectRect(child, area.size, skin).shift(area.topLeft);
      // Region cutters remove from the window rather than add to it.
      final draws =
          !child.subtractsRegion &&
          switch (child.tag) {
            "layer" ||
            "animatedlayer" ||
            "button" ||
            "togglebutton" => skin.bitmap(child["image"]) != null,
            "nstatesbutton" => skin.bitmap(_nStatesImage(child)) != null,
            "slider" ||
            "text" ||
            "songticker" ||
            "grid" ||
            "progressgrid" ||
            "status" ||
            "vis" ||
            "eqvis" ||
            "albumart" => true,
            "component" || "windowholder" => wasabiComponentName(child) != null,
            "componentbucket" => true,
            "group" => child.background != null,
            _ => false,
          };
      if (draws) rects.add(rect.intersect(bounds));
      if (child.tag == "group") visit(child, rect);
    }
  }

  visit(layout.root, bounds);
  if (layout.root.background != null) return null;
  rects.removeWhere((r) => r.isEmpty || r.width <= 0 || r.height <= 0);
  // What the windows drawn over this one cover is part of it too.
  final over = [
    for (final companion in companions) ...?wasabiWindowShape(skin, companion),
  ];
  if (rects.isEmpty && over.isEmpty) return null;
  return [
    for (final r in rects) [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
    ...over,
  ];
}

/// The region of a layout with a shaped background as it is now: the
/// background's region combined with the regions of its objects that have
/// a `sysregion` (BaseWnd::computeComposedRegion), so what scripts slide
/// out from under the background (Anexa's drawers, inside `AND` masks)
/// becomes part of the window. [WasabiLayout.region] when nothing in the
/// layout has a `sysregion`, or when the layout has no shaped background.
List<List<Offset>>? wasabiLayoutRegion(
  WasabiSkinData skin,
  WasabiLayout layout,
) {
  final base = layout.region;
  if (base == null) return null;
  final cache = _composedRegions[layout];
  final key = _regionKey(skin, layout);
  if (key == null) return base;
  if (cache != null && listEquals(cache.$1, key)) return cache.$2;

  final size = layout.size;
  final width = size.width.round();
  final height = size.height.round();
  final subtractor = RegionMask(width, height);
  final own = RegionMask(width, height);
  for (final polygon in base) {
    own.addRect(Rect.fromPoints(polygon[0], polygon[2]));
  }
  final composed = _compose(
    skin,
    layout.root,
    Offset.zero & size,
    own,
    subtractor,
  )..subtract(subtractor);
  final region = composed.isFull ? null : rectPolygons(composed.toRects());
  _composedRegions[layout] = (key, region);
  return region;
}

final Expando<(List<Object?>, List<List<Offset>>?)> _composedRegions =
    Expando();

/// What the composed region of [layout] depends on: the layout size and
/// the place, op, visibility and image of every object with a region op.
/// Null when no object has one.
List<Object?>? _regionKey(WasabiSkinData skin, WasabiLayout layout) {
  final key = <Object?>[layout.size];
  var any = false;
  void visit(WasabiObject group, Rect area) {
    for (final child in group.children) {
      final op = _regionOp(child);
      if (op == _regionNone) continue;
      any = true;
      final rect = wasabiObjectRect(child, area.size, skin).shift(area.topLeft);
      key.addAll([child, rect, op, _paints(child), child["image"]]);
      if (_paints(child) && child.tag == "group") visit(child, rect);
    }
  }

  visit(layout.root, Offset.zero & layout.size);
  return any ? key : null;
}

const int _regionNone = 0;
const int _regionOr = 1;
const int _regionAnd = 2;
const int _regionSub = -1;
const int _regionSub2 = -2;

/// [object]'s region op (`sysregion`, SkinParser::parseRegionOp). A group
/// without one takes `or` when any of its objects has one (Group's
/// autoregionop).
int _regionOp(WasabiObject object) {
  final value = object["sysregion"]?.trim().toLowerCase();
  if (value != null && value.isNotEmpty) {
    return switch (value) {
      "or" => _regionOr,
      "and" => _regionAnd,
      "sub" => _regionSub,
      "sub2" => _regionSub2,
      _ => int.tryParse(value) ?? _regionNone,
    };
  }
  if (object.tag != "group") return _regionNone;
  return object.children.any((c) => _regionOp(c) != _regionNone)
      ? _regionOr
      : _regionNone;
}

/// Whether [object] is shown and not fully transparent: hidden objects
/// leave the region (`isVisible`, `getPaintingAlpha`).
bool _paints(WasabiObject object) => object.visible && object.alpha != 0;

/// The composed region of [object] placed at [rect] (layout pixels),
/// starting from its own region [own]. `sub2` regions go to [subtractor],
/// which the window loses at the end.
RegionMask _compose(
  WasabiSkinData skin,
  WasabiObject object,
  Rect rect,
  RegionMask own,
  RegionMask subtractor,
) {
  RegionMask? ors;
  RegionMask? ands;
  RegionMask? subs;
  RegionMask blank() => RegionMask(own.width, own.height);
  for (final child in object.children) {
    if (!_paints(child)) continue;
    final op = _regionOp(child);
    if (op == _regionNone) continue;
    final childRect = wasabiObjectRect(
      child,
      rect.size,
      skin,
    ).shift(rect.topLeft);
    final region = _compose(
      skin,
      child,
      childRect,
      _ownRegion(skin, child, childRect, blank()),
      subtractor,
    );
    switch (op) {
      case _regionOr:
        (ors ??= blank()).or(region);
      case _regionAnd:
        (ands ??= blank()).or(region);
      case _regionSub:
        (subs ??= blank()).or(region);
      case _regionSub2:
        subtractor.or(region);
    }
  }
  if (ands != null) own.and(ands);
  if (ors != null) own.or(ors);
  if (subs != null) own.subtract(subs);
  return own;
}

/// [object]'s own region at [rect], drawn into [mask]: a group's
/// background shape (none without a background), a layer's image shape,
/// the whole rectangle for anything else (BaseWnd's `rectrgn`).
RegionMask _ownRegion(
  WasabiSkinData skin,
  WasabiObject object,
  Rect rect,
  RegionMask mask,
) {
  final bitmap = switch (object.tag) {
    "group" => object.background,
    "layer" when object["rectrgn"]?.trim() != "1" => skin.bitmap(
      object["image"],
    ),
    _ => null,
  };
  if (object.tag == "group" && bitmap == null) return mask;
  final rects = bitmap == null ? null : skin.bitmapRegion(bitmap);
  if (bitmap == null || rects == null) {
    mask.addRect(rect);
  } else {
    mask.addScaled(rects, bitmap.size, rect);
  }
  return mask;
}

/// Whether a `<componentbucket>` lists its items downwards.
bool wasabiBucketIsVertical(WasabiObject bucket) => bucket.boolAttr("vertical");

/// How long the items of a `<componentbucket>` of the skin's own groups
/// are together, margins included (`ComponentBucket2::getMaxHeight`).
double wasabiBucketExtent(WasabiObject bucket, WasabiSkinData skin) {
  final vertical = wasabiBucketIsVertical(bucket);
  var extent = bucket.intAttr("leftmargin", 2).toDouble();
  for (final item in bucket.children) {
    final natural = _naturalSize(item, skin);
    final size = vertical
        ? item.optInt("h")?.toDouble() ?? natural?.height
        : item.optInt("w")?.toDouble() ?? natural?.width;
    extent += (size ?? 0) + bucket.intAttr("spacing", 2);
  }
  return extent + bucket.intAttr("rightmargin", 2);
}

/// The size an object takes without `w`/`h` (`getPreferences(SUGGESTED_W)`),
/// or null to fill the rest of the parent.
Size? _naturalSize(WasabiObject object, WasabiSkinData skin) {
  switch (object.tag) {
    case "layer":
      return skin.bitmap(object["image"])?.size;
    case "animatedlayer":
      final bitmap = skin.bitmap(object["image"]);
      if (bitmap == null) return null;
      return wasabiAnimationFrames(object, bitmap)?.frame ?? bitmap.size;
    case "button" || "togglebutton":
      final image = skin.bitmap(object["image"])?.size;
      if (image != null) return image;
      // With no picture it is as big as its text (`ButtonWnd::getWidth`:
      // the text between two "j", a tenth wider and 8 at least; its
      // height a tenth over the text's).
      final label = object["text"] ?? "";
      // With neither it has nothing to draw or take the mouse (a skin's
      // button naming a picture it does not define), not the whole parent.
      if (label.isEmpty || object.tag != "button") return Size.zero;
      final painter = TextPainter(
        text: TextSpan(
          text: "j${label}j",
          style: const TextStyle(fontSize: 14, height: 1),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final size = Size(
        math.max((painter.width * 1.1).floorToDouble(), 8),
        math.max((painter.height * 1.1).floorToDouble(), 4),
      );
      painter.dispose();
      return size;
    case "nstatesbutton":
      return skin.bitmap(_nStatesImage(object))?.size;
    case "status":
      // As big as its bitmaps (Amped Modern's light up the transport
      // button of what the player is doing).
      return (skin.bitmap(object["stopbitmap"]) ??
              skin.bitmap(object["playbitmap"]) ??
              skin.bitmap(object["pausebitmap"]))
          ?.size;
    case "slider":
      final thumb = skin.bitmap(object["thumb"]);
      final vertical =
          object["orientation"]?.toLowerCase().startsWith("v") ?? false;
      return vertical
          ? Size(thumb?.width ?? 0, 64)
          : Size(64, thumb?.height ?? 0);
    case "text" || "songticker":
      // As tall as its lines in its font size (`Text::getPreferences`
      // SUGGESTED_H), with no preference for the width.
      final lines = _staticText(object).split("\n").length;
      return Size(
        double.nan,
        object.intAttr("fontsize", 14) * lines.toDouble(),
      );
    case "vis":
      return const Size(76, 16);
    case "group":
      final background = object.background;
      // `autowidthsource`: as wide as that child reaches
      // (Group::getWidthBasedOn).
      double? based(String attribute, {required bool width}) {
        final id = object[attribute]?.toLowerCase();
        if (id == null) return null;
        for (final child in object.children) {
          if (child.id.toLowerCase() != id) continue;
          // A text is as wide as its string; one that follows its group's
          // width () leaves the group that much wider than
          // itself (Group::getWidthBasedOn).
          if (width && (child.tag == "text" || child.tag == "songticker")) {
            final auto = wasabiTextAutoWidth(child, skin);
            final w = child.optInt("w");
            if (child.intAttr("relatx") != 0) return null;
            if (w != null && child.intAttr("relatw") == 1) return auto - w;
            return auto + child.intAttr("x");
          }
          final natural = _naturalSize(child, skin);
          final size = width ? child.optInt("w") : child.optInt("h");
          final extent =
              size?.toDouble() ??
              (width ? natural?.width : natural?.height) ??
              0;
          return extent + (width ? child.intAttr("x") : child.intAttr("y"));
        }
        return null;
      }

      final w =
          object.optInt("default_w")?.toDouble() ??
          based("autowidthsource", width: true) ??
          background?.width;
      final h =
          object.optInt("default_h")?.toDouble() ??
          based("autoheightsource", width: false) ??
          background?.height;
      if (w == null && h == null) return null;
      return Size(w ?? double.nan, h ?? double.nan);
    default:
      return null;
  }
}

/// How an animated layer cuts its image into frames (AnimatedLayer's
/// ANIM_VERT and ANIM_HORZ styles): the size of a frame, whether the
/// frames are stacked down the image, and how many there are. A
/// `frameheight` or `framewidth` says so; otherwise a `h` or `w` smaller
/// than the image does (AnimatedLayer::onInit). Null when the image is a
/// single frame.
({Size frame, bool vertical, int count})? wasabiAnimationFrames(
  WasabiObject object,
  WasabiBitmap bitmap,
) {
  int? positive(String name) {
    final value = object.optInt(name);
    return value != null && value > 0 ? value : null;
  }

  final frameHeight = positive("frameheight");
  final frameWidth = positive("framewidth");
  final w = positive("w");
  final h = positive("h");
  final bool vertical;
  final Size frame;
  if (frameHeight != null) {
    vertical = true;
    frame = Size(bitmap.width, frameHeight.toDouble());
  } else if (frameWidth != null) {
    vertical = false;
    frame = Size(frameWidth.toDouble(), bitmap.height);
  } else if (w != null && w < bitmap.width) {
    vertical = false;
    frame = Size(w.toDouble(), bitmap.height);
  } else if (h != null && h < bitmap.height) {
    vertical = true;
    frame = Size(bitmap.width, h.toDouble());
  } else {
    return null;
  }
  final count = vertical
      ? bitmap.height ~/ frame.height
      : bitmap.width ~/ frame.width;
  return (frame: frame, vertical: vertical, count: math.max(1, count));
}

/// The current frame of an animated layer, which its scripts move.
int wasabiAnimationFrame(WasabiObject object) =>
    int.tryParse(object["#frame"] ?? "") ?? 0;

/// The part of [bitmap] that animated layer [object] shows now: its current
/// frame (AnimatedLayer::getSourceOffsetX/Y), the first one when it is
/// past the end, or all of [bitmap] for a single frame.
WasabiBitmap wasabiFrameBitmap(WasabiObject object, WasabiBitmap bitmap) {
  final frames = wasabiAnimationFrames(object, bitmap);
  if (frames == null) return bitmap;
  var index = wasabiAnimationFrame(object);
  if (index < 0 || index >= frames.count) index = 0;
  final offset = frames.vertical
      ? Offset(0, index * frames.frame.height)
      : Offset(index * frames.frame.width, 0);
  return WasabiBitmap(
    bitmap.image,
    (bitmap.src.topLeft + offset) & frames.frame,
  );
}

/// What a `<text display="time">` shows: the elapsed (or remaining) time as
/// `m:ss`, or what its `timeroffstyle` says while stopped. Scripts that read
/// the text (Avalon's timer script reformats it) get the same string.
String wasabiTimeText(WasabiHost host, WasabiObject object) {
  String minSec(int seconds) {
    final s = seconds.abs();
    return "${s ~/ 60}:${(s % 60).toString().padLeft(2, "0")}";
  }

  final position = host.positionMs;
  final length = host.lengthMs;
  final remaining = host.timeRemaining && length > 0;
  if (position < 0) {
    // Stopped: what `timeroffstyle` says.
    final sign = host.timeRemaining ? "-" : "";
    return switch (object.intAttr("timeroffstyle")) {
      1 => "${sign}00:00",
      2 => "",
      3 => "${sign}0:00:00",
      4 => " :  :  ",
      _ => "",
    };
  }
  final seconds = remaining ? (length - position) ~/ 1000 : position ~/ 1000;
  return "${remaining ? "-" : ""}${minSec(seconds)}";
}

/// The children of a group or layout, stacked in XML order.
class _GroupBody extends StatelessWidget {
  const _GroupBody({required this.group, required this.size});

  final WasabiObject group;
  final Size size;

  @override
  Widget build(BuildContext context) {
    // `<Menu>` objects show and hide the buttons beside them as the mouse
    // moves over them.
    final menus = [
      for (final child in group.children)
        if (WasabiMenu.of(child) case final menu?) (menu, _menuLookOf(child)),
    ];
    final scope = _WasabiScope.of(context);
    // Layouts with a shaped background compose `sub` into their region
    // (wasabiLayoutRegion); the others clip the group itself.
    final cutouts = scope.layout.region == null
        ? wasabiGroupCutouts(scope.skin, group, size)
        : const <Rect>[];
    final body = menus.isEmpty
        ? _GroupStack(group: group, size: size)
        : ListenableBuilder(
            listenable: Listenable.merge([for (final (_, look) in menus) look]),
            builder: (context, _) => _GroupStack(
              group: group,
              size: size,
              menus: [for (final (menu, look) in menus) (menu, look.value)],
            ),
          );
    if (cutouts.isEmpty) return body;
    return ClipPath(
      clipper: _RegionClipper(null, cutouts),
      clipBehavior: Clip.hardEdge,
      child: body,
    );
  }
}

/// The look of each `<Menu>` object, kept with the object so its group can
/// show the right button.
final Expando<ValueNotifier<WasabiMenuLook>> _menuLooks = Expando();

ValueNotifier<WasabiMenuLook> _menuLookOf(WasabiObject menu) =>
    _menuLooks[menu] ??= ValueNotifier(WasabiMenuLook.normal);

class _GroupStack extends StatelessWidget {
  const _GroupStack({
    required this.group,
    required this.size,
    this.menus = const [],
  });

  final WasabiObject group;
  final Size size;

  /// The group's menus and how they look.
  final List<(WasabiMenu, WasabiMenuLook)> menus;

  bool _shows(WasabiObject child) {
    for (final (menu, look) in menus) {
      if (menu.showsButton(child.id, look) case final shows?) return shows;
    }
    return child.visible;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    // `drawbackground="0"` keeps the background bitmap as the group's shape
    // only (Riddick's eyes: a white mask over a visualization).
    // With desktop alpha off a layout draws its plain `background`, not the
    // `alphabackground` made for see-through windows.
    final plain =
        group.tag == "layout" &&
            scope.scripts != null &&
            !scope.scripts!.desktopAlpha
        ? skin.bitmap(group["background"])
        : null;
    final background = group["drawbackground"]?.trim() == "0"
        ? null
        : plain ?? group.background;
    // A group's alpha fades everything in it (a child window paints with
    // its parent's alpha): Graviton fades four visualizations in and out
    // as groups.
    final groupAlpha = group.tag == "layout" ? 255 : scope.alphaOf(group);
    final stack = Stack(
      // A group is a window of its own, so what its objects draw outside it
      // is cut off (BaseWnd children clip to their parent). Amped Modern's
      // video/vis frame relies on it: its bottom edge sits above its top
      // while the drawer is still opening.
      clipBehavior: group.tag == "layout" ? Clip.none : Clip.hardEdge,
      children: [
        if (background != null)
          Positioned.fill(
            // A ghost group lets the mouse through itself, not through its
            // objects (BaseWnd::findRootWndChild asks them first).
            child: IgnorePointer(
              ignoring: group.ghost,
              child: _BitmapPaint(
                bitmap: background,
                alpha: 255,
              ),
            ),
          ),
        for (final child in _paintOrder(group.children))
          if (_shows(child) && _isDrawn(child.tag))
            Positioned.fromRect(
              // Keyed by the object: a script moving it to the front
              // (`bringToFront`, as ClassicPro's tabs do on a press) moves
              // its widgets with it, so the press in progress finishes on
              // the same object instead of on its neighbour.
              key: ObjectKey(child),
              rect: wasabiObjectRect(child, size, skin),
              child: _ObjectView(
                object: child,
                size: wasabiObjectRect(child, size, skin).size,
              ),
            ),
      ],
    );
    // A group whose background is only its shape (`drawbackground="0"`), or
    // that has a `regionop="and"` child, shows only where that picture is
    // opaque: Catwoman's EQ drawer slides out of a pocket-shaped mask, and
    // Mercury's tabs stay inside its glass.
    final shape = group.tag == "group" ? group.background : null;
    final mask =
        shape != null &&
            (group["drawbackground"]?.trim() == "0" ||
                group.children.any((c) => _regionOp(c) == _regionAnd))
        ? scope.skin.bitmapRegion(shape)
        : null;
    final Widget body = mask == null
        ? stack
        : ClipPath(
            clipper: _ScaledRectsClipper(mask, shape!.size),
            clipBehavior: Clip.hardEdge,
            child: stack,
          );
    return groupAlpha >= 255
        ? body
        : Opacity(opacity: groupAlpha / 255, child: body);
  }

  /// The children in paint order. The Media Library is a window of its
  /// own in the classic player, in front of the frame its skin draws around it, but
  /// Amped Modern lists its `<component>` before that frame's group, which
  /// would paint over it.
  static List<WasabiObject> _paintOrder(List<WasabiObject> children) {
    bool isLibrary(WasabiObject child) => wasabiComponentName(child) == "ml";
    if (!children.any(isLibrary)) return children;
    return [
      ...children.where((child) => !isLibrary(child)),
      ...children.where(isLibrary),
    ];
  }

  static bool _isDrawn(String tag) => const {
    "layer",
    "animatedlayer",
    "button",
    "togglebutton",
    "nstatesbutton",
    "slider",
    "text",
    "songticker",
    "edit",
    "grid",
    "progressgrid",
    "status",
    "vis",
    "eqvis",
    "colorthemes:list",
    "wasabibutton",
    "rect",
    "checkbox",
    "tabsheet",
    "dropdownlist",
    "albumart",
    "boxframe",
    "framedivider",
    "browser",
    "winamp:browser",
    "component",
    "windowholder",
    "componentbucket",
    "group",
    "menu",
  }.contains(tag);
}

/// The cover a skin's notifier shows: [online] (iTunes) or the track's own.
/// Nothing while there is none (the skin's own "no image" for the local one).
class _CoverView extends StatelessWidget {
  const _CoverView({
    required this.object,
    required this.size,
    required this.online,
  });

  final WasabiObject object;
  final Size size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final art = online ? scope.host.onlineAlbumArt : scope.host.albumArt;
    if (art == null) {
      return online
          ? const SizedBox.shrink()
          : _LayerView(object: object, size: size);
    }
    return RawImage(
      image: art,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// The plain frame of a `Wasabi:TitleBox` whose skin has no pieces for one:
/// a thin line in the title's colour, broken where the title sits.
/// The divider of a `Wasabi:Frame`: its picture, and a strip to drag it by.
class _FrameDividerView extends StatelessWidget {
  const _FrameDividerView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final frame = object.parent;
    final picture = object["image"] == null
        ? const SizedBox.expand()
        : _LayerView(object: object, size: size);
    final scripts = scope.scripts;
    if (frame == null || scripts == null || object["#fixed"] == "1") {
      return picture;
    }
    final stacked = frame["#frame.stacked"] == "1";
    var travelled = 0.0;
    return MouseRegion(
      cursor: stacked
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          travelled = 0;
          scripts.frameDragStart(frame);
        },
        onPanUpdate: (details) {
          travelled += stacked ? details.delta.dy : details.delta.dx;
          scripts.frameDragBy(frame, travelled);
        },
        onPanEnd: (_) => scripts.frameDragEnd(frame),
        child: picture,
      ),
    );
  }
}

class _BoxFrameView extends StatelessWidget {
  const _BoxFrameView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final color = scope.skin.color(object["color"]) ?? const Color(0xFFFFFFFF);
    return CustomPaint(
      size: Size.infinite,
      painter: _BoxFramePainter(
        color.withAlpha(scope.alphaOf(object)),
        (object.optInt("#gap") ?? 0).toDouble(),
      ),
    );
  }
}

class _BoxFramePainter extends CustomPainter {
  const _BoxFramePainter(this.color, this.gap);

  final Color color;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = false;
    final r = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    canvas.drawLine(r.bottomLeft, r.bottomRight, paint);
    canvas.drawLine(r.topLeft, r.bottomLeft, paint);
    canvas.drawLine(r.topRight, r.bottomRight, paint);
    canvas.drawLine(r.topLeft, Offset(r.left + 4, r.top), paint);
    canvas.drawLine(Offset(r.left + 6 + gap, r.top), r.topRight, paint);
  }

  @override
  bool shouldRepaint(_BoxFramePainter old) =>
      old.color != color || old.gap != gap;
}

/// A button's `tooltip` (`|` starts a new line), shown after the pointer
/// rests on it a moment.
class _SkinTooltip extends StatefulWidget {
  const _SkinTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<_SkinTooltip> createState() => _SkinTooltipState();
}

class _SkinTooltipState extends State<_SkinTooltip> {
  Timer? _timer;
  OverlayEntry? _entry;

  void _enter() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _show);
  }

  void _show() {
    // `Enable tooltips` of the skin's options turns them off.
    final scope = _WasabiScope.of(context);
    const attribute = WasabiCfgAttrib(
      WasabiCfgAttrib.uiOptions,
      "Enable tooltips",
    );
    final enabled =
        scope.scripts?.cfgAttribValue(attribute) ??
        scope.host.configValue(attribute);
    if (enabled == 0) return;
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.attached || _entry != null) {
      return;
    }
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height),
      ancestor: overlayBox,
    );
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: at.dx,
        top: at.dy + 4,
        child: IgnorePointer(
          child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFE1),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFF000000)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  widget.message.replaceAll("|", "\n"),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF000000),
                    height: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _leave() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    // A MouseRegion takes its whole box unless told to defer to its child: a
    // shaped button (Orbis' drawer handles, each as big as the window) would
    // otherwise cover the buttons under it.
    hitTestBehavior: HitTestBehavior.deferToChild,
    onEnter: (_) => _enter(),
    onExit: (_) => _leave(),
    child: Listener(
      onPointerDown: (_) => _leave(),
      child: widget.child,
    ),
  );
}

class _ObjectView extends StatelessWidget {
  const _ObjectView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    var view = switch (object.tag) {
      // A skin notifier's cover: the classic player showed the internet one in a
      // browser and read the local one from a file beside the track; here
      // the file's own cover and one from iTunes stand in.
      "browser" when object.id.contains("cdcover") => _CoverView(
        object: object,
        size: size,
        online: true,
      ),
      // Web pages are not something this player shows.
      "browser" || "winamp:browser" => _BrowserUnavailableView(
        object: object,
        size: size,
      ),
      "layer" when object.id == "local.cdcover" => _CoverView(
        object: object,
        size: size,
        online: false,
      ),
      "boxframe" => _BoxFrameView(object: object),
      "framedivider" => _FrameDividerView(object: object, size: size),
      "layer" || "animatedlayer" => _LayerRegionClip(
        object: object,
        child: _LayerView(object: object, size: size),
      ),
      "button" ||
      "togglebutton" ||
      "nstatesbutton" => _ButtonView(object: object, size: size),
      "slider" => _SliderView(object: object, size: size),
      // Wasabi 5's <SongTicker> is a text showing the scrolling song title.
      "text" || "songticker" => _TextView(object: object, size: size),
      "edit" => _EditView(object: object, size: size),
      "grid" => _GridView(object: object),
      "progressgrid" => _ProgressGridView(object: object),
      "status" => _StatusView(object: object),
      "vis" => _VisView(object: object),
      "component" || "windowholder" => _ComponentView(object: object),
      "eqvis" => _EqVisView(object: object),
      "colorthemes:list" => WasabiColorThemesView(
        skin: scope.skin,
        host: scope.host,
        object: object,
      ),
      "wasabibutton" => _WasabiButtonView(object: object, size: size),
      "rect" => _RectView(object: object, size: size),
      "checkbox" => _CheckBoxView(object: object, size: size),
      "tabsheet" => _TabSheetView(object: object, size: size),
      "dropdownlist" => _DropDownView(object: object, size: size),
      "albumart" => _AlbumArtView(object: object),
      "componentbucket" => _ComponentBucketView(object: object, size: size),
      "group" when object["#xfade"] == "1" => _XFadeView(
        object: object,
        size: size,
      ),
      "group" => _GroupBody(group: object, size: size),
      "menu" => _MenuView(object: object, size: size),
      _ => const SizedBox.shrink(),
    };
    // Ghost objects let the mouse through to what is under them; a ghost
    // group still passes it to its objects ([_GroupBody]).
    if (object.ghost && object.tag != "group") {
      return IgnorePointer(child: view);
    }
    final tip = object["tooltip"]?.trim() ?? "";
    if (tip.isNotEmpty &&
        const {
          "button",
          "togglebutton",
          "nstatesbutton",
          "slider",
          "wasabibutton",
        }.contains(object.tag)) {
      view = _SkinTooltip(message: tip, child: view);
    }
    // `cursor="id"`: the skin's own pointer over the object.
    final cursor = scope.skin.cursor(object["cursor"]);
    if (cursor != null) {
      view = MouseRegion(
        cursor: cursor,
        hitTestBehavior: HitTestBehavior.deferToChild,
        child: view,
      );
    }
    final resize = object["resize"]?.toLowerCase();
    if (resize != null &&
        (resize.contains("right") || resize.contains("bottom"))) {
      return _ResizeHandle(edges: resize, child: view);
    }
    // `rightclickaction="trackmenu"` on a text: the action runs on a right
    // press (`TextBase::onRightButtonDown`), and the window's own menu stays
    // closed.
    final rightAction = object["rightclickaction"]?.trim() ?? "";
    if (rightAction.isNotEmpty) {
      view = _RightClickAction(
        action: rightAction,
        param: object["rclickparam"],
        child: view,
      );
    }
    final doubleClick = _doubleClickAction(object);
    final scripts = scope.scripts;
    final scripted = scripts != null && scripts.scriptObjectOf(object) != null;
    if (doubleClick == null && !scripted) return view;
    final withScripts = scripted
        ? _ScriptMouse(object: object, scripts: scripts, child: view)
        : view;
    if (doubleClick == null) return withScripts;
    return _DoubleClickAction(
      action: doubleClick.$1,
      param: doubleClick.$2,
      child: withScripts,
    );
  }

  /// What a `dblclickaction` does on a double click, as an action and its
  /// parameter: `switch;<layout>` (Wasabi's `Title`, `Layer` and `Text`),
  /// or an action by name with `dblclickparam` (`trackinfo`, `close`,
  /// `vid_fs`).
  static (String, String?)? _doubleClickAction(WasabiObject object) {
    final action = object["dblclickaction"]?.trim();
    if (action == null || action.isEmpty) return null;
    if (action.length > 7 &&
        action.substring(0, 7).toLowerCase() == "switch;") {
      return ("SWITCH", action.substring(7));
    }
    return (action.toUpperCase(), object["dblclickparam"]);
  }
}

/// Runs an action on a right press, which then does not open the window's
/// own menu (`rightclickaction`).
class _RightClickAction extends StatelessWidget {
  const _RightClickAction({
    required this.action,
    required this.param,
    required this.child,
  });

  final String action;
  final String? param;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons != kSecondaryButton) return;
        final scope = _WasabiScope.of(context);
        scope.host.pressSecondaryAction(
          WasabiAction(action.toUpperCase(), param, container: scope.container),
          event,
        );
      },
      child: child,
    );
  }
}

/// Runs an action on a left double click (as `Layer::onLeftButtonDblClk`),
/// e.g. a title bar toggling windowshade (`switch;shade`). The presses still
/// reach the window, so it drags as before.
class _DoubleClickAction extends StatefulWidget {
  const _DoubleClickAction({
    required this.action,
    required this.param,
    required this.child,
  });

  final String action;
  final String? param;
  final Widget child;

  @override
  State<_DoubleClickAction> createState() => _DoubleClickActionState();
}

class _DoubleClickActionState extends State<_DoubleClickAction> {
  Duration? _lastDownTime;
  Offset? _lastDownPosition;

  void _onDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    final last = _lastDownTime;
    final isDouble =
        last != null &&
        event.timeStamp - last < kDoubleTapTimeout &&
        (event.position - _lastDownPosition!).distance < kDoubleTapSlop;
    _lastDownTime = isDouble ? null : event.timeStamp;
    _lastDownPosition = event.position;
    if (!isDouble) return;
    final scope = _WasabiScope.of(context);
    scope.host.runAction(
      WasabiAction(widget.action, widget.param, container: scope.container),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      child: widget.child,
    );
  }
}

/// A classic player component in a skin: the playlist, or what the app provides
/// for the others.
class _ComponentView extends StatelessWidget {
  const _ComponentView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    var name = wasabiComponentName(object);
    // `guid:default` is whichever component the window holds: a copy of the
    // skin's component frame was made for it.
    final spec = (object["param"] ?? object["hold"] ?? "").toLowerCase();
    if (name == null && (spec.contains("default") || spec.contains("@all@"))) {
      final held = scope.skin.container(scope.container)?.component;
      name = held == null ? null : wasabiComponentOf(held);
    }
    if (name == "pl") {
      return WasabiPlaylistView(
        skin: scope.skin,
        host: scope.host,
        object: object,
      );
    }
    final component = scope.components[name];
    if (component == null) return const SizedBox.shrink();
    // `noshowcmdbar="1"`: the component does not draw its own command bar
    // (`WindowHolder` -> `CompWnd::suppressStatusBar`); the skin has one.
    return WasabiComponentOptions(
      noCommandBar: object.boolAttr("noshowcmdbar"),
      child: component,
    );
  }
}

/// What the skin's `<component>` (a window holder) asks of the component it
/// holds, for the component to read: the library leaves out its bottom strip
/// when the holder says `noshowcmdbar="1"`.
class WasabiComponentOptions extends InheritedWidget {
  const WasabiComponentOptions({
    required this.noCommandBar,
    required super.child,
    super.key,
  });

  /// Whether the component draws no command bar of its own.
  final bool noCommandBar;

  static WasabiComponentOptions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WasabiComponentOptions>();

  @override
  bool updateShouldNotify(WasabiComponentOptions old) =>
      noCommandBar != old.noCommandBar;
}

/// What a `<browser>` (or `winamp:Browser`) shows: the classic player showed web pages
/// in it, which this player does not, so it says so.
class _BrowserUnavailableView extends StatelessWidget {
  const _BrowserUnavailableView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final skin = _WasabiScope.of(context).skin;
    final color =
        skin.color("wasabi.list.text") ??
        skin.color("wasabi.window.text") ??
        const Color(0xFF9A9A9A);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          "Web pages are not available here.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: skin.fontFamily(object["font"]),
            fontSize: 11,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// A `<rect>`: a filled rectangle, or just its edges, in a color
/// (`ScriptRect`: `color`, `filled`, `edges`, `thickness`).
class _RectView extends StatelessWidget {
  const _RectView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final color =
        scope.skin.color(object["color"], group: object["gammagroup"]) ??
        const Color(0xFFFFFFFF);
    final edges = (object["edges"] ?? "left|right|top|bottom").toLowerCase();
    return IgnorePointer(
      child: CustomPaint(
        size: size,
        painter: _RectPainter(
          color: color,
          filled: object.intAttr("filled") != 0,
          thickness: math.max(1, object.intAttr("thickness")),
          left: edges.contains("left"),
          right: edges.contains("right"),
          top: edges.contains("top"),
          bottom: edges.contains("bottom"),
        ),
      ),
    );
  }
}

class _RectPainter extends CustomPainter {
  const _RectPainter({
    required this.color,
    required this.filled,
    required this.thickness,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final Color color;
  final bool filled;
  final int thickness;
  final bool left;
  final bool right;
  final bool top;
  final bool bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    if (filled) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    final t = thickness.toDouble();
    if (top) canvas.drawRect(Rect.fromLTWH(0, 0, w, t), paint);
    if (bottom) canvas.drawRect(Rect.fromLTWH(0, h - t, w, t), paint);
    // The sides leave a pixel to the top and bottom ones.
    if (right) canvas.drawRect(Rect.fromLTWH(w - t, 1, t, h - 2), paint);
    if (left) canvas.drawRect(Rect.fromLTWH(0, 0, t, h), paint);
  }

  @override
  bool shouldRepaint(_RectPainter old) =>
      color != old.color ||
      filled != old.filled ||
      thickness != old.thickness ||
      left != old.left ||
      right != old.right ||
      top != old.top ||
      bottom != old.bottom;
}

/// A `<componentbucket>`: the Thinger's launcher buttons.
class _ComponentBucketView extends StatelessWidget {
  const _ComponentBucketView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    if (object.children.isNotEmpty) {
      // A bucket of the skin's own groups: they scroll along it, a page at
      // a time (`cb_prevpage`, `cb_nextpage`).
      final vertical = wasabiBucketIsVertical(object);
      final content = wasabiBucketExtent(object, scope.skin);
      final area = vertical
          ? Size(size.width, math.max(size.height, content))
          : Size(math.max(size.width, content), size.height);
      return ClipRect(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: object.intAttr("#scroll").toDouble()),
          // `scrollpage_speed`.
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutSine,
          // A Stack, not an OverflowBox: that takes taps only inside its
          // own (clipped) size, and the scrolled entries are outside it.
          builder: (context, scroll, child) => Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: vertical ? 0 : -scroll.roundToDouble(),
                top: vertical ? -scroll.roundToDouble() : 0,
                width: area.width,
                height: area.height,
                child: child!,
              ),
            ],
          ),
          child: _GroupStack(group: object, size: area),
        ),
      );
    }
    final text = _BucketText.of(context);
    return WasabiComponentBucket(
      object: object,
      size: size,
      skin: scope.skin,
      host: scope.host,
      container: scope.container,
      onHover: (label) => text?.value = label,
    );
  }
}

/// A `resize="right|bottom|bottomright"` object: dragging it resizes the
/// window, within the layout's `minimum_w`/`maximum_w` (and `_h`).
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.edges, required this.child});

  final String edges;
  final Widget child;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  /// Which edges this drag moves: the handle's own, and the other one too
  /// when it began within [_corner] of the corner (a skin's grip glyph sits
  /// over the end of its bottom edge, which is not a corner piece).
  static const double _corner = 28;

  int? _pointer;
  PointerRoute? _route;

  // Not stopped in dispose: resizing rebuilds the skin, which disposes this
  // handle in the middle of its own drag, and the drag goes on without it.

  void _stop() {
    final pointer = _pointer;
    final route = _route;
    if (pointer != null && route != null) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, route);
    }
    _pointer = null;
    _route = null;
  }

  /// Follows a press until its release through the pointer router, not this
  /// widget: resizing rebuilds the skin under the pointer, and a [Listener]
  /// torn down mid-drag stops getting its events.
  void _begin(PointerDownEvent event, _WasabiScope scope) {
    final layout = scope.layout;
    final right = widget.edges.contains("right");
    final bottom = widget.edges.contains("bottom");
    final box = context.size;
    // A strip along an edge also takes the corner at its end; a small grip
    // (the Base Skin's `resize="right"` one in the player's corner) is no
    // strip, and keeps to its own direction.
    final stripAlongRight =
        box != null && box.height >= box.width * 3 && box.height > _corner * 2;
    final stripAlongBottom =
        box != null && box.width >= box.height * 3 && box.width > _corner * 2;
    final moveRight =
        right ||
        (bottom &&
            stripAlongBottom &&
            !widget.edges.contains("left") &&
            event.localPosition.dx >= box.width - _corner);
    final moveBottom =
        bottom ||
        (right &&
            stripAlongRight &&
            !widget.edges.contains("top") &&
            event.localPosition.dy >= box.height - _corner);
    final start = layout.size;
    final host = scope.host;
    final container = scope.container;
    // The window's UI scale: global moves are in screen pixels.
    final transform = context.findRenderObject()?.getTransformTo(null);
    final scale = transform == null || transform.entry(0, 0) == 0
        ? 1.0
        : transform.entry(0, 0);
    var moved = Offset.zero;
    final pointer = event.pointer;
    _stop();
    late final PointerRoute route;
    route = (PointerEvent e) {
      if (e is PointerMoveEvent) {
        moved += e.delta / scale;
        final root = layout.root;
        double clampTo(double v, String min, String max) => v.clamp(
          (root.optInt(min) ?? 16).toDouble(),
          (root.optInt(max) ?? 8000).toDouble(),
        );
        final size = Size(
          moveRight
              ? clampTo(start.width + moved.dx, "minimum_w", "maximum_w")
              : start.width,
          moveBottom
              ? clampTo(start.height + moved.dy, "minimum_h", "maximum_h")
              : start.height,
        );
        final rounded = Size(
          size.width.roundToDouble(),
          size.height.roundToDouble(),
        );
        if (rounded != layout.size)
          host.resizeLayout(container, layout, rounded);
      } else if (e is PointerUpEvent || e is PointerCancelEvent) {
        GestureBinding.instance.pointerRouter.removeRoute(pointer, route);
        if (_pointer == pointer) {
          _pointer = null;
          _route = null;
        }
      }
    };
    _pointer = pointer;
    _route = route;
    GestureBinding.instance.pointerRouter.addRoute(pointer, route);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final right = widget.edges.contains("right");
    final bottom = widget.edges.contains("bottom");
    final cursor = right && bottom
        ? SystemMouseCursors.resizeDownRight
        : right
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
    return MouseRegion(
      cursor: cursor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          WasabiPointerClaim.claim?.call(event);
          _begin(event, scope);
        },
        child: widget.child,
      ),
    );
  }
}

/// Passes the mouse events of an object scripts listen to on to them
/// (`onLeftButtonDown`, `onEnterArea`, ...), without taking them from the
/// object itself.
class _ScriptMouse extends StatelessWidget {
  const _ScriptMouse({
    required this.object,
    required this.scripts,
    required this.child,
    this.bare = false,
  });

  /// Takes the mouse only where a child does (the root of a frame drawn
  /// over another window, whose empty area is not its own).
  final bool bare;
  final WasabiObject object;
  final WasabiScriptRuntime scripts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A shaped layer only takes the mouse over its pixels, which its view
    // decides.
    final shaped =
        wasabiShapedLayer(object) &&
        _WasabiScope.of(context).skin.bitmap(object["image"]) != null;
    return MouseRegion(
      // A group only takes the mouse where something in it does (its
      // background or a child), so a scripted group spanning the window
      // does not swallow clicks meant for what is under it. Other objects,
      // image-less mouse-trap layers among them, take it over their box.
      opaque: object.tag != "group" && !shaped && !bare,
      onEnter: (_) => scripts.pointer(object, "onEnterArea"),
      onExit: (_) => scripts.pointer(object, "onLeaveArea"),
      onHover: (event) => scripts.pointer(
        object,
        "onMouseMove",
        _inParent(context, event.localPosition),
      ),
      child: Listener(
        behavior: shaped || bare
            ? HitTestBehavior.deferToChild
            : HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (_heardElsewhere(event.pointer)) return;
          if (object.tag == "button") _claim(event.pointer);
          final right = event.buttons == kSecondaryButton;
          _rightPresses[event.pointer] = right;
          // `move="0"` keeps the window still under a press on the object
          // (the color changer's palette is dragged over, not the window).
          if (object["move"]?.trim() == "0") {
            WasabiPointerClaim.claim?.call(event);
          }
          // A mouse trap over a `<vis>` (Amped Modern's
          // `main.vis.trigger`, whose script changes the mode) leaves the
          // vis its clicks, so a double-click still opens the
          // visualization.
          if (!right && _coversVis(context)) {
            _WasabiScope.of(context).host.clickVis();
          }
          final at = _inParent(context, event.localPosition);
          scripts.pointer(
            object,
            right ? "onRightButtonDown" : "onLeftButtonDown",
            at,
          );
          // A second press close in time and place also is a double click
          // (`BaseWnd::checkDoubleClick`), told after the press.
          final last = _lastPresses[object];
          final isDouble =
              last != null &&
              last.right == right &&
              event.timeStamp - last.time < kDoubleTapTimeout &&
              (event.position - last.position).distance < kDoubleTapSlop;
          _lastPresses[object] = isDouble
              ? null
              : (time: event.timeStamp, position: event.position, right: right);
          if (isDouble) {
            scripts.pointer(
              object,
              right ? "onRightButtonDblClk" : "onLeftButtonDblClk",
              at,
            );
          }
          // A button's right press is its right click (`onRightPush`).
          if (right && object.tag == "button") {
            scripts.pointer(object, "onRightClick");
          }
        },
        onPointerSignal: (event) {
          // The wheel: `onMouseWheelUp`/`Down(clicked, lines)`.
          if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
          scripts.mouseWheel(object, up: event.scrollDelta.dy < 0);
        },
        onPointerMove: (event) => scripts.pointer(
          object,
          "onMouseMove",
          _inParent(context, event.localPosition),
        ),
        onPointerCancel: (event) => _release(event.pointer),
        onPointerUp: (event) {
          _release(event.pointer);
          if (_heardElsewhere(event.pointer)) {
            _rightPresses.remove(event.pointer);
            return;
          }
          final right = _rightPresses.remove(event.pointer) ?? false;
          scripts.pointer(
            object,
            right ? "onRightButtonUp" : "onLeftButtonUp",
            _inParent(context, event.localPosition),
          );
        },
        child: child,
      ),
    );
  }

  /// Makes [object] the one that has the press [pointer]: the objects
  /// behind it do not hear it (a window takes the click at its topmost
  /// object, where the pixels of a shaped button are).
  void _claim(int pointer) {
    _claims[pointer] = object;
  }

  /// Ends the claim [object] has on [pointer], once the press has been told
  /// to everything that hears it.
  void _release(int pointer) {
    if (!identical(_claims[pointer], object)) return;
    scheduleMicrotask(() {
      if (identical(_claims[pointer], object)) _claims.remove(pointer);
    });
  }

  /// Whether another object has the press [pointer] (see [_claim]): not
  /// one of the claimer's own ancestors, which hear it too.
  bool _heardElsewhere(int pointer) {
    final claimer = _claims[pointer];
    if (claimer == null || identical(claimer, object)) return false;
    for (WasabiObject? at = claimer.parent; at != null; at = at.parent) {
      if (identical(at, object)) return false;
    }
    return true;
  }

  /// [local], a position in [object], as its scripts get it: in the
  /// coordinates of the window it is in, the way Wasabi hands a virtual
  /// child the position the window got (a script subtracts the object's
  /// `getLeft()` and `getTop()` to find where in it the mouse is).
  Offset _inParent(BuildContext context, Offset local) {
    final parent = object.parent;
    if (parent == null) return local;
    final scope = _WasabiScope.of(context);
    final area = scripts.rectOf(parent).size;
    return local + wasabiObjectRect(object, area, scope.skin).topLeft;
  }

  /// Whether [object] is an image-less layer lying over a `<vis>` of its
  /// group.
  bool _coversVis(BuildContext context) {
    final parent = object.parent;
    if (object.tag != "layer" || object["image"] != null || parent == null) {
      return false;
    }
    final scope = _WasabiScope.of(context);
    final size = scripts.rectOf(parent).size;
    final own = wasabiObjectRect(object, size, scope.skin);
    return parent.children.any(
      (other) =>
          other.tag == "vis" &&
          other.visible &&
          wasabiObjectRect(other, size, scope.skin).overlaps(own),
    );
  }

  /// Whether each pressed pointer went down with the right button.
  static final Map<int, bool> _rightPresses = {};

  /// The object that has each press (see [_claim]).
  static final Map<int, WasabiObject> _claims = {};

  /// The last press on each object, to tell a double click.
  static final Map<
    WasabiObject,
    ({Duration time, Offset position, bool right})?
  >
  _lastPresses = Map.identity();
}

/// Paints [bitmap] stretched over the box (or tiled with [tile]).
class _BitmapPaint extends StatelessWidget {
  const _BitmapPaint({
    required this.bitmap,
    this.alpha = 255,
    this.tile = false,
    this.hitShape,
  });

  final WasabiBitmap bitmap;
  final int alpha;
  final bool tile;

  /// Where the bitmap takes the mouse; null for everywhere.
  final _HitShape? hitShape;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BitmapPainter(bitmap, alpha, tile, hitShape));
  }
}

/// Where a shaped layer of [size] takes the mouse: [region], the pixels
/// with any alpha of the image it was cut from, with the part it shows
/// [offset] from that image's origin.
class _HitShape {
  const _HitShape(this.region, this.offset, this.size);

  final List<Rect> region;
  final Offset offset;
  final Size size;
}

class _BitmapPainter extends CustomPainter {
  _BitmapPainter(this.bitmap, this.alpha, this.tile, this.hitShape)
    : image = bitmap.image;

  final WasabiBitmap bitmap;

  /// [bitmap]'s picture in the color theme it is painted in.
  final ui.Image image;
  final int alpha;
  final bool tile;
  final _HitShape? hitShape;

  @override
  bool? hitTest(Offset position) {
    final shape = hitShape;
    if (shape == null || shape.size.isEmpty) return null;
    final inBitmap = tile
        ? Offset(position.dx % bitmap.width, position.dy % bitmap.height)
        : Offset(
            position.dx * bitmap.width / shape.size.width,
            position.dy * bitmap.height / shape.size.height,
          );
    final point = shape.offset + inBitmap;
    return shape.region.any((r) => r.contains(point));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha == 0 || size.isEmpty) return;
    // Not the picture this was made with: a color theme change since may
    // have disposed it before this painter was rebuilt.
    final image = bitmap.image;
    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..filterQuality = FilterQuality.none;
    if (!tile) {
      canvas.drawImageRect(image, bitmap.src, Offset.zero & size, paint);
      return;
    }
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (var y = 0.0; y < size.height; y += bitmap.height) {
      for (var x = 0.0; x < size.width; x += bitmap.width) {
        canvas.drawImageRect(
          image,
          bitmap.src,
          Offset(x, y) & bitmap.size,
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BitmapPainter oldDelegate) =>
      oldDelegate.bitmap != bitmap ||
      oldDelegate.image != image ||
      oldDelegate.alpha != alpha ||
      oldDelegate.tile != tile;
}

/// Paints [bitmap] through a layer effect's warp: each grid point of the
/// box shows the image point [mesh] gives it, the image stretched in
/// between.
class _FxPainter extends CustomPainter {
  _FxPainter(this.bitmap, this.mesh, this.alpha) : image = bitmap.image;

  final WasabiBitmap bitmap;
  final WasabiFxMesh mesh;
  final int alpha;

  /// [bitmap]'s picture in the color theme it is painted in.
  final ui.Image image;

  /// [bitmap] as an image of its own, so wrapping repeats it and not the
  /// sheet it was cut from: the sheet it was cut from, and the cut.
  static final Expando<(ui.Image, ui.Image)> _crops = Expando();

  ui.Image _image() {
    // Not the picture this was made with: a color theme change since may
    // have disposed it before this painter was rebuilt.
    final image = bitmap.image;
    final whole =
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
    if (bitmap.src == whole) return image;
    final cached = _crops[bitmap];
    if (cached != null) {
      if (cached.$1 == image) return cached.$2;
      // Cut from another color theme's picture.
      cached.$2.dispose();
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      bitmap.src,
      Offset.zero & bitmap.size,
      Paint(),
    );
    final picture = recorder.endRecording();
    final crop = picture.toImageSync(
      bitmap.width.round(),
      bitmap.height.round(),
    );
    picture.dispose();
    _crops[bitmap] = (image, crop);
    return crop;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha == 0 || size.isEmpty) return;
    final columns = mesh.columns;
    final rows = mesh.rows;
    final positions = <Offset>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          Offset(
            column * size.width / (columns - 1),
            row * size.height / (rows - 1),
          ),
    ];
    final indices = <int>[
      for (var row = 0; row < rows - 1; row++)
        for (var column = 0; column < columns - 1; column++) ...[
          row * columns + column,
          row * columns + column + 1,
          (row + 1) * columns + column,
          row * columns + column + 1,
          (row + 1) * columns + column + 1,
          (row + 1) * columns + column,
        ],
    ];
    final tile = mesh.wrap ? TileMode.repeated : TileMode.clamp;
    final quality = mesh.bilinear ? FilterQuality.low : FilterQuality.none;
    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..filterQuality = quality
      ..shader = ImageShader(
        _image(),
        tile,
        tile,
        Matrix4.identity().storage,
        filterQuality: quality,
      );
    final alphas = mesh.alphas;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawVertices(
        ui.Vertices(
          VertexMode.triangles,
          positions,
          textureCoordinates: mesh.source,
          colors: alphas == null
              ? null
              : [
                  for (final a in alphas)
                    Color.fromARGB((a * 255).round(), 255, 255, 255),
                ],
          indices: indices,
        ),
        alphas == null ? BlendMode.srcOver : BlendMode.modulate,
        paint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_FxPainter oldDelegate) =>
      oldDelegate.bitmap != bitmap ||
      oldDelegate.image != image ||
      oldDelegate.mesh != mesh ||
      oldDelegate.alpha != alpha;
}

/// Clips a layer to the region a script gave it from a map
/// (`Layer.setRegionFromMap`), for drawing and the mouse, as `Layer::onPaint`
/// clips to its `secrgn`.
class _LayerRegionClip extends StatelessWidget {
  const _LayerRegionClip({required this.object, required this.child});

  final WasabiObject object;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final region = _WasabiScope.of(context).scripts?.layerRegionOf(object);
    if (region == null) return child;
    return ClipPath(clipper: _RectsClipper(region), child: child);
  }
}

/// Clips to [rects], which are in the pixels of a picture of [source] size,
/// stretched over the clipped area.
class _ScaledRectsClipper extends CustomClipper<Path> {
  const _ScaledRectsClipper(this.rects, this.source);

  final List<Rect> rects;
  final Size source;

  @override
  Path getClip(Size size) {
    final sx = source.width == 0 ? 1.0 : size.width / source.width;
    final sy = source.height == 0 ? 1.0 : size.height / source.height;
    final path = Path();
    for (final r in rects) {
      path.addRect(
        Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy),
      );
    }
    return path;
  }

  @override
  bool shouldReclip(_ScaledRectsClipper oldClipper) =>
      !identical(oldClipper.rects, rects) || oldClipper.source != source;
}

/// Clips to [rects].
class _RectsClipper extends CustomClipper<Path> {
  const _RectsClipper(this.rects);

  final List<Rect> rects;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final rect in rects) {
      path.addRect(rect);
    }
    return path;
  }

  @override
  bool shouldReclip(_RectsClipper oldClipper) =>
      !identical(oldClipper.rects, rects);
}

class _LayerView extends StatelessWidget {
  const _LayerView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    final image = skin.bitmap(object["image"]);
    // A layer without an image is an invisible mouse trap.
    if (image == null) return const SizedBox.expand();
    final mesh = scope.scripts?.fxMeshOf(object);
    if (mesh != null) {
      return CustomPaint(
        painter: _FxPainter(image, mesh, scope.alphaOf(object)),
        size: size,
      );
    }
    final bitmap = object.tag == "animatedlayer"
        ? wasabiFrameBitmap(object, image)
        : image;
    // A shaped layer takes the mouse only over its pixels; an opaque image
    // has no region and takes it everywhere.
    final region = wasabiShapedLayer(object) ? skin.bitmapRegion(image) : null;
    return _BitmapPaint(
      bitmap: bitmap,
      alpha: scope.alphaOf(object),
      tile: object.boolAttr("tile"),
      hitShape: region == null
          ? null
          : _HitShape(region, bitmap.src.topLeft - image.src.topLeft, size),
    );
  }
}

// --- Album art ---------------------------------------------------------------

/// Where an `<AlbumArt>` object of [box] size draws a picture of [image]
/// size (gen_ff `AlbumArt::layer_adjustDest`): the whole box when
/// [stretched], else as large as fits without distortion, placed by
/// [align] and [valign] (-1 left/top, 0 centered, 1 right/bottom).
Rect wasabiAlbumArtRect(
  Size image,
  Size box, {
  int align = 0,
  int valign = 0,
  bool stretched = false,
}) {
  if (stretched || image.isEmpty) return Offset.zero & box;
  final scale = math.min(box.width / image.width, box.height / image.height);
  final width = (image.width * scale).truncateToDouble();
  final height = (image.height * scale).truncateToDouble();
  double offset(double free, int where) => switch (where) {
    -1 => 0,
    1 => free,
    _ => (free / 2).truncateToDouble(),
  };
  return Rect.fromLTWH(
    offset(box.width - width, align),
    offset(box.height - height, valign),
    width,
    height,
  );
}

/// Where [layout]'s first visible `<AlbumArt>` draws, at the layout's
/// size, or null when it has none or that one is `stretched` (so has no
/// shape to keep). Frames that place their content from scripts
/// (`Wasabi:StandardFrame`) have it only once the scripts run.
Rect? wasabiAlbumArtArea(WasabiSkinData skin, WasabiLayout layout) {
  Rect? find(WasabiObject group, Rect area) {
    for (final child in group.children) {
      if (!child.visible) continue;
      final rect = wasabiObjectRect(child, area.size, skin).shift(area.topLeft);
      if (child.tag == "albumart") {
        return child.boolAttr("stretched") ? null : rect;
      }
      if (child.children.isNotEmpty) {
        final found = find(child, rect);
        if (found != null) return found;
      }
    }
    return null;
  }

  return find(layout.root, Offset.zero & layout.size);
}

/// An `<AlbumArt>` (gen_ff `AlbumArt`, a `Layer`): the playing item's
/// cover, or the skin's `notfoundimage` bitmap without one
/// (`winamp.cover.notfound` by default), kept to its aspect ratio unless
/// `stretched`.
class _AlbumArtView extends StatelessWidget {
  const _AlbumArtView({required this.object});

  final WasabiObject object;

  /// `align`/`valign`: -1 for left/top, 1 for right/bottom, else 0.
  static int _side(String? value, String start, String end) =>
      switch (value?.trim().toLowerCase()) {
        final v when v == start => -1,
        final v when v == end => 1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final art = scope.host.albumArt;
    final WasabiBitmap? bitmap = art != null
        ? WasabiBitmap(
            art,
            Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
          )
        : scope.skin.bitmap(object["notfoundimage"] ?? "winamp.cover.notfound");
    // A script's layer effect (a reflection) warps the picture over the
    // whole object.
    final mesh = scope.scripts?.fxMeshOf(object);
    if (mesh != null && bitmap != null) {
      return _AlbumArtMouse(
        host: scope.host,
        child: CustomPaint(
          size: Size.infinite,
          painter: _FxPainter(bitmap, mesh, scope.alphaOf(object)),
        ),
      );
    }
    return _AlbumArtMouse(
      host: scope.host,
      // Nothing to draw still takes the mouse, for the menu.
      child: bitmap == null
          // A skin that gives no picture for a missing cover (the classic player
          // supplies one itself) gets amped's plate with a note.
          ? CustomPaint(
              size: Size.infinite,
              painter: _NoCoverPainter(scope.alphaOf(object)),
            )
          : CustomPaint(
              size: Size.infinite,
              painter: _AlbumArtPainter(
                bitmap,
                scope.alphaOf(object),
                align: _side(object["align"], "left", "right"),
                valign: _side(object["valign"], "top", "bottom"),
                stretched: object.boolAttr("stretched"),
              ),
            ),
    );
  }
}

/// What an album art object shows when the item has no cover and the skin
/// has no picture for that: a rounded plate with a music note, in white and
/// black over what is behind it, so it takes the skin's frame and color
/// theme.
class _NoCoverPainter extends CustomPainter {
  const _NoCoverPainter(this.alpha);

  final int alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha == 0 || size.isEmpty) return;
    final side = math.min(size.width, size.height) * 0.9;
    if (side < 8) return;
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: side,
        height: side,
      ),
      Radius.circular(side * 0.08),
    );
    final fade = alpha / 255;
    canvas
      ..drawRRect(
        plate,
        Paint()
          ..shader = ui.Gradient.linear(
            plate.outerRect.topCenter,
            plate.outerRect.bottomCenter,
            [
              Color.fromRGBO(255, 255, 255, 0.30 * fade),
              Color.fromRGBO(0, 0, 0, 0.14 * fade),
            ],
          ),
      )
      ..drawRRect(
        plate.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Color.fromRGBO(255, 255, 255, 0.45 * fade),
      );
    // An eighth note, in a box a third of the plate. Drawn solid into a
    // layer that is made translucent as a whole, so where its head, stem
    // and flag cross they are no brighter than the rest.
    final box = side / 3;
    // (0.466, 0.579) is the middle of the note's bounds: head, stem and flag.
    final origin = plate.outerRect.center - Offset(box * 0.466, box * 0.579);
    Offset at(double x, double y) => origin + Offset(x * box, y * box);
    final solid = Paint()..color = const Color(0xFFFFFFFF);
    final stem = Paint()
      ..color = solid.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = box * 0.1
      ..strokeCap = StrokeCap.round;
    canvas
      ..saveLayer(
        plate.outerRect,
        Paint()..color = Color.fromRGBO(255, 255, 255, 0.5 * fade),
      )
      ..save()
      ..translate(at(0.28, 0.9).dx, at(0.28, 0.9).dy)
      ..rotate(-0.3)
      ..drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: box * 0.5,
          height: box * 0.36,
        ),
        solid,
      )
      ..restore()
      ..drawLine(at(0.46, 0.85), at(0.46, 0.12), stem)
      ..drawPath(
        Path()
          ..moveTo(at(0.46, 0.12).dx, at(0.46, 0.12).dy)
          ..quadraticBezierTo(
            at(0.9, 0.2).dx,
            at(0.9, 0.2).dy,
            at(0.84, 0.55).dx,
            at(0.84, 0.55).dy,
          ),
        stem,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_NoCoverPainter oldDelegate) => oldDelegate.alpha != alpha;
}

/// The album art menu on a right-click and the file's folder on a
/// double-click, which the stock skins' `albumart.maki` provides through
/// a `PopupMenu` and `navigateUrl` (not scriptable here). The presses still
/// reach the window, so `move="1"` drags it.
class _AlbumArtMouse extends StatefulWidget {
  const _AlbumArtMouse({required this.host, required this.child});

  final WasabiHost host;
  final Widget child;

  @override
  State<_AlbumArtMouse> createState() => _AlbumArtMouseState();
}

class _AlbumArtMouseState extends State<_AlbumArtMouse> {
  int? _menuPointer;
  Duration? _lastDownTime;
  Offset? _lastDownPosition;

  void _onDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryButton) {
      widget.host.pressAlbumArtMenu(event);
      _menuPointer = event.pointer;
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    final last = _lastDownTime;
    final isDouble =
        last != null &&
        event.timeStamp - last < kDoubleTapTimeout &&
        (event.position - _lastDownPosition!).distance < kDoubleTapSlop;
    _lastDownTime = isDouble ? null : event.timeStamp;
    _lastDownPosition = event.position;
    if (isDouble) widget.host.openAlbumArtFolder();
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _menuPointer) return;
    _menuPointer = null;
    widget.host.showAlbumArtMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      child: widget.child,
    );
  }
}

class _AlbumArtPainter extends CustomPainter {
  const _AlbumArtPainter(
    this.bitmap,
    this.alpha, {
    required this.align,
    required this.valign,
    required this.stretched,
  });

  final WasabiBitmap bitmap;
  final int alpha;
  final int align;
  final int valign;
  final bool stretched;

  @override
  bool hitTest(Offset position) => true;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha == 0 || size.isEmpty) return;
    final dest = wasabiAlbumArtRect(
      bitmap.size,
      size,
      align: align,
      valign: valign,
      stretched: stretched,
    );
    // Covers are scaled smoothly (`HQSkinBitmap`).
    final paint = Paint()
      ..color = Color.fromARGB(alpha, 255, 255, 255)
      ..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(bitmap.image, bitmap.src, dest, paint);
  }

  @override
  bool shouldRepaint(_AlbumArtPainter oldDelegate) =>
      oldDelegate.bitmap.image != bitmap.image ||
      oldDelegate.bitmap.src != bitmap.src ||
      oldDelegate.alpha != alpha ||
      oldDelegate.align != align ||
      oldDelegate.valign != valign ||
      oldDelegate.stretched != stretched;
}

// --- Buttons -----------------------------------------------------------------

/// An `<NStatesButton>`'s first image, which sizes it.
String? _nStatesImage(WasabiObject object) {
  final states = WasabiNStates(object);
  return states.count > 1 ? states.image(object["image"], 0) : object["image"];
}

/// A `<button>`: `image`, `downimage` while pressed with the pointer over
/// it, `hoverimage` under the pointer, `activeimage` while its action is on.
/// Releasing over the button runs its action (`Wasabi::Button`). An
/// `<NStatesButton>` of more than one state steps through them instead,
/// showing each state's own images ([WasabiNStates]).
class _ButtonView extends StatefulWidget {
  const _ButtonView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_ButtonView> createState() => _ButtonViewState();
}

class _ButtonViewState extends State<_ButtonView> {
  bool _hover = false;
  bool _pressed = false;
  bool _inside = false;

  bool _contains(Offset local) => (Offset.zero & widget.size).contains(local);

  bool get _isToggle =>
      widget.object.tag == "togglebutton" ||
      widget.object.tag == "nstatesbutton";

  /// The config attribute a toggle button shows and sets, or null.
  WasabiCfgAttrib? get _cfgAttrib =>
      _isToggle ? WasabiCfgAttrib.parse(widget.object["cfgattrib"]) : null;

  /// An `<NStatesButton>`'s states, or null for other buttons and one with
  /// a single state, which is a toggle button.
  WasabiNStates? get _nStates {
    if (widget.object.tag != "nstatesbutton") return null;
    final states = WasabiNStates(widget.object);
    return states.count > 1 ? states : null;
  }

  /// The state an `<NStatesButton>` shows: its config attribute's, or its
  /// own (kept when the attribute's value is none of its states).
  int _state(_WasabiScope scope, WasabiNStates states) {
    final cfgAttrib = _cfgAttrib;
    final own = widget.object.intAttr("#state");
    if (cfgAttrib == null) return own;
    return states.stateOf(_configValue(scope, cfgAttrib)) ?? own;
  }

  /// The value of [attribute]: a skin option its scripts made (the classic player
  /// Modern's "Animate Config Drawer") is theirs; the host keeps any other.
  static int _configValue(_WasabiScope scope, WasabiCfgAttrib attribute) =>
      scope.scripts?.cfgAttribValue(attribute) ??
      scope.host.configValue(attribute);

  /// Sets [attribute] where [_configValue] reads it.
  static void _setConfigValue(
    _WasabiScope scope,
    WasabiCfgAttrib attribute,
    int value,
  ) {
    final scripts = scope.scripts;
    if (scripts == null || !scripts.setCfgAttribValue(attribute, value)) {
      scope.host.setConfigValue(attribute, value);
    }
  }

  void _run() {
    final scope = _WasabiScope.of(context);
    final object = widget.object;
    final cfgAttrib = _cfgAttrib;
    final states = _nStates;
    if (states != null) {
      // On to the next state, which stores its cfgval
      // (NStatesTgButton::autoToggle, setState); scripts then see it.
      final state = states.next(_state(scope, states));
      object.attributes["#state"] = "$state";
      if (cfgAttrib != null) {
        _setConfigValue(scope, cfgAttrib, states.cfgValue(state));
      }
      scope.scripts?.buttonClicked(object);
    } else if (cfgAttrib == null) {
      scope.scripts?.buttonClicked(object);
    } else {
      // The button flips from the attribute's state, which may have been
      // changed elsewhere, and stores its `cfgval` when it turns on
      // (ToggleButton::onToggle).
      // A skin option its scripts made (Amped Modern's "Animate Config
      // Drawer") is theirs; the host keeps any other.
      final on = _configValue(scope, cfgAttrib) == 0;
      object.attributes["#active"] = on ? "0" : "1";
      scope.scripts?.buttonClicked(object);
      object.attributes["#active"] = on ? "1" : "0";
      _setConfigValue(scope, cfgAttrib, on ? object.intAttr("cfgval", 1) : 0);
    }
    final action = object["action"]?.toUpperCase();
    if (action == null || action.isEmpty) return;
    // An action for another object of the skin (`action_target`), or for
    // its buckets (`cb_prevpage`), is the scripts' to run.
    if (scope.scripts?.buttonAction(object) ?? false) return;
    final param = object["param"];
    final before = scope.host.isActive(action, param);
    scope.host.runAction(
      WasabiAction(action, param, container: scope.container),
    );
    // A toggle button whose action has a state the player keeps (EQ on/off,
    // a window's visibility) shows that state alone, as Wasabi sets it from
    // the core. Its own flip would otherwise keep it lit for good once the
    // two disagree, e.g. when the EQ was already on.
    if (cfgAttrib == null &&
        states == null &&
        _isToggle &&
        scope.host.isActive(action, param) != before) {
      object.attributes["#active"] = "0";
      scope.scripts?.changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    final object = widget.object;
    final action = object["action"]?.toUpperCase();
    final cfgAttrib = _cfgAttrib;
    final states = _nStates;
    final down = _pressed && _inside;
    final WasabiBitmap? bitmap;
    if (states != null) {
      // Each state has its own images and no active one, unless all states
      // share theirs (`autoelements="0"`, like Amped Modern's Repeat LED):
      // then it is active in any state but the first
      // (NStatesTgButton::setupBitmaps, getActivatedButton).
      final state = _state(scope, states);
      WasabiBitmap? image(String attribute) =>
          skin.bitmap(states.image(object[attribute], state));
      final active = states.oneVisualState && state != 0;
      bitmap =
          (down ? image("downimage") : null) ??
          (active ? image("activeimage") : null) ??
          (_hover && !_pressed ? image("hoverimage") : null) ??
          image("image");
    } else {
      // Activated by its config attribute, its action's state or a script
      // (`setActivated`, a toggle button's own state).
      final active = cfgAttrib != null
          ? _configValue(scope, cfgAttrib) != 0
          : object["#active"] == "1" ||
                (action != null &&
                    scope.host.isActive(action, object["param"]));
      bitmap =
          (down ? skin.bitmap(object["downimage"]) : null) ??
          (active ? skin.bitmap(object["activeimage"]) : null) ??
          (_hover && !_pressed ? skin.bitmap(object["hoverimage"]) : null) ??
          skin.bitmap(object["image"]);
    }
    // Unless it says `rectrgn="1"`, a button takes the mouse only over the
    // pixels of its picture (Act3scene2's E, P and M buttons are three
    // segments of an arc, each as big as the arc's box).
    final shapeBitmap = skin.bitmap(object["image"]);
    final shapeRegion = object["rectrgn"]?.trim() == "1" || shapeBitmap == null
        ? null
        : skin.bitmapRegion(shapeBitmap);
    final shape = shapeRegion == null || shapeBitmap == null
        ? null
        : _HitShape(shapeRegion, Offset.zero, widget.size);
    return MouseRegion(
      // A shaped button lets the pointer through its transparent pixels, to
      // the button under it.
      hitTestBehavior: shape == null
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: shape == null
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          WasabiPointerClaim.claim?.call(event);
          setState(() {
            _pressed = true;
            _inside = true;
          });
        },
        onPointerMove: (event) {
          if (!_pressed) return;
          final inside = _contains(event.localPosition);
          if (inside != _inside) setState(() => _inside = inside);
        },
        onPointerUp: (event) {
          if (!_pressed) return;
          final run = _contains(event.localPosition);
          setState(() => _pressed = false);
          if (run) _run();
        },
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // `borders="1"`: the system's button frame under the picture
            // (`ButtonWnd` draws a `DrawSysObject::BUTTON`).
            if (object.boolAttr("borders"))
              CustomPaint(painter: _SystemButtonPainter(pressed: down)),
            if (bitmap != null)
              object.boolAttr("center_image")
                  // `center_image="1"`: the picture at its own size in the
                  // middle (a pressed button shifts it a pixel).
                  ? Center(
                      child: Transform.translate(
                        offset: down ? const Offset(1, 1) : Offset.zero,
                        child: SizedBox(
                          width: bitmap.width,
                          height: bitmap.height,
                          child: _BitmapPaint(
                            bitmap: bitmap,
                            alpha: scope.alphaOf(object),
                          ),
                        ),
                      ),
                    )
                  : _BitmapPaint(
                      bitmap: bitmap,
                      alpha: scope.alphaOf(object),
                      hitShape: shape,
                    ),
            // A button's own label, in its colour (Ebonite's config tabs).
            if ((object["text"] ?? "").isNotEmpty)
              IgnorePointer(
                child: Align(
                  alignment: switch (object["align"]?.toLowerCase()) {
                    "right" => Alignment.centerRight,
                    "center" => Alignment.center,
                    _ => Alignment.centerLeft,
                  },
                  child: Text(
                    object["text"]!,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: object.intAttr("fontsize", 14) * 72 / 96,
                      fontFamily: scope.skin.fontFamily(object["font"]),
                      color:
                          scope.skin.color(object["color"]) ??
                          const Color(0xFFFFFFFF),
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The frame of a `borders="1"` button: a plain raised face, sunk (and
/// tinted) while pressed, as the system draws a push button.
class _SystemButtonPainter extends CustomPainter {
  const _SystemButtonPainter({required this.pressed});

  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..drawRect(
        rect,
        Paint()
          ..color = pressed ? const Color(0xFFCCE4F7) : const Color(0xFFE1E1E1),
      )
      ..drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = pressed ? const Color(0xFF005499) : const Color(0xFFADADAD),
      );
  }

  @override
  bool shouldRepaint(_SystemButtonPainter old) => old.pressed != pressed;
}

// --- Menus -------------------------------------------------------------------

/// A `<Menu>` (`MenuButton`): pressing it opens the player menu it names
/// below it; its group shows its `hover` and `down` objects meanwhile.
class _MenuView extends StatefulWidget {
  const _MenuView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<_MenuView> {
  bool _hover = false;
  bool _open = false;

  void _update() {
    _menuLookOf(widget.object).value = _open
        ? WasabiMenuLook.down
        : _hover
        ? WasabiMenuLook.hover
        : WasabiMenuLook.normal;
  }

  /// This menu's box in layout pixels.
  Rect _anchor() {
    final box = context.findRenderObject() as RenderBox?;
    final layout = context
        .getElementForInheritedWidgetOfExactType<_WasabiScope>()
        ?.findRenderObject();
    if (box == null || layout == null) return Offset.zero & widget.size;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: layout);
    return topLeft & widget.size;
  }

  Future<void> _openMenu() async {
    final menu = WasabiMenu.of(widget.object);
    if (menu == null || _open) return;
    final scope = _WasabiScope.of(context);
    _open = true;
    _update();
    try {
      await scope.host.openMenu(
        WasabiMenuRequest(
          menu: menu.menu,
          container: scope.container,
          anchor: _anchor(),
        ),
      );
    } finally {
      // The pointer has likely moved on while the menu was open.
      _open = false;
      _hover = false;
      _update();
    }
  }

  @override
  void dispose() {
    // The tree is locked while this runs: notifying the group that shows the
    // look would make it call setState, so reset it once the frame is done.
    final look = _menuLookOf(widget.object);
    if (look.value != WasabiMenuLook.normal) {
      scheduleMicrotask(() => look.value = WasabiMenuLook.normal);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) {
        if (_hover) return;
        _hover = true;
        _update();
      },
      onExit: (_) {
        _hover = false;
        _update();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          WasabiPointerClaim.claim?.call(event);
          unawaited(_openMenu());
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

// --- Sliders -----------------------------------------------------------------

/// A `<slider>` (`SliderWnd`): a thumb moved along the box, horizontal by
/// default. The value is 0..1 from the left (or bottom).
class _SliderView extends StatefulWidget {
  const _SliderView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_SliderView> createState() => _SliderViewState();
}

class _SliderViewState extends State<_SliderView> {
  /// The value while dragging, which wins over the host's.
  double? _dragValue;

  /// Where on the thumb it was grabbed (`origPos`).
  double _grab = 0;
  bool _hover = false;

  bool get _vertical =>
      widget.object["orientation"]?.toLowerCase().startsWith("v") ?? false;

  String get _action => (widget.object["action"] ?? "").toUpperCase();

  Size _thumbSize(WasabiSkinData skin) {
    if (widget.object["#builtin"] == "1") return const Size(8, 14);
    final thumb = skin.bitmap(widget.object["thumb"]);
    return thumb?.size ?? const Size(5, 5);
  }

  /// The thumb's travel (`w` in SliderWnd::onPaint).
  double _travel(Size thumb) => math.max(
    0,
    _vertical
        ? widget.size.height - thumb.height
        : widget.size.width - thumb.width,
  );

  /// The thumb's offset along the travel for [value].
  double _offsetFor(double value, Size thumb) {
    final travel = _travel(thumb);
    return (_vertical ? 1 - value : value) * travel;
  }

  double _valueAt(Offset local, Size thumb) {
    final travel = _travel(thumb);
    if (travel <= 0) return 0;
    final p = (_vertical ? local.dy : local.dx) - _grab;
    var value = (p / travel).clamp(0.0, 1.0);
    if (_vertical) value = 1 - value;
    // The EQ sliders snap to the middle (`hotPosition`), within 7.5%.
    if (_action == "EQ_BAND" || _action == "EQ_PREAMP") {
      if ((value - 0.5).abs() < 0.075) value = 0.5;
    }
    return value;
  }

  void _set(double value, {required bool done}) {
    final scope = _WasabiScope.of(context);
    if (_action.isEmpty) {
      // A slider of the skin's own, which only its scripts read.
      scope.scripts?.sliderMoved(widget.object, value, done: done);
      return;
    }
    scope.host.setSliderValue(
      _action,
      widget.object["param"],
      value,
      done: done,
    );
    // The seek bar posts its position when it is let go, the volume bar and
    // the others as they move (`onPostedPosition`).
    if (done || _action != "SEEK") {
      scope.scripts?.sliderPosted(widget.object, value);
    }
    // A seek lets the scripts know where to (`System.onSeek`, in ms).
    if (done && _action == "SEEK") {
      scope.scripts?.seeked((scope.host.lengthMs * value).round());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    final object = widget.object;
    final thumbSize = _thumbSize(skin);
    final value =
        _dragValue ??
        (_action.isEmpty
            ? scope.scripts?.sliderValueOf(object) ?? 0
            : scope.host.sliderValue(_action, object["param"]));
    final thumb =
        (_dragValue != null ? skin.bitmap(object["downthumb"]) : null) ??
        (_hover ? skin.bitmap(object["hoverthumb"]) : null) ??
        skin.bitmap(object["thumb"]);
    final size = widget.size;
    Rect? thumbRect;
    if (value != null) {
      final along = _offsetFor(value, thumbSize);
      thumbRect = _vertical
          ? Rect.fromLTWH(
              ((size.width - thumbSize.width) / 2).truncateToDouble(),
              along.truncateToDouble(),
              thumbSize.width,
              thumbSize.height,
            )
          : Rect.fromLTWH(
              along.truncateToDouble(),
              ((size.height - thumbSize.height) / 2).truncateToDouble(),
              thumbSize.width,
              thumbSize.height,
            );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton || value == null) return;
          WasabiPointerClaim.claim?.call(event);
          final local = event.localPosition;
          final along = _vertical ? local.dy : local.dx;
          final start = _offsetFor(value, thumbSize);
          final extent = _vertical ? thumbSize.height : thumbSize.width;
          // Grabbing the thumb keeps it under the pointer; elsewhere it
          // jumps there (SliderWnd::onLeftButtonDown).
          _grab = along - start;
          if (_grab < 0 || _grab > extent) _grab = extent / 2 - 2;
          final next = _valueAt(local, thumbSize);
          setState(() => _dragValue = next);
          _set(next, done: false);
        },
        onPointerMove: (event) {
          if (_dragValue == null) return;
          final next = _valueAt(event.localPosition, thumbSize);
          if (next == _dragValue) return;
          setState(() => _dragValue = next);
          _set(next, done: false);
        },
        onPointerUp: (event) {
          final last = _dragValue;
          if (last == null) return;
          setState(() => _dragValue = null);
          _set(last, done: true);
        },
        onPointerCancel: (_) => setState(() => _dragValue = null),
        child: SizedBox.fromSize(
          size: size,
          child: object["#builtin"] == "1"
              ? _BuiltinSliderPaint(
                  vertical: _vertical,
                  thumb: thumbRect,
                  down: _dragValue != null,
                )
              : thumb == null || thumbRect == null
              ? null
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fromRect(
                      rect: thumbRect,
                      child: _BitmapPaint(
                        bitmap: thumb,
                        alpha: scope.alphaOf(object),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// --- GroupXFade --------------------------------------------------------------

/// A `<GroupXFade>`: shows the group its `groupid` names, fading from the
/// one before over `speed` seconds (`GroupXFade::setNewGroup`). The classic player
/// Modern's options pages change this way.
class _XFadeView extends StatefulWidget {
  const _XFadeView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_XFadeView> createState() => _XFadeViewState();
}

class _XFadeViewState extends State<_XFadeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    value: 1,
  );

  /// The group shown, and the one it is taking over from.
  WasabiObject? _shown;
  WasabiObject? _leaving;

  WasabiObject? get _current {
    for (final child in widget.object.children) {
      if (child.visible) return child;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _shown = _current;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (!identical(current, _shown)) {
      _leaving = _shown;
      _shown = current;
      final seconds = double.tryParse(widget.object["speed"] ?? "") ?? 0;
      _fade.duration = Duration(milliseconds: (seconds * 1000).round());
      unawaited(
        _fade.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _leaving = null);
        }),
      );
    }
    final shown = _shown;
    final leaving = _leaving;
    final size = widget.size;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (leaving != null)
          Positioned.fill(
            // The group on its way out no longer takes the mouse.
            child: IgnorePointer(
              child: FadeTransition(
                opacity: ReverseAnimation(_fade),
                child: _GroupBody(group: leaving, size: size),
              ),
            ),
          ),
        if (shown != null)
          Positioned.fill(
            child: FadeTransition(
              opacity: _fade,
              child: _GroupBody(group: shown, size: size),
            ),
          ),
      ],
    );
  }
}

// --- Grid and status ---------------------------------------------------------

/// A `<Grid>`: up to nine bitmaps, the corners at their own size and the
/// sides and `middle` stretched between them (`Grid::doPaint`). The classic player
/// Modern's drawer tabs are a `left`, a `middle` and a `right`.
/// A `<progressgrid>`: its `middle` bitmap, with `right` as the end cap,
/// from the left edge as far as the song has played (the seek position).
class _ProgressGridView extends StatelessWidget {
  const _ProgressGridView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    final middle = skin.bitmap(object["middle"]);
    final right = skin.bitmap(object["right"]);
    return ListenableBuilder(
      listenable: scope.host,
      builder: (context, _) => CustomPaint(
        painter: _ProgressGridPainter(
          middle: middle,
          right: right,
          image: middle?.image,
          capImage: right?.image,
          value: (scope.host.sliderValue("SEEK", null) ?? 0).clamp(0.0, 1.0),
          alpha: scope.alphaOf(object),
        ),
      ),
    );
  }
}

class _ProgressGridPainter extends CustomPainter {
  _ProgressGridPainter({
    required this.middle,
    required this.right,
    required this.image,
    required this.capImage,
    required this.value,
    required this.alpha,
  });

  final WasabiBitmap? middle;
  final WasabiBitmap? right;
  final ui.Image? image;
  final ui.Image? capImage;
  final double value;
  final int alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final filled = size.width * value;
    if (alpha == 0 || size.isEmpty || filled <= 0) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromARGB(alpha, 255, 255, 255);
    final capWidth = math.min(right?.width ?? 0, filled);
    final image = middle?.image;
    final capImage = right?.image;
    if (middle != null && image != null && filled > capWidth) {
      canvas.drawImageRect(
        image,
        middle!.src,
        Rect.fromLTRB(0, 0, filled - capWidth, size.height),
        paint,
      );
    }
    if (right != null && capImage != null && capWidth > 0) {
      canvas.drawImageRect(
        capImage,
        right!.src,
        Rect.fromLTRB(filled - capWidth, 0, filled, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressGridPainter old) =>
      old.value != value ||
      old.image != image ||
      old.capImage != capImage ||
      old.alpha != alpha;
}

class _GridView extends StatelessWidget {
  const _GridView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    return CustomPaint(
      painter: _GridPainter(
        cells: [
          for (final name in _GridPainter.names) skin.bitmap(object[name]),
        ],
        alpha: scope.alphaOf(object),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.cells, required this.alpha})
    : images = [for (final cell in cells) cell?.image];

  static const List<String> names = [
    "topleft",
    "top",
    "topright",
    "left",
    "middle",
    "right",
    "bottomleft",
    "bottom",
    "bottomright",
  ];

  /// The bitmaps, in the order of [names].
  final List<WasabiBitmap?> cells;

  /// The pictures of [cells] in the color theme they are painted in.
  final List<ui.Image?> images;
  final int alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha == 0 || size.isEmpty) return;
    final [
      topLeft,
      top,
      topRight,
      left,
      middle,
      right,
      bottomLeft,
      bottom,
      bottomRight,
    ] = cells;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromARGB(alpha, 255, 255, 255);
    void draw(WasabiBitmap? bitmap, Rect cell) {
      if (bitmap == null || cell.width <= 0 || cell.height <= 0) return;
      canvas.drawImageRect(bitmap.image, bitmap.src, cell, paint);
    }

    double w(WasabiBitmap? bitmap) => bitmap?.width ?? 0;
    double h(WasabiBitmap? bitmap) => bitmap?.height ?? 0;
    final r = Offset.zero & size;
    draw(topLeft, r.topLeft & (topLeft?.size ?? Size.zero));
    draw(
      top,
      Rect.fromLTRB(w(topLeft), 0, r.right - w(topRight), h(top)),
    );
    draw(
      topRight,
      Rect.fromLTRB(r.right - w(topRight), 0, r.right, h(topRight)),
    );
    draw(
      left,
      Rect.fromLTRB(0, h(topLeft), w(left), r.bottom - h(bottomLeft)),
    );
    draw(
      middle,
      Rect.fromLTRB(w(left), h(top), r.right - w(right), r.bottom - h(bottom)),
    );
    draw(
      right,
      Rect.fromLTRB(
        r.right - w(right),
        h(top),
        r.right,
        r.bottom - h(bottomRight),
      ),
    );
    draw(
      bottomLeft,
      Rect.fromLTRB(0, r.bottom - h(bottomLeft), w(bottomLeft), r.bottom),
    );
    draw(
      bottom,
      Rect.fromLTRB(
        w(bottomLeft),
        r.bottom - h(bottom),
        r.right - w(bottomRight),
        r.bottom,
      ),
    );
    draw(
      bottomRight,
      Rect.fromLTRB(
        r.right - w(bottomRight),
        r.bottom - h(bottomRight),
        r.right,
        r.bottom,
      ),
    );
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.alpha != alpha ||
      !listEquals(oldDelegate.cells, cells) ||
      !listEquals(oldDelegate.images, images);
}

/// A `<status>`: the bitmap for what the player is doing (`stopBitmap`,
/// `playBitmap`, `pauseBitmap`).
class _StatusView extends StatelessWidget {
  const _StatusView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final bitmap = scope.skin.bitmap(
      object[switch (scope.host.playbackStatus) {
        1 => "playbitmap",
        -1 => "pausebitmap",
        _ => "stopbitmap",
      }],
    );
    if (bitmap == null) return const SizedBox.shrink();
    return _BitmapPaint(bitmap: bitmap, alpha: scope.alphaOf(object));
  }
}

// --- Text --------------------------------------------------------------------

/// The static string of a `<text>` (a script's `setText`, or its `text` or
/// `default`). `:componentname` is the name of the window the text is in,
/// [componentName] (Amped Modern titles its playlist that way); the other
/// names the window manager fills in are empty.
String _staticText(WasabiObject object, {String? componentName}) {
  final text = object["#text"] ?? object["text"] ?? object["default"] ?? "";
  // A backslash and an `n` in a skin's text is a line break (Mercury's About
  // page writes its paragraphs that way).
  if (!text.startsWith(":")) return text.replaceAll(r"\n", "\n");
  return text.toLowerCase() == ":componentname" ? componentName ?? "" : "";
}

/// The TrueType style of a `<text>`, in [color].
TextStyle _textStyle(WasabiObject object, WasabiSkinData skin, Color color) =>
    TextStyle(
      fontFamily: skin.fontFamily(object["font"]),
      // Font sizes are pixels at 96 dpi turned into points
      // (TrueTypeFont_Win32::MakeFont).
      fontSize: object.intAttr("fontsize", 14) * 72 / 96,
      color: color,
      fontWeight: object.boolAttr("bold") ? FontWeight.bold : FontWeight.normal,
      fontStyle: object.boolAttr("italic")
          ? FontStyle.italic
          : FontStyle.normal,
      // `forcefixed`: every digit as wide as the others, so a time does not
      // shift as it counts.
      fontFeatures: object.boolAttr("forcefixed")
          ? const [FontFeature.tabularFigures()]
          : null,
      height: 1,
    );

/// The width a `<text>` asks for (`Text::getPreferences(SUGGESTED_W)`): its
/// string in its font, 4 pixels, and its paddings.
double wasabiTextAutoWidth(
  WasabiObject object,
  WasabiSkinData skin, {
  String? componentName,
}) {
  final text = _cased(
    object,
    _staticText(object, componentName: componentName),
  );
  final font = skin.bitmapFont(object["font"]);
  final double width;
  if (font != null) {
    width = font.textWidth(text).toDouble();
  } else {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _textStyle(object, skin, const Color(0xFFFFFFFF)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    width = painter.width.ceilToDouble();
    painter.dispose();
  }
  return width +
      4 +
      object.intAttr("leftpadding") +
      object.intAttr("rightpadding");
}

/// The height a `<text>` asks for (`Text::getPreferences(SUGGESTED_H)`): one
/// line of its font. Scripts that stack texts read it (`getAutoHeight`).
double wasabiTextAutoHeight(WasabiObject object, WasabiSkinData skin) {
  final font = skin.bitmapFont(object["font"]);
  if (font != null) return font.charHeight.toDouble();
  final painter = TextPainter(
    text: TextSpan(
      text: "Ag",
      style: _textStyle(object, skin, const Color(0xFFFFFFFF)),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

/// [text] in the case a `<text>` forces (`forceupcase`, `forcelowercase`
/// and their longer spellings).
String _cased(WasabiObject object, String text) {
  if (object.boolAttr("forceupcase") || object.boolAttr("forceuppercase")) {
    return text.toUpperCase();
  }
  if (object.boolAttr("forcelowercase") || object.boolAttr("forcelocase")) {
    return text.toLowerCase();
  }
  return text;
}

/// How a `<SongTicker>` moves a title that does not fit (`ticker`).
enum _TickerMode { off, scroll, bounce }

/// A `<text>` (`Text`): a static string or a live display (`display="time"`,
/// `"songname"`, ...) in a skin font, scrolled back and forth with
/// `ticker="1"` when it does not fit. A `<SongTicker>` (gen_ff's
/// `SongTicker`) shows the song title, and moves it as its `ticker` says:
/// `bounce` back and forth, `scroll` round and round, or `off`; the mouse
/// drags it.
/// An `<edit>`: a line of text to type in. Amped Modern's playlist search
/// box is one; it takes the keyboard focus when it comes up.
class _EditView extends StatefulWidget {
  const _EditView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.object["#text"] ?? widget.object["default"] ?? "",
  );
  final FocusNode _focus = FocusNode();
  int _focusAsked = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final scripts = scope.scripts;
    final skin = scope.skin;
    final object = widget.object;
    // A script that sets the text (clearing the box) moves the field too.
    final text = object["#text"];
    if (text != null && text != _controller.text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    // A script's `setFocus` (and `selectAll`) asks the field for the focus.
    final asked = object.intAttr("#focus");
    if (asked != _focusAsked) {
      _focusAsked = asked;
      final selectAll = object.attributes.remove("#selectall") == "1";
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        if (selectAll) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      });
    }
    final color = skin.color("wasabi.list.text") ?? const Color(0xFFFFFFFF);
    return Focus(
      // Typing must not reach the window's shortcuts (Space plays, Delete
      // removes tracks): stop keys without Ctrl, Alt or Cmd here. They still
      // go on to the text field below.
      onKeyEvent: (node, event) {
        // The edit's scripts hear the key (`onKeyDown`, `onKeyUp`, `onChar`).
        final vk = wasabiVirtualKey(event.logicalKey);
        if (vk != null && scripts != null) {
          final character = event.character;
          scripts.objectKey(
            object,
            vk,
            down: event is! KeyUpEvent,
            character:
                character != null &&
                    character.length == 1 &&
                    character.codeUnitAt(0) >= 0x20
                ? character
                : null,
          );
        }
        final keys = HardwareKeyboard.instance;
        return keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed
            ? KeyEventResult.ignored
            : KeyEventResult.skipRemainingHandlers;
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              scripts?.editCancelled(object),
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: EditableText(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            style: TextStyle(
              fontFamily: skin.fontFamily(object["font"] ?? "arial"),
              fontSize: object.intAttr("fontsize", 14) * 72 / 96,
              color: color,
            ),
            cursorColor: color,
            backgroundCursorColor: color,
            selectionColor: color.withValues(alpha: 0.3),
            maxLines: 1,
            onChanged: (value) {
              object.attributes["#text"] = value;
              if (scripts != null) {
                scripts.editChanged(object, value);
              } else {
                skin.playlistFilter.value = value;
              }
            },
            onSubmitted: (_) => scripts?.editSubmitted(object),
          ),
        ),
      ),
    );
  }
}

class _TextView extends StatefulWidget {
  const _TextView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView>
    with SingleTickerProviderStateMixin {
  /// The pause at either end of a ticker scroll (`TTS_DELAY`).
  static const Duration _pause = Duration(milliseconds: 4000);

  /// One pixel every other 25 ms tick (`Text Ticker Speed` 1/2).
  static const Duration _step = Duration(milliseconds: 50);

  /// A song ticker's pause at either end of a bounce
  /// (`SONGTICKER_SKIP_MS`).
  static const Duration _songPause = Duration(milliseconds: 2000);

  /// A song ticker moves a pixel every 13 ms at full speed, and at half
  /// speed unless told otherwise (`SONGTICKER_SCROLL_ONE_PIXEL_MS`,
  /// `Text Ticker Speed`).
  static const Duration _songStep = Duration(milliseconds: 26);

  /// What a scrolling song ticker puts between the end of the title and
  /// its start (`rotatingDisplay`).
  static const String _separator = " *** ";

  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  Duration _wait = _pause;
  Duration _carry = Duration.zero;
  double _scroll = 0;
  bool _backwards = false;
  double _overflow = 0;
  String _shown = "";

  /// A song ticker's mode, the width its scrolling text repeats after, and
  /// whether the mouse holds it.
  _TickerMode _mode = _TickerMode.off;
  double _wrap = 0;
  double? _grab;

  bool get _songTicker => widget.object.tag == "songticker";

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _last;
    if (_songTicker) {
      _last = elapsed;
      if (_overflow <= 0 || _grab != null || _mode == _TickerMode.off) return;
      if (_wait > Duration.zero) {
        _wait -= delta;
        return;
      }
      _carry += delta;
      final steps = _carry.inMicroseconds ~/ _songStep.inMicroseconds;
      if (steps == 0) return;
      _carry -= _songStep * steps;
      setState(() {
        _scroll += _backwards ? -steps : steps;
        _keepInRange();
      });
      return;
    }
    if (delta < _step) return;
    _last = elapsed;
    if (_overflow <= 0) return;
    if (_wait > Duration.zero) {
      _wait -= delta;
      return;
    }
    setState(() {
      _scroll += _backwards ? -1 : 1;
      if (_scroll >= _overflow) {
        _scroll = _overflow;
        _backwards = true;
        _wait = _pause;
      } else if (_scroll <= 0) {
        _scroll = 0;
        _backwards = false;
        _wait = _pause;
      }
    });
  }

  /// Keeps a song ticker's position where its mode lets it be, turning a
  /// bouncing one around at either end (`SongTicker::getBufferPaintSource`).
  void _keepInRange() {
    switch (_mode) {
      case _TickerMode.off:
        _scroll = _scroll.clamp(0, math.max(0, _overflow));
      case _TickerMode.scroll:
        if (_wrap > 0) _scroll %= _wrap;
      case _TickerMode.bounce:
        if (_scroll >= _overflow) {
          _scroll = math.max(0, _overflow - 1);
          _backwards = true;
          _wait = _songPause;
        }
        if (_scroll < 0) {
          _scroll = 0;
          _backwards = false;
          _wait = _songPause;
        }
    }
  }

  String _text(WasabiHost host, String? bucketText, String? componentName) {
    final object = widget.object;
    final display = _display(object) ?? "";
    String text;
    // A script's setText wins over the display.
    final scripted = object["#text"];
    switch (scripted == null ? display : "#text") {
      case "#text":
        text = scripted!;
      case "time":
        text = wasabiTimeText(host, object);
      case "songname" || "songtitle":
        text = host.songTitle;
        // A SongTicker always adds the length (SongTicker::BuildTitle).
        if ((_songTicker || object.boolAttr("showlen")) && host.lengthMs > 0) {
          text += " (${_minSec(host.lengthMs ~/ 1000)})";
        }
      case "tracktitle":
        // Just the track: the artist has a line of its own.
        final title = host.playItemMetadata("title");
        text = title.isEmpty ? host.trackTitle : title;
        if (host.lengthMs > 0) text += " (${_minSec(host.lengthMs ~/ 1000)})";
      case "songartist":
        text = host.playItemMetadata("artist");
      case "songalbum":
        final album = host.playItemMetadata("album");
        final track = host.playItemMetadata("track");
        text = track.isEmpty || album.isEmpty ? album : "$album (Track $track)";
      case "playlistposition":
        text = host.playlistLength == 0
            ? ""
            : "${host.playlistCurrent + 1} of ${host.playlistLength}";
      case "notifierstatus":
        text = switch (host.playbackStatus) {
          1 => "  New track  ",
          -1 => "  Playback paused  ",
          _ => "  Playback stopped  ",
        };
      case "songlength":
        text = host.lengthMs > 0 ? _minSec(host.lengthMs ~/ 1000) : "";
      case "pe_info":
        text = wasabiPlaylistInfo(host);
      case "vid_info":
        text = host.videoInfoText;
      case "componentbucket":
        text = bucketText ?? "";
      default:
        text = _staticText(object, componentName: componentName);
    }
    return _cased(object, text);
  }

  /// What a text shows: `display`, or the song title for a SongTicker.
  static String? _display(WasabiObject object) =>
      object["display"]?.toLowerCase() ??
      (object.tag == "songticker" ? "songtitle" : null);

  static String _minSec(int seconds) {
    final s = seconds.abs();
    return "${s ~/ 60}:${(s % 60).toString().padLeft(2, "0")}";
  }

  /// A song ticker's `ticker`: `bounce`, `scroll` (also when it says
  /// nothing) or `off`. Other values are other skins' on/off switches.
  static _TickerMode _tickerMode(WasabiObject object) =>
      switch (object["ticker"]?.trim().toLowerCase()) {
        "bounce" => _TickerMode.bounce,
        "off" || "0" => _TickerMode.off,
        "1" => _TickerMode.bounce,
        _ => _TickerMode.scroll,
      };

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final object = widget.object;
    final skin = scope.skin;
    final text = _text(
      scope.host,
      _BucketText.of(context)?.value,
      skin.container(scope.container)?.name,
    );
    final color = skin.color(object["color"]) ?? const Color(0xFFFFFFFF);
    final alpha = scope.alphaOf(object);
    final bitmapFont = skin.bitmapFont(object["font"]);
    final style = _textStyle(
      object,
      skin,
      color.withAlpha(color.a == 1 ? alpha : (color.a * alpha).round()),
    );
    // A shadow given as numbers is in the `Text backgrounds` gamma group
    // (Text::Text); a color element is in its own.
    final shadowColor = skin.color(
      object["shadowcolor"],
      defaultGroup:
          skin.colors.containsKey(object["shadowcolor"]?.trim().toLowerCase())
          ? "Text"
          : "Text backgrounds",
    );
    final shadowOffset = Offset(
      object.intAttr("shadowx").toDouble(),
      object.intAttr("shadowy").toDouble(),
    );
    // A shadow close to the text's own color (a color theme can bring them
    // together) only smears the text into a blurry double.
    final shadow =
        shadowColor == null ||
            shadowOffset == Offset.zero ||
            (shadowColor.computeLuminance() - color.computeLuminance()).abs() <
                0.25
        ? null
        : (color: shadowColor, offset: shadowOffset);
    final runs = <_TextRun>[];
    _TextRun run(String string, double x, {double? wrapWidth}) {
      final made = bitmapFont != null
          ? _BitmapRun(font: bitmapFont, text: string, alpha: alpha, x: x)
          : _TypeRun(
              text: string,
              style: style,
              shadow: shadow?.color,
              x: x,
              wrapWidth: wrapWidth,
              align: switch (object["align"]?.toLowerCase()) {
                "center" => TextAlign.center,
                "right" => TextAlign.right,
                _ => TextAlign.left,
              },
            );
      runs.add(made);
      return made;
    }

    final width = widget.size.width;
    final leftPadding = object.intAttr("leftpadding").toDouble();
    final rightPadding = object.intAttr("rightpadding").toDouble();
    final offsetX = object.intAttr("offsetx").toDouble();
    final align = object["align"]?.toLowerCase() ?? "left";
    final display = _display(object);
    final colon = display == "time" ? text.indexOf(":") : -1;
    var overflow = 0.0;
    var wrap = 0.0;
    final mode = _songTicker ? _tickerMode(object) : _TickerMode.off;
    double height;
    if (colon >= 0) {
      // The time, drawn as minutes, a colon and seconds so the colon can
      // be narrower than a digit (`timecolonwidth`).
      final minutes = run(text.substring(0, colon), 0);
      final separator = run(":", 0);
      final seconds = run(text.substring(colon + 1), 0);
      final colonWidth =
          object.optInt("timecolonwidth")?.toDouble() ?? separator.width;
      final total = minutes.width + colonWidth + seconds.width;
      final x =
          offsetX +
          switch (align) {
            "center" => ((width - total) / 2).truncateToDouble(),
            "right" => width - 2 - rightPadding - total,
            _ => 2 + leftPadding,
          };
      minutes.x = x;
      separator.x = x + minutes.width;
      seconds.x = x + minutes.width + colonWidth;
      height = minutes.height;
    } else if (_songTicker) {
      // SongTicker::onBufferPaint: the title from the left padding on, in
      // a box as wide as the ticker or the title, whichever is wider.
      final title = run(text, 0);
      final padded = title.width + leftPadding - rightPadding;
      overflow = math.max(0, padded - width);
      var shown = title;
      if (overflow > 0 && mode == _TickerMode.scroll) {
        runs.clear();
        shown = run("$text$_separator$text", 0);
        wrap = shown.width - title.width;
      }
      final box = math.max(width - leftPadding + rightPadding, shown.width);
      shown.x = leftPadding + _aligned(align, box - shown.width);
      height = shown.height;
    } else if (object.boolAttr("wrap") && bitmapFont == null) {
      // `wrap="1"`: lines broken to the box (`Canvas::textOutWrapped`).
      final room = math.max(1.0, width - 2 - leftPadding - rightPadding);
      final block = run(text, 2 + leftPadding + offsetX, wrapWidth: room);
      height = block.height;
    } else {
      final line = run(text, 0);
      final fits = line.width <= width - 2 - leftPadding - rightPadding;
      // Text wider than its box starts at the left so it can scroll.
      final padded = !fits || align != "center";
      final ticker = object.boolAttr("ticker");
      overflow = ticker ? math.max(0, line.width - (width - 2)) : 0;
      line.x =
          2 +
          (padded ? leftPadding : 0) +
          offsetX +
          (fits ? _aligned(align, width - 2 - line.width) : 0);
      height = line.height;
    }
    if (text != _shown ||
        overflow != _overflow ||
        mode != _mode ||
        wrap != _wrap) {
      final moved = text != _shown || mode != _mode || overflow <= 0;
      _shown = text;
      _overflow = overflow;
      _mode = mode;
      _wrap = wrap;
      if (moved) {
        _scroll = 0;
        _backwards = false;
        _carry = Duration.zero;
        // A song ticker starts moving at once; a text waits first.
        _wait = _songTicker ? Duration.zero : _pause;
      } else if (_songTicker) {
        _keepInRange();
      }
    }
    final moving = overflow > 0 && (!_songTicker || mode != _TickerMode.off);
    if (moving && !_ticker.isActive) {
      _last = Duration.zero;
      unawaited(_ticker.start());
    } else if (!moving && _ticker.isActive) {
      _ticker.stop();
    }
    final y =
        (object["valign"]?.toLowerCase() == "top"
            ? 0.0
            : ((widget.size.height - height) / 2).truncateToDouble()) +
        object.intAttr("offsety");
    final paint = CustomPaint(
      size: widget.size,
      painter: _TextPainter(
        runs: runs,
        origin: Offset(-_scroll, y),
        shadow: shadow?.offset,
      ),
    );
    if (display == "time") {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => scope.host.toggleTimeRemaining(),
        child: paint,
      );
    }
    // `nograb` keeps the mouse from dragging the title.
    if (!_songTicker || overflow <= 0 || object.boolAttr("nograb")) {
      return paint;
    }
    // The mouse drags a title that does not fit.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        WasabiPointerClaim.claim?.call(event);
        _grab = event.localPosition.dx + _scroll;
      },
      onPointerMove: (event) {
        final grab = _grab;
        if (grab == null) return;
        setState(() {
          _scroll = (grab - event.localPosition.dx).roundToDouble();
          _keepInRange();
        });
      },
      onPointerUp: (_) => _grab = null,
      onPointerCancel: (_) => _grab = null,
      child: paint,
    );
  }

  /// Where text with [room] to spare starts in its box.
  static double _aligned(String align, double room) => switch (align) {
    "center" => (room / 2).truncateToDouble(),
    "right" => room,
    _ => 0,
  };
}

/// A string in a skin font, at [x] in its text box.
abstract class _TextRun {
  _TextRun(this.x);

  double x;

  double get width;
  double get height;

  /// Draws the string at [origin]; [shadow] draws its shadow instead.
  void paint(Canvas canvas, Offset origin, {required bool shadow});

  /// Whether [other] draws the same thing.
  bool same(_TextRun other);
}

/// A string in a TrueType font.
class _TypeRun extends _TextRun {
  _TypeRun({
    required this.text,
    required this.style,
    required this.shadow,
    required double x,
    this.wrapWidth,
    this.align = TextAlign.left,
  }) : super(x);

  final String text;
  final TextStyle style;

  /// The shadow's color, when the text has one.
  final Color? shadow;

  /// The width the text wraps at (`wrap="1"`), or null for one line.
  final double? wrapWidth;
  final TextAlign align;

  late final TextPainter _painter = _painterOf(style);

  TextPainter _painterOf(TextStyle style) => wrapWidth == null
      ? (TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout())
      : (TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textAlign: align,
        )..layout(minWidth: wrapWidth!, maxWidth: wrapWidth!));

  @override
  double get width => _painter.width;

  @override
  double get height => _painter.height;

  @override
  void paint(Canvas canvas, Offset origin, {required bool shadow}) {
    if (!shadow) {
      _painter.paint(canvas, origin + Offset(x, 0));
      return;
    }
    _painterOf(style.copyWith(color: this.shadow)).paint(
      canvas,
      origin + Offset(x, 0),
    );
  }

  @override
  bool same(_TextRun other) =>
      other is _TypeRun &&
      other.text == text &&
      other.style == style &&
      other.shadow == shadow &&
      other.wrapWidth == wrapWidth &&
      other.align == align &&
      other.x == x;

  @override
  String toString() => text;
}

/// A string in a bitmap font: its characters copied out of the font's
/// table, each [WasabiBitmapFont.advance] after the last
/// (`BitmapFont::do_textOut`). The font's picture has its own colors, so
/// a shadow is the same picture again.
class _BitmapRun extends _TextRun {
  _BitmapRun({
    required this.font,
    required this.text,
    required this.alpha,
    required double x,
  }) : image = font.table.image,
       super(x);

  final WasabiBitmapFont font;
  final String text;
  final int alpha;

  /// The font's picture in the color theme the string is painted in.
  final ui.Image image;

  @override
  double get width => font.textWidth(text).toDouble();

  @override
  double get height => font.charHeight.toDouble();

  @override
  void paint(Canvas canvas, Offset origin, {required bool shadow}) {
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromARGB(alpha, 255, 255, 255);
    final table = font.table;
    final size = Size(font.charWidth.toDouble(), font.charHeight.toDouble());
    // C's `hor_spacing / 2`, which rounds toward zero.
    var left = origin.dx + x + (font.hSpacing / 2).truncateToDouble();
    for (final code in text.runes) {
      final glyph = font.glyph(code);
      // A table too small for a character draws nothing for it.
      if (glyph.dx + size.width <= table.width &&
          glyph.dy + size.height <= table.height) {
        canvas.drawImageRect(
          image,
          (table.src.topLeft + glyph) & size,
          Offset(left, origin.dy) & size,
          paint,
        );
      }
      left += font.advance;
    }
  }

  @override
  bool same(_TextRun other) =>
      other is _BitmapRun &&
      identical(other.font, font) &&
      other.image == image &&
      other.text == text &&
      other.alpha == alpha &&
      other.x == x;

  @override
  String toString() => text;
}

class _TextPainter extends CustomPainter {
  _TextPainter({
    required this.runs,
    required this.origin,
    required this.shadow,
  });

  /// What to draw, each at its own `x`.
  final List<_TextRun> runs;

  /// Where the text box's left edge and the text's top are.
  final Offset origin;

  /// How far the shadow is from the text, when it has one.
  final Offset? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final shadow = this.shadow;
    if (shadow != null) {
      for (final run in runs) {
        run.paint(canvas, origin + shadow, shadow: true);
      }
    }
    for (final run in runs) {
      run.paint(canvas, origin, shadow: false);
    }
    canvas.restore();
  }

  @override
  String toString() => "_TextPainter(${runs.join()})";

  @override
  bool shouldRepaint(_TextPainter oldDelegate) {
    if (oldDelegate.origin != origin ||
        oldDelegate.shadow != shadow ||
        oldDelegate.runs.length != runs.length) {
      return true;
    }
    for (var i = 0; i < runs.length; i++) {
      if (!runs[i].same(oldDelegate.runs[i])) return true;
    }
    return false;
  }
}

/// How a `<vis>` draws: the player's classic visualization options, with
/// whatever the skin's scripts set on the object in their place (`setMode`,
/// and the `bandwidth`, `oscstyle`, `peaks` and `coloring` parameters).
/// Amped Modern's `visualizer.maki` keeps its own mode this way.
ClassicVisOptions wasabiVisOptions(
  WasabiObject object,
  ClassicVisOptions options,
) {
  String? param(String name) => object[name]?.trim().toLowerCase();
  return options.copyWith(
    mode: switch (object.optInt("#mode")) {
      0 => ClassicVisMode.off,
      1 => ClassicVisMode.spectrum,
      2 => ClassicVisMode.oscilloscope,
      _ => null,
    },
    thinBands: switch (param("bandwidth")) {
      "thin" => true,
      "wide" => false,
      _ => null,
    },
    scopeStyle: switch (param("oscstyle")) {
      "solid" => ScopeStyle.solid,
      "dots" => ScopeStyle.dots,
      "lines" => ScopeStyle.lines,
      _ => null,
    },
    peaks: switch (param("peaks")) {
      "1" => true,
      "0" => false,
      _ => null,
    },
    analyzerStyle: switch (param("coloring")) {
      "normal" => AnalyzerStyle.normal,
      "fire" => AnalyzerStyle.fire,
      "line" => AnalyzerStyle.line,
      _ => null,
    },
  );
}

// --- Visualization -----------------------------------------------------------

/// The gamma group of what the analyzer and the equalizer's curve draw
/// (`QuickPaintWnd::getFiltersGroup`, `SEQVis::onQuickPaint`).
const String _visGroup = "Vis/Eq";

/// The 24 colors a `<vis>` draws with: [defaults] (the classic ones), in the
/// color theme, then the skin's own (`SAWnd::setBandColor`, `setOscColor`).
/// `colorband1` is the lowest band, drawn with palette entry 17, and
/// `colorband16` the highest, entry 2; `colorallbands` sets all sixteen
/// first, and `colorallosc` the first four oscilloscope colors.
List<int> wasabiVisPalette(
  WasabiObject object,
  WasabiSkinData skin,
  List<int> defaults,
) {
  // The whole picture is in one gamma group (`gammagroup`, or SAWnd's
  // `Vis/Eq`), the colors the skin does not give too.
  final named = object["gammagroup"]?.trim() ?? "";
  final group = named.isEmpty ? _visGroup : named;
  final gamma = skin.colorThemes.applied?.resolve(group);
  final palette = [
    defaults.first,
    for (final color in defaults.skip(1))
      gamma == null ? color : gamma.filterColor(Color(color)).toARGB32(),
  ];
  final allBands = skin.color(object["colorallbands"], group: group);
  if (allBands != null) {
    for (var i = 2; i <= 17; i++) {
      palette[i] = allBands.toARGB32();
    }
  }
  for (var i = 1; i <= 16; i++) {
    final color = skin.color(object["colorband$i"], group: group);
    if (color != null) palette[18 - i] = color.toARGB32();
  }
  final allOsc = skin.color(object["colorallosc"], group: group);
  if (allOsc != null) {
    for (var i = 18; i <= 21; i++) {
      palette[i] = allOsc.toARGB32();
    }
  }
  for (var i = 1; i <= 5; i++) {
    final color = skin.color(object["colorosc$i"], group: group);
    if (color != null) palette[i + 17] = color.toARGB32();
  }
  final peak = skin.color(object["colorbandpeak"], group: group);
  if (peak != null) palette[23] = peak.toARGB32();
  return palette;
}

/// A `<vis>` (`SAWnd`): the classic 72×16 analyzer picture stretched over the
/// box, in the skin's `colorband*`/`colorosc*`/`colorbandpeak` colors, on a
/// transparent background.
class _VisView extends StatefulWidget {
  const _VisView({required this.object});

  final WasabiObject object;

  @override
  State<_VisView> createState() => _VisViewState();
}

class _VisViewState extends State<_VisView> {
  static const List<int> _defaultPalette = [
    0xFF000000, 0xFF4B4850, //
    0xFFFF3710, 0xFFFF3710, 0xFFFF5000, 0xFFFF5000, 0xFFEF7000, 0xFFEF7000,
    0xFFFFA820, 0xFFFFA820, 0xFFB0FF2F, 0xFFB0FF2F, 0xFF2FEF00, 0xFF2FEF00,
    0xFF30A000, 0xFF30A000, 0xFF208000, 0xFF208000, //
    0xFFFFFFFF, 0xFFD6D6DE, 0xFFB5BDBD, 0xFFA0AAAF, 0xFF949CA5, //
    0xFF969696,
  ];

  final ClassicVisController _controller = ClassicVisController();
  Timer? _timer;
  WasabiHost? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = _WasabiScope.of(context).host;
    if (host == _host) return;
    _host?.stopVisualization();
    _host = host..startVisualization();
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _host?.stopVisualization();
    _controller.dispose();
    super.dispose();
  }

  void _tick() {
    final host = _host;
    if (host == null) return;
    final options = wasabiVisOptions(widget.object, host.visOptions);
    final samples = host.visSamples;
    _controller.tick(
      running: host.visRunning && options.mode != ClassicVisMode.off,
      keepPicture: false,
      options: options,
      windowShade: false,
      left: samples?.$1,
      right: samples?.$2,
    );
  }

  List<int> _palette(WasabiSkinData skin) =>
      wasabiVisPalette(widget.object, skin, _defaultPalette);

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _host?.clickVis(),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => CustomPaint(
          painter: _controller.showing
              ? _VisPainter(
                  picture: _controller.picture!,
                  colors: _palette(skin),
                  frame: _controller.frame,
                  alpha: scope.alphaOf(widget.object),
                  flipH: widget.object.intAttr("fliph") != 0,
                  flipV: widget.object.intAttr("flipv") != 0,
                )
              : null,
        ),
      ),
    );
  }
}

class _VisPainter extends CustomPainter {
  _VisPainter({
    required this.picture,
    required this.colors,
    required this.frame,
    required this.alpha,
    this.flipH = false,
    this.flipV = false,
  });

  final ClassicVisPicture picture;
  final List<int> colors;
  final int frame;
  final int alpha;

  /// `fliph` / `flipv`: the picture mirrored.
  final bool flipH;
  final bool flipV;

  @override
  void paint(Canvas canvas, Size size) {
    // `getQuickPaintSource`: the left 72×16 of the picture.
    canvas
      ..save()
      ..scale(size.width / 72, size.height / 16);
    if (flipH)
      canvas
        ..translate(72, 0)
        ..scale(-1, 1);
    if (flipV)
      canvas
        ..translate(0, 16)
        ..scale(1, -1);
    final paths = <int, Path>{};
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 72; x++) {
        final index = picture.pixelAt(x, y);
        // Colors 0 and 1 (the background and its dots) stay transparent.
        if (index < 2 || index >= colors.length) continue;
        (paths[index] ??= Path()).addRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
        );
      }
    }
    for (final MapEntry(key: index, value: path) in paths.entries) {
      canvas.drawPath(
        path,
        Paint()..color = Color(colors[index]).withAlpha(alpha),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VisPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.colors != colors ||
      oldDelegate.flipH != flipH ||
      oldDelegate.flipV != flipV;
}

// --- EQ graph ----------------------------------------------------------------

/// An `<eqvis>` (`SEQVis`): the EQ curve through the ten bands, colored
/// from `colortop` through `colormiddle` to `colorbottom`, with the preamp
/// level as a line in `colorpreamp`.
class _EqVisView extends StatelessWidget {
  const _EqVisView({required this.object});

  final WasabiObject object;

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final skin = scope.skin;
    final host = scope.host;
    return CustomPaint(
      painter: _EqVisPainter(
        bands: [
          for (var i = 1; i <= 10; i++)
            host.sliderValue("EQ_BAND", "$i") ?? 0.5,
        ],
        preamp: host.sliderValue("EQ_PREAMP", null) ?? 0.5,
        top:
            skin.color(object["colortop"], group: _visGroup) ??
            const Color(0xFFFF0000),
        middle:
            skin.color(object["colormiddle"], group: _visGroup) ??
            const Color(0xFFFFFF00),
        bottom:
            skin.color(object["colorbottom"], group: _visGroup) ??
            const Color(0xFF00FF00),
        preampColor:
            skin.color(object["colorpreamp"], group: _visGroup) ??
            const Color(0xFFFFFFFF),
        alpha: scope.alphaOf(object),
      ),
    );
  }
}

class _EqVisPainter extends CustomPainter {
  _EqVisPainter({
    required this.bands,
    required this.preamp,
    required this.top,
    required this.middle,
    required this.bottom,
    required this.preampColor,
    required this.alpha,
  });

  final List<double> bands;
  final double preamp;
  final Color top;
  final Color middle;
  final Color bottom;
  final Color preampColor;
  final int alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    double yFor(double value) =>
        ((1 - value) * (size.height - 1)).roundToDouble();
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    canvas.drawRect(
      Rect.fromLTWH(0, yFor(preamp), size.width, 1),
      Paint()..color = preampColor.withAlpha(alpha),
    );
    // A Catmull-Rom curve through the bands, one pixel per column.
    final points = <Offset>[];
    for (var x = 0; x < size.width; x++) {
      final t = x / math.max(1, size.width - 1) * 9;
      final i = t.floor().clamp(0, 8);
      final f = t - i;
      double at(int k) => bands[k.clamp(0, 9)];
      final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
      final v =
          0.5 *
          (2 * p1 +
              (-p0 + p2) * f +
              (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f +
              (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f);
      points.add(Offset(x + 0.5, yFor(v.clamp(0.0, 1.0)) + 0.5));
    }
    final shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      [
        top.withAlpha(alpha),
        middle.withAlpha(alpha),
        bottom.withAlpha(alpha),
      ],
      const [0, 0.5, 1],
    );
    canvas
      ..drawPoints(
        ui.PointMode.polygon,
        points,
        Paint()
          ..shader = shader
          ..strokeWidth = 1,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_EqVisPainter oldDelegate) =>
      oldDelegate.preamp != preamp || !_listEquals(oldDelegate.bands, bands);

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A push button drawn from a skin's `wasabi.button.*` pieces, the way
/// Wasabi's standard button is: nine pieces (`top.left`, `top`, ... or the
/// three of `left`, `middle`, `right`), in a normal, `hover.` and `pressed.`
/// look, with the label in `wasabi.button.text` (`dimmedText` when off).
/// Null from [WasabiGridButton.supported] when the skin draws no buttons.
class WasabiGridButton extends StatefulWidget {
  const WasabiGridButton({
    required this.skin,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.height = 20,
    this.padding = 10,
    super.key,
  });

  final WasabiSkinData skin;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final double height;
  final double padding;

  /// Whether [skin] has pieces to draw a button from.
  static bool supported(WasabiSkinData skin) =>
      skin.bitmap("wasabi.button.center") != null ||
      skin.bitmap("wasabi.button.middle") != null;

  @override
  State<WasabiGridButton> createState() => _WasabiGridButtonState();
}

class _WasabiGridButtonState extends State<WasabiGridButton> {
  bool _hover = false;
  bool _down = false;

  /// The average color of the button's face in the look it has now, once
  /// read, and the picture it was read from.
  Color? _face;
  ui.Image? _faceOf;
  WasabiBitmap? _faceBitmap;

  /// Reads the face of [piece] (the picture a color theme gives it).
  Future<void> _readFace(WasabiBitmap piece) async {
    final image = piece.image;
    _faceOf = image;
    _faceBitmap = piece;
    final data = await image.toByteData();
    if (data == null || !mounted || _faceOf != image) return;
    final src = piece.src;
    var red = 0, green = 0, blue = 0, count = 0;
    for (var y = src.top.floor(); y < src.bottom.ceil(); y++) {
      for (var x = src.left.floor(); x < src.right.ceil(); x++) {
        final at = (y * image.width + x) * 4;
        if (x < 0 ||
            y < 0 ||
            x >= image.width ||
            at + 3 >= data.lengthInBytes) {
          continue;
        }
        if (data.getUint8(at + 3) < 128) continue;
        red += data.getUint8(at);
        green += data.getUint8(at + 1);
        blue += data.getUint8(at + 2);
        count++;
      }
    }
    if (count == 0) return;
    setState(
      () => _face = Color.fromARGB(
        255,
        red ~/ count,
        green ~/ count,
        blue ~/ count,
      ),
    );
  }

  WasabiBitmap? _piece(String state, String name) =>
      widget.skin.bitmap("wasabi.button.$state$name") ??
      (state.isEmpty ? null : widget.skin.bitmap("wasabi.button.$name"));

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final enabled = widget.enabled;
    final state = !enabled
        ? ""
        : _down
        ? "pressed."
        : _hover
        ? "hover."
        : "";
    final three = skin.bitmap("wasabi.button.center") == null;
    var color =
        skin.color(
          enabled
              ? (_hover || _down
                    ? "wasabi.button.hiliteText"
                    : "wasabi.button.text")
              : "wasabi.button.dimmedText",
        ) ??
        const Color(0xFFFFFFFF);
    // A color theme can leave the label too close to the face.
    final face = _piece(state, three ? "middle" : "center");
    if (face != null && (face != _faceBitmap || face.image != _faceOf)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (face != _faceBitmap || face.image != _faceOf)) {
          unawaited(_readFace(face));
        }
      });
    }
    if (_face case final background?) {
      color = wasabiLegible(color, background);
    }
    final text = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, height: 1, color: color),
    );
    Widget pieces(BoxConstraints box) {
      final width = box.maxWidth;
      final height = widget.height;
      final children = <Widget>[];
      void put(WasabiBitmap? b, double x, double y, double w, double h) {
        if (b == null || w <= 0 || h <= 0) return;
        children.add(
          Positioned(
            left: x,
            top: y,
            width: w,
            height: h,
            child: _BitmapPaint(bitmap: b),
          ),
        );
      }

      if (three) {
        final left = _piece(state, "left");
        final right = _piece(state, "right");
        final lw = left?.width ?? 0.0;
        final rw = right?.width ?? 0.0;
        put(left, 0, 0, lw, height);
        put(_piece(state, "middle"), lw, 0, width - lw - rw, height);
        put(right, width - rw, 0, rw, height);
      } else {
        final tl = _piece(state, "top.left");
        final tr = _piece(state, "top.right");
        final bl = _piece(state, "bottom.left");
        final br = _piece(state, "bottom.right");
        final l = tl?.width ?? 0.0;
        final r = tr?.width ?? 0.0;
        final t = tl?.height ?? 0.0;
        final b = bl?.height ?? 0.0;
        final mw = width - l - r;
        final mh = height - t - b;
        put(tl, 0, 0, l, t);
        put(_piece(state, "top"), l, 0, mw, t);
        put(tr, width - r, 0, r, t);
        put(_piece(state, "left"), 0, t, l, mh);
        put(_piece(state, "center"), l, t, mw, mh);
        put(_piece(state, "right"), width - r, t, r, mh);
        put(bl, 0, height - b, l, b);
        put(_piece(state, "bottom"), l, height - b, mw, b);
        put(br, width - r, height - b, r, b);
      }
      return Stack(fit: StackFit.expand, children: children);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled ? widget.onPressed : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 40, minHeight: widget.height),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: LayoutBuilder(builder: (context, box) => pieces(box)),
              ),
              SizedBox(
                height: widget.height,
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: widget.padding),
                    child: text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rectangles of the components (`<component>`, `<windowholder>`) and
/// the buttons in [layout], in layout pixels: where its window, not the
/// frame drawn over it, has the mouse.
List<Rect> _componentRects(WasabiSkinData skin, WasabiLayout layout) {
  final rects = <Rect>[];
  if (layout.root["#hidden"] == "1") return rects;
  void visit(WasabiObject group, Rect area) {
    for (final child in group.children) {
      if (!child.visible) continue;
      final rect = wasabiObjectRect(child, area.size, skin).shift(area.topLeft);
      final spec = (child["param"] ?? child["hold"] ?? "").toLowerCase();
      if ((child.tag == "component" || child.tag == "windowholder") &&
          (wasabiComponentName(child) != null ||
              spec.contains("@all@") ||
              spec.contains("default"))) {
        rects.add(rect);
      } else if (!child.ghost &&
          const {
            "button",
            "togglebutton",
            "nstatesbutton",
            "slider",
            "edit",
          }.contains(child.tag)) {
        // The window a frame follows is over it (the classic player raises it above its
        // frame), so what it draws that takes the mouse is its own.
        rects.add(rect);
      }
      if (child.tag == "group") visit(child, rect);
    }
  }

  visit(layout.root, Offset.zero & layout.size);
  return rects;
}

/// [child] without the mouse inside [holes].
class _HoleHitTest extends SingleChildRenderObjectWidget {
  const _HoleHitTest({required this.holes, required super.child});

  final List<Rect> holes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoleHitTest(holes);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoleHitTest renderObject,
  ) => renderObject.holes = holes;
}

class _RenderHoleHitTest extends RenderProxyBox {
  _RenderHoleHitTest(this.holes);

  List<Rect> holes;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (holes.any((hole) => hole.contains(position))) return false;
    return super.hitTest(result, position: position);
  }
}

// --- Wasabi's own controls --------------------------------------------------

/// A `<Wasabi:Button>`: drawn from the skin's `wasabi.button.*` pieces.
class _WasabiButtonView extends StatelessWidget {
  const _WasabiButtonView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  void _press(_WasabiScope scope) {
    scope.scripts?.buttonClicked(object);
    final action = object["action"]?.toUpperCase();
    if (action == null || action.isEmpty) return;
    if (scope.scripts?.buttonAction(object) ?? false) return;
    scope.host.runAction(
      WasabiAction(action, object["param"], container: scope.container),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _WasabiScope.of(context);
    final label = object["#text"] ?? object["text"] ?? "";
    final height = size.height > 0 ? size.height : 21.0;
    final Widget button;
    if (WasabiGridButton.supported(scope.skin)) {
      button = WasabiGridButton(
        skin: scope.skin,
        label: label,
        height: height,
        padding: 2,
        onPressed: () => _press(scope),
      );
    } else {
      button = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _press(scope),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFB4B4B4)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFFFFFFF),
                height: 1,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: size.width > 0 ? size.width : null,
      height: height,
      child: button,
    );
  }
}

/// A `<Wasabi:CheckBox>`, which is a radio button when it names a
/// `radioid` (the others of its group then turn off).
class _CheckBoxView extends StatefulWidget {
  const _CheckBoxView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_CheckBoxView> createState() => _CheckBoxViewState();
}

class _CheckBoxViewState extends State<_CheckBoxView> {
  /// The config attribute a box shows and sets (`cfgattrib`), or null.
  static WasabiCfgAttrib? _cfg(WasabiObject object) =>
      WasabiCfgAttrib.parse(object["cfgattrib"]);

  void _toggle() {
    final scope = _WasabiScope.of(context);
    final object = widget.object;
    final radio = object["radioid"];
    final on = object["#active"] == "1";
    if (radio != null && on) return;
    final scripts = scope.scripts;
    if (scripts != null) {
      scripts.buttonClicked(object);
    } else {
      object.attributes["#active"] = on ? "0" : "1";
    }
    if (_cfg(object) case final cfg?) {
      _ButtonViewState._setConfigValue(
        scope,
        cfg,
        object["#active"] == "1" ? 1 : 0,
      );
    }
    if (radio != null) {
      for (final peer in object.parent?.children ?? const <WasabiObject>[]) {
        if (!identical(peer, object) &&
            peer.tag == "checkbox" &&
            peer["radioid"] == radio &&
            peer["#active"] == "1") {
          peer.attributes["#active"] = "0";
          if (_cfg(peer) case final cfg?) {
            _ButtonViewState._setConfigValue(scope, cfg, 0);
          }
        }
      }
      scripts?.changed();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a script changes the box.
    _WasabiScope.of(context);
    final object = widget.object;
    // A box with a config attribute shows its value.
    if (_cfg(object) case final cfg?) {
      object.attributes["#active"] =
          _ButtonViewState._configValue(_WasabiScope.of(context), cfg) != 0
          ? "1"
          : "0";
    }
    final checked = object["#active"] == "1";
    final color =
        _WasabiScope.of(context).skin.color(object["color"]) ??
        const Color(0xFFFFFFFF);
    // The skin's own marker (Wasabi draws checkboxes and radio buttons
    // alike as a box with it inside) when it has one.
    final marker = _WasabiScope.of(context).skin.bitmap(
      "wasabi.button.checkbox.pressed",
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: !checked
                ? null
                : marker != null
                ? SizedBox.fromSize(
                    size: marker.size,
                    child: _BitmapPaint(bitmap: marker),
                  )
                : SizedBox.square(
                    dimension: 6,
                    child: ColoredBox(color: color),
                  ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              object["#text"] ?? object["text"] ?? "",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// A `<Wasabi:TabSheet>`: a strip of tabs, one per group of its `children`,
/// above whichever group is selected. The others are hidden, which their
/// scripts hear about (`onSetVisible`).
class _TabSheetView extends StatefulWidget {
  const _TabSheetView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_TabSheetView> createState() => _TabSheetViewState();
}

class _TabSheetViewState extends State<_TabSheetView> {
  static const double _strip = 22;

  /// The shown page, kept in the node so scripts can read and set it
  /// (`TabSheet.getCurPage`, `setCurPage`).
  int get _selected {
    final count = widget.object.children.length;
    final page = int.tryParse(widget.object["#page"] ?? "") ?? 0;
    return count == 0 ? 0 : page.clamp(0, count - 1);
  }

  set _selected(int page) => widget.object.attributes["#page"] = "$page";
  OverlayEntry? _list;

  /// `type="2"` picks the page from a drop-down list instead of tabs.
  bool get _dropdown => widget.object["type"]?.trim() == "2";

  void _select(int index) {
    _closeList();
    if (index == _selected) return;
    final pages = widget.object.children;
    final scripts = _WasabiScope.of(context).scripts;
    void set(WasabiObject page, bool visible) {
      if (scripts != null) {
        scripts.setNodeVisible(page, visible);
      } else {
        page.attributes["visible"] = visible ? "1" : "0";
      }
    }

    set(pages[_selected], false);
    set(pages[index], true);
    setState(() => _selected = index);
  }

  void _closeList() {
    _list?.remove();
    _list = null;
  }

  @override
  void dispose() {
    _closeList();
    super.dispose();
  }

  void _openList() {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    _closeList();
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final pages = widget.object.children;
    _list = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeList,
            ),
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy + _strip - 2,
            width: box.size.width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF101030),
                border: Border.all(color: const Color(0xFFB4B4B4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(i),
                      child: Container(
                        height: 20,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: i == _selected ? const Color(0x33FFFFFF) : null,
                        child: Text(
                          pages[i]["name"] ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFFFFFF),
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_list!);
  }

  static const TextStyle _label = TextStyle(
    fontSize: 11,
    color: Color(0xFFFFFFFF),
    height: 1,
  );

  Widget _header(List<WasabiObject> pages, int selected) {
    if (_dropdown) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openList,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            border: Border.all(color: const Color(0xFFB4B4B4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    pages[selected]["name"] ?? "",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text("\u25BE", style: _label),
              ),
            ],
          ),
        ),
      );
    }
    // Tabs as wide as their names, side by side from the left; the chosen
    // one stands taller and is open to the page below.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < pages.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(i),
            child: Container(
              height: i == selected ? _strip : _strip - 4,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.fromRGBO(
                  255,
                  255,
                  255,
                  i == selected ? 0.2 : 0.07,
                ),
                border: Border(
                  top: BorderSide(
                    color: Color.fromRGBO(
                      255,
                      255,
                      255,
                      i == selected ? 0.8 : 0.4,
                    ),
                  ),
                  left: const BorderSide(color: Color(0x66FFFFFF)),
                  right: const BorderSide(color: Color(0x66FFFFFF)),
                  bottom: i == selected
                      ? BorderSide.none
                      : const BorderSide(color: Color(0x99FFFFFF)),
                ),
              ),
              child: Text(
                pages[i]["name"] ?? "",
                maxLines: 1,
                style: _label,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _WasabiScope.of(context);
    final pages = widget.object.children;
    if (pages.isEmpty) return const SizedBox.shrink();
    final selected = _selected.clamp(0, pages.length - 1);
    final size = widget.size;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: _strip,
          width: size.width,
          height: (size.height - _strip).clamp(0, double.infinity),
          child: _ObjectView(
            object: pages[selected],
            size: Size(size.width, (size.height - _strip).clamp(0, 99999)),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: size.width,
          height: _strip,
          child: _header(pages, selected),
        ),
      ],
    );
  }
}

/// A `<Wasabi:HSlider>`'s track and thumb, for a skin that draws neither.
class _BuiltinSliderPaint extends StatelessWidget {
  const _BuiltinSliderPaint({
    required this.vertical,
    required this.thumb,
    required this.down,
  });

  final bool vertical;
  final Rect? thumb;
  final bool down;

  @override
  Widget build(BuildContext context) {
    final thumb = this.thumb;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Align(
            child: FractionallySizedBox(
              widthFactor: vertical ? null : 1,
              heightFactor: vertical ? 1 : null,
              child: SizedBox(
                width: vertical ? 2 : null,
                height: vertical ? null : 2,
                child: const ColoredBox(color: Color(0x99FFFFFF)),
              ),
            ),
          ),
        ),
        if (thumb != null)
          Positioned.fromRect(
            rect: thumb,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(down ? 0xFFFFFFFF : 0xFFD8D8D8),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFF404040)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A `<Wasabi:Dropdownlist>`: its `items` (separated by `;`), the one
/// shown being the text its scripts see inside it.
class _DropDownView extends StatefulWidget {
  const _DropDownView({required this.object, required this.size});

  final WasabiObject object;
  final Size size;

  @override
  State<_DropDownView> createState() => _DropDownViewState();
}

class _DropDownViewState extends State<_DropDownView> {
  OverlayEntry? _entry;

  List<String> get _items => [
    for (final item in (widget.object["items"] ?? "").split(";"))
      if (item.isNotEmpty) item,
  ];

  WasabiObject? get _text => widget.object.children.firstOrNull;

  String get _shown {
    final items = _items;
    return _text?["#text"] ??
        widget.object["default"] ??
        (items.isEmpty ? "" : items.first);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _choose(String item) {
    _close();
    final text = _text;
    if (text != null) {
      final scripts = _WasabiScope.of(context).scripts;
      if (scripts != null) {
        scripts.setNodeText(text, item);
      } else {
        text.attributes["#text"] = item;
      }
    }
    setState(() {});
  }

  void _open() {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final items = _items;
    if (items.isEmpty || box == null) return;
    if (overlay == null) {
      // Without a place to list them, a click goes to the next item.
      final at = items.indexOf(_shown);
      _choose(items[(at + 1) % items.length]);
      return;
    }
    _close();
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy + box.size.height,
            width: box.size.width,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF101030),
                border: Border.all(color: const Color(0xFFB4B4B4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _choose(item),
                      child: Container(
                        height: 20,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        color: item == _shown ? const Color(0x33FFFFFF) : null,
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFFFFFF),
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    _WasabiScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x22FFFFFF),
          border: Border.all(color: const Color(0xFFB4B4B4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFFFFFF),
                    height: 1,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text(
                "\u25BE",
                style: TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
