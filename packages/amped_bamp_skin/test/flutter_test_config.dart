import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

/// Serves the base skin archive the classic loader needs from this package's
/// tests: the application ships it in `assets/skins`, not in this package.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = File(
    "test/fixtures/base.wsz",
  ).readAsBytesSync();
  final assets = <String, Uint8List>{"assets/skins/base-amped.wsz": base};
  final manifest = <Object?, Object?>{
    for (final asset in assets.keys)
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
      final asset = assets[key];
      if (asset != null) {
        return Future<ByteData?>.value(ByteData.sublistView(asset));
      }
    }
    if (previous != null) return previous(channel, handler, message);
    return handler?.call(message) ?? delegate.send(channel, message);
  };

  await testMain();
}
