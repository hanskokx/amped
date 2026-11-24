import "package:amped_l10n/amped_l10n.dart";
import "package:material_ui/material_ui.dart";

import "../remote/remote_credentials.dart";

/// Asks for the name and password of a network share. The ones saved for
/// it come filled in; [onAnswer] gets the entered login, or null on Cancel.
class RemoteLoginPage extends StatefulWidget {
  const RemoteLoginPage({
    required this.request,
    required this.onAnswer,
    super.key,
  });

  final RemoteLoginRequest? request;
  final void Function(RemoteLogin? login) onAnswer;

  @override
  State<RemoteLoginPage> createState() => _RemoteLoginPageState();
}

class _RemoteLoginPageState extends State<RemoteLoginPage> {
  late final TextEditingController _user = TextEditingController(
    text: widget.request?.login?.user ?? "",
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.request?.login?.password ?? "",
  );

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_user.text.isEmpty) return;
    widget.onAnswer(RemoteLogin(_user.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final request = widget.request;
    final error = request?.error;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localizations.remoteLoginPrompt(request?.server ?? "")),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              localizations.remoteLoginFailed(error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _user,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.remoteLoginUser,
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: localizations.remoteLoginPassword,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => widget.onAnswer(null),
                child: Text(localizations.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Text(localizations.remoteLoginSignIn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
