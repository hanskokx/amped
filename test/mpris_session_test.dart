import "dart:io";
import "dart:typed_data";

import "package:amped/src/app/mpris_session.dart";
import "package:dbus/dbus.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  late DBusServer server;
  late MprisSession session;
  late DBusClient shell;
  late DBusRemoteObject player;
  final commands = <(String, double?)>[];

  DBusClient connect(DBusAddress address) =>
      DBusClient(address, authClient: DBusAuthClient(uid: "1000"));

  setUp(() async {
    commands.clear();
    server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    session = MprisSession(
      (command, {position}) => commands.add((command, position)),
      client: connect(address),
    );
    shell = connect(address);
    player = DBusRemoteObject(
      shell,
      name: "org.mpris.MediaPlayer2.amped",
      path: DBusObjectPath("/org/mpris/MediaPlayer2"),
    );
    await session.setNowPlaying({
      "state": "playing",
      "title": "Llama Whippin' Intro",
      "artist": "DJ Mike Llama",
      "album": "Amped",
      "duration": 5,
      "elapsed": 1,
    });
  });

  tearDown(() async {
    await shell.close();
    await session.dispose();
    await server.close();
  });

  Future<DBusValue> property(String name) =>
      player.getProperty("org.mpris.MediaPlayer2.Player", name);

  test("publishes the current track", () async {
    expect(await property("PlaybackStatus"), const DBusString("Playing"));
    final metadata = (await property("Metadata")).asStringVariantDict();
    expect(metadata["xesam:title"], const DBusString("Llama Whippin' Intro"));
    expect(metadata["xesam:artist"], DBusArray.string(["DJ Mike Llama"]));
    expect(metadata["mpris:length"], const DBusInt64(5000000));
    final position = (await property("Position")).asInt64();
    expect(position, inInclusiveRange(1000000, 2000000));
  });

  test("publishes cover art as a file URL", () async {
    await session.setArtwork(Uint8List.fromList([1, 2, 3]));
    final metadata = (await property("Metadata")).asStringVariantDict();
    final url = Uri.parse(metadata["mpris:artUrl"]!.asString());
    expect(File.fromUri(url).readAsBytesSync(), [1, 2, 3]);
    await session.setArtwork(null);
    expect(File.fromUri(url).existsSync(), isFalse);
  });

  test("carries transport controls to the player", () async {
    const iface = "org.mpris.MediaPlayer2.Player";
    await player.callMethod(iface, "PlayPause", []);
    await player.callMethod(iface, "Next", []);
    await player.callMethod(iface, "Stop", []);
    final metadata = (await property("Metadata")).asStringVariantDict();
    await player.callMethod(iface, "SetPosition", [
      metadata["mpris:trackid"]!,
      const DBusInt64(3000000),
    ]);
    // Past the end skips to the next track, as the spec asks.
    await player.callMethod(iface, "Seek", [const DBusInt64(60000000)]);
    expect(commands, [
      ("togglePlayPause", null),
      ("next", null),
      ("stop", null),
      ("seek", 3.0),
      ("next", null),
    ]);
  });

  test("signals a seek", () async {
    final seeked = DBusRemoteObjectSignalStream(
      object: player,
      interface: "org.mpris.MediaPlayer2.Player",
      name: "Seeked",
    ).first;
    // Let the match rule reach the bus.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await session.setNowPlaying({
      "state": "playing",
      "title": "Llama Whippin' Intro",
      "artist": "DJ Mike Llama",
      "album": "Amped",
      "duration": 5,
      "elapsed": 4,
    });
    final signal = await seeked.timeout(const Duration(seconds: 2));
    expect(signal.values.single.asInt64(), inInclusiveRange(4000000, 5000000));
  });
}
