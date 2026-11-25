import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The Amped landing page.
class App extends StatelessComponent {
  const App({super.key});

  static const _repository = 'https://github.com/hanskokx/amped';
  static const _releases = '$_repository/releases/latest';

  static const _sources = [
    'Local files',
    'Plex',
    'Jellyfin',
    'Subsonic',
    'Navidrome',
    'SoundCloud',
    'Audiobookshelf',
    'Podcasts',
    'SMB & WebDAV',
    'Internet streams',
  ];

  static const _features = [
    (
      'Every source',
      'Your files, your servers, your podcasts and your radio streams, '
          'all in one player.',
    ),
    (
      'Equalizer and visuals',
      'Equalizer, visualizations, volume and balance work the same '
          'whatever format is playing.',
    ),
    (
      'Network shares',
      'Play straight from SMB and WebDAV shares. Logins are kept in your '
          'system\'s secure storage.',
    ),
    (
      'Video too',
      'MKV, MP4, WebM, AVI and more play in their own video window.',
    ),
    (
      'Tags',
      'Read and write tags, from ID3 and Vorbis comments to APEv2.',
    ),
    (
      'Desktop native',
      'Built with Flutter for macOS, Windows and Linux, with skin previews '
          'in your file manager.',
    ),
  ];

  /// The skin families Amped wears: name, where each comes from, and a link
  /// to find out more or get skins.
  static const _skinFormats = [
    (
      'Classic',
      'The skins of the desktop player that defined the late 1990s. People '
          'have made tens of thousands of them, and Amped draws them pixel for '
          'pixel, so your old favorites look the way you remember.',
      'Browse classic skins',
      'https://skins.webamp.org/',
    ),
    (
      'Modern (Wasabi)',
      'That player\'s next generation brought Wasabi: free-form skins with '
          'sliding drawers, color themes and animation. Amped runs their '
          'scripts, so they behave as their authors meant them to. ClassicPro '
          'skins work too.',
      'Browse modern skins',
      'https://winampheritage.com/skins',
    ),
    (
      'Audacious',
      'Audacious is a free, open source audio player, long a favorite on '
          'Linux, with a collection of skins of its own. Amped wears them, so '
          'they can come with you to macOS and Windows too.',
      'Browse Audacious skins',
      'https://www.gnome-look.org/browse?cat=129&ord=rating',
    ),
    (
      'BAMP',
      'BAMP is a newer, open source way to make classic skins, with artwork '
          'layered the way the finished player looks, ready for your favorite '
          'image editor. Amped loads BAMP skins as they are, so there\'s no '
          'converting them yourself.',
      'Visit bamp.skin',
      'https://bamp.skin/',
    ),
  ];

  static const _formats = [
    'MP3',
    'FLAC',
    'Ogg Vorbis',
    'Opus',
    'WAV',
    'Speex',
    'Ogg FLAC',
    'Monkey\'s Audio',
    'Musepack',
    'WavPack',
    'TTA',
    'TAK',
    'OptimFROG',
    'M3U',
    'PLS',
  ];

