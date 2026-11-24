import "dart:convert";
import "dart:typed_data";

import "package:amped_maki/amped_maki.dart";

/// The basic MAKI value types (`vcputypes.h`). Object variables carry the
/// class instead.
abstract final class MakiType {
  static const int voidType = 0;
  static const int event = 1;
  static const int int_ = 2;
  static const int float = 3;
  static const int double_ = 4;
  static const int boolean = 5;
  static const int string = 6;
  static const int object = 7;
  static const int any = 8;
}

/// A function a script imports (an entry of the DLF table): a member of a
/// class, called by name.
class MakiImport {
  const MakiImport(this.className, this.name, this.paramTypes, this.returns);

  /// The lower-cased class the function was compiled against, or null when
  /// the script names a class this runtime does not know.
  final String? className;

  /// The lower-cased member name.
  final String name;

  /// The declared parameter types (lower-cased), or null when unknown.
  final List<String>? paramTypes;

  /// The declared parameter count, or -1 when unknown.
  int get params => paramTypes?.length ?? -1;

  /// The lower-cased declared return type, or null.
  final String? returns;
}

/// A variable declared by a script, with its initial value.
class MakiVariableInfo {
  const MakiVariableInfo({
    required this.type,
    required this.className,
    required this.initial,
    required this.transient,
    required this.isStatic,
    required this.subclassOf,
  });

  /// One of [MakiType], [MakiType.object] for objects.
  final int type;

  /// The lower-cased class of an object variable.
  final String? className;

  /// The initial value: an `int`, `double`, `bool` or `String`, or null.
  final Object? initial;

  /// A transient variable does not receive its object's events.
  final bool transient;

  /// A static variable is instantiated (or bound to System) at load.
  final bool isStatic;

  /// For a script-defined class (`class X extends Y`), the variable index of
  /// the variable it extends; else null.
  final int? subclassOf;
}

/// An event handler: code to run when the object in [variable] fires the
/// event [import] names.
class MakiEventInfo {
  const MakiEventInfo(this.variable, this.import, this.address);

  final int variable;
  final int import;
  final int address;
}

/// A compiled MAKI script (`.maki`), as `VCPU::addScript` reads it.
class MakiBinary {
  MakiBinary._({
    required this.version,
    required this.classes,
    required this.imports,
    required this.variables,
    required this.events,
    required this.code,
  });

  /// The format version byte (0x15..0x17).
  final int version;

  /// The script's class table: the lower-cased class names its type ids
  /// (from 0x100) refer to; null for classes this runtime lacks.
  final List<String?> classes;

  final List<MakiImport> imports;
  final List<MakiVariableInfo> variables;
  final List<MakiEventInfo> events;
  final Uint8List code;

  static final Map<String, MakiClassInfo> _byGuid = {
    for (final info in makiClasses.values) info.guid: info,
  };

  /// Finds [member] in [className] or its ancestors.
  static MakiMemberInfo? memberOf(String? className, String member) {
    var name = className;
    while (name != null) {
      final info = makiClasses[name];
      if (info == null) return null;
      final found = info.members[member];
      if (found != null) return found;
      name = info.parent;
    }
    return null;
  }

  /// Parses [bytes]; throws [FormatException] for files it cannot read.
  factory MakiBinary.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var p = 0;
    int i32() {
      final v = data.getInt32(p, Endian.little);
      p += 4;
      return v;
    }

    int u16() {
      final v = data.getUint16(p, Endian.little);
      p += 2;
      return v;
    }

    String text(int length) {
      final s = utf8.decode(bytes.sublist(p, p + length), allowMalformed: true);
      p += length;
      return s;
    }

    if (bytes.length < 8 ||
        bytes[0] != 0x46 ||
        bytes[1] != 0x47 ||
        bytes[2] != 3 ||
        bytes[3] != 4) {
      throw const FormatException("Not a MAKI script");
    }
    final version = bytes[4];
    if (version < 0x15) throw const FormatException("Deprecated MAKI binary");
    if (version > 0x17)
      throw const FormatException("MAKI binary from a newer version");
    // Version 0x15 used fixed class ids instead of a GUID table; skins of
    // that age are rare and not supported here.
    if (version == 0x15) throw const FormatException("Old MAKI object format");
    p = 8;

