import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:amped_wasabi/amped_wasabi.dart";
import "package:archive/archive.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test(
    "a skin includes a plugin's files through the classic player's path variables",
    () async {
      final install = Directory.systemTemp.createTempSync("player");
      final skinDir = Directory.systemTemp.createTempSync("plugin_skin");
      addTearDown(() {
        WasabiSkinData.playerPath = null;
        install.deleteSync(recursive: true);
        skinDir.deleteSync(recursive: true);
      });
      Directory(
        "${install.path}/Plugins/ClassicPro/engine/widgets/load",
      ).createSync(recursive: true);
      File(
        "${install.path}/Plugins/ClassicPro/engine/load.xml",
      ).writeAsStringSync(
        '<include file="widgets\\load\\*.xml"/>',
      );
      for (final name in ["a", "b"]) {
        File(
          "${install.path}/Plugins/ClassicPro/engine/widgets/load/$name.xml",
        ).writeAsStringSync('<color id="$name.color" value="1,2,3"/>');
      }
      File("${skinDir.path}/skin.xml").writeAsStringSync('''
<WasabiXML version="1.2">
<include file="@COLORTHEMESPATH@/../../plugins/classicPro/engine/load.xml"/>
<container id="main"><layout id="normal" w="10" h="10"/></container>
</WasabiXML>''');

      // Without the plugin the include finds nothing.
      WasabiSkinData.playerPath = null;
      var skin = await WasabiSkinData.load(skinDir);
      expect(skin.sourceColor("a.color"), isNull);

      // With it, the include and the wildcard include inside it are read.
      WasabiSkinData.playerPath = install;
      skin = await WasabiSkinData.load(skinDir);
      expect(skin.sourceColor("a.color"), isNotNull);
      expect(skin.sourceColor("b.color"), isNotNull);
      expect(
        skin.expandPathVariables("@SKINPATH@x"),
        "${skinDir.path}/x",
      );
    },
  );

  test(
    "plugins mounted in memory are found without touching the disk",
    () async {
      final skinDir = Directory.systemTemp.createTempSync("plugin_mem");
      addTearDown(() {
        WasabiFiles.unmount();
        skinDir.deleteSync(recursive: true);
      });
      final zip = Archive()
        ..addFile(
          ArchiveFile.bytes(
            "Plugins/ClassicPro/engine/load.xml",
            utf8.encode('<include file="widgets\\load\\*.xml"/>'),
          ),
        )
        ..addFile(
          ArchiveFile.bytes(
            "Plugins/ClassicPro/engine/widgets/load/a.xml",
            utf8.encode('<color id="mem.color" value="4,5,6"/>'),
          ),
        );
      WasabiSkinData.mountPlugins(Uint8List.fromList(ZipEncoder().encode(zip)));
      File("${skinDir.path}/skin.xml").writeAsStringSync('''
<WasabiXML version="1.2">
<include file="@WINAMPPATH@\\Plugins\\classicpro\\ENGINE\\load.xml"/>
<container id="main"><layout id="normal" w="10" h="10"/></container>
</WasabiXML>''');
      final skin = await WasabiSkinData.load(skinDir);
      expect(skin.sourceColor("mem.color"), isNotNull);
    },
  );
}
