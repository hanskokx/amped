import "dart:async";
import "dart:typed_data";

import "package:amped_l10n/amped_l10n.dart";
import "package:amped_logging/amped_logging.dart";
import "package:flutter/services.dart" show LogicalKeyboardKey;
import "package:material_ui/material_ui.dart";

import "../player/album_art_fetch.dart";
import "../tags/tag_io.dart";
import "../tags/tag_lookup.dart";
import "file_icon.dart";
import "fingerprint_image.dart";
import "tag_lookup_dialog.dart";

/// Reads the tags of a file (a background read in the app; tests pass a
/// synchronous one).
typedef TagReader = Future<FileTags> Function(String path);

/// Saves the changed fields of a file.
typedef TagSaver = Future<void> Function(
  String path,
  Map<TagField, String> changes,
);

/// Saves the changed fields of a file and, when given, replaces its
/// embedded pictures.
typedef FileInfoSaver = Future<void> Function(
  String path,
  Map<TagField, String> changes, {
  List<EmbeddedPicture>? pictures,
  Id3Edit? id3,
});

/// Reads the pictures embedded in a file.
typedef PictureReader = Future<FilePictures> Function(String path);

/// Lets the user pick an image file; its bytes, or `null` when cancelled.
typedef ImageOpener = Future<Uint8List?> Function();

/// Lets the user save a picture to an image file.
typedef ImageExporter = Future<void> Function(EmbeddedPicture picture);

/// The classic player's File Info dialog (`IDD_FILEINFO` with its Basic Info tab,
/// `IDD_FILEINFO_METADATA`, from FileInfo.cpp): the file name, the tag
/// fields to edit, the format and ReplayGain info, an Advanced tab listing
/// every raw tag item, an Artwork tab (`IDD_FILEINFO_ARTWORK`) to view,
/// add, replace, export and remove embedded pictures, and OK/Cancel. OK
/// writes only the fields that were changed, and the pictures when they
/// were. "Look up tags..." fills the fields from MusicBrainz (still unsaved
/// until OK).
class FileInfoPage extends StatefulWidget {
  const FileInfoPage({
    required this.path,
    required this.read,
    required this.readPictures,
    required this.save,
    required this.openImage,
    required this.exportImage,
    required this.onClose,
    this.lookup,
    this.downloadImage = _fetchArt,
    this.storeImage,
    this.makeFileIcon = scaleToFileIcon,
    super.key,
  });

  final String path;
  final TagReader read;
  final PictureReader readPictures;
  final FileInfoSaver save;
  final ImageOpener openImage;
  final ImageExporter exportImage;

  /// Looks up tags online; no "Look up tags..." button without one.
  final TagLookupFn? lookup;

  /// Keeps a cover in the database for a file that can't hold pictures;
  /// without it, Download needs a file that can.
  final Future<bool> Function(String path, Uint8List bytes)? storeImage;

  /// Finds the cover of an album online (the "Download Artwork" button).
  final Future<Uint8List?> Function({
    required String artist,
    required String album,
  })
  downloadImage;

  /// Makes the 32x32 PNG file icon from a front cover's image, or null
  /// when it can't.
  final Future<Uint8List?> Function(Uint8List cover) makeFileIcon;

  /// Called after OK (once saved) or Cancel, with whether it was OK.
  final void Function({required bool ok}) onClose;

  @override
  State<FileInfoPage> createState() => _FileInfoPageState();
}

Future<Uint8List?> _fetchArt({
  required String artist,
  required String album,
}) => fetchAlbumArt(artist: artist, album: album);

class _FileInfoPageState extends State<FileInfoPage> {
  FileTags? _tags;
  final Map<TagField, TextEditingController> _controllers = {
    for (final field in TagField.values) field: TextEditingController(),
  };

  /// The ID3v1 and ID3v2 tabs' fields (an MP3's two tags, edited apart).
  final Map<TagField, TextEditingController> _v1Controllers = {
    for (final field in _id3v1Fields) field: TextEditingController(),
  };
  final Map<TagField, TextEditingController> _v2Controllers = {
    for (final field in _id3v2Fields) field: TextEditingController(),
  };

  /// The "Include ... tag in file" boxes.
  bool _includeV1 = false;
  bool _includeV2 = false;

  late final TextEditingController _path = TextEditingController(
    text: widget.path,
  );
  bool _saving = false;
  String? _saveError;

  /// Whether a lookup's tags were put into the fields.
  bool _lookupApplied = false;

  /// What the file holds, once read.
  FilePictures? _filePictures;