    final classes = <String?>[];
    final classCount = i32();
    for (var i = 0; i < classCount; i++) {
      classes.add(_byGuid[_guid(bytes, p)]?.name.toLowerCase());
      p += 16;
    }

    String? classOf(int type) {
      if (type >= 0x100 && type < 0x10000) {
        final index = type - 0x100;
        return index < classes.length ? classes[index] : null;
      }
      return null;
    }

    final imports = <MakiImport>[];
    final importCount = i32();
    for (var i = 0; i < importCount; i++) {
      final className = classOf(i32());
      final name = text(u16()).toLowerCase();
      final member = memberOf(className, name);
      imports.add(
        MakiImport(className, name, member?.paramTypes, member?.returns),
      );
    }

    final variables = <MakiVariableInfo>[];
    final variableCount = i32();
    for (var i = 0; i < variableCount; i++) {
      final rawType = i32();
      final value = ByteData.sublistView(bytes, p, p + 8);
      p += 8;
      final transient = bytes[p++] == 0;
      final isStatic = version >= 0x17 && bytes[p++] != 0;
      int? subclassOf;
      var type = rawType;
      String? className;
      if (rawType >= 0x10000) {
        subclassOf = rawType - 0x10000;
        type = MakiType.object;
        // The class of a script-defined class is its base's.
        var base = subclassOf;
        while (base < variables.length && variables[base].subclassOf != null) {
          base = variables[base].subclassOf!;
        }
        className = base < variables.length ? variables[base].className : null;
      } else if (rawType >= 0x100) {
        type = MakiType.object;
        className = classOf(rawType);
      }
      final Object? initial = switch (type) {
        MakiType.int_ => value.getInt32(0, Endian.little),
        MakiType.boolean => value.getInt32(0, Endian.little) != 0,
        // Doubles are stored as floats too (`e.data.ddata = e.data.fdata`).
        MakiType.float ||
        MakiType.double_ => value.getFloat32(0, Endian.little).toDouble(),
        MakiType.string => "",
        _ => null,
      };
      variables.add(
        MakiVariableInfo(
          type: type,
          className: className,
          initial: initial,
          transient: transient,
          isStatic: isStatic,
          subclassOf: subclassOf,
        ),
      );
    }

    final strings = <int, String>{};
    final stringCount = i32();
    for (var i = 0; i < stringCount; i++) {
      final variable = i32();
      strings[variable] = text(u16());
    }
    for (final MapEntry(key: index, value: value) in strings.entries) {
      if (index < 0 || index >= variables.length) {
        throw const FormatException("Invalid string variable");
      }
      final v = variables[index];
      variables[index] = MakiVariableInfo(
        type: v.type,
        className: v.className,
        initial: value,
        transient: v.transient,
        isStatic: v.isStatic,
        subclassOf: v.subclassOf,
      );
    }

    final events = <MakiEventInfo>[];
    final eventCount = i32();
    for (var i = 0; i < eventCount; i++) {
      final variable = i32();
      final import = i32();
      final address = i32();
      if (import < 0 ||
          import >= imports.length ||
          variable < 0 ||
          variable >= variables.length ||
          address < 0) {
        throw const FormatException("Invalid event entry");
      }
      events.add(MakiEventInfo(variable, import, address));
    }

    final codeSize = i32();
    if (p + codeSize > bytes.length)
      throw const FormatException("Truncated code");
    final code = Uint8List.sublistView(bytes, p, p + codeSize);
    return MakiBinary._(
      version: version,
      classes: classes,
      imports: imports,
      variables: variables,
      events: events,
      code: code,
    );
  }

  static String _guid(Uint8List b, int p) {
    String hex(int from, int to, {bool reverse = false}) {
      final bytes = b.sublist(p + from, p + to);
      final ordered = reverse ? bytes.reversed : bytes;
      return ordered.map((x) => x.toRadixString(16).padLeft(2, "0")).join();
    }

    return "${hex(0, 4, reverse: true)}-${hex(4, 6, reverse: true)}-"
        "${hex(6, 8, reverse: true)}-${hex(8, 10)}-${hex(10, 16)}";
  }
}
