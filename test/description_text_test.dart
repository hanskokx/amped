import "package:amped/src/library/description_text.dart";
import "package:flutter_test/flutter_test.dart";

List<String> links(String text) => [
  for (final part in parseDescription(text))
    if (part is LinkPart) part.uri.toString(),
];

List<Duration> times(String text, {Duration? length}) => [
  for (final part in parseDescription(text, length: length))
    if (part is TimePart) part.at,
];

void main() {
  test("finds links with and without a scheme", () {
    expect(
      links(
        "See https://example.com/a?b=1, or plus.npr.org. Also (bbc.co.uk).",
      ),
      [
        "https://example.com/a?b=1",
        "https://plus.npr.org",
        "https://bbc.co.uk",
      ],
    );
    expect(links("http://x.org/y_z)"), ["http://x.org/y_z"]);
  });

  test("leaves emails and file names alone", () {
    expect(links("write to me@example.com or open notes.txt"), isEmpty);
  });

  test("finds times in brackets and on their own", () {
    expect(times("Intro (3:05) and [1:02:03] then 12:30 - topic"), [
      const Duration(minutes: 3, seconds: 5),
      const Duration(hours: 1, minutes: 2, seconds: 3),
      const Duration(minutes: 12, seconds: 30),
    ]);
    expect(times("00:45 Welcome\n10:00 Main"), hasLength(2));
  });

  test("skips clock times, odd numbers and times past the end", () {
    expect(times("Meet at 10:30 PM or 7:15pm"), isEmpty);
    expect(times("ratio 3:99 and 1:75"), isEmpty);
    expect(times("(5:00) and (50:00)", length: const Duration(minutes: 30)), [
      const Duration(minutes: 5),
    ]);
  });

  test("a link's own numbers are not times", () {
    expect(times("see http://x.org/12:30"), isEmpty);
  });
}
