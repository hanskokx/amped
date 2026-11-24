import "package:amped_classic_skin/amped_classic_skin.dart";
import "package:amped_skin/amped_skin.dart";
import "package:flutter/widgets.dart";

import "../player/playlist.dart";
import "../player/tag_cache.dart";
import "../skin/skin_views.dart";
import "amped_shell.dart";
import "notifications.dart";
import "skinned_window.dart";

/// The playback notification of skins without a notifier of their own: a
/// `gen.bmp` frame in the skin (like the Album Art window) around the
/// playing item's cover and details, in the skin's playlist colors.
class NotificationView extends StatelessWidget {
  const NotificationView({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.player, shell.skins]),
      builder: (context, _) {
        final scale = shell.windowState.scaleOf(SkinWindow.notifier);
        final size = shell.windowState.baseSize(SkinWindow.notifier);
        final player = shell.player;
        final status = player.paused
            ? "Playback paused"
            : player.playing
            ? "New track"
            : "Playback stopped";
        // Not draggable and not closable: a click brings the player
        // forward, and the frame's own buttons never see the pointer.
        return _Slide(
          anchor: shell.notifications.position.slideAnchor,
          revealed: shell.notifications.revealed,
          duration: Notifications.slide,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: shell.activateApplication,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                    size: size * scale,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      filterQuality: FilterQuality.none,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: size.width,
                        maxWidth: size.width,
                        minHeight: size.height,
                        maxHeight: size.height,
                        child: ActiveWindow(
                          child: SkinButtonScope(
                            child: IgnorePointer(
                              child: AlbumArtWindow(
                                host: shell.classic,
                                title: status,
                                showControls: false,
                                content: NotificationDetails(shell: shell),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reveals [child] from the [anchor] edge outward, and takes it back in.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.anchor,
    required this.revealed,
    required this.duration,
    required this.child,
  });

  final Alignment anchor;
  final bool revealed;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: revealed ? 1 : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, factor, child) => Align(
        alignment: anchor,
        child: ClipRect(
          child: Align(alignment: anchor, widthFactor: factor, child: child),
        ),
      ),
      child: child,
    );
  }
}

/// The cover, position, title, artist and album inside the frame.
class NotificationDetails extends StatelessWidget {
  const NotificationDetails({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.player, shell.albumArt]),
      builder: (context, _) {
        final colors = shell.skins.current.classicData.pledit;
        final playlist = shell.player.playlist;
        final entry = playlist.currentEntry;
        final family = colors.fontName.isEmpty ? null : colors.fontName;
        TextStyle style(Color color, double size) => TextStyle(
          color: color,
          fontFamily: family,
          fontSize: size,
          height: 1.15,
          decoration: TextDecoration.none,
        );
        final text = entry == null
            ? null
            : NotificationText.of(
                entry,
                playlist.current,
                playlist.length,
                tags: shell.sources.tagsOf(entry.location),
              );
        final title = text?.title ?? "Amped";
        final album = text?.album;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: colors.normalBg,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 66,
                    child: RawImage(
                      image: shell.albumArt.image,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text?.position ?? "",
                          style: style(colors.normal, 10),
                        ),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style(colors.current, 12),
                        ),
                        if (text?.artist case final artist?)
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style(colors.normal, 10),
                          ),
                        if (album != null)
                          Text(
                            album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style(colors.normal, 10),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The lines a track's notification shows, in the in-app popup and the
/// system one alike.
class NotificationText {
  const NotificationText({
    required this.position,
    required this.title,
    this.artist,
    this.album,
  });

  /// "3 of 161".
  final String position;

  /// The title with its length: "Song (3:03)".
  final String title;
  final String? artist;

  /// The album with its track number: "Album (Track 3)".
  final String? album;

  /// The lines for [entry], the [index]th of [count]. [tags] are what its
  /// source knows of it, which fill in what the entry itself does not (an
  /// item restored from a saved playlist before its source loaded).
  ///
  /// A podcast episode is "Show (Episode 4)" where a track is "Album (Track
  /// 4)", and has no artist line when that is only the show again.
  factory NotificationText.of(
    PlaylistEntry entry,
    int index,
    int count, {
    TrackTags? tags,
  }) {
    final duration = entry.duration ?? tags?.duration;
    final number = entry.trackNumber ?? tags?.trackNumber;
    final album = _nonEmpty(entry.album) ?? _nonEmpty(tags?.album);
    final artist = _nonEmpty(entry.artist) ?? _nonEmpty(tags?.artist);
    final podcast =
        (entry.genres.isEmpty ? tags?.genres : entry.genres)?.contains(
          "Podcast",
        ) ??
        false;
    final audiobook =
        (entry.genres.isEmpty ? tags?.genres : entry.genres)?.contains(
          "Audiobook",
        ) ??
        false;
    final noun = podcast
        ? "Episode"
        : audiobook
        ? "Part"
        : "Track";
    return NotificationText(
      position: "${index + 1} of $count",
      title:
          "${_name(entry, tags)}"
          "${duration == null ? "" : " (${_length(duration)})"}",
      artist: artist == album ? null : artist,
      album: album == null
          ? (number == null ? null : "$noun $number")
          : number == null
          ? album
          : "$album ($noun $number)",
    );
  }
}

String? _nonEmpty(String? text) =>
    text == null || text.trim().isEmpty ? null : text;

/// What to call [entry]: its station or track title, else its display
/// title, else its file's name (an untagged file has no title at all).
String _name(PlaylistEntry entry, [TrackTags? tags]) {
  for (final name in [
    entry.streamTitle,
    entry.trackTitle,
    tags?.title,
    entry.title,
  ]) {
    if (name != null && name.trim().isNotEmpty) return name;
  }
  final file = entry.location.split(RegExp(r"[/\\]")).last;
  final dot = file.lastIndexOf(".");
  return dot > 0 ? file.substring(0, dot) : file;
}

String _length(Duration d) {
  String two(int n) => n.toString().padLeft(2, "0");
  final seconds = two(d.inSeconds % 60);
  return d.inHours > 0
      ? "${d.inHours}:${two(d.inMinutes % 60)}:$seconds"
      : "${d.inMinutes}:$seconds";
}
