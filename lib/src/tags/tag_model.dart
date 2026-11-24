/// The format-neutral view of a file's tags that the File Info dialog shows
/// and edits.
library;

/// The fields of the File Info dialog's Basic Info tab
/// (`IDD_FILEINFO_METADATA` and `strfields` in the classic player's FileInfo.cpp).
enum TagField {
  track,
  disc,
  bpm,
  title,
  artist,
  album,
  albumArtist,
  year,
  genre,
  comment,
  composer,
  publisher,

  /// The Chromaprint fingerprint tag lookup computed, cached as Picard does
  /// (`ACOUSTID_FINGERPRINT`, ID3 `TXXX:Acoustid Fingerprint`). Not shown on
  /// the Basic Info tab.
  acoustIdFingerprint,
}

/// One raw tag item, as the file stores it (the Advanced tab).
class TagEntry {
  const TagEntry(this.name, this.value);

  /// The frame id, field name or chunk id.
  final String name;

  /// The decoded text, or a description of binary data.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is TagEntry && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => "$name=$value";
}

/// The container formats amped can read and write tags in.
enum TagFormat {
  mp3,
  flac,
  oggVorbis,
  oggOpus,
  oggSpeex,
  oggFlac,
  wav,

  /// Monkey's Audio, Musepack, WavPack, TTA, TAK and OptimFROG, whose tags
  /// are APEv2.
  apeTagged,
  unknown,
}

/// What [readFileTags] found in one file. Plain data, so it can cross
/// isolates.
class FileTags {
  const FileTags({
    required this.format,
    required this.tagTypes,
    required this.fields,
    required this.raw,
    required this.editable,
    this.id3v1,
    this.id3v2,
    this.stream = const StreamInfo(),
    this.error,
  });

  /// A file whose tags could not be read.
  const FileTags.unreadable(
    this.format,
    this.error, {
    this.stream = const StreamInfo(),
  }) : tagTypes = const [],
       id3v1 = null,
       id3v2 = null,
       fields = const {},
       raw = const [],
       editable = const {};

  final TagFormat format;

  /// The tag kinds present, e.g. `ID3v2.3`, `ID3v1`, `Vorbis comment`.
  final List<String> tagTypes;

  /// The Basic Info fields that have a value.
  final Map<TagField, String> fields;

  /// Every raw item of every tag, in file order.
  final List<TagEntry> raw;

  /// The fields that can be written to this file.
  final Set<TagField> editable;

  /// An MP3's ID3v1 and ID3v2 tags apart, with the fields each holds; null
  /// for a tag the file lacks, and for any file but an MP3.
  final Map<TagField, String>? id3v1;
  final Map<TagField, String>? id3v2;

  /// The audio stream's properties (the Format Info box).
  final StreamInfo stream;

  /// Why reading failed, when it did.
  final String? error;

  String operator [](TagField field) => fields[field] ?? "";
}

/// What the File Info dialog's ID3v1 and ID3v2 tabs change in an MP3, each
/// tag apart from the other and from the Basic Info tab's changes (which
/// go to both tags).
class Id3Edit {
  const Id3Edit({
    this.v1 = const {},
    this.v2 = const {},
    this.includeV1,
    this.includeV2,
  });

  /// Fields to set in the ID3v1 / ID3v2 tag alone (empty removes one).
  final Map<TagField, String> v1;
  final Map<TagField, String> v2;

  /// Whether the file should have each tag (the "Include ... tag in file"
  /// boxes); null leaves it as it is.
  final bool? includeV1;
  final bool? includeV2;

  bool get isEmpty =>
      v1.isEmpty && v2.isEmpty && includeV1 == null && includeV2 == null;
}

/// What the File Info dialog's Format Info and Replay Gain boxes show.
class StreamInfo {
  const StreamInfo({
    this.fileSize,
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.replayGain = const {},
  });

  final int? fileSize;
  final Duration? duration;

  /// In kbps.
  final int? bitrate;
  final int? sampleRate;
  final int? channels;

  /// `track_gain`, `track_peak`, `album_gain`, `album_peak`, when tagged.
  final Map<String, String> replayGain;
}

/// Thrown when tags can't be written to a file.
class TagWriteException implements Exception {
  const TagWriteException(this.message);

  final String message;

  @override
  String toString() => "TagWriteException: $message";
}

