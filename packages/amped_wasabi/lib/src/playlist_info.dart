import "wasabi_host.dart";

/// The playlist's `PE_Info` text feed: the selected and the total playing
/// time as `selected/total`, the string the classic player draws at the bottom of the
/// playlist (`draw_pe_infostr` in `draw_pe.cpp`). A `+` marks a time that
/// leaves out tracks of unknown length, `?` one made only of them.
String wasabiPlaylistInfo(WasabiHost host) {
  var selected = 0;
  var total = 0;
  var selectedUnknown = false;
  var totalUnknown = false;
  for (var i = 0; i < host.playlistLength; i++) {
    final ms = host.playlistItemLengthMs(i);
    final unknown = ms < 0;
    if (unknown) {
      totalUnknown = true;
    } else {
      total += ms ~/ 1000;
    }
    if (host.isPlaylistSelected(i)) {
      if (unknown) {
        selectedUnknown = true;
      } else {
        selected += ms ~/ 1000;
      }
    }
  }
  final info =
      "${_time(selected, unknown: selectedUnknown)}/"
      "${_time(total, unknown: totalUnknown)}";
  // The classic player keeps 17 characters of it.
  return info.length > 17 ? info.substring(0, 17) : info;
}

String _time(int seconds, {required bool unknown}) {
  if (seconds == 0) return unknown ? "?" : "0:00";
  String two(int n) => n.toString().padLeft(2, "0");
  final time = seconds < 60 * 60
      ? "${seconds ~/ 60}:${two(seconds % 60)}"
      : "${seconds ~/ 3600}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}";
  return unknown ? "$time+" : time;
}
