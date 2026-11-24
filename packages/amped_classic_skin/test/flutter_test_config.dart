import "dart:async";
import "dart:convert";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

import "test_assets.dart";

/// Points the package's tests at the application's built-in skin assets.
///
/// The archives live in the app's `assets/skins`, not this package, so the
/// asset manifest and archives are served from test fixtures. Other assets
/// keep using `flutter test`'s own asset handler.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest = <Object?, Object?>{
    for (final asset in builtInSkinAssets.keys)
      asset: [
        <Object?, Object?>{"asset": asset},
      ],
  };
  final encodedManifest = const StandardMessageCodec().encodeMessage(
    manifest,
  )!;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final delegate = messenger.delegate;
  final previous = messenger.allMessagesHandler;
  messenger.allMessagesHandler = (channel, handler, message) {
    if (channel == "flutter/assets" && message != null) {
      final key = utf8.decode(
        message.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),
      );
      if (key == "AssetManifest.bin") {
        return Future<ByteData?>.value(encodedManifest);
      }
      final asset = builtInSkinAssets[key];
      if (asset != null) {
        return Future<ByteData?>.value(ByteData.sublistView(asset));
      }
    }
    if (previous != null) return previous(channel, handler, message);
    return handler?.call(message) ?? delegate.send(channel, message);
  };

  await testMain();
}