  @override
  Component build(BuildContext context) {
    return div([
      div(classes: 'glow', []),
      header(classes: 'wrap top', [
        a(classes: 'brand', href: '/', [
          img(src: 'images/amped.png', alt: '', width: 36, height: 36),
          Component.text('Amped'),
        ]),
        nav([
          a(href: '#skins', [Component.text('Skins')]),
          a(href: '#features', [Component.text('Features')]),
          _external(_repository, 'GitHub'),
        ]),
      ]),
      section(classes: 'wrap hero', [
        div([
          h1([
            Component.text('Crank '),
            _shine('it up.'),
          ]),
          p(classes: 'lead', [
            Component.text(
              'A desktop music player for macOS, Windows and Linux '
              'that plays from anywhere and wears any skin.',
            ),
          ]),
          // download.js swaps this for the installers that fit the visitor's OS.
          div(id: 'download', [
            _external(_releases, 'Download', classes: 'button'),
            p(classes: 'meta', [_external(_releases, 'All downloads')]),
          ]),
        ]),
        _player(
          'classic',
          'Amped\'s classic skin, with its player, equalizer and playlist '
              'windows',
          width: 1100,
          height: 1856,
          skinWidth: 275,
        ),
      ]),
      div(classes: 'ticker', [
        ul([
          for (final s in _sources) li([Component.text(s)]),
          // Seen only by the scrolling ticker, which needs it to loop.
          for (final s in _sources)
            li(
              classes: 'copy',
              attributes: {'aria-hidden': 'true'},
              [Component.text(s)],
            ),
        ]),
      ]),
      section(id: 'skins', classes: 'wrap', [
        div(classes: 'skins', [
          div(classes: 'reveal', [
            h2([Component.text('Wear any '), _shine('skin.')]),
            p([
              Component.text(
                'Bring the skins you already love, from four families. Amped '
                'ships with a classic and a modern one to get you started.',
              ),
            ]),
          ]),
          div(classes: 'reveal', [_modernPlayer()]),
        ]),
        div(classes: 'skin-formats', [
          for (final f in _skinFormats)
            div(classes: 'feature reveal', [
              h3([Component.text(f.$1)]),
              p([Component.text(f.$2)]),
              _external(f.$4, f.$3, classes: 'more'),
            ]),
        ]),
        div(classes: 'make-your-own reveal', [
          div([
            h3([Component.text('Make your own.')]),
            p([
              Component.text(
                'Your artwork doesn\'t have to be .bmp anymore. Draw a '
                'classic-style skin in PNG, JPG or GIF: keep the classic file '
                'names and change the extension, so main.png stands in for '
                'main.bmp.',
              ),
            ]),
            _external(
              'https://winampskins.neocities.org/',
              'Read the classic skin tutorial',
              classes: 'more',
            ),
          ]),
          _chips(['.png', '.jpg', '.jpeg', '.gif', '.bmp']),
        ]),
      ]),
      section(id: 'radio', classes: 'wrap', [
        div(classes: 'radio reveal', [
          div([
            h2([Component.text('Tune in to '), _shine('internet radio.')]),
            p([
              Component.text(
                'Amped plays streaming playlists. Add a station\'s .pls, .m3u '
                'or .m3u8 link and it plays the stream inside. SHOUTcast and '
                'Icecast stations that send song titles show you what\'s on '
                'right now.',
              ),
            ]),
            _chips(['.pls', '.m3u', '.m3u8']),
            _external(
              'https://directory.shoutcast.com/',
              'Find stations on SHOUTcast',
              classes: 'button',
            ),
          ]),
          // A station on the air, for decoration.
          div(classes: 'on-air', attributes: {'aria-hidden': 'true'}, [
            for (var i = 0; i < 3; i++) Component.element(tag: 'i'),
            span([Component.text('ON AIR')]),
          ]),
        ]),
      ]),
      section(id: 'features', classes: 'wrap', [
        h2(classes: 'reveal', [
          _shine('Plays'),
          Component.text(' what you have.'),
        ]),
        div(classes: 'features', [
          for (final f in _features)
            div(classes: 'feature reveal', [
              div(classes: 'bars', attributes: {'aria-hidden': 'true'}, [
                for (var i = 0; i < 4; i++) Component.element(tag: 'i'),
              ]),
              h3([Component.text(f.$1)]),
              p([Component.text(f.$2)]),
            ]),
        ]),
      ]),
      section(classes: 'wrap formats reveal', [
        h2([Component.text('Nearly every '), _shine('format.')]),
        _chips(_formats),
      ]),
      section(classes: 'wrap closing reveal', [
        h2([_shine('Ready'), Component.text(' when you are.')]),
        _external(_releases, 'Get Amped', classes: 'button'),
      ]),
      // download.js opens the one that fits a macOS or Windows download.
      _installHelp(
        'macos',
        title: 'Opening Amped on macOS',
        why:
            'Amped isn\'t signed with an Apple developer certificate, so macOS '
            'stops it the first time you open it.',
        steps: [
          [_text('Open the downloaded disk image and drag Amped to Applications.')],
          [
            _text('Open Amped. When macOS says it can\'t verify it, click '),
            _name('Done'),
            _text('.'),
          ],
          [
            _text('Open '),
            _name('System Settings'),
            _text(', click '),
            _name('Privacy & Security'),
            _text(' and scroll down to '),
            _name('Security'),
            _text('.'),
          ],
          [
            _text('Click '),
            _name('Open Anyway'),
            _text(
              '. The button is there for about an hour after you try to open '
              'Amped.',
            ),
          ],
          [
            _text('Click '),
            _name('Open'),
            _text(', and enter your password if you\'re asked for it.'),
          ],
        ],
        after: 'After that, Amped opens like any other app.',
        more: _external(
          'https://support.apple.com/en-us/102445',
          'Apple\'s instructions',
          classes: 'more',
        ),
      ),
      _installHelp(
        'windows',
        title: 'Installing Amped on Windows',
        why:
            'Amped\'s installer isn\'t code signed, so Microsoft Defender '
            'SmartScreen may warn you about it.',
        steps: [
          [_text('If your browser warns about the download, choose to keep it.')],
          [_text('Open the setup file you downloaded.')],
          [
            _text('When you see '),
            _name('Windows protected your PC'),
            _text(', click '),
            _name('More info'),
            _text('.'),
          ],
          [
            _text('Click '),
            _name('Run anyway'),
            _text(', then follow the installer.'),
          ],
        ],
      ),
      footer([
        Component.text('© Amped'),
        _external(_repository, 'Source'),
        _external('$_repository/issues', 'Report a bug'),
      ]),
    ]);
  }

