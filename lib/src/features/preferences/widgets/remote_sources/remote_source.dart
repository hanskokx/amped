import "dart:async";

import "package:amped_jellyfin/amped_jellyfin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_plex/amped_plex.dart";
import "package:amped_podcast/amped_podcast.dart";
import "package:amped_soundcloud/amped_soundcloud.dart";
import "package:amped_subsonic/amped_subsonic.dart";
import "package:material_ui/material_ui.dart";

import "../../../../library/library_source_manager.dart";
import "../../../../library/source_settings.dart";
import "../../../../remote/browser_sign_in.dart";
import "../../../../remote/remote_credentials.dart";
import "../../../remote_source/classes/remote_source_type.dart";

/// The form that adds a Navidrome/Subsonic server, or edits one. The server
/// is contacted before it is saved.
class SourceForm extends StatefulWidget {
  const SourceForm({
    required this.sources,
    required this.onDone,
    this.type = RemoteSourceType.navidrome,
    this.editing,
    super.key,
  });

  final LibrarySourceManager sources;

  /// The source being edited; null adds a new one.
  final RemoteSourceConfig? editing;

  /// What kind of source the form is for.
  final RemoteSourceType type;
  final VoidCallback onDone;

  @override
  State<SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<SourceForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? "",
  );
  late final TextEditingController _server = TextEditingController(
    text: widget.editing?.server ?? "",
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.editing?.user ?? "",
  );
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _browserSignIn = false;

  /// The source's refreshing and completion settings, as set so far.
  late SourceSettings _settings =
      widget.editing?.settings ??
      SourceSettings.usualFor(
        podcast:
            widget.type == RemoteSourceType.podcast ||
            widget.type == RemoteSourceType.audiobookshelf,
      );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _user.dispose();
    _password.dispose();
    _term.dispose();
    _plexPin.dispose();
    super.dispose();
  }

  bool get _soundCloud => widget.type == RemoteSourceType.soundcloud;
  bool get _plex => widget.type == RemoteSourceType.plex;
  bool get _jellyfin => widget.type == RemoteSourceType.jellyfin;
  bool get _podcast => widget.type == RemoteSourceType.podcast;
  bool get _audiobookshelf => widget.type == RemoteSourceType.audiobookshelf;

  /// Sources that sign in with a token alone, or not at all.
  bool get _tokenOnly => _plex || _audiobookshelf || _podcast;

  final TextEditingController _term = TextEditingController();
  List<PodcastSearchResult> _results = const [];
  bool _searching = false;

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final search = ItunesSearch();
    try {
      final results = await search.search(_term.text);
      if (mounted) setState(() => _results = results);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            PodcastException(:final message) => message,
            _ => "$error",
          };
        });
      }
    } finally {
      search.close();
      if (mounted) setState(() => _searching = false);
    }
  }

  bool _signingIn = false;

  /// The users of the signed-in Plex Home, and the one to present as.
  List<PlexUser> _plexUsers = const [];
  PlexUser? _plexUser;
  final TextEditingController _plexPin = TextEditingController();

  /// Opens plex.tv in the browser and waits for the user to approve; the
  /// token fills the form, and so does the server when none was typed.
  Future<void> _signInWithPlex() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final result = await widget.sources.signInToPlex();
      if (!mounted) return;
      _password.text = result.token;
      _plexUsers = result.users;
      _plexUser = null;
      _plexPin.clear();
      if (_server.text.trim().isEmpty && result.server != null) {
        _server.text = result.server!;
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            BrowserSignInException(:final message) => message,
            PlexException(:final message) => message,
            _ => "$error",
          };
        });
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    final editing = widget.editing;
    if ((_server.text.trim().isEmpty && !_browserSignIn) ||
        (!_tokenOnly && _user.text.trim().isEmpty)) {
      return;
    }
    if (editing == null && !_podcast && _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _plexUser;
      if (editing == null && _plex && user != null) {
        _password.text = await widget.sources.switchPlexUser(
          _password.text,
          user,
          pin: _plexPin.text,
        );
        _plexUsers = const [];
        _plexUser = null;
      }
      if (editing == null && _podcast) {
        await widget.sources.addPodcast(
          name: _name.text,
          feed: _server.text,
          settings: _settings,
        );
      } else if (editing == null && _audiobookshelf) {
        await widget.sources.addAudiobookshelf(
          name: _name.text,
          server: _server.text,
          token: _password.text,
          settings: _settings,
        );
      } else if (editing == null && _plex) {
        await widget.sources.addPlex(
          name: _name.text,
          server: _server.text,
          token: _password.text,
          settings: _settings,
        );
      } else if (editing == null && _jellyfin) {
        await widget.sources.addJellyfin(
          name: _name.text,
          server: _server.text,
          user: _user.text,
          password: _password.text,
          settings: _settings,
        );
      } else if (editing == null && _soundCloud) {
        await widget.sources.addSoundCloud(
          name: _name.text,
          profile: _server.text,
          clientId: _user.text,
          clientSecret: _password.text,
          browserSignIn: _browserSignIn,
          settings: _settings,
        );
      } else if (editing == null) {
        await widget.sources.addNavidrome(
          name: _name.text,
          server: _server.text,
          user: _user.text,
          password: _password.text,
          settings: _settings,
        );
      } else {
        await widget.sources.edit(
          editing.id,
          name: _name.text.trim().isEmpty ? editing.name : _name.text,
          server: _server.text,
          user: _podcast
              ? LibrarySourceManager.podcastUser
              : _tokenOnly
              ? LibrarySourceManager.plexUser
              : _user.text,
          password: _password.text.isEmpty ? null : _password.text,
          settings: _settings,
        );
      }
      if (mounted) widget.onDone();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (error) {
          RemoteAuthException(:final message) => message,
          SubsonicException(:final message) => message,
          SoundCloudException(:final message) => message,
          PlexException(:final message) => message,
          JellyfinException(:final message) => message,
          PodcastException(:final message) => message,
          _ => "$error",
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          _soundCloud
              ? localizations.libraryAddSoundCloud
              : _podcast
              ? localizations.libraryAddPodcast
              : _audiobookshelf
              ? localizations.libraryAddAudiobookshelf
              : _plex
              ? localizations.libraryAddPlex
              : _jellyfin
              ? localizations.libraryAddJellyfin
              : localizations.libraryAddNavidrome,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_soundCloud) ...[
          Text(
            localizations.librarySoundCloudProOnly,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(localizations.librarySoundCloudInstructions),
          const SizedBox(height: 12),
        ],
        if (_plex) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _signingIn || _busy
                  ? null
                  : () => unawaited(_signInWithPlex()),
              child: Text(
                _signingIn
                    ? localizations.librarySourcePlexWaiting
                    : localizations.librarySourcePlexSignIn,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_plexUsers.length > 1) ...[
            DropdownButtonFormField<PlexUser>(
              initialValue: _plexUser,
              decoration: InputDecoration(
                labelText: localizations.librarySourcePlexUser,
              ),
              items: [
                for (final user in _plexUsers)
                  DropdownMenuItem(value: user, child: Text(user.name)),
              ],
              onChanged: _busy
                  ? null
                  : (user) => setState(() {
                      _plexUser = user;
                      _plexPin.clear();
                    }),
            ),
            if (_plexUser?.protected ?? false)
              TextField(
                controller: _plexPin,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: localizations.librarySourcePlexPin,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
        if (_podcast && widget.editing == null) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _term,
                  decoration: InputDecoration(
                    labelText: localizations.librarySourcePodcastSearch,
                  ),
                  onSubmitted: (_) => unawaited(_search()),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _searching ? null : () => unawaited(_search()),
                child: Text(
                  _searching ? "..." : localizations.librarySourcePodcastSearch,
                ),
              ),
            ],
          ),
          for (final result in _results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: result.image == null
                  ? null
                  : Image.network(
                      result.image!,
                      width: 40,
                      height: 40,
                      errorBuilder: (context, error, stack) =>
                          const SizedBox(width: 40, height: 40),
                    ),
              title: Text(result.name),
              onTap: () => setState(() {
                _server.text = result.feed;
                _name.text = result.name;
                _results = const [];
              }),
            ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: localizations.librarySourceName,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        if (_soundCloud && widget.editing == null) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _browserSignIn,
            title: Text(localizations.librarySoundCloudBrowserSignIn),
            onChanged: (value) =>
                setState(() => _browserSignIn = value ?? false),
          ),
          if (_browserSignIn)
            Text(
              localizations.librarySoundCloudRedirectHint(
                SoundCloudClient.redirectUriText(),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (!_browserSignIn)
          TextField(
            controller: _server,
            decoration: InputDecoration(
              labelText: _soundCloud
                  ? localizations.librarySoundCloudProfile
                  : _podcast
                  ? localizations.librarySourceFeedUrl
                  : "URL",
              hintText: _soundCloud
                  ? "https://soundcloud.com/artist"
                  : _podcast
                  ? "https://example.com/feed.xml"
                  : _plex
                  ? "http://192.168.1.10:32400"
                  : _jellyfin
                  ? "http://192.168.1.10:8096"
                  : "https://music.example.com",
            ),
            textInputAction: TextInputAction.next,
          ),
        if (!_browserSignIn) const SizedBox(height: 8),
        if (!_tokenOnly) ...[
          TextField(
            controller: _user,
            decoration: InputDecoration(
              labelText: _soundCloud
                  ? localizations.librarySoundCloudClientId
                  : localizations.remoteLoginUser,
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
        ],
        if (!_podcast)
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _soundCloud
                  ? localizations.librarySoundCloudClientSecret
                  : _audiobookshelf
                  ? localizations.librarySourceApiToken
                  : _plex
                  ? localizations.librarySourceToken
                  : localizations.remoteLoginPassword,
              helperText: widget.editing == null
                  ? null
                  : _soundCloud
                  ? localizations.librarySoundCloudSecretKeep
                  : localizations.librarySourcePasswordKeep,
            ),
            onSubmitted: (_) => unawaited(_save()),
          ),
        const SizedBox(height: 16),
        SourceSettingsSection(
          settings: _settings,
          podcast: _podcast || _audiobookshelf,
          onChanged: (settings) => setState(() => _settings = settings),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            localizations.librarySourceFailed(_error!),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_save()),
              child: Text(
                _busy
                    ? _browserSignIn
                          ? localizations.librarySourceWaitingForBrowser
                          : localizations.librarySourceChecking
                    : localizations.librarySourceSave,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : widget.onDone,
              child: Text(localizations.cancel),
            ),
          ],
        ),
      ],
    );
  }
}

