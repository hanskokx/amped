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
      head: [
        link(href: '/favicon.ico', rel: 'icon', attributes: {'sizes': 'any'}),
        link(href: '/icon-192.png', rel: 'icon', type: 'image/png', attributes: {'sizes': '192x192'}),
        link(href: '/apple-touch-icon.png', rel: 'apple-touch-icon'),
        link(href: '/styles.css', rel: 'stylesheet'),
        script(src: 'download.js', defer: true),
        script(src: 'player.js', defer: true),
      ],
      body: const App(),
    ),
  );
}
