import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../../../../app/amped_shell.dart";
import "../../../../app/episode_click_action.dart";
import "../../../../app/notification_position.dart";

/// Preferences > General Preferences > Notifications: where Amped's own
/// notification appears.
class NotificationPreferencesPage extends StatelessWidget {
  const NotificationPreferencesPage({required this.shell, super.key});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.sources]),
      builder: (context, _) {
        // The skin's own options (when to show, fades) come first; the
        // position applies to every in-app notification, the skin's too.
        final inAppEnabled =
            shell.notifications.enabled && !shell.notifications.native;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: shell.notifications.enabled,
              title: Text(localizations.playbackNotifications),
              subtitle: Text(localizations.notificationsEnabledHint),
              onChanged: (value) =>
                  shell.notifications.setEnabled(enabled: value),
            ),
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: shell.notifications.native,
              title: Text(localizations.nativeNotifications),
              onChanged: shell.notifications.enabled
                  ? (value) =>
                        shell.notifications.setNative(enabled: value ?? false)
                  : null,
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: inAppEnabled ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: !inAppEnabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.inAppNotifications,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localizations.notificationPosition,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    localizations.notificationPositionDisplayed(
                                      positionLabel(
                                        localizations,
                                        shell.notifications.position,
                                      ),
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            NotificationPositionPicker(
                              selected: shell.notifications.position,
                              onSelected: shell.notifications.setPosition,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (shell.sources.hasPodcastSource) ...[
              const SizedBox(height: 12),
              Opacity(
                opacity: shell.notifications.enabled ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !shell.notifications.enabled,
                  child: _NewEpisodeSettings(shell: shell),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// What clicking the notification of newly added episodes does; shown only
/// when a podcast source could bring some.
class _NewEpisodeSettings extends StatelessWidget {
  const _NewEpisodeSettings({required this.shell});

  final AmpedShell shell;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final labels = {
      EpisodeClickAction.nothing: localizations.newEpisodeClickNothing,
      EpisodeClickAction.enqueue: localizations.newEpisodeClickEnqueue,
      EpisodeClickAction.play: localizations.newEpisodeClickPlay,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.newEpisodeNotifications,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    localizations.newEpisodeClickAction,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                RadioGroup<EpisodeClickAction>(
                  groupValue: shell.notifications.episodeClick,
                  onChanged: (value) {
                    if (value != null) {
                      shell.notifications.setEpisodeClick(value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final entry in labels.entries)
                        RadioListTile<EpisodeClickAction>(
                          dense: true,
                          value: entry.key,
                          title: Text(entry.value),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The lowercase name of [position] for a sentence.
String positionLabel(
  AppLocalizations localizations,
  NotificationPosition position,
) => switch (position) {
  NotificationPosition.topLeft => localizations.notificationPositionTopLeft,
  NotificationPosition.topCenter => localizations.notificationPositionTopCenter,
  NotificationPosition.topRight => localizations.notificationPositionTopRight,
  NotificationPosition.bottomLeft =>
    localizations.notificationPositionBottomLeft,
  NotificationPosition.bottomCenter =>
    localizations.notificationPositionBottomCenter,
  NotificationPosition.bottomRight =>
    localizations.notificationPositionBottomRight,
};

/// A miniature screen with a pill at each of the six positions; the chosen
/// one is highlighted and checked.
class NotificationPositionPicker extends StatelessWidget {
  const NotificationPositionPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final NotificationPosition selected;
  final ValueChanged<NotificationPosition> onSelected;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      height: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final top in const [true, false])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final position in NotificationPosition.values.where(
                  (position) => position.isTop == top,
                ))
                  Tooltip(
                    message: positionLabel(localizations, position),
                    child: GestureDetector(
                      key: ValueKey(position),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(position),
                      child: _PositionPill(selected: position == selected),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PositionPill extends StatelessWidget {
  const _PositionPill({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 60,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: selected
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

/// A modern skin's own notifier options, the same ones as its config
/// drawer's Notifications page: when it shows, whether fullscreen and the
/// artwork matter, and how long it fades and stays.
class SkinNotifierOptions extends StatelessWidget {
  const SkinNotifierOptions({required this.shell, super.key});

  final AmpedShell shell;

  static const _fullscreen = "Disable in fullscreen";
  static const _artwork = "Show Now Playing Artwork";
  static const _fadeIn = "Notifications fade in time";
  static const _hold = "Notifications display time";
  static const _fadeOut = "Notifications fade out time";

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = shell.notifications.skinNotifierMode;
    final labels = {
      SkinNotifierMode.always: localizations.notificationShowAlways,
      SkinNotifierMode.windowshade: localizations.notificationShowWindowshade,
      SkinNotifierMode.minimized: localizations.notificationShowMinimized,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.skinNotifications,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        RadioGroup<SkinNotifierMode>(
          groupValue: mode,
          onChanged: (value) {
            if (value != null) shell.notifications.setSkinNotifierMode(value);
          },
          child: Column(
            children: [
              for (final entry in labels.entries)
                RadioListTile<SkinNotifierMode>(
                  dense: true,
                  value: entry.key,
                  title: Text(entry.value),
                ),
            ],
          ),
        ),
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: shell.notifications.skinNotifierOption(_fullscreen) == "1",
          title: Text(localizations.notificationDisableFullscreen),
          onChanged: (value) => shell.notifications.setSkinNotifierOption(
            _fullscreen,
            value! ? "1" : "0",
          ),
        ),
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: shell.notifications.skinNotifierOption(_artwork) == "1",
          title: Text(localizations.notificationShowArtwork),
          onChanged: (value) => shell.notifications.setSkinNotifierOption(
            _artwork,
            value! ? "1" : "0",
          ),
        ),
        _SkinSeconds(
          shell: shell,
          option: _fadeIn,
          label: localizations.notificationFadeIn,
        ),
        _SkinSeconds(
          shell: shell,
          option: _hold,
          label: localizations.notificationHold,
        ),
        _SkinSeconds(
          shell: shell,
          option: _fadeOut,
          label: localizations.notificationFadeOut,
        ),
      ],
    );
  }
}

/// A skin option holding milliseconds, edited in seconds (0 to 10).
class _SkinSeconds extends StatelessWidget {
  const _SkinSeconds({
    required this.shell,
    required this.option,
    required this.label,
  });

  final AmpedShell shell;
  final String option;
  final String label;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final millis =
        int.tryParse(shell.notifications.skinNotifierOption(option) ?? "") ?? 0;
    final seconds = (millis / 1000).clamp(0, 10).toDouble();
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Slider(
            value: seconds,
            max: 10,
            divisions: 40,
            onChanged: (value) => shell.notifications.setSkinNotifierOption(
              option,
              "${(value * 1000).round()}",
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            localizations.notificationSeconds(seconds.toStringAsFixed(1)),
          ),
        ),
      ],
    );
  }
}
