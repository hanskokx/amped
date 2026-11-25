import "dart:async";

import "package:amped_jellyfin/amped_jellyfin.dart";
import "package:amped_l10n/amped_l10n.dart";
import "package:amped_plex/amped_plex.dart";
import "package:amped_podcast/amped_podcast.dart";
import "package:amped_soundcloud/amped_soundcloud.dart";
import "package:amped_subsonic/amped_subsonic.dart";
import "package:flutter/services.dart";
import "package:material_ui/material_ui.dart";

import "../../../../library/library_source_manager.dart";
import "../../../../library/source_settings.dart";
import "../../../../remote/browser_sign_in.dart";
import "../../../../remote/remote_credentials.dart";
import "../../../remote_source/classes/remote_source_type.dart";
import "../../../remote_source/widgets/preferences_subpage_header.dart";
import "../../../remote_source/widgets/source_panel.dart";
import "../../../remote_source/widgets/source_type_icon.dart";

/// The form that adds a remote source, or edits one. The server is contacted
/// before it is saved.
class SourceForm extends StatefulWidget {
  const SourceForm({
    required this.sources,
    required this.onDone,
    this.onBack,
    this.type = RemoteSourceType.navidrome,
    this.editing,
    super.key,
  });

  final LibrarySourceManager sources;

  /// The source being edited; null adds a new one.
  final RemoteSourceConfig? editing;

  /// What kind of source the form is for.
  final RemoteSourceType type;

  /// Called when the form is saved or cancelled.
  final VoidCallback onDone;

  /// Where the back arrow goes; [onDone] when null.
  final VoidCallback? onBack;

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

  /// What the last search found; null when there is none to show.
  List<PodcastSearchResult>? _results;
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
  bool _plexSignedIn = false;

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
      _plexSignedIn = true;
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

  /// Whether the fields that are needed are filled in.
  bool get _complete =>
      (_browserSignIn || _server.text.trim().isNotEmpty) &&
      (_tokenOnly || _user.text.trim().isNotEmpty) &&
      (widget.editing != null || _podcast || _password.text.isNotEmpty);

