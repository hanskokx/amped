import "dart:async";

import "package:amped_l10n/amped_l10n.dart";
import "package:flutter/services.dart" show LogicalKeyboardKey;
import "package:material_ui/material_ui.dart";

import "../tags/tag_io.dart";
import "file_info_page.dart" show TagSaver;

/// Reads the tags of several files.
typedef TagBatchReader = Future<List<FileTags>> Function(List<String> paths);

/// The classic player's "Edit Item Metadata" dialog (`IDD_EDIT_INFO`, Playlist > Edit
/// metadata for selection..., Shift+E): edits the tags of every selected
/// file at once.
///
/// A field the files agree on starts filled in. One where they differ
/// starts empty, saying so, so that it isn't overwritten by accident. Only
/// ticked fields are written (typing in one ticks it), to the files that
/// can store them, and only where the value changes. Fields none of the
/// files can store are disabled.
class EditMetadataPage extends StatefulWidget {
  const EditMetadataPage({
    required this.paths,
    required this.read,
    required this.save,
    required this.onClose,
    super.key,
  });

  final List<String> paths;
  final TagBatchReader read;
  final TagSaver save;
  final VoidCallback onClose;

  /// The fields in the order of `IDD_EDIT_INFO`.
  static const List<TagField> fieldOrder = [
    TagField.artist,
    TagField.title,
    TagField.album,
    TagField.comment,
    TagField.track,
    TagField.genre,
    TagField.bpm,
    TagField.year,
    TagField.disc,
    TagField.albumArtist,
    TagField.publisher,
    TagField.composer,
  ];

  @override
  State<EditMetadataPage> createState() => _EditMetadataPageState();
}

class _EditMetadataPageState extends State<EditMetadataPage> {
  List<FileTags>? _files;
  Map<TagField, SharedField> _shared = const {};
  final Map<TagField, TextEditingController> _controllers = {
    for (final field in TagField.values) field: TextEditingController(),
  };
  final Set<TagField> _ticked = {};

  /// Files written so far while updating, or null when not updating.
  int? _done;
  final List<(String, String)> _errors = [];
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<FileTags> files;
    try {
      files = await widget.read(widget.paths);
    } on Object catch (error) {
      files = [
        for (final _ in widget.paths)
          FileTags.unreadable(TagFormat.unknown, "$error"),
      ];
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      _shared = shareFields(files);
      for (final MapEntry(key: field, value: shared) in _shared.entries) {
        _controllers[field]!.text = shared.value;
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setTicked(TagField field, bool ticked) => setState(() {
    if (ticked) {
      _ticked.add(field);
    } else {
      _ticked.remove(field);
      // Unticking undoes the edit.
      _controllers[field]!.text = _shared[field]?.value ?? "";
    }
  });

  Future<void> _update() async {
    final files = _files!;
    final values = {
      for (final field in _ticked) field: _controllers[field]!.text,
    };
    setState(() {
      _done = 0;
      _errors.clear();
    });
    for (final (i, file) in files.indexed) {
      final changes = changesFor(file, values);
      if (changes.isNotEmpty) {
        try {
          await widget.save(widget.paths[i], changes);
        } on Object catch (error) {
          _errors.add((
            widget.paths[i],
            error is TagWriteException ? error.message : "$error",
          ));
        }
      }
      if (!mounted) return;
      setState(() => _done = i + 1);
    }
    if (_errors.isEmpty) {
      widget.onClose();
    } else {
      setState(() => _finished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final files = _files;
    final done = _done;
    final updating = done != null && !_finished;
    final unreadable = files?.where((f) => f.error != null).length ?? 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!updating) widget.onClose();
        },
      },
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.itemsSelected(widget.paths.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (unreadable > 0)
              Text(
                localizations.filesUnreadableSkipped(unreadable),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: files == null
                  ? const Center(child: CircularProgressIndicator())
                  : _finished
                  ? _ErrorList(errors: _errors)
                  : ListView(
                      children: [
                        for (final field in EditMetadataPage.fieldOrder)
                          _SharedFieldRow(
                            field: field,
                            shared: _shared[field]!,
                            controller: _controllers[field]!,
                            ticked: _ticked.contains(field),
                            enabled: !updating,
                            onTicked: (ticked) => _setTicked(field, ticked),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            if (updating)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: files!.isEmpty ? null : done / files.length,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localizations.updatingFiles(done, files.length),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_finished)
                  FilledButton(
                    onPressed: widget.onClose,
                    child: Text(localizations.close),
                  )
                else ...[
                  FilledButton(
                    onPressed: files == null || _ticked.isEmpty || updating
                        ? null
                        : () => unawaited(_update()),
                    child: Text(localizations.updateAction),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: updating ? null : widget.onClose,
                    child: Text(localizations.cancel),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One field: its checkbox and label, the value, and what the files say.
class _SharedFieldRow extends StatelessWidget {
  const _SharedFieldRow({
    required this.field,
    required this.shared,
    required this.controller,
    required this.ticked,
    required this.enabled,
    required this.onTicked,
  });

  final TagField field;
  final SharedField shared;
  final TextEditingController controller;
  final bool ticked;
  final bool enabled;
  final ValueChanged<bool> onTicked;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final usable = enabled && !shared.unsupported;
    final unsupportedCount = shared.total - shared.supported;
    final hint = shared.unsupported
        ? localizations.fieldNotStorable
        : shared.varies
        ? localizations.fieldMultipleValues(shared.distinct)
        : null;
    final notes = [
      if (shared.partial)
        localizations.fieldSetInSome(shared.filled, shared.total),
      if (!shared.unsupported && unsupportedCount > 0)
        localizations.fieldNotStorableIn(unsupportedCount),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: CheckboxListTile(
              key: ValueKey(("tick", field)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              visualDensity: VisualDensity.compact,
              value: ticked,
              onChanged: usable ? (value) => onTicked(value ?? false) : null,
              title: Text(
                _FieldLabel.of(field, localizations),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: ValueKey(field),
              controller: controller,
              enabled: usable,
              minLines: 1,
              maxLines: field == TagField.comment ? 3 : 1,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) {
                if (!ticked) onTicked(true);
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                helperText: notes.isEmpty ? null : notes.join(" · "),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The labels of the fields.
abstract final class _FieldLabel {
  static String of(TagField field, AppLocalizations localizations) =>
      switch (field) {
        TagField.track => localizations.tagTrack,
        TagField.disc => localizations.tagDisc,
        TagField.bpm => localizations.tagBpm,
        TagField.title => localizations.tagTitle,
        TagField.artist => localizations.tagArtist,
        TagField.album => localizations.tagAlbum,
        TagField.albumArtist => localizations.tagAlbumArtist,
        TagField.year => localizations.tagYear,
        TagField.genre => localizations.tagGenre,
        TagField.comment => localizations.tagComment,
        TagField.composer => localizations.tagComposer,
        TagField.publisher => localizations.tagPublisher,
        TagField.acoustIdFingerprint => localizations.tagAcoustIdFingerprint,
      };
}

/// The files that could not be updated, and why.
class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors});

  final List<(String, String)> errors;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListView(
      children: [
        Text(localizations.filesNotUpdated(errors.length)),
        const SizedBox(height: 8),
        for (final (path, message) in errors)
          ListTile(
            dense: true,
            title: Text(path, style: const TextStyle(fontSize: 12)),
            subtitle: Text(message, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
