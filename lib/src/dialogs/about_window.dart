import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart" show AppLogging;
import "package:amped_wasabi/amped_wasabi.dart";
import "package:material_ui/material_ui.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "bug_report.dart";

/// The short git commit the build was made from, passed at build time with
/// `--dart-define=AMPED_GIT_COMMIT=$(git rev-parse --short HEAD)`.
const String _gitCommit = String.fromEnvironment("AMPED_GIT_COMMIT");

/// The About window: what Amped is and, for a modern skin that draws a
/// panel about itself, that panel on a tab of its own. The window has a fixed
/// size ([AmpedDialog.about]), which all of it has to fit.
class AboutWindow extends StatelessWidget {
  const AboutWindow({
    required this.skin,
    required this.host,
    this.reportNote,
    super.key,
  });

  /// The active skin, when it is a modern one.
  final WasabiSkinData? skin;
  final WasabiHost host;

  /// What shows under the bug report button before it is pressed.
  @visibleForTesting
  final String? reportNote;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final skin = this.skin;
    final page = _AboutPage(reportNote: reportNote);
    if (skin == null || !WasabiAboutPanel.isIn(skin)) return page;
    return DefaultTabController(
      // Another skin starts on the first tab again.
      key: ObjectKey(skin),
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: localizations.appName),
              Tab(text: localizations.skinMenu),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                page,
                Center(
                  child: WasabiAboutPanel(skin: skin, host: host),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutPage extends StatefulWidget {
  const _AboutPage({this.reportNote});

  final String? reportNote;

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();
  late String? _reportNote = widget.reportNote;

  Future<void> _reportBug() async {
    final localizations = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final info = await _info;
    final opened = await BugReport.open(
      environment: BugReport.environment(
        version: info.version,
        buildNumber: info.buildNumber,
        commit: _gitCommit,
        locale: locale,
      ),
      logs: AppLogging.recent.text,
    );
    if (!mounted) return;
    setState(() {
      _reportNote = opened
          ? localizations.aboutReportBugNote
          : localizations.aboutReportBugFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SelectionArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset("assets/icons/about_icon.png", width: 96, height: 96),
              const SizedBox(height: 16),
              Text(
                localizations.appName,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              FutureBuilder<PackageInfo>(
                future: _info,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  if (info == null) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Version ${info.version} (${info.buildNumber})"),
                      if (_gitCommit.isNotEmpty) const Text(_gitCommit),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(localizations.ampedTagline),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(BugReport.website),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  "www.amped-player.com",
                  style: TextStyle(decoration: TextDecoration.underline),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _reportBug,
                icon: const Icon(Icons.bug_report_outlined),
                label: Text(localizations.aboutReportBug),
              ),
              if (_reportNote != null) ...[
                const SizedBox(height: 12),
                Text(
                  _reportNote!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
