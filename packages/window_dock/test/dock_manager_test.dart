import "dart:ui";

import "package:flutter/painting.dart" show EdgeInsets;
import "package:flutter_test/flutter_test.dart";
import "package:window_dock/window_dock.dart";

enum W { main, eq, pl }

const _screen = Rect.fromLTWH(0, 0, 1920, 1080);

DockManager<W> _manager() {
  return DockManager<W>(primary: W.main, workAreas: () => const [_screen])
    ..register(W.main, rect: const Rect.fromLTWH(100, 100, 275, 116))
    ..register(W.eq, rect: const Rect.fromLTWH(100, 216, 275, 116))
    ..register(W.pl, rect: const Rect.fromLTWH(600, 600, 275, 232));
}

/// Drags [id] by [delta], grabbing it 5 px inside its top-left corner.
void _drag(DockManager<W> m, W id, Offset delta, {bool shift = false}) {
  final grab = m.rectOf(id)!.topLeft + const Offset(5, 5);
  m
    ..beginDrag(id, grab, invertSnap: shift)
    ..updateDrag(grab + delta, invertSnap: shift)
    ..endDrag();
}

void main() {
  test("a window's see-through top edge may go past the screen's", () {
    final m = _manager()
      ..setTransparentEdges(W.main, const EdgeInsets.only(top: 15));
    // Dragged to 7 px above the top of the screen: its visible part is 8 px
    // from the top, which snaps, so the window sits 15 px above it.
    _drag(m, W.main, const Offset(0, -107));
    expect(m.rectOf(W.main)!.top, -15);
  });

  group("keeping windows on screen", () {
    test("fitInto pulls a window past the bottom-left corner in", () {
      expect(
        DockGeometry.fitInto(
          const Rect.fromLTWH(-300, 1000, 400, 300),
          const [_screen],
        ),
        const Rect.fromLTWH(0, 780, 400, 300),
      );
    });

    test("fitInto leaves a window that fits, and aligns a too big one", () {
      const inside = Rect.fromLTWH(10, 10, 100, 100);
      expect(DockGeometry.fitInto(inside, const [_screen]), inside);
      expect(
        DockGeometry.fitInto(
          const Rect.fromLTWH(-50, -50, 3000, 2000),
          const [_screen],
        ),
        const Rect.fromLTWH(0, 0, 3000, 2000),
      );
    });

    test("fitInto uses the nearest monitor when off every one", () {
      const second = Rect.fromLTWH(1920, 0, 1000, 800);
      expect(
        DockGeometry.fitInto(
          const Rect.fromLTWH(5000, -900, 200, 100),
          const [_screen, second],
        ),
        const Rect.fromLTWH(2720, 0, 200, 100),
      );
    });

    test("a resize that would leave the screen stays on it", () {
      final m = _manager();
      m.resize(W.pl, const Size(1000, 700));
      expect(m.rectOf(W.pl), const Rect.fromLTWH(600, 380, 1000, 700));
    });
  });

  group("DockGeometry", () {
    test("attachment detects stacked and side-by-side seams", () {
      const a = Rect.fromLTWH(0, 0, 275, 116);
      expect(
        DockGeometry.attachment(a, const Rect.fromLTWH(0, 116, 275, 116)),
        2,
      );
      expect(
        DockGeometry.attachment(a, const Rect.fromLTWH(275, 50, 275, 116)),
        1,
      );
      expect(
        DockGeometry.attachment(a, const Rect.fromLTWH(0, 117, 275, 116)),
        0,
      );
    });

    test("snapToWindow docks below and aligns left edges", () {
      final snapped = DockGeometry.snapToWindow(
        const Rect.fromLTWH(106, 222, 275, 116),
        const Rect.fromLTWH(100, 100, 275, 116),
      );
      expect(snapped, const Rect.fromLTWH(100, 216, 275, 116));
    });

    test("snapToWindow docks to the right and aligns tops", () {
      final snapped = DockGeometry.snapToWindow(
        const Rect.fromLTWH(380, 95, 275, 116),
        const Rect.fromLTWH(100, 100, 275, 116),
      );
      expect(snapped, const Rect.fromLTWH(375, 100, 275, 116));
    });

    test("snapToScreen magnetizes to work-area edges", () {
      final snapped = DockGeometry.snapToScreen(
        const Rect.fromLTWH(4, 1070 - 116 + 5, 275, 116),
        _screen,
      );
      expect(snapped.left, 0);
      expect(snapped.bottom, 1080);
    });
  });

  group("DockManager", () {
    test("dragging the primary window carries attached windows", () {
      final m = _manager();
      _drag(m, W.main, const Offset(300, 200));
      expect(m.rectOf(W.main), const Rect.fromLTWH(400, 300, 275, 116));
      expect(m.rectOf(W.eq), const Rect.fromLTWH(400, 416, 275, 116));
      expect(m.rectOf(W.pl), const Rect.fromLTWH(600, 600, 275, 232));
    });

    test("attachment is transitive through visible windows only", () {
      final m = _manager()..moveTo(W.pl, const Offset(100, 332));
      _drag(m, W.main, const Offset(50, 0));
      expect(m.rectOf(W.pl)!.left, 150);

      final hidden = _manager()
        ..moveTo(W.pl, const Offset(100, 332))
        ..setVisible(W.eq, false);
      _drag(hidden, W.main, const Offset(50, 0));
      // EQ is attached (and follows) but, hidden, does not chain to PL.
      expect(hidden.rectOf(W.eq)!.left, 150);
      expect(hidden.rectOf(W.pl)!.left, 100);
    });

    test("dragging a docked secondary window undocks it", () {
      final m = _manager();
      _drag(m, W.eq, const Offset(0, 300));
      expect(m.rectOf(W.main), const Rect.fromLTWH(100, 100, 275, 116));
      expect(m.rectOf(W.eq)!.top, 516);
    });

    test("secondary windows snap onto other windows", () {
      final m = _manager();
      // Bring PL within snapping distance of EQ's bottom-left corner.
      _drag(m, W.pl, const Offset(100 - 600 + 4, 332 - 600 + 6));
      expect(m.rectOf(W.pl)!.topLeft, const Offset(100, 332));
    });

    test("a window that does not dock neither snaps nor is snapped to", () {
      final m = _manager()..setDockable(W.pl, false);
      _drag(m, W.pl, const Offset(100 - 600 + 4, 332 - 600 + 6));
      expect(m.rectOf(W.pl)!.topLeft, const Offset(104, 338));
      // Nothing snaps to it either.
      m.moveTo(W.pl, const Offset(800, 100));
      _drag(m, W.main, const Offset(800 - 375 - 4, 0));
      expect(m.rectOf(W.main)!.right, 796);
    });

    test("a window that does not dock is not carried by the primary", () {
      final m = _manager()..setDockable(W.eq, false);
      _drag(m, W.main, const Offset(50, 0));
      expect(m.rectOf(W.main)!.left, 150);
      expect(m.rectOf(W.eq)!.left, 100);
    });

    test("snap points of the same id dock windows through them", () {
      final m = _manager()
        ..setSnapPoints(W.main, const [DockSnapPoint("a", Offset(100, 50))])
        ..setSnapPoints(W.pl, const [DockSnapPoint("a", Offset(10, 10))]);
      // PL's point lands (6, 4) off MAIN's: 200,150 vs 206,154.
      _drag(m, W.pl, const Offset(206 - 10 - 600 - 0, 154 - 10 - 600 - 0));
      final pl = m.rectOf(W.pl)!;
      expect(pl.topLeft + const Offset(10, 10), const Offset(200, 150));
      // A different id does not match.
      m.setSnapPoints(W.pl, const [DockSnapPoint("b", Offset(10, 10))]);
      m.moveTo(W.pl, const Offset(600, 600));
      _drag(m, W.pl, const Offset(206 - 10 - 600 - 0, 154 - 10 - 600 - 0));
      expect(m.rectOf(W.pl)!.topLeft, const Offset(196, 144));
    });

    test("Shift inverts snapping", () {
      final m = _manager();
      _drag(m, W.pl, const Offset(100 - 600 + 4, 332 - 600 + 6), shift: true);
      expect(m.rectOf(W.pl)!.topLeft, const Offset(104, 338));
    });

    test("the primary window snaps to windows it is not attached to", () {
      final m = _manager()..moveTo(W.eq, const Offset(800, 100));
      // Move main so its right edge lands 4 px short of EQ's left edge.
      _drag(m, W.main, const Offset(800 - 375 - 4, 0));
      expect(m.rectOf(W.main)!.right, 800);
    });

    test("resizing re-pins windows docked to the bottom edge", () {
      final m = _manager()..moveTo(W.pl, const Offset(100, 332));
      m.resize(W.main, const Size(275, 14));
      expect(m.rectOf(W.eq)!.top, 114);
      expect(m.rectOf(W.pl)!.top, 230);
    });

    test("resizing with repin: false leaves docked windows where they are", () {
      final m = _manager()..moveTo(W.pl, const Offset(375, 100));
      m.resize(W.main, const Size(550, 232), repin: false);
      expect(m.rectOf(W.pl)!.left, 375);
      expect(m.rectOf(W.main)!.width, 550);
    });

    test("resizing re-pins windows docked to the right edge", () {
      final m = _manager()..moveTo(W.pl, const Offset(375, 100));
      m.resize(W.main, const Size(550, 232));
      expect(m.rectOf(W.pl)!.left, 650);
    });
  });

  group("resize snapping", () {
    const main = Rect.fromLTWH(100, 100, 275, 116);

    test("a moving edge snaps flush with a neighbour's edge", () {
      // A playlist docked under the main window, resized 4 px short of it.
      final rect = DockGeometry.snapResize(
        const Rect.fromLTWH(100, 216, 271, 200),
        others: const [main],
        right: true,
      );
      expect(rect, const Rect.fromLTWH(100, 216, 275, 200));
    });

    test("a moving edge snaps against a neighbour's facing edge", () {
      // The playlist beside the main window, its bottom 6 px past it.
      final rect = DockGeometry.snapResize(
        const Rect.fromLTWH(375, 100, 200, 122),
        others: const [Rect.fromLTWH(600, 50, 100, 400), main],
        bottom: true,
      );
      expect(rect.bottom, main.bottom);
      expect(rect.topLeft, const Offset(375, 100));
    });

    test("edges that do not move never snap", () {
      final rect = DockGeometry.snapResize(
        const Rect.fromLTWH(100, 216, 271, 200),
        others: const [main],
        bottom: true,
      );
      expect(rect, const Rect.fromLTWH(100, 216, 271, 200));
    });

    test("only windows it ends up touching pull an edge", () {
      // Far below the main window: lining up with it would not dock.
      final rect = DockGeometry.snapResize(
        const Rect.fromLTWH(100, 400, 271, 200),
        others: const [main],
        right: true,
      );
      expect(rect.width, 271);
    });

    test("the snap distance is exclusive", () {
      Rect snap(double width) => DockGeometry.snapResize(
        Rect.fromLTWH(100, 216, width, 200),
        others: const [main],
        right: true,
      );
      expect(snap(275 - 9).width, 275);
      expect(snap(275 - 10).width, 265);
      expect(snap(275 + 9).width, 275);
    });

    test("a moving edge snaps to the work area", () {
      final rect = DockGeometry.snapResize(
        const Rect.fromLTWH(1600, 800, 315, 275),
        workArea: _screen,
        right: true,
        bottom: true,
      );
      expect(rect.bottomRight, _screen.bottomRight);
    });

    test("DockManager snaps the edges that change to visible windows", () {
      final m = _manager()
        ..setRect(W.pl, const Rect.fromLTWH(100, 332, 275, 232));
      // Resizing the playlist 5 px narrower and 3 px taller: the right edge
      // springs back to the stack's, the bottom edge has nothing to meet.
      expect(m.snapResize(W.pl, const Size(270, 235)), const Size(275, 235));
      // Hidden windows do not pull.
      m
        ..setVisible(W.main, false)
        ..setVisible(W.eq, false);
      expect(m.snapResize(W.pl, const Size(270, 235)), const Size(270, 235));
    });

    test("Shift or disabled snapping leaves the size alone", () {
      final m = _manager()
        ..setRect(W.pl, const Rect.fromLTWH(100, 332, 275, 232));
      expect(
        m.snapResize(W.pl, const Size(270, 232), invertSnap: true),
        const Size(270, 232),
      );
      m.snapEnabled = false;
      expect(m.snapResize(W.pl, const Size(270, 232)), const Size(270, 232));
    });
  });
}
