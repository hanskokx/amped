import "dart:ui" as ui;

import "package:flutter/widgets.dart";

/// Glyph mapping for the skin's small text font (text.bmp, 5×6 per character).
///
/// Mirrors `getXYfromChar` in the original draw.cpp: A–Z and a–z live in row 0
/// at `c * 5`, digits 0–9 and punctuation in row 1 (y = 6), the extended
/// characters `?`/`*` in row 2 (y = 12), and `"`/`@` at x = 26/27 in row 0.
/// Unknown characters and a space use the blank 5×6 glyph at (30, 0).
class TextFont {
  TextFont(this.image);

  static const double charWidth = 5;
  static const double charHeight = 6;

  final ui.Image image;
  final Map<String, Rect> _glyphCache = {};

  /// Returns the source rect for [char], or a blank glyph for unknown input.
  Rect glyphRect(String char) {
    if (char.isEmpty) return const Rect.fromLTWH(150, 0, 5, 6);
    final rect = _glyphCache[char] ?? _rectFor(char);
    _glyphCache[char] = rect;
    return rect;
  }

  Rect _rectFor(String char) {
    final code = char.codeUnitAt(0);
    int c;
    int c2;
    if (code >= 0x41 && code <= 0x5A) {
      c = code - 0x41;
      c2 = 0;
    } else if (code >= 0x61 && code <= 0x7A) {
      c = code - 0x61;
      c2 = 0;
    } else {
      c = 10;
      c2 = 6;
      const row1 = <int, int>{
        0x01: 10, // \1 (blank)
        0x30: 0, 0x31: 1, 0x32: 2, 0x33: 3, 0x34: 4,
        0x35: 5, 0x36: 6, 0x37: 7, 0x38: 8, 0x39: 9,
        0x2E: 11, // .
        0x3A: 12, // :
        0x28: 13, // (
        0x29: 14, // )
        0x2D: 15, // -
        0x27: 16, // '
        0x60: 16, // `
        0x21: 17, // !
        0x5F: 18, // _
        0x2B: 19, // +
        0x5C: 20, // backslash
        0x2F: 21, // /
        0x5B: 22, 0x7B: 22, 0x3C: 22, // [ { <
        0x5D: 23, 0x7D: 23, 0x3E: 23, // ] } >
        0x7E: 24, 0x5E: 24, // ~ ^
        0x26: 25, // &
        0x25: 26, // %
        0x2C: 27, // ,
        0x3D: 28, // =
        0x24: 29, // $
        0x23: 30, // #
      };
      final mapped = row1[code];
      if (mapped != null) {
        c = mapped;
      } else if (code == 0x3F) {
        // ?
        c = 3;
        c2 = 12;
      } else if (code == 0x2A) {
        // *
        c = 4;
        c2 = 12;
      } else if (code == 0x22) {
        // "
        c = 26;
        c2 = 0;
      } else if (code == 0x40) {
        // @
        c = 27;
        c2 = 0;
      } else {
        c = 30;
        c2 = 0;
      }
    }
    return Rect.fromLTWH(c * 5.0, c2.toDouble(), 5, 6);
  }
}

/// Paints [text] left-to-right using the 5×6 text font, clipped to [clip].
class SkinText extends StatelessWidget {
  const SkinText({
    required this.font,
    required this.text,
    required this.clip,
    super.key,
    this.leadingWidth = 0,
  });

  final TextFont font;
  final String text;
  final Rect clip;

  /// Horizontal padding before the first glyph.
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(clip.width, clip.height),
      painter: _SkinTextPainter(font, text, clip, leadingWidth),
    );
  }
}

class _SkinTextPainter extends CustomPainter {
  const _SkinTextPainter(this.font, this.text, this.clip, this.leadingWidth);

  final TextFont font;
  final String text;
  final Rect clip;
  final double leadingWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(clip);
    var x = clip.left + leadingWidth;
    final paint = Paint();
    for (final char in text.characters) {
      final src = font.glyphRect(char);
      final dst = Rect.fromLTWH(
        x,
        clip.top,
        TextFont.charWidth,
        TextFont.charHeight,
      );
      canvas.drawImageRect(font.image, src, dst, paint);
      x += TextFont.charWidth;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkinTextPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.clip != clip ||
        oldDelegate.leadingWidth != leadingWidth;
  }
}
