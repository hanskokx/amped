# Amped

Crank it up.

Amped is a desktop music player written in Flutter, for macOS, Windows and
Linux. It plays from files, streams and network shares, and from Plex,
Jellyfin, Subsonic/Navidrome, SoundCloud, Audiobookshelf, podcasts and
YouTube; and it wears skins: classic bitmap skins, Audacious and Bamp skins,
and modern (Wasabi) skins.

## Building

Amped's parts live in their own repositories in the
[Amped organization](https://git.hadak.org/Amped) (the skin engines, the
media sources, window docking, logging, ...). `flutter pub get` fetches them
from git; nothing else has to be checked out.

```shell
flutter pub get
flutter run -d macos   # or windows, linux
```

`assets/skins` holds the skins that ship with the app: `base-amped.wsz`
(the classic skin every other classic skin falls back to, which is why its file
name has to start with `base`) and `Amped-Modern.wal`.

## Supported formats

### Audio

| Format | Extensions | Played by | Tags (read and write) |
| --- | --- | --- | --- |
| MP3 | `.mp3` | SoLoud | ID3v1, ID3v2, APEv2 |
| WAV | `.wav` | SoLoud | RIFF INFO |
| FLAC | `.flac` | SoLoud | Vorbis comments, APEv2 |
| Ogg Vorbis | `.ogg`, `.oga` | SoLoud | Vorbis comments |
| Opus | `.opus`, `.ogg`, `.oga` | SoLoud | Vorbis comments |
| Ogg Speex | `.spx`, `.ogg`, `.oga` | media_kit | Vorbis comments |
| Ogg FLAC | `.oga`, `.ogg` | media_kit | Vorbis comments |
| Monkey's Audio | `.ape`, `.mac` | media_kit | APEv2 |
| Musepack | `.mpc`, `.mp+`, `.mpp` | media_kit | APEv2 |
| WavPack | `.wv` | media_kit | APEv2 |
| TTA | `.tta` | media_kit | APEv2 |
| TAK | `.tak` | media_kit | APEv2 |
| OptimFROG | `.ofr` | media_kit | APEv2 |

SoLoud plays its formats directly. The media_kit formats are decoded to a
temporary file first and then played through SoLoud, so the equalizer,
visualizations, volume, balance and seeking work the same for every format.
Files that share `.ogg` or `.oga` (Vorbis, Opus, Speex, Ogg FLAC) are told
apart by their content. URLs of media_kit formats are not supported.

### Video

Played through media_kit (the sound goes through SoLoud, the picture shows in
the Video window): `.avi`, `.mpg`, `.mpeg`, `.m2v`, `.mp4`, `.m4v`, `.mkv`,
`.webm`, `.mov`, `.wmv`, `.asf`, `.flv`, `.nsv`, `.ogv`, `.3gp`, `.ts`.

### Playlists

`.m3u`, `.m3u8`, `.pls`, read and written. Live Shoutcast/Icecast stream URLs
and HTTP files can be added too.

### Skins

- Classic skins: `.wsz`.
- Audacious and Bamp skins: `.zip` (plain zips), and the tarballs Audacious
  skins also come in: `.tar`, `.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz2`.
- Modern (Wasabi) skins: `.wal`.

## Linux build setup

Packages needed to build on Linux (GTK, X11 for the tray icon, libsecret for
saved network share logins, libmpv for audio and video playback):

```shell
sudo apt-get install libgtk-3-dev libx11-dev libxi-dev libsecret-1-dev libmpv-dev mpv
```

## YouTube (yt-dlp)

YouTube links are resolved with [yt-dlp](https://github.com/yt-dlp/yt-dlp),
which every build bundles. It is downloaded and checksum-verified
automatically the first time you build (network needed once; it is cached in
the `binaries` folder of the `amped_ytdlp` package). See the
[amped_ytdlp](https://git.hadak.org/Amped/amped_ytdlp) README for how it is
bundled and how to update it. On macOS the Runner's **Bundle yt-dlp** build
phase runs `macos/bundle_yt_dlp.sh`, which finds that package wherever pub put
it.

## Network shares

Amped plays from SMB (`smb://`) and WebDAV (`webdav://`, `webdavs://`) shares.
The names and passwords you enter are kept in the system's secure storage: the
Keychain on macOS, the Credential Manager on Windows and the Secret Service on
Linux.

On Linux, saving logins needs a Secret Service provider such as GNOME Keyring
or KeePassXC (libsecret, installed with the packages under
[Linux build setup](#linux-build-setup)).

## Tag lookup API key

Tag lookup identifies songs with AcoustID, which needs an application API key
(free at <https://acoustid.org/new-application>), built in at compile time:

```shell
flutter build macos --dart-define=ACOUSTID_API_KEY=your-key
```

Without a key, tag lookup says it isn't available in that build. Anything compiled into an app can be extracted from it, which is fine for
AcoustID's per-application keys.

## Git commit in the About dialog

On macOS the build stamps the short git commit into the app automatically. On
Linux and Windows, pass it at build time:

```shell
flutter build linux --dart-define=AMPED_GIT_COMMIT=$(git rev-parse --short HEAD)
```

## Native skin previews

`native/skin_preview` is the C renderer behind the Quick Look, Explorer and
freedesktop skin previews. The `packages/skin_preview` package, which draws
the in-app previews, compiles the same source.
