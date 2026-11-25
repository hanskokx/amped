import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The Amped landing page.
class App extends StatelessComponent {
  const App({super.key});

  static const _releases = 'https://github.com/hanskokx/amped/releases/latest';

  static const _features = [
    (
      'Every source',
      'Local files, streams and network shares, plus Plex, '
          'Jellyfin, Subsonic/Navidrome, SoundCloud, Audiobookshelf and podcasts.',
    ),
    (
      'Skins',
      'Classic bitmap skins, Audacious and Bamp skins, and modern '
          '(Wasabi) skins. Wear what you like.',
    ),
    (
      'Every format',
      'MP3, FLAC, Ogg, Opus, WAV, Monkey\'s Audio, Musepack, '
          'WavPack and more, plus video and playlists.',
    ),
    ('Desktop native', 'Built with Flutter for macOS, Windows and Linux.'),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: 'page', [
      section(classes: 'hero', [
        img(src: 'images/amped.png', alt: 'Amped', width: 128, height: 128),
        h1([Component.text('Amped')]),
        p(classes: 'tagline', [Component.text('Crank it up.')]),
        p([
          Component.text(
            'A desktop music player for macOS, Windows and Linux '
            'that plays from anywhere and wears any skin.',
          ),
        ]),
        // download.js swaps this for the installers that fit the visitor's OS.
        div(id: 'download', [
          a(classes: 'button', href: _releases, [
            Component.text('Download'),
          ]),
          p(classes: 'meta', [
            a(href: _releases, [Component.text('All downloads')]),
          ]),
        ]),
      ]),
      section(classes: 'features', [
        for (final f in _features)
          div(classes: 'feature', [
            h2([Component.text(f.$1)]),
            p([Component.text(f.$2)]),
          ]),
      ]),
      footer([Component.text('© Amped')]),
    ]);
  }
}
