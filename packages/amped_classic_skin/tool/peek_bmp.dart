import "dart:io";

import "package:amped_classic_skin/amped_classic_skin.dart";

void main(List<String> args) {
  final file = File(args[0]);
  final bytes = file.readAsBytesSync();
  final img = decodeBmp(bytes);
  final rect = _parseRect(
    args.length > 1 ? args[1] : "0,0,${img.width},${img.height}",
  );
  final mode = args.length > 2 ? args[2] : "text";
  final x = rect[0];
  final y = rect[1];
  final w = rect[2];
  final h = rect[3];
  stdout.writeln("$file ${img.width}x${img.height}");
  for (var row = 0; row < h; row++) {
    final sb = StringBuffer();
    for (var col = 0; col < w; col++) {
      final i = ((y + row) * img.width + (x + col)) * 4;
      final r = img.rgba[i];
      final g = img.rgba[i + 1];
      final b = img.rgba[i + 2];
      if (mode == "px") {
        sb.write("($r,$g,$b) ");
      } else {
        sb.write(r > 128 || g > 128 || b > 128 ? "#" : ".");
      }
    }
    stdout.writeln(sb.toString());
  }
}

List<int> _parseRect(String s) {
  final parts = s.split(",").map(int.parse).toList();
  if (parts.length == 4) return parts;
  throw ArgumentError("rect must be x,y,w,h");
}