  /// The pictures as edited.
  List<EmbeddedPicture> _pictures = const [];
  bool _picturesChanged = false;
  int? _selectedPicture;

  /// The type a loaded picture gets (the "Artwork type" combo box).
  ArtworkType _newPictureType = ArtworkType.frontCover;

  /// Whether the last picked file wasn't an image.
  bool _notAnImage = false;

  /// Whether a cover is being downloaded, or none was found.
  bool _downloading = false;
  bool _noDownload = false;

  /// Whether the downloaded cover went to the database.
  bool _storedInDatabase = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadPictures());
  }

  Future<void> _loadPictures() async {
    FilePictures pictures;
    try {
      pictures = await widget.readPictures(widget.path);
    } on Object catch (error) {
      pictures = FilePictures.unreadable("$error");
    }
    if (!mounted) return;
    setState(() {
      _filePictures = pictures;
      _pictures = pictures.pictures;
      _selectedPicture = _pictures.isEmpty
          ? null
          : _pictures.indexOf(pictures.cover!);
    });
  }

  /// Load Artwork... (a new picture of [_newPictureType], replacing one of
  /// that type) or, with [replaceSelected], Change... (new image data for
  /// the selected picture).
  Future<void> _loadPicture({required bool replaceSelected}) async {
    final Uint8List? data;
    try {
      data = await widget.openImage();
    } on Object catch (error) {
      Arcane.log(
        "Could not load the image",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileInfoPage",
      );
      return;
    }
    if (data == null || !mounted) return;
    _applyPicture(data, replaceSelected: replaceSelected);
  }

  /// The "Download Artwork" button: the album's cover from the web, as a
  /// new picture of [_newPictureType].
  Future<void> _downloadPicture() async {
    final artist = _controllers[TagField.artist]!.text.trim();
    final album = _controllers[TagField.album]!.text.trim();
    if (artist.isEmpty || album.isEmpty) {
      setState(() => _noDownload = true);
      return;
    }
    setState(() {
      _downloading = true;
      _noDownload = false;
    });
    Uint8List? data;
    try {
      data = await widget.downloadImage(artist: artist, album: album);
    } on Object catch (error) {
      Arcane.log(
        "Could not download the artwork",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileInfoPage",
      );
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    if (data == null) {
      setState(() => _noDownload = true);
      return;
    }
    if (_filePictures?.editable ?? true) {
      _applyPicture(data, replaceSelected: false);
      return;
    }
    // The file can't hold it: kept in the database, now rather than on OK.
    final stored = await widget.storeImage?.call(widget.path, data) ?? false;
    if (!mounted) return;
    setState(() {
      _noDownload = !stored;
      _storedInDatabase = stored;
    });
  }

  void _applyPicture(Uint8List data, {required bool replaceSelected}) {
    final mime = sniffImageMime(data);
    if (mime == null) {
      setState(() => _notAnImage = true);
      return;
    }
    setState(() {
      _notAnImage = false;
      final pictures = [..._pictures];
      final selected = _selectedPicture;
      if (replaceSelected && selected != null) {
        final old = pictures[selected];
        pictures[selected] = EmbeddedPicture(
          type: old.type,
          mimeType: mime,
          description: old.description,
          data: data,
        );
      } else {
        final picture = EmbeddedPicture(
          type: _newPictureType,
          mimeType: mime,
          data: data,
        );
        final same = pictures.indexWhere((p) => p.type == _newPictureType);
        if (same < 0) {
          pictures.add(picture);
          _selectedPicture = pictures.length - 1;
        } else {
          pictures[same] = picture;
          _selectedPicture = same;
        }
      }
      _pictures = pictures;
      _picturesChanged = true;
    });
    final applied = _selectedPicture;
    if (applied != null && _pictures[applied].type == ArtworkType.frontCover) {
      unawaited(_addFileIcon(data));
    }
  }

  /// Sets the file icon to [cover] (scaled down), replacing any there is.
  Future<void> _addFileIcon(Uint8List cover) async {
    final Uint8List? icon;
    try {
      icon = await widget.makeFileIcon(cover);
    } on Object catch (error) {
      Arcane.log(
        "Could not make the file icon",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileInfoPage",
      );
      return;
    }
    if (icon == null || !mounted) return;
    final made = EmbeddedPicture(
      type: ArtworkType.fileIcon,
      mimeType: "image/png",
      data: icon,
    );
    setState(() {
      final pictures = [..._pictures];
      final old = pictures.indexWhere((p) => p.type == ArtworkType.fileIcon);
      if (old < 0) {
        pictures.add(made);
      } else {
        pictures[old] = made;
      }
      _pictures = pictures;
      _picturesChanged = true;
    });
  }

  void _deletePicture() {
    final selected = _selectedPicture;
    if (selected == null) return;
    setState(() {
      _pictures = [..._pictures]..removeAt(selected);
      _picturesChanged = true;
      _notAnImage = false;
      _selectedPicture = _pictures.isEmpty
          ? null
          : selected.clamp(0, _pictures.length - 1);
    });
  }

  Future<void> _exportPicture() async {
    final selected = _selectedPicture;
    if (selected == null) return;
    try {
      await widget.exportImage(_pictures[selected]);
    } on Object catch (error) {
      Arcane.log(
        "Could not save the image",
        metadata: {"error": "$error"},
        level: Level.warning,
        module: "FileInfoPage",
      );
    }
  }

  Future<void> _load() async {
    final FileTags tags;
    try {
      tags = await widget.read(widget.path);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _tags = FileTags.unreadable(TagFormat.unknown, "$error"),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _tags = tags;
      for (final MapEntry(key: field, value: controller)
          in _controllers.entries) {
        controller.text = tags[field];
      }
      _includeV1 = tags.id3v1 != null;
      _includeV2 = tags.id3v2 != null;
      for (final MapEntry(key: field, value: controller)
          in _v1Controllers.entries) {
        controller.text = tags.id3v1?[field] ?? "";
      }
      for (final MapEntry(key: field, value: controller)
          in _v2Controllers.entries) {
        controller.text = tags.id3v2?[field] ?? "";
      }
    });
  }

  /// Copies what the ID3v1 tab holds into the ID3v2 tab's fields, or the
  /// other way round (the "Copy to ID3v2" and "Copy to ID3v1" buttons); the
  /// other tag keeps what ID3v1 has no room for.
  void _copyId3({required bool toV2}) {
    final from = toV2 ? _v1Controllers : _v2Controllers;
    final to = toV2 ? _v2Controllers : _v1Controllers;
    setState(() {
      for (final MapEntry(key: field, value: controller) in from.entries) {
        to[field]?.text = controller.text;
      }
      if (toV2) {
        _includeV2 = true;
      } else {
        _includeV1 = true;
      }
    });
  }

  @override
  void dispose() {
    _path.dispose();
    for (final controller in [
      ..._controllers.values,
      ..._v1Controllers.values,
      ..._v2Controllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<TagField, String> get _changes {
    final tags = _tags;
    if (tags == null || tags.error != null) return const {};
    return {
      for (final MapEntry(key: field, value: controller)
          in _controllers.entries)
        if (tags.editable.contains(field) &&
            controller.text.trim() != tags[field])
          field: controller.text.trim(),
    };
  }

  /// What the ID3v1 and ID3v2 tabs changed, or null for an MP3's tags left
  /// alone.
  Id3Edit? get _id3Edit {
    final tags = _tags;
    if (tags == null || tags.error != null || tags.format != TagFormat.mp3) {
      return null;
    }
    Map<TagField, String> changed(
      Map<TagField, TextEditingController> controllers,
      Map<TagField, String>? held,
    ) => {
      for (final MapEntry(key: field, value: controller) in controllers.entries)
        if (controller.text.trim() != (held?[field] ?? ""))
          field: controller.text.trim(),
    };
    final edit = Id3Edit(
      v1: changed(_v1Controllers, tags.id3v1),
      v2: changed(_v2Controllers, tags.id3v2),
      includeV1: _includeV1 == (tags.id3v1 != null) ? null : _includeV1,
      includeV2: _includeV2 == (tags.id3v2 != null) ? null : _includeV2,
    );
    return edit.isEmpty ? null : edit;
  }

  /// Asks for the lookup's candidates and puts the picked one into the
  /// editable fields. Fields it has no value for keep theirs. The
  /// fingerprint goes into its (hidden) field too, so OK caches it in the
  /// file and the next lookup skips computing it.
  Future<void> _lookUp(TagLookupFn lookup) async {
    final fingerprint = _controllers[TagField.acoustIdFingerprint]!;
    // A DialogRoute, not showDialog: with windowing on, showDialog opens a
    // native window sized to its content, and on macOS that window stays
    // 0x0, an invisible modal that freezes File Info. The route draws the
    // box inside File Info's own window instead.
    final picked = await Navigator.of(context).push(
      DialogRoute<TagLookupPick>(
        context: context,
        builder: (context) => TagLookupDialog(
          path: widget.path,
          lookup: lookup,
          cachedFingerprint: fingerprint.text.trim(),
        ),
      ),
    );
    final tags = _tags;
    if (picked == null || tags == null || !mounted) return;
    setState(() {
      final fields = {
        ...picked.candidate.fields,
        TagField.acoustIdFingerprint: picked.fingerprint,
      };
      for (final MapEntry(key: field, value: value) in fields.entries) {
        if (tags.editable.contains(field)) _controllers[field]!.text = value;
      }
      _lookupApplied = true;
    });
    // The new tags name the album: fetch its cover too, unless the file
    // has one already (or can't hold one).
    final hasCover = _pictures.any((p) => p.type == ArtworkType.frontCover);
    if ((_filePictures?.editable ?? false) && !hasCover) {
      await _downloadPicture();
    }
  }

  Future<void> _ok() async {
    final changes = _changes;
    final pictures = _picturesChanged ? _pictures : null;
    final id3 = _id3Edit;
    if (changes.isEmpty && pictures == null && id3 == null) {
      widget.onClose(ok: true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.save(widget.path, changes, pictures: pictures, id3: id3);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = error is TagWriteException ? error.message : "$error";
        });
      }
      return;
    }
    if (mounted) widget.onClose(ok: true);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final tags = _tags;
    final saveError = _saveError;
    final lookup = widget.lookup;
    final id3Tabs =
        tags != null && tags.error == null && tags.format == TagFormat.mp3;
    final canLookUp =
        lookup != null && tags != null && tags.error == null && !_saving;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onClose(ok: false),
      },
      child: DefaultTabController(
        length: id3Tabs ? 5 : 3,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _path,
                readOnly: true,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: localizations.basicInfo, height: 32),
                  Tab(text: localizations.advancedTab, height: 32),
                  Tab(text: localizations.artworkTab, height: 32),
                  if (id3Tabs) ...[
                    Tab(text: localizations.id3v1Tab, height: 32),
                    Tab(text: localizations.id3v2Tab, height: 32),
                  ],
                ],
              ),
              Expanded(
                child: tags == null
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          for (final tab in [
                            _BasicInfoTab(
                              tags: tags,
                              controllers: _controllers,
                            ),
                            _AdvancedTab(tags: tags),
                            _ArtworkTab(
                              file: _filePictures,
                              pictures: _pictures,
                              selected: _selectedPicture,
                              newType: _newPictureType,
                              notAnImage: _notAnImage,
                              onSelect: (index) =>
                                  setState(() => _selectedPicture = index),
                              onNewType: (type) =>
                                  setState(() => _newPictureType = type),
                              onLoad: () => unawaited(
                                _loadPicture(replaceSelected: false),
                              ),
                              onDownload: () => unawaited(_downloadPicture()),
                              downloading: _downloading,
                              noDownload: _noDownload,
                              canStore: widget.storeImage != null,
                              storedInDatabase: _storedInDatabase,
                              onChange: () => unawaited(
                                _loadPicture(replaceSelected: true),
                              ),
                              onSaveAs: () => unawaited(_exportPicture()),
                              onDelete: _deletePicture,
                            ),
                            if (id3Tabs) ...[
                              _Id3Tab(
                                version: 1,
                                tags: tags,
                                controllers: _v1Controllers,
                                include: _includeV1,
                                onInclude: (value) =>
                                    setState(() => _includeV1 = value),
                                onCopy: () => _copyId3(toV2: true),
                              ),
                              _Id3Tab(
                                version: 2,
                                tags: tags,
                                controllers: _v2Controllers,
                                include: _includeV2,
                                onInclude: (value) =>
                                    setState(() => _includeV2 = value),
                                onCopy: () => _copyId3(toV2: false),
                              ),
                            ],
                          ])
                            // Room for the group boxes' labels, which stick
                            // out above them and the tab view would clip.
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: tab,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (lookup != null) ...[
                    Tooltip(
                      message: localizations.lookUpTagsTooltip,
                      child: OutlinedButton(
                        onPressed: canLookUp
                            ? () => unawaited(_lookUp(lookup))
                            : null,
                        child: Text(localizations.lookUpTagsEllipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: saveError != null
                        ? Text(
                            localizations.fileInfoWriteError(saveError),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          )
                        : _lookupApplied
                        ? Text(
                            localizations.tagLookupApplied,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : const SizedBox(),
                  ),
                  FilledButton(
                    onPressed: tags == null || _saving
                        ? null
                        : () => unawaited(_ok()),
                    child: Text(localizations.ok),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _saving ? null : () => widget.onClose(ok: false),
                    child: Text(localizations.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Basic Info tab: the Metadata box beside Format Info and Replay Gain.
class _BasicInfoTab extends StatelessWidget {
  const _BasicInfoTab({required this.tags, required this.controllers});

  final FileTags tags;
  final Map<TagField, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final error = tags.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 209,
          child: _GroupBox(
            label: localizations.metadataGroup,
            child: error != null
                ? Text(localizations.fileInfoReadError(error))
                : _MetadataFields(tags: tags, controllers: controllers),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 127,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GroupBox(
                label: localizations.formatInfoGroup,
                child: SelectableText(
                  _FormatInfo.describe(tags, localizations),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              _GroupBox(
                label: localizations.replayGainGroup,
                child: SelectableText(
                  [
                    if (tags.stream.replayGain["track_gain"] case final gain?)
                      localizations.replayGainTrack(gain),
                    if (tags.stream.replayGain["album_gain"] case final gain?)
                      localizations.replayGainAlbum(gain),
                  ].join("\n"),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The fields of an MP3's ID3v1 tab (ID3v1.1: `IDD_FILEINFO_ID3V1`) and
/// ID3v2 tab (`IDD_FILEINFO_ID3V2`).
const List<TagField> _id3v1Fields = [
  TagField.track,
  TagField.title,
  TagField.artist,
  TagField.album,
  TagField.year,
  TagField.genre,
  TagField.comment,
];
const List<TagField> _id3v2Fields = [
  TagField.track,
  TagField.disc,
  TagField.bpm,
  TagField.title,
  TagField.artist,
  TagField.album,
  TagField.albumArtist,
  TagField.year,
  TagField.genre,
  TagField.comment,
  TagField.composer,
  TagField.publisher,
];

/// The ID3v1 or ID3v2 tab: one tag's fields, edited apart from the other
/// tag's, with the box to keep the tag in the file and the button that
/// copies its fields to the other tag.
class _Id3Tab extends StatelessWidget {
  const _Id3Tab({
    required this.version,
    required this.tags,
    required this.controllers,
    required this.include,
    required this.onInclude,
    required this.onCopy,
  });

  final int version;
  final FileTags tags;
  final Map<TagField, TextEditingController> controllers;
  final bool include;
  final ValueChanged<bool> onInclude;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final v1 = version == 1;
    Widget field(TagField field, {int lines = 1}) => TextField(
      key: ValueKey("id3v$version.${field.name}"),
      controller: controllers[field],
      enabled: include,
      minLines: lines,
      maxLines: lines,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: OutlineInputBorder(),
      ),
    );
    Widget row(String label, TagField f, {int lines = 1}) => _FieldRow(
      label: label,
      child: field(f, lines: lines),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: v1 ? 330 : 420,
        child: _GroupBox(
          label: v1 ? localizations.id3v1Tab : localizations.id3v2Tab,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  key: ValueKey("id3v$version.include"),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: include,
                  title: Text(
                    v1
                        ? localizations.includeId3v1
                        : localizations.includeId3v2,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged: (value) => onInclude(value ?? false),
                ),
                Row(
                  children: [
                    _Label(localizations.tagTrack),
                    SizedBox(width: 64, child: field(TagField.track)),
                    if (!v1) ...[
                      _Label(localizations.tagDisc, width: 52),
                      Expanded(child: field(TagField.disc)),
                      _Label(localizations.tagBpm, width: 40),
                      Expanded(child: field(TagField.bpm)),
                    ],
                  ],
                ),
                row(localizations.tagTitle, TagField.title),
                row(localizations.tagArtist, TagField.artist),
                row(localizations.tagAlbum, TagField.album),
                if (!v1)
                  row(localizations.tagAlbumArtist, TagField.albumArtist),
                Row(
                  children: [
                    _Label(localizations.tagYear),
                    SizedBox(width: 64, child: field(TagField.year)),
                    _Label(localizations.tagGenre, width: 52),
                    Expanded(
                      child: _GenreField(
                        key: ValueKey("id3v$version.genre"),
                        controller: controllers[TagField.genre]!,
                        enabled: include,
                      ),
                    ),
                  ],
                ),
                row(
                  localizations.tagComment,
                  TagField.comment,
                  lines: v1 ? 1 : 3,
                ),
                if (!v1) ...[
                  row(localizations.tagComposer, TagField.composer),
                  row(localizations.tagPublisher, TagField.publisher),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      key: ValueKey("id3v$version.copy"),
                      onPressed: include ? onCopy : null,
                      child: Text(
                        v1
                            ? localizations.copyToId3v2
                            : localizations.copyToId3v1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Format Info box's text.
abstract final class _FormatInfo {
  static String describe(FileTags tags, AppLocalizations localizations) {
    final stream = tags.stream;
    final channels = stream.channels;
    return [
      switch (tags.format) {
        TagFormat.mp3 => localizations.formatMp3,
        TagFormat.flac => localizations.formatFlac,
        TagFormat.oggVorbis => localizations.formatOggVorbis,
        TagFormat.oggOpus => localizations.formatOggOpus,
        TagFormat.oggSpeex => localizations.formatOggSpeex,
        TagFormat.oggFlac => localizations.formatOggFlac,
        TagFormat.apeTagged => localizations.formatApeTagged,
        TagFormat.wav => localizations.formatWav,
        TagFormat.unknown => localizations.formatUnknown,
      },
      if (tags.tagTypes.isEmpty)
        localizations.formatInfoNoTags
      else
        localizations.formatInfoTags(tags.tagTypes.join(", ")),
      if (stream.fileSize case final size?) localizations.formatInfoSize(size),
      if (stream.duration case final duration?)
        localizations.formatInfoLength(duration.inSeconds),
      if (stream.bitrate case final kbps?)
        localizations.formatInfoBitrate(kbps),
      if (stream.sampleRate case final hz?)
        localizations.formatInfoSampleRate(hz),
      if (channels != null)
        switch (channels) {
          1 => localizations.channelsMono,
          2 => localizations.channelsStereo,
          _ => localizations.channelsCount(channels),
        },
    ].join("\n");
  }
}

/// The Metadata box's fields, laid out as in `IDD_FILEINFO_METADATA`.
class _MetadataFields extends StatelessWidget {
  const _MetadataFields({required this.tags, required this.controllers});

  final FileTags tags;
  final Map<TagField, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Label(localizations.tagTrack),
              Expanded(
                child: _TagTextField(
                  field: TagField.track,
                  tags: tags,
                  controllers: controllers,
                ),
              ),
              _Label(localizations.tagDisc, width: 52),
              Expanded(
                child: _TagTextField(
                  field: TagField.disc,
                  tags: tags,
                  controllers: controllers,
                ),
              ),
              _Label(localizations.tagBpm, width: 40),
              Expanded(
                child: _TagTextField(
                  field: TagField.bpm,
                  tags: tags,
                  controllers: controllers,
                ),
              ),
            ],
          ),
          _FieldRow(
            label: localizations.tagTitle,
            child: _TagTextField(
              field: TagField.title,
              tags: tags,
              controllers: controllers,
            ),
          ),
          _FieldRow(
            label: localizations.tagArtist,
            child: _TagTextField(
              field: TagField.artist,
              tags: tags,
              controllers: controllers,
            ),
          ),
          _FieldRow(
            label: localizations.tagAlbum,
            child: _TagTextField(
              field: TagField.album,
              tags: tags,
              controllers: controllers,
            ),
          ),
          _FieldRow(
            label: localizations.tagAlbumArtist,
            child: _TagTextField(
              field: TagField.albumArtist,
              tags: tags,
              controllers: controllers,
            ),
          ),
          // A narrow window shrinks the Year box, so the row always fits.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _Label(localizations.tagYear),
                SizedBox(
                  width: (constraints.maxWidth - 80 - 52 - 72).clamp(
                    24.0,
                    64.0,
                  ),
                  child: _TagTextField(
                    field: TagField.year,
                    tags: tags,
                    controllers: controllers,
                  ),
                ),
                _Label(localizations.tagGenre, width: 52),
                Expanded(
                  child: _GenreField(
                    controller: controllers[TagField.genre]!,
                    enabled: tags.editable.contains(TagField.genre),
                  ),
                ),
              ],
            ),
          ),
          _FieldRow(
            label: localizations.tagComment,
            child: _TagTextField(
              field: TagField.comment,
              tags: tags,
              controllers: controllers,
              lines: 3,
            ),
          ),
          _FieldRow(
            label: localizations.tagComposer,
            child: _TagTextField(
              field: TagField.composer,
              tags: tags,
              controllers: controllers,
            ),
          ),
          _FieldRow(
            label: localizations.tagPublisher,
            child: _TagTextField(
              field: TagField.publisher,
              tags: tags,
              controllers: controllers,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        Expanded(child: child),
      ],
    ),
  );
}

/// A right-aligned field label (`RTEXT`).
class _Label extends StatelessWidget {
  const _Label(this.text, {this.width = 80});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.only(right: 6, top: 6),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12),
      ),
    ),
  );
}

class _TagTextField extends StatelessWidget {
  const _TagTextField({
    required this.field,
    required this.tags,
    required this.controllers,
    this.lines = 1,
  });

  final TagField field;
  final FileTags tags;
  final Map<TagField, TextEditingController> controllers;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final enabled = tags.editable.contains(field);
    return Tooltip(
      message: enabled ? "" : AppLocalizations.of(context).fileInfoNotEditable,
      child: TextField(
        key: ValueKey(field),
        controller: controllers[field],
        enabled: enabled,
        minLines: lines,
        maxLines: lines,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// The genre combo box: free text, with the genre list to pick from.
class _GenreField extends StatelessWidget {
  const _GenreField({
    required this.controller,
    required this.enabled,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;

  static final List<String> _sorted = [...id3Genres]
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  @override
  Widget build(BuildContext context) => TextField(
    key: key ?? const ValueKey(TagField.genre),
    controller: controller,
    enabled: enabled,
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      border: const OutlineInputBorder(),
      suffixIconConstraints: const BoxConstraints(maxHeight: 32),
      suffixIcon: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: AppLocalizations.of(context).genreListTooltip,
        icon: const Icon(Icons.arrow_drop_down, size: 18),
        padding: EdgeInsets.zero,
        onSelected: (genre) => controller.text = genre,
        itemBuilder: (context) => [
          for (final genre in _sorted)
            PopupMenuItem(value: genre, height: 28, child: Text(genre)),
        ],
      ),
    ),
  );
}

class _GroupBox extends StatelessWidget {
  const _GroupBox({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
    ),
    child: child,
  );
}

/// The Advanced tab: every raw tag item, by name and value.
class _AdvancedTab extends StatelessWidget {
  const _AdvancedTab({required this.tags});

  final FileTags tags;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (tags.raw.isEmpty) {
      return Center(child: Text(localizations.fileInfoNoRawTags));
    }
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        border: TableBorder.all(color: Theme.of(context).dividerColor),
        children: [
          TableRow(
            children: [
              _Cell(localizations.tagNameColumn, bold: true),
              _Cell(localizations.tagValueColumn, bold: true),
            ],
          ),
          for (final entry in tags.raw)
            if (_fingerprintRow(entry) case (final text, final png))
              TableRow(
                children: [
                  _Cell(localizations.tagAcoustIdFingerprint),
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: FingerprintImage(png: png, semanticLabel: text),
                  ),
                ],
              )
            else
              TableRow(children: [_Cell(entry.name), _Cell(entry.value)]),
        ],
      ),
    );
  }
}

/// The fingerprint text and its image when [entry] is an AcoustID
/// fingerprint that decodes; otherwise null, and it shows as text.
(String, Uint8List)? _fingerprintRow(TagEntry entry) {
  final text = fingerprintOfTagEntry(entry.name, entry.value);
  if (text == null) return null;
  final png = fingerprintPngOrNull(text);
  return png == null ? null : (text, png);
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    child: SelectableText(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
  );
}

/// The Artwork tab (`IDD_FILEINFO_ARTWORK`): the pictures by type, the type
/// for new ones and Load Artwork... on the left; the selected picture with
/// its details, Change..., Save As... and Delete on the right. Changes are
/// written on OK.
class _ArtworkTab extends StatelessWidget {
  const _ArtworkTab({
    required this.file,
    required this.pictures,
    required this.selected,
    required this.newType,
    required this.notAnImage,
    required this.onSelect,
    required this.onNewType,
    required this.onLoad,
    required this.onDownload,
    required this.downloading,
    required this.noDownload,
    required this.canStore,
    required this.storedInDatabase,
    required this.onChange,
    required this.onSaveAs,
    required this.onDelete,
  });

  /// What the file holds; `null` while it's being read.
  final FilePictures? file;
  final List<EmbeddedPicture> pictures;
  final int? selected;
  final ArtworkType newType;
  final bool notAnImage;
  final ValueChanged<int> onSelect;
  final ValueChanged<ArtworkType> onNewType;
  final VoidCallback onLoad;
  final VoidCallback onDownload;
  final bool downloading;
  final bool noDownload;
  final bool canStore;
  final bool storedInDatabase;
  final VoidCallback onChange;
  final VoidCallback onSaveAs;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final file = this.file;
    if (file == null) return const Center(child: CircularProgressIndicator());
    final error = file.error;
    final editable = file.editable;
    final index = selected;
    final picture = index == null ? null : pictures[index];
    const style = TextStyle(fontSize: 12);
    final button = OutlinedButton.styleFrom(
      textStyle: const TextStyle(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    );
    return _GroupBox(
      label: localizations.artworkEditorGroup,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: pictures.length,
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey(("picture", i)),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        selected: i == index,
                        title: Text(
                          artworkTypeName(localizations, pictures[i].type),
                          style: style,
                        ),
                        onTap: () => onSelect(i),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(localizations.artworkTypeLabel, style: style),
                DropdownButton<ArtworkType>(
                  key: const ValueKey("artworkType"),
                  value: newType,
                  isDense: true,
                  isExpanded: true,
                  style: style.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onChanged: editable
                      ? (type) {
                          if (type != null) onNewType(type);
                        }
                      : null,
                  items: [
                    for (final type in ArtworkType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(
                          artworkTypeName(localizations, type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: button,
                  onPressed: editable ? onLoad : null,
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text(localizations.uploadArtwork, maxLines: 1),
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  style: button,
                  onPressed:
                      (editable || (canStore && error == null)) && !downloading
                      ? onDownload
                      : null,
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(localizations.downloadArtwork, maxLines: 1),
                ),
                if (noDownload)
                  Text(localizations.artworkNotFound, style: style)
                else if (storedInDatabase)
                  Text(localizations.artworkStoredInDatabase, style: style),
                if (error != null)
                  Text(
                    localizations.fileInfoPicturesReadError(error),
                    style: style.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else if (!editable)
                  Text(localizations.artworkNotEditable, style: style)
                else if (notAnImage)
                  Text(
                    localizations.artworkNotAnImage,
                    style: style.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _GroupBox(
              label: picture == null
                  ? localizations.noImage
                  : _ArtworkDetails.describe(picture, localizations),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: picture == null
                        ? const SizedBox()
                        : Image.memory(
                            picture.data,
                            key: ObjectKey(picture),
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                Text(localizations.noImage, style: style),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton(
                          style: button,
                          onPressed: picture != null && editable
                              ? onChange
                              : null,
                          child: Text(
                            localizations.changeArtwork,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton(
                          style: button,
                          onPressed: picture != null ? onSaveAs : null,
                          child: Text(
                            localizations.saveArtworkAs,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton(
                          style: button,
                          onPressed: picture != null && editable
                              ? onDelete
                              : null,
                          child: Text(
                            localizations.deleteArtwork,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture frame's caption (`IDS_ARTWORK_DETAILS`).
abstract final class _ArtworkDetails {
  static String describe(
    EmbeddedPicture picture,
    AppLocalizations localizations,
  ) {
    final size = picture.size;
    final format = picture.formatName;
    return localizations.artworkDetails(
      artworkTypeName(localizations, picture.type),
      size == null ? "?" : "${size.$1}",
      size == null ? "?" : "${size.$2}",
      localizations.artworkOriginEmbedded,
      format.isEmpty ? localizations.unknownMime : format,
    );
  }
}

/// The name shown for a picture [type].
String artworkTypeName(
  AppLocalizations localizations,
  ArtworkType type,
) => switch (type) {
  ArtworkType.other => localizations.artworkTypeOther,
  ArtworkType.fileIcon => localizations.artworkTypeFileIcon,
  ArtworkType.otherFileIcon => localizations.artworkTypeOtherFileIcon,
  ArtworkType.frontCover => localizations.artworkTypeFrontCover,
  ArtworkType.backCover => localizations.artworkTypeBackCover,
  ArtworkType.leaflet => localizations.artworkTypeLeaflet,
  ArtworkType.media => localizations.artworkTypeMedia,
  ArtworkType.leadArtist => localizations.artworkTypeLeadArtist,
  ArtworkType.artist => localizations.artworkTypeArtist,
  ArtworkType.conductor => localizations.artworkTypeConductor,
  ArtworkType.band => localizations.artworkTypeBand,
  ArtworkType.composer => localizations.artworkTypeComposer,
  ArtworkType.lyricist => localizations.artworkTypeLyricist,
  ArtworkType.recordingLocation => localizations.artworkTypeRecordingLocation,
  ArtworkType.duringRecording => localizations.artworkTypeDuringRecording,
  ArtworkType.duringPerformance => localizations.artworkTypeDuringPerformance,
  ArtworkType.videoCapture => localizations.artworkTypeVideoCapture,
  ArtworkType.brightFish => localizations.artworkTypeBrightFish,
  ArtworkType.illustration => localizations.artworkTypeIllustration,
  ArtworkType.bandLogo => localizations.artworkTypeBandLogo,
  ArtworkType.publisherLogo => localizations.artworkTypePublisherLogo,
};
