/// The server did not accept the sign-in (or needs one).
class RemoteAuthException implements Exception {
  const RemoteAuthException(this.message);

  final String message;

  @override
  String toString() => "RemoteAuthException: $message";
}
