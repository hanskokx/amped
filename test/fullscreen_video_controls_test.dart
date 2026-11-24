import "package:amped/src/app/fullscreen_video_controls.dart";
import "package:amped/src/app/video_view.dart";
import "package:amped/src/player/video_engine.dart";
import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:material_ui/material_ui.dart" show Icons;

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: Center(child: SizedBox(width: 600, child: child)),
  ),
);

void main() {
  test("times read as m:ss, and h:mm:ss from an hour", () {
    expect(formatVideoTime(Duration.zero), "0:00");
    expect(formatVideoTime(const Duration(seconds: 75)), "1:15");
    expect(
      formatVideoTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      "1:02:03",
    );
  });

  test("a subtitle track is named by language and title", () {
    expect(const TrackOption(id: "1").label("Track 1"), "Track 1");
    expect(
      const TrackOption(id: "1", language: "en", title: "SDH").label("x"),
      "en - SDH",
    );
    expect(const TrackOption(id: "1", language: "fr").label("x"), "fr");
  });

  testWidgets("pressing the progress bar seeks to that point", (tester) async {
    Duration? sought;
    await tester.pumpWidget(
      _host(
        VideoSeekBar(
          elapsed: Duration.zero,
          total: const Duration(seconds: 100),
          label: "Position",
          onSeek: (at) => sought = at,
        ),
      ),
    );
    expect(find.text("1:40"), findsOneWidget);
    final bar = tester.getRect(find.byType(VideoSeekBar));
    // Halfway along the bar between the two time labels.
    await tester.tapAt(Offset(bar.center.dx, bar.center.dy));
    expect(sought, const Duration(seconds: 50));
  });

  testWidgets("dragging the progress bar seeks once, where it ends", (
    tester,
  ) async {
    final sought = <Duration>[];
    await tester.pumpWidget(
      _host(
        VideoSeekBar(
          elapsed: Duration.zero,
          total: const Duration(seconds: 100),
          label: "Position",
          onSeek: sought.add,
        ),
      ),
    );
    final bar = tester.getRect(find.byType(VideoSeekBar));
    final gesture = await tester.startGesture(
      Offset(bar.left + 60, bar.center.dy),
    );
    await gesture.moveTo(Offset(bar.center.dx, bar.center.dy));
    await tester.pump();
    expect(sought, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(sought, hasLength(1));
    expect(sought.single.inSeconds, inInclusiveRange(48, 52));
  });

  testWidgets("the picker lists Off and the tracks, and says the choice", (
    tester,
  ) async {
    final chosen = <String?>[];
    await tester.pumpWidget(
      _host(
        TrackPicker(
          options: const [
            TrackOption(id: "1", language: "en"),
            TrackOption(id: "2"),
          ],
          selected: "1",
          offLabel: "Off",
          trackLabel: (n) => "Track $n",
          onSelected: chosen.add,
        ),
      ),
    );
    expect(find.text("Off"), findsOneWidget);
    expect(find.text("en"), findsOneWidget);
    expect(find.text("Track 2"), findsOneWidget);
    await tester.tap(find.text("Track 2"));
    await tester.tap(find.text("Off"));
    expect(chosen, ["2", null]);
  });

  testWidgets("the volume slider sets the fraction pressed", (tester) async {
    double? volume;
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.centerLeft,
          child: VideoVolume(
            value: 0,
            label: "Volume",
            onChanged: (v) => volume = v,
          ),
        ),
      ),
    );
    final slider = find.byType(VideoVolume);
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    expect(volume, closeTo(1, 0.02));
  });

  testWidgets("pressing the speaker mutes", (tester) async {
    var muted = 0;
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.centerLeft,
          child: VideoVolume(
            value: 0.5,
            label: "Volume",
            onChanged: (_) {},
            onMute: () => muted++,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.volume_up));
    expect(muted, 1);
  });

  testWidgets("a disabled button does nothing", (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host(
        VideoButton(
          icon: Icons.subtitles,
          label: "Subtitles",
          enabled: false,
          onPressed: () => pressed++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.subtitles));
    expect(pressed, 0);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1));
  });

  testWidgets("an audio list has no Off", (tester) async {
    await tester.pumpWidget(
      _host(
        TrackPicker(
          options: const [TrackOption(id: "1", language: "en")],
          selected: "1",
          trackLabel: (n) => "Track $n",
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text("Off"), findsNothing);
    expect(find.text("en"), findsOneWidget);
  });

  testWidgets("an unsupported track says so and cannot be chosen", (
    tester,
  ) async {
    final chosen = <String?>[];
    await tester.pumpWidget(
      _host(
        TrackPicker(
          options: const [
            TrackOption(id: "1", language: "en", supported: false),
          ],
          selected: null,
          offLabel: "Off",
          unsupportedLabel: "Unsupported",
          trackLabel: (n) => "Track $n",
          onSelected: chosen.add,
        ),
      ),
    );
    expect(find.text("Unsupported"), findsOneWidget);
    await tester.tap(find.text("en"));
    expect(chosen, isEmpty);
  });

  test("the picture size is named by its class", () {
    VideoSizeClass of(double w, double h) => VideoSizeClass.of(Size(w, h));
    expect(of(640, 480), VideoSizeClass.sd);
    expect(of(1280, 720), VideoSizeClass.hd);
    expect(of(1920, 960), VideoSizeClass.fhd);
    expect(of(2560, 1440), VideoSizeClass.qhd);
    expect(of(3840, 1600), VideoSizeClass.uhd4k);
    expect(of(7680, 4320), VideoSizeClass.uhd8k);
    expect(VideoSizeClass.fhd.label, "FHD");
    expect(VideoSizeClass.uhd4k.label, "4K");
  });

  test("the playback time keeps its width as it counts", () {
    String time(int elapsed, int total) => ClassicVideoWindow.playbackTime(
      Duration(seconds: elapsed),
      Duration(seconds: total),
    );
    expect(time(309, 6110), "0:05:09 / 1:41:50");
    expect(time(309, 2530), "05:09 / 42:10");
    expect(time(0, 0), "00:00 / 00:00");
  });

  test("chapters are read from mpv's chapter list, in time order", () {
    final chapters = VideoChapter.parse(
      '[{"title":"Second","time":60.5},{"title":"","time":0.0}]',
    );
    expect(chapters.map((c) => c.time), [
      Duration.zero,
      const Duration(milliseconds: 60500),
    ]);
    expect(chapters.map((c) => c.title), [null, "Second"]);
    expect(VideoChapter.parse("not json"), isEmpty);
    expect(VideoChapter.parse('{"a": 1}'), isEmpty);
  });

  testWidgets("hovering the progress bar previews the time and chapter", (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.only(top: 200),
          child: VideoSeekBar(
            elapsed: Duration.zero,
            total: const Duration(seconds: 100),
            label: "Position",
            showTimes: false,
            chapters: const [
              VideoChapter(time: Duration.zero, title: "Opening"),
              VideoChapter(time: Duration(seconds: 40), title: "Heist"),
            ],
            onSeek: (_) {},
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final bar = tester.getRect(find.byType(VideoSeekBar));
    await mouse.moveTo(Offset(bar.center.dx, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("0:50"), findsOneWidget);
    expect(find.text("Heist"), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text("0:50"), findsNothing);
  });
}
