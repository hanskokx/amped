/// Stand-in for amped_ytdlp: nothing is run.
library;

typedef LogCallback = void Function(
  String message, {
  Map<String, Object?>? metadata,
});

/// Finds no addresses.
class YtDlp {
  YtDlp({this.log});

  final LogCallback? log;

  Future<List<String>> addresses(String url, {required String format}) async =>
      const [];
}
