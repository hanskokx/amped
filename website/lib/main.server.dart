import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    Document(
      title: 'Amped - Crank it up.',
      meta: {
        'description': 'Amped is a desktop music player for macOS, Windows and Linux.',
        'viewport': 'width=device-width, initial-scale=1',
      },
      styles: [
        css('html, body').styles(
          margin: Margin.zero,
          backgroundColor: const Color('#14101c'),
          color: const Color('#eee9f7'),
          fontFamily: const FontFamily.list([
            FontFamily('system-ui'),
            FontFamilies.sansSerif,
          ]),
        ),
        css('.page').styles(
          maxWidth: 960.px,
          margin: Margin.symmetric(horizontal: Unit.auto),
          padding: Padding.all(24.px),
        ),
        css('.hero').styles(
          textAlign: TextAlign.center,
          padding: Padding.symmetric(vertical: 64.px),
        ),
        css('.hero h1').styles(
          fontSize: 4.rem,
          margin: Margin.only(top: 16.px, bottom: 0.px),
        ),
        css('.tagline').styles(color: const Color('#b58cff'), fontSize: 1.5.rem),
        css('.button').styles(
          display: Display.inlineBlock,
          padding: Padding.symmetric(vertical: 12.px, horizontal: 32.px),
          backgroundColor: const Color('#8b4dff'),
          color: Colors.white,
          textDecoration: const TextDecoration(line: TextDecorationLine.none),
          fontWeight: FontWeight.w700,
          radius: BorderRadius.circular(8.px),
        ),
        css('.meta').styles(color: const Color('#8a82a0'), fontSize: 0.9.rem),
        css('.meta a, details a').styles(color: const Color('#b58cff')),
        css('details').styles(margin: Margin.only(top: 16.px)),
        css('details ul').styles(listStyle: ListStyle.none, padding: Padding.zero),
        css('.features').styles(
          display: Display.grid,
          gap: Gap.all(24.px),
        ),
        css('.feature').styles(
          padding: Padding.all(20.px),
          backgroundColor: const Color('#201a2e'),
          radius: BorderRadius.circular(12.px),
        ),
        css('footer').styles(
          textAlign: TextAlign.center,
          padding: Padding.symmetric(vertical: 40.px),
          color: const Color('#8a82a0'),
        ),
      ],
      head: [
        link(href: '/favicon.ico', rel: 'icon', attributes: {'sizes': 'any'}),
        link(href: '/icon-192.png', rel: 'icon', type: 'image/png', attributes: {'sizes': '192x192'}),
        link(href: '/apple-touch-icon.png', rel: 'apple-touch-icon'),
        script(src: 'download.js', defer: true),
      ],
      body: const App(),
    ),
  );
}