/// The genre list of the File Info dialog's combo box: the ID3v1 genres
/// with the classic player's extensions, in index order (`genres` in FileInfo.cpp).
const List<String> id3Genres = [
  "Blues",
  "Classic Rock",
  "Country",
  "Dance",
  "Disco",
  "Funk",
  "Grunge",
  "Hip-Hop",
  "Jazz",
  "Metal",
  "New Age",
  "Oldies",
  "Other",
  "Pop",
  "R&B",
  "Rap",
  "Reggae",
  "Rock",
  "Techno",
  "Industrial",
  "Alternative",
  "Ska",
  "Death Metal",
  "Pranks",
  "Soundtrack",
  "Euro-Techno",
  "Ambient",
  "Trip-Hop",
  "Vocal",
  "Jazz+Funk",
  "Fusion",
  "Trance",
  "Classical",
  "Instrumental",
  "Acid",
  "House",
  "Game",
  "Sound Clip",
  "Gospel",
  "Noise",
  "Alt Rock",
  "Bass",
  "Soul",
  "Punk",
  "Space",
  "Meditative",
  "Instrumental Pop",
  "Instrumental Rock",
  "Ethnic",
  "Gothic",
  "Darkwave",
  "Techno-Industrial",
  "Electronic",
  "Pop-Folk",
  "Eurodance",
  "Dream",
  "Southern Rock",
  "Comedy",
  "Cult",
  "Gangsta Rap",
  "Top 40",
  "Christian Rap",
  "Pop/Funk",
  "Jungle",
  "Native American",
  "Cabaret",
  "New Wave",
  "Psychedelic",
  "Rave",
  "Showtunes",
  "Trailer",
  "Lo-Fi",
  "Tribal",
  "Acid Punk",
  "Acid Jazz",
  "Polka",
  "Retro",
  "Musical",
  "Rock & Roll",
  "Hard Rock",
  "Folk",
  "Folk-Rock",
  "National Folk",
  "Swing",
  "Fast-Fusion",
  "Bebop",
  "Latin",
  "Revival",
  "Celtic",
  "Bluegrass",
  "Avantgarde",
  "Gothic Rock",
  "Progressive Rock",
  "Psychedelic Rock",
  "Symphonic Rock",
  "Slow Rock",
  "Big Band",
  "Chorus",
  "Easy Listening",
  "Acoustic",
  "Humour",
  "Speech",
  "Chanson",
  "Opera",
  "Chamber Music",
  "Sonata",
  "Symphony",
  "Booty Bass",
  "Primus",
  "Porn Groove",
  "Satire",
  "Slow Jam",
  "Club",
  "Tango",
  "Samba",
  "Folklore",
  "Ballad",
  "Power Ballad",
  "Rhythmic Soul",
  "Freestyle",
  "Duet",
  "Punk Rock",
  "Drum Solo",
  "A Cappella",
  "Euro-House",
  "Dance Hall",
  "Goa",
  "Drum & Bass",
  "Club-House",
  "Hardcore",
  "Terror",
  "Indie",
  "BritPop",
  "Afro-Punk",
  "Polsk Punk",
  "Beat",
  "Christian Gangsta Rap",
  "Heavy Metal",
  "Black Metal",
  "Crossover",
  "Contemporary Christian",
  "Christian Rock",
  "Merengue",
  "Salsa",
  "Thrash Metal",
  "Anime",
  "JPop",
  "Synthpop",
  "Abstract",
  "Art Rock",
  "Baroque",
  "Bhangra",
  "Big Beat",
  "Breakbeat",
  "Chillout",
  "Downtempo",
  "Dub",
  "EBM",
  "Eclectic",
  "Electro",
  "Electroclash",
  "Emo",
  "Experimental",
  "Garage",
  "Global",
  "IDM",
  "Illbient",
  "Industro-Goth",
  "Jam Band",
  "Krautrock",
  "Leftfield",
  "Lounge",
  "Math Rock",
  "New Romantic",
  "Nu-Breakz",
  "Post-Punk",
  "Post-Rock",
  "Psytrance",
  "Shoegaze",
  "Space Rock",
  "Trop Rock",
  "World Music",
  "Neoclassical",
  "Audiobook",
  "Audio Theatre",
  "Neue Deutsche Welle",
  "Podcast",
  "Indie Rock",
  "G-Funk",
  "Dubstep",
  "Garage Rock",
  "Psybient",
];