  /// A link to another site, which opens in a new tab.
  static Component _external(String href, String label, {String? classes}) => a(
    classes: classes,
    href: href,
    attributes: {'target': '_blank', 'rel': 'noopener'},
    [Component.text(label)],
  );

  /// The steps for getting past a system's warning about an unsigned app, in
  /// a dialog that stays closed until a download opens it.
  static Component _installHelp(
    String system, {
    required String title,
    required String why,
    required List<List<Component>> steps,
    String? after,
    Component? more,
  }) => Component.element(
    tag: 'dialog',
    id: 'help-$system',
    classes: 'install-help',
    attributes: {'aria-labelledby': 'help-$system-title'},
    children: [
      // Padded inside, so that only a click outside lands on the dialog.
      div([
        h2(id: 'help-$system-title', [Component.text(title)]),
        p([Component.text(why)]),
        ol([for (final step in steps) li(step)]),
        if (after != null) p([Component.text(after)]),
        p(classes: 'caution', [
          Component.text(
            'Only do this for a copy you downloaded from this site or from '
            'Amped\'s releases on GitHub.',
          ),
        ]),
        ?more,
        Component.element(
          tag: 'form',
          attributes: {'method': 'dialog'},
          children: [
            Component.element(
              tag: 'button',
              classes: 'button',
              children: [Component.text('Got it')],
            ),
          ],
        ),
      ]),
    ],
  );

  static Component _text(String words) => Component.text(words);

  /// The name of a button, menu or message, as the system shows it.
  static Component _name(String words) =>
      Component.element(tag: 'strong', children: [Component.text(words)]);

  /// The words of a heading whose colors shift.
  static Component _shine(String words) =>
      span(classes: 'shine', [Component.text(words)]);

  static Component _chips(List<String> labels) => ul(classes: 'chips', [
    for (final label in labels) li([Component.text(label)]),
  ]);

  /// Amped Modern playing: frames recorded from the app's own skin engine.
  /// Visitors who ask for less motion get one still frame.
  static Component _modernPlayer() => div(
    classes: 'stage',
    attributes: {'data-tilt': ''},
    [
      div(classes: 'tilt', [
        div(classes: 'player', [
          Component.element(
            tag: 'picture',
            children: [
              Component.element(
                tag: 'source',
                attributes: {
                  'srcset': 'images/modern.webp',
                  'type': 'image/webp',
                  'media': '(prefers-reduced-motion: no-preference)',
                },
              ),
              img(
                src: 'images/modern.png',
                alt: 'The Amped Modern skin, with its player and playlist '
                    'windows',
                width: 1062,
                height: 1134,
              ),
            ],
          ),
        ]),
      ]),
    ],
  );

  /// A picture of a skin, with the canvas player.js animates over it.
  static Component _player(
    String name,
    String description, {
    required int width,
    required int height,
    required int skinWidth,
  }) => div(
    classes: 'stage',
    attributes: {'data-tilt': ''},
    [
      div(classes: 'tilt', [
        div(classes: 'player', [
          img(
            src: 'images/$name.png',
            alt: description,
            width: width,
            height: height,
          ),
          Component.element(
            tag: 'canvas',
            attributes: {
              'width': '$width',
              'height': '$height',
              'data-player': name,
              'data-skin-width': '$skinWidth',
              'aria-hidden': 'true',
            },
          ),
        ]),
      ]),
    ],
  );
}