/// The settings of a source that are not about signing in: whether and how
/// often it is refreshed in the background and, for podcasts, when an
/// episode counts as played.
class SourceSettingsSection extends StatelessWidget {
  const SourceSettingsSection({
    required this.settings,
    required this.podcast,
    required this.onChanged,
    super.key,
  });

  final SourceSettings settings;

  /// Whether the source has episodes, which can be played or not.
  final bool podcast;
  final ValueChanged<SourceSettings> onChanged;

  /// "5 minutes", "1 hour", "30 seconds".
  static String describe(AppLocalizations localizations, Duration duration) =>
      duration.inSeconds >= 3600 && duration.inSeconds % 3600 == 0
      ? localizations.durationHours(duration.inHours)
      : duration.inSeconds >= 60 && duration.inSeconds % 60 == 0
      ? localizations.durationMinutes(duration.inMinutes)
      : localizations.durationSeconds(duration.inSeconds);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // A value saved by hand stays among the choices.
    List<T> choices<T extends Comparable<dynamic>>(
      List<T> offered,
      T current,
    ) => offered.contains(current) ? offered : ([...offered, current]..sort());
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          control,
        ],
      ),
    );
    Widget durations({
      required String label,
      required List<Duration> offered,
      required Duration current,
      required ValueChanged<Duration> onPicked,
      bool enabled = true,
    }) => row(
      label,
      DropdownButton<Duration>(
        value: current,
        onChanged: enabled
            ? (value) {
                if (value != null) onPicked(value);
              }
            : null,
        items: [
          for (final duration in choices(offered, current))
            DropdownMenuItem(
              value: duration,
              child: Text(describe(localizations, duration)),
            ),
        ],
      ),
    );
    final completion = settings.completion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.sourceRefreshTitle,
          style: theme.textTheme.titleSmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.refresh,
          title: Text(localizations.sourceRefreshEnabled),
          subtitle: Text(localizations.sourceRefreshHint),
          onChanged: (value) => onChanged(settings.copyWith(refresh: value)),
        ),
        durations(
          label: localizations.sourceRefreshEvery,
          offered: SourceSettings.intervals,
          current: settings.refreshEvery,
          enabled: settings.refresh,
          onPicked: (value) =>
              onChanged(settings.copyWith(refreshEvery: value)),
        ),
        durations(
          label: localizations.sourceRefreshFirst,
          offered: SourceSettings.startDelays,
          current: settings.refreshFirst,
          enabled: settings.refresh,
          onPicked: (value) =>
              onChanged(settings.copyWith(refreshFirst: value)),
        ),
        if (podcast) ...[
          const SizedBox(height: 16),
          Text(
            localizations.sourceCompletedTitle,
            style: theme.textTheme.titleSmall,
          ),
          Text(
            localizations.sourceCompletedHint,
            style: theme.textTheme.bodySmall,
          ),
          row(
            "",
            DropdownButton<CompletionMode>(
              value: completion.mode,
              onChanged: (value) {
                if (value != null) {
                  onChanged(
                    settings.copyWith(
                      completion: completion.copyWith(mode: value),
                    ),
                  );
                }
              },
              items: [
                DropdownMenuItem(
                  value: CompletionMode.percent,
                  child: Text(localizations.sourceCompletedPercent),
                ),
                DropdownMenuItem(
                  value: CompletionMode.remaining,
                  child: Text(localizations.sourceCompletedRemaining),
                ),
              ],
            ),
          ),
          if (completion.mode == CompletionMode.percent)
            row(
              "",
              DropdownButton<int>(
                value: completion.percent,
                onChanged: (value) {
                  if (value != null) {
                    onChanged(
                      settings.copyWith(
                        completion: completion.copyWith(percent: value),
                      ),
                    );
                  }
                },
                items: [
                  for (final percent in choices<int>(
                    PodcastCompletion.percentChoices,
                    completion.percent,
                  ))
                    DropdownMenuItem(
                      value: percent,
                      child: Text(localizations.percentValue(percent)),
                    ),
                ],
              ),
            )
          else
            durations(
              label: "",
              offered: PodcastCompletion.remainingChoices,
              current: completion.remaining,
              onPicked: (value) => onChanged(
                settings.copyWith(
                  completion: completion.copyWith(remaining: value),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