  Future<void> _save() async {
    final editing = widget.editing;
    if (_busy || !_complete) return;
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

  static InputDecoration _decoration(
    String label, {
    String? hint,
    String? helper,
    Widget? suffix,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    suffixIcon: suffix,
    border: const OutlineInputBorder(),
    isDense: true,
  );

  static const _gap = SizedBox(height: 12);

  /// The widest the fields get, so that they stay easy to read.
  static const _maxWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final editing = widget.editing;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_busy) widget.onDone();
        },
      },
      child: Column(
        children: [
          PreferencesSubpageHeader(
            title: editing == null
                ? localizations.libraryAddSourceTitle(
                    widget.type.title(localizations),
                  )
                : localizations.libraryEditSourceTitle(editing.name),
            leading: SourceTypeIcon(widget.type),
            onBack: _busy ? null : widget.onBack ?? widget.onDone,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_soundCloud) ..._soundCloudIntro(context),
                      if (_plex) ..._plexSignInSection(context),
                      if (_podcast && editing == null)
                        ..._podcastSearch(context),
                      ..._fields(context),
                      _gap,
                      _options(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          _footer(context),
        ],
      ),
    );
  }

  List<Widget> _soundCloudIntro(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      SourcePanel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.librarySoundCloudProOnly,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                localizations.librarySoundCloudInstructions,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      _gap,
    ];
  }

  List<Widget> _plexSignInSection(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: _signingIn || _busy
              ? null
              : () => unawaited(_signInWithPlex()),
          icon: _signingIn
              ? const _Spinner()
              : const Icon(Icons.open_in_new, size: 18),
          label: Text(
            _signingIn
                ? localizations.librarySourcePlexWaiting
                : localizations.librarySourcePlexSignIn,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _plexSignedIn
            ? localizations.libraryPlexSignedIn
            : localizations.libraryPlexOrToken,
        style: theme.textTheme.bodySmall,
      ),
      _gap,
      if (_plexUsers.length > 1) ...[
        DropdownButtonFormField<PlexUser>(
          initialValue: _plexUser,
          decoration: _decoration(localizations.librarySourcePlexUser),
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
        _gap,
        if (_plexUser?.protected ?? false) ...[
          TextField(
            controller: _plexPin,
            obscureText: true,
            decoration: _decoration(localizations.librarySourcePlexPin),
          ),
          _gap,
        ],
      ],
    ];
  }

  List<Widget> _podcastSearch(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final results = _results;
    return [
      TextField(
        controller: _term,
        autofocus: true,
        decoration: _decoration(
          localizations.librarySourcePodcastSearch,
          hint: localizations.libraryPodcastSearchHint,
          suffix: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: _Spinner(),
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: localizations.librarySourcePodcastSearch,
                  onPressed: () => unawaited(_search()),
                ),
        ),
        onSubmitted: (_) {
          if (!_searching) unawaited(_search());
        },
      ),
      if (results != null) ...[
        const SizedBox(height: 8),
        if (results.isEmpty)
          Text(localizations.libraryPodcastNoResults)
        else
          SourcePanel(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final result in results)
                    ListTile(
                      dense: true,
                      leading: _cover(result.image),
                      title: Text(result.name),
                      onTap: () => setState(() {
                        _server.text = result.feed;
                        _name.text = result.name;
                        _results = null;
                      }),
                    ),
                ],
              ),
            ),
          ),
      ],
      _gap,
      Text(
        localizations.libraryPodcastOrFeed,
        style: theme.textTheme.bodySmall,
      ),
      _gap,
    ];
  }

  Widget _cover(String? url) {
    const placeholder = SizedBox.square(
      dimension: 40,
      child: Icon(Icons.podcasts),
    );
    return url == null
        ? placeholder
        : Image.network(
            url,
            width: 40,
            height: 40,
            errorBuilder: (context, error, stack) => placeholder,
          );
  }

  /// Where the source is and how to sign in to it, then what to call it.
  List<Widget> _fields(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final editing = widget.editing != null;
    return [
      if (_soundCloud && !editing) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _browserSignIn,
          title: Text(localizations.librarySoundCloudBrowserSignIn),
          onChanged: _busy
              ? null
              : (value) => setState(() => _browserSignIn = value ?? false),
        ),
        if (_browserSignIn)
          SelectableText(
            localizations.librarySoundCloudRedirectHint(
              SoundCloudClient.redirectUriText(),
            ),
            style: theme.textTheme.bodySmall,
          ),
        _gap,
      ],
      if (!_browserSignIn) ...[
        TextField(
          controller: _server,
          // Plex starts with its sign-in button, a new podcast with the
          // search.
          autofocus: !_plex && !(_podcast && !editing),
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: _decoration(
            _soundCloud
                ? localizations.librarySoundCloudProfile
                : _podcast
                ? localizations.librarySourceFeedUrl
                : localizations.librarySourceServer,
            hint: _soundCloud
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
        _gap,
      ],
      if (!_tokenOnly) ...[
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: _decoration(
            _soundCloud
                ? localizations.librarySoundCloudClientId
                : localizations.librarySourceUser,
          ),
          textInputAction: TextInputAction.next,
        ),
        _gap,
      ],
      if (!_podcast) ...[
        TextField(
          controller: _password,
          obscureText: true,
          decoration: _decoration(
            _soundCloud
                ? localizations.librarySoundCloudClientSecret
                : _audiobookshelf
                ? localizations.librarySourceApiToken
                : _plex
                ? localizations.librarySourceToken
                : localizations.remoteLoginPassword,
            helper: !editing
                ? null
                : _soundCloud
                ? localizations.librarySoundCloudSecretKeep
                : localizations.librarySourcePasswordKeep,
          ),
          textInputAction: TextInputAction.next,
        ),
        _gap,
      ],
      TextField(
        controller: _name,
        decoration: _decoration(localizations.librarySourceNameOptional),
        onSubmitted: (_) => unawaited(_save()),
      ),
    ];
  }

  /// The settings that rarely need changing, closed until asked for.
  Widget _options(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final episodes = _podcast || _audiobookshelf;
    return SourcePanel(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          episodes
              ? localizations.librarySourceOptions
              : localizations.librarySourceOptionsRefresh,
        ),
        subtitle: Text(
          _settings.refresh
              ? localizations.libraryRefreshSummaryOn(
                  SourceSettingsSection.describe(
                    localizations,
                    _settings.refreshEvery,
                  ),
                )
              : localizations.libraryRefreshSummaryOff,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          SourceSettingsSection(
            settings: _settings,
            podcast: episodes,
            onChanged: (settings) => setState(() => _settings = settings),
          ),
        ],
      ),
    );
  }

  /// Cancel and save, always in view, with why saving failed.
  Widget _footer(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = _error;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                localizations.librarySourceFailed(error),
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: Text(localizations.cancel),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_server, _user, _password]),
                  builder: (context, _) => FilledButton.icon(
                    onPressed: _busy || !_complete
                        ? null
                        : () => unawaited(_save()),
                    icon: _busy ? const _Spinner() : null,
                    label: Text(
                      _busy
                          ? _browserSignIn
                                ? localizations.librarySourceWaitingForBrowser
                                : localizations.librarySourceChecking
                          : widget.editing != null
                          ? localizations.librarySourceSave
                          : _podcast
                          ? localizations.librarySourceSubscribe
                          : localizations.librarySourceConnect,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The small turning circle that stands for work being done.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
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
        if (podcast)
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
