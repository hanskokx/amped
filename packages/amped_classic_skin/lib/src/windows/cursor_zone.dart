import "package:flutter/widgets.dart";

import "../classic_skin_data.dart";
import "../skin_cursors.dart";

/// A rectangle (in unscaled skin pixels) that shows a skin cursor, mirroring
/// the hit tables of `ui_handlecursor`/`eq_ui_handlecursor`/
/// `pe_ui_handlecursor`. Place zones behind the controls; controls set their
/// own cursor.
class CursorZone extends StatelessWidget {
  const CursorZone({
    required this.skin,
    required this.rect,
    required this.cursor,
    super.key,
  });

  final ClassicSkinData skin;
  final Rect rect;
  final SkinCursor cursor;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(cursor: skin.cursor(cursor), opaque: false),
    );
  }
}
