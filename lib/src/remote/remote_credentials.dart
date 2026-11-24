import "dart:convert";

import "package:amped_logging/amped_logging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";

export "package:amped_media_source/amped_media_source.dart"
    show RemoteAuthException;

/// A name and password for a network share.
@immutable
class RemoteLogin {
  const RemoteLogin(this.user, this.password);

  final String user;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is RemoteLogin && other.user == user && other.password == password;

  @override
  int get hashCode => Object.hash(user, password);
}

/// What the sign-in dialog is shown for.
@immutable
class RemoteLoginRequest {
  const RemoteLoginRequest(this.server, {this.login, this.error});

  /// The server, without credentials: `smb://nas`.
  final String server;

  /// The name and password to start with: the ones saved before.
  final RemoteLogin? login;

  /// Why the earlier sign-in failed, when one did.
  final String? error;
}

/// Asks the user to sign in; null when they cancel.
typedef RemoteLoginPrompt = Future<RemoteLogin?> Function(
  RemoteLoginRequest request,
);

/// Where the names and passwords of network shares are kept, by server.
abstract class RemoteCredentialStore {
  Future<RemoteLogin?> read(String server);

  Future<void> write(String server, RemoteLogin login);

  /// Forgets the login of [server].
  Future<void> delete(String server);
}

/// Keeps them in the system's secure storage: the Keychain on macOS, the
/// Credential Manager on Windows, the Secret Service (libsecret) on Linux.
class SecureCredentialStore implements RemoteCredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The app isn't sandboxed, so it uses the login keychain
            // rather than one that needs a signed keychain group.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  static String _key(String server) => "amped.remote.$server";

  @override
  Future<RemoteLogin?> read(String server) async {
    try {
      final text = await _storage.read(key: _key(server));
      if (text == null) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      return RemoteLogin(json["user"] as String, json["password"] as String);
    } on Object catch (error) {
      Arcane.log(
        "Could not read the saved login",
        metadata: {"server": server, "error": "$error"},
        level: Level.warning,
        module: "RemoteCredentials",
      );
      return null;
    }
  }

  @override
  Future<void> write(String server, RemoteLogin login) async {
    try {
      await _storage.write(
        key: _key(server),
        value: jsonEncode({"user": login.user, "password": login.password}),
      );
    } on Object catch (error) {
      Arcane.log(
        "Could not save the login",
        metadata: {"server": server, "error": "$error"},
        level: Level.warning,
        module: "RemoteCredentials",
      );
    }
  }

  @override
  Future<void> delete(String server) async {
    try {
      await _storage.delete(key: _key(server));
    } on Object catch (error) {
      Arcane.log(
        "Could not forget the login",
        metadata: {"server": server, "error": "$error"},
        level: Level.warning,
        module: "RemoteCredentials",
      );
    }
  }
}
