import "tag_model.dart";

/// What the selected files say about one field, for editing them together
/// (the classic player's "Edit Item Metadata" dialog, `EditInfo` in FileInfo.cpp).
class SharedField {
  const SharedField({
    required this.value,
    required this.distinct,
    required this.filled,
    required this.supported,
    required this.total,
  });

  /// The value every file that has one agrees on, or "" when they differ
  /// or none has one. Like the original's `SAVE_LAST_STR`, files without a
  /// value don't count against agreeing.
  final String value;

  /// How many different non-empty values the files have.
  final int distinct;

  /// How many files have a value.
  final int filled;

  /// How many files can store the field.
  final int supported;

  /// How many files were looked at.
  final int total;

  /// Whether the files disagree, so the field starts empty and unticked.
  bool get varies => distinct > 1;

  /// Whether no file can store the field.
  bool get unsupported => supported == 0;

  /// Whether some (but not all) files have no value.
  bool get partial => filled > 0 && filled < total && !varies;
}

/// Combines the tags of several files field by field.
Map<TagField, SharedField> shareFields(List<FileTags> files) => {
  for (final field in TagField.values) field: _share(field, files),
};

SharedField _share(TagField field, List<FileTags> files) {
  final values = <String>{};
  var filled = 0;
  var supported = 0;
  for (final file in files) {
    if (file.editable.contains(field)) supported++;
    final value = file[field];
    if (value.isEmpty) continue;
    filled++;
    values.add(value);
  }
  return SharedField(
    value: values.length == 1 ? values.first : "",
    distinct: values.length,
    filled: filled,
    supported: supported,
    total: files.length,
  );
}

/// The changes to write to [file] when [values] are applied to a selection:
/// the fields [file] can store whose value would change.
Map<TagField, String> changesFor(FileTags file, Map<TagField, String> values) =>
    {
      for (final MapEntry(key: field, :value) in values.entries)
        if (file.editable.contains(field) && file[field] != value.trim())
          field: value.trim(),
    };
