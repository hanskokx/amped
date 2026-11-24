import "package:amped_maki/amped_maki.dart";
import "package:flutter/foundation.dart";

import "../wasabi_path.dart";
import "maki_binary.dart";

/// Returned by [MakiObject.invoke] for members the object does not
/// implement; the VCPU logs the call once and returns the type's default.
const Object makiUnhandled = _Unhandled();

class _Unhandled {
  const _Unhandled();
}

/// An object scripts can hold and call: System, a GUI object, a Timer, ...
abstract class MakiObject {
  /// The lower-cased MAKI class name.
  String get makiClass;

  /// The non-transient variables holding this object, whose scripts get its
  /// events (`vcpu_getAssignedVariable`).
  final List<MakiVariable> bindings = [];

  /// The member variables scripts gave this object (`Member` declarations
  /// of script-defined classes), by script and name.
  final Map<(MakiScript, String), MakiVariable> memberVariables = {};

  /// Calls [member] (lower-cased) with [args] (int, double, bool, String,
  /// MakiObject or null). Return [makiUnhandled] for unknown members.
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    // Calling an event triggers it, as the native side does with
    // SCRIPT_EXEC_EVENT.
    if (member.startsWith("on") && _isEvent(member))
      return vm.fire(this, member, args);
    return switch (member) {
      "getclassname" => makiClasses[makiClass]?.name ?? makiClass,
      "getid" => "",
      _ => makiUnhandled,
    };
  }

  /// Whether [member] is an event (declared without a return type) of this
  /// object's class or its ancestors.
  bool _isEvent(String member) {
    String? name = makiClass;
    while (name != null) {
      final info = makiClasses[name];
      final declared = info?.members[member];
      if (declared != null) return declared.returns == null;
      name = info?.parent;
    }
    return false;
  }

  /// Called when a script deletes the object.
  void dispose() {}

  /// Whether this object is a [className] or derives from it.
  bool isA(String className) {
    String? name = makiClass;
    while (name != null) {
      if (name == className) return true;
      name = makiClasses[name]?.parent;
    }
    return false;
  }
}

/// A script variable.
class MakiVariable {
  MakiVariable(this.script, this.index, this.info) : value = info.initial;

  final MakiScript script;
  final int index;
  final MakiVariableInfo info;

  /// int, double, bool, String or MakiObject (or null).
  Object? value;

  int get type => info.type;
}

/// A loaded script: its variables and code.
class MakiScript {
  MakiScript._(this.vm, this.binary, this.name, this.system);

  final MakiVm vm;
  final MakiBinary binary;

  /// Where the script came from, for messages.
  final String name;

  /// The script's System object.
  final MakiObject system;

  late final List<MakiVariable> variables = [
    for (final (i, info) in binary.variables.indexed)
      MakiVariable(this, i, info),
  ];

  /// The events each variable handles, by lower-cased event name.
  late final Map<int, Map<String, int>> _handlers = () {
    final map = <int, Map<String, int>>{};
    for (final event in binary.events) {
      (map[event.variable] ??= {})[binary.imports[event.import].name] =
          event.address;
    }
    return map;
  }();

  bool unloaded = false;
}

class _Slot {
  const _Slot(this.type, this.value, [this.ref]);

  final int type;
  final Object? value;
  final MakiVariable? ref;
}

/// Thrown when a script cannot go on (`Script::guruMeditation`).
class MakiError implements Exception {
  MakiError(this.message);
  final String message;

  @override
  String toString() => "MAKI error: $message";
}

/// The MAKI virtual CPU (`VCPU`): runs compiled scripts' event handlers.
/// An event handler call: where it is and what it was given.
class MakiHandlerCall {
  const MakiHandlerCall(this.script, this.address, this.args);

  final MakiScript script;
  final int address;
  final List<Object?> args;
}

class MakiVm {
  MakiVm({this.instantiate, this.log});

  /// Creates an object for `new` and static class variables, or null for
  /// classes that cannot be instantiated.
  final MakiObject? Function(String className)? instantiate;

  /// Receives guru meditations and unimplemented-call notices.
  final void Function(String message)? log;

  final List<MakiScript> scripts = [];

  /// Debugging: called before each instruction.
  void Function(String script, int ip, int opcode, int depth)? trace;
  final List<_Slot> _stack = [];
  final Set<String> _reported = {};

  // Where the last instruction was, for error messages.
  int _ip = 0;
  String _lastCall = "";

  /// Set by `complete;` to stop an event from reaching further scripts.
  bool _complete = false;

  /// Whether the handler that ran last called `complete` (a script took the
  /// event).
  bool get completed => _complete;

  /// Instructions one event may run before it is stopped as a runaway.
  static const int instructionBudget = 5000000;

  void _log(String message) => (log ?? debugPrint)(message);

  /// Loads [binary], giving it [system] as its System object.
  MakiScript load(
    MakiBinary binary, {
    required MakiObject system,
    String name = "",
  }) {
    final script = MakiScript._(this, binary, name, system);
    for (final variable in script.variables) {
      final info = variable.info;
      final isSystem = info.className == "system";
      if (isSystem && (info.isStatic || binary.version < 0x17)) {
        _assignObject(variable, system);
      } else if (info.isStatic && info.className != null) {
        final object = instantiate?.call(info.className!);
        if (object != null) _assignObject(variable, object);
      }
    }
    scripts.add(script);
    return script;
  }

  /// Unloads [script]: its variables let go of their objects.
  void unload(MakiScript script) {
    script.unloaded = true;
    for (final variable in script.variables) {
      final value = variable.value;
      if (value is MakiObject) value.bindings.remove(variable);
      variable.value = null;
    }
    scripts.remove(script);
  }

  /// Whether any script has a handler for [event] (lower-cased) on [target].
  bool handles(MakiObject target, String event) {
    for (final variable in target.bindings) {
      if (variable.script.unloaded) continue;
      if (variable.script._handlers[variable.index]?[event] != null) {
        return true;
      }
    }
    return false;
  }

  /// Fires [event] (lower-cased) on [target]: every script holding the
  /// object in a variable with a handler for it runs that handler, until one
  /// says `complete`. Returns the last handler's result.
  ///
  /// A variable of a script-defined class (`Class Button EQButtons;`) also
  /// runs the handlers written for that class and its user ancestors
  /// (`EQButtons.onLeftButtonUp`), with the class variable holding [target]
  /// while they run (`vcpu_addAssignedVariable` adds the ancestors, and
  /// `VCPU::callEvent` sets `vclass->v.data.odata`).
  Object? fire(
    MakiObject target,
    String event, [
    List<Object?> args = const [],
  ]) {
    _complete = false;
    Object? result;
    // Each class's handler runs once, however many of its variables hold
    // the object.
    final classes = <MakiVariable>{};
    for (final variable in List.of(target.bindings)) {
      final script = variable.script;
      if (script.unloaded) continue;
      final address = script._handlers[variable.index]?[event];
      if (address != null) {
        result = run(script, address, args);
        if (_complete) break;
      }
      var ancestor = variable.info.subclassOf;
      while (ancestor != null &&
          ancestor >= 0 &&
          ancestor < script.variables.length) {
        final classVariable = script.variables[ancestor];
        if (!classes.add(classVariable)) break;
        final handler = script._handlers[ancestor]?[event];
        if (handler != null) {
          classVariable.value = target;
          result = run(script, handler, args);
          if (_complete) break;
        }
        ancestor = classVariable.info.subclassOf;
      }
      if (_complete) break;
    }
    return result;
  }

  final Set<String> _nullCalls = {};

  int _runDepth = 0;
  MakiHandlerCall? _outerHandler;

  /// The event handler that is running (the outermost one), to run again
  /// later: a script's menu answers after the handler that opened it has
  /// returned, so the handler runs again and gets the answer then.
  MakiHandlerCall? get runningHandler => _outerHandler;

  /// Runs [call] again.
  Object? rerun(MakiHandlerCall call) =>
      run(call.script, call.address, call.args);

  /// Runs the code at [address] of [script] with [args] as its parameters.
  Object? run(MakiScript script, int address, List<Object?> args) {
    if (_runDepth == 0) {
      _outerHandler = MakiHandlerCall(script, address, List.of(args));
    }
    _runDepth++;
    try {
      return _run(script, address, args);
    } finally {
      _runDepth--;
    }
  }

  Object? _run(MakiScript script, int address, List<Object?> args) {
    final base = _stack.length;
    // The first parameter ends up on top (`executeEvent` reverses them).
    for (final arg in args.reversed) {
      _stack.add(_slotOf(arg));
    }
    try {
      _execute(script, address);
      if (_stack.length > base) return _stack.removeLast().value;
      return null;
    } on MakiError catch (error) {
      _log(
        "${script.name}: $error (at 0x${_ip.toRadixString(16)}, after $_lastCall)",
      );
      return null;
    } finally {
      if (_stack.length > base) _stack.length = base;
    }
  }

  void _execute(MakiScript script, int address) {
    final code = script.binary.code;
    final data = ByteData.sublistView(code);
    final calls = <int>[];
    var ip = address;
    var budget = instructionBudget;

    int operand() {
      final v = data.getInt32(ip, Endian.little);
      ip += 4;
      return v;
    }

    MakiVariable variable(int id) {
      if (id < 0 || id >= script.variables.length)
        throw MakiError("Invalid variable $id");
      return script.variables[id];
    }

    _Slot pop() {
      if (_stack.isEmpty) throw MakiError("Stack underflow");
      return _stack.removeLast();
    }

    while (true) {
      if (--budget < 0) throw MakiError("Script runs too long, stopped");
      if (ip < 0 || ip >= code.length)
        throw MakiError("Jumped outside the code");
      _ip = ip;
      trace?.call(script.name, ip, code[ip], _stack.length);
      final opcode = code[ip++];
      switch (opcode) {
        case 0x01: // PUSH
          final v = variable(operand());
          _stack.add(_Slot(v.type, v.value, v));
        case 0x02: // POPI
          pop();
        case 0x03: // POP
          final v = variable(operand());
          _assign(v, pop());
        case 0x08 || 0x09 || 0x0A || 0x0B || 0x0C || 0x0D: // CMPxx
          final b = pop();
          final a = pop();
          _stack.add(_Slot(MakiType.int_, _compare(opcode, a, b) ? 1 : 0));
        case 0x10: // JIZ
          final shift = operand();
          if (!_bool(pop())) ip += shift;
        case 0x11: // JNZ
          final shift = operand();
          if (_bool(pop())) ip += shift;
        case 0x12: // JMP
          final shift = operand();
          ip += shift;
        case 0x18: // CALLM
          final import = operand();
          var np = -1;
          if (ip + 4 <= code.length) {
            final marker = data.getInt32(ip, Endian.little);
            if (marker & 0xFFFF0000 == 0xFFFF0000) {
              np = marker & 0xFFFF;
              ip += 4;
            }
          }
          _call(script, import, np);
        case 0x70: // CALLM2
          final import = operand();
          final np = code[ip++];
          _call(script, import, np);
        case 0x19: // CALLC
          final shift = operand();
          calls.add(ip);
          ip += shift;
        case 0x20 || 0x21: // RET, RETF
          if (calls.isEmpty) return;
          ip = calls.removeLast();
        case 0x28: // CMPLT
          _complete = true;
        case 0x30: // SET
          final b = pop();
          final a = pop();
          final target = a.ref;
          if (target == null) throw MakiError("Assignment to a non-variable");
          _assign(target, b);
          _stack.add(_Slot(target.type, target.value, target));
        case 0x38 || 0x39 || 0x3A || 0x3B: // INCS, DECS, INCP, DECP
          final v = pop();
          final up = opcode == 0x38 || opcode == 0x3A;
          final Object next = switch (v.type) {
            MakiType.boolean => up,
            MakiType.int_ => _int(v) + (up ? 1 : -1),
            MakiType.float || MakiType.double_ => _double(v) + (up ? 1 : -1),
            _ => throw MakiError("Increment of a non-number"),
          };
          final updated = _Slot(v.type, next, v.ref);
          final ref = v.ref;
          if (ref != null) _assign(ref, updated);
          _stack.add(opcode < 0x3A ? v : updated);
        case 0x40: // ADD
          final b = pop();
          final a = pop();
          if (b.type == MakiType.string) {
            final left = a.value is String ? a.value! as String : "";
            _stack.add(_Slot(MakiType.string, "$left${b.value ?? ""}"));
          } else {
            _stack.add(_Slot(MakiType.double_, _double(a) + _double(b)));
          }
        case 0x41: // SUB
          final b = pop();
          final a = pop();
          _stack.add(_Slot(MakiType.double_, _double(a) - _double(b)));
        case 0x42: // MUL
          final b = pop();
          final a = pop();
          _stack.add(_Slot(MakiType.double_, _double(a) * _double(b)));
        case 0x43: // DIV
          final b = pop();
          final a = pop();
          final divisor = _double(b);
          // The classic player warns and goes on with 0 (`VCPU::safeDiv`); a warp
          // effect divides by zero at its centre on every frame, so once.
          if (divisor == 0 &&
              _reported.add("${script.name}: division by zero")) {
            _log(
              "${script.name}: division by zero (the result is 0), at "
              "0x${_ip.toRadixString(16)}, after $_lastCall",
            );
          }
          _stack.add(
            _Slot(MakiType.double_, divisor == 0 ? 0.0 : _double(a) / divisor),
          );
        case 0x44: // MOD
          final b = pop();
          final a = pop();
          final divisor = _int(b);
          if (divisor == 0) throw MakiError("Modulo by zero");
          _stack.add(_retype(a, _int(a).remainder(divisor)));
        case 0x48 || 0x49 || 0x4D || 0x58 || 0x59: // AND, OR, XOR, SHL, SHR
          final b = pop();
          final a = pop();
          final x = _int(a);
          final y = _int(b);
          final int r = switch (opcode) {
            0x48 => x & y,
            0x49 => x | y,
            0x4D => x ^ y,
            0x58 => (x << y).toSigned(32),
            _ => x >> y,
          };
          _stack.add(_retype(a, r));
        case 0x4A: // NOT
          _stack.add(_Slot(MakiType.boolean, !_bool(pop())));
        case 0x4B: // BNOT
          final a = pop();
          _stack.add(_retype(a, ~_int(a)));
        case 0x4C: // NEG
          final a = pop();
          _stack.add(switch (a.type) {
            MakiType.boolean => a,
            MakiType.int_ => _Slot(a.type, -_int(a)),
            MakiType.float || MakiType.double_ => _Slot(a.type, -_double(a)),
            _ => throw MakiError("Negation of a non-number"),
          });
        case 0x50: // LAND
          final b = pop();
          final a = pop();
          _stack.add(_Slot(MakiType.boolean, _bool(a) && _bool(b)));
        case 0x51: // LOR
          final b = pop();
          final a = pop();
          _stack.add(_Slot(MakiType.boolean, _bool(a) || _bool(b)));
        case 0x60: // NEW
          final className = _classOfType(script, operand());
          final object = className == null
              ? null
              : instantiate?.call(className);
          _stack.add(_Slot(MakiType.object, object));
        case 0x61: // DELETE
          final a = pop();
          final object = a.value;
          if (object is MakiObject) {
            object.dispose();
            final ref = a.ref;
            if (ref != null) _assign(ref, const _Slot(MakiType.object, null));
          }
          _stack.add(a);
        case 0x68: // UMV: a member variable of a script-defined class
          // (`Member String WidgetPlace.name;`): it belongs to the object the
          // script holds, one per script and name, made on first use
          // (`ScriptObject::vcpu_getMember`).
          final type = operand();
          final name = pop().value;
          final owner = pop().value;
          if (name is! String) throw MakiError("Member without a name");
          MakiVariable make() => MakiVariable(
            script,
            -1,
            MakiVariableInfo(
              type: type >= 0x100 ? MakiType.object : type,
              className: null,
              initial: switch (type) {
                MakiType.int_ => 0,
                MakiType.float || MakiType.double_ => 0.0,
                MakiType.boolean => false,
                MakiType.string => "",
                _ => null,
              },
              transient: true,
              isStatic: false,
              subclassOf: null,
            ),
          );
          // A member of no object reads as nothing and keeps nothing, as in
          // the original (ClassicPro's tabs ask the active tab's `ID` before there
          // is one).
          final member = owner is MakiObject
              ? owner.memberVariables.putIfAbsent((script, name), make)
              : make();
          _stack.add(_Slot(member.type, member.value, member));
        case 0x69: // UMC: not used by any script seen
          operand();
          pop();
          pop();
          _report("${script.name}: UMC");
          _stack.add(const _Slot(MakiType.object, null));
        case 0x00: // NOP
          break;
        default:
          throw MakiError(
            "Opcode 0x${opcode.toRadixString(16)} not implemented",
          );
      }
    }
  }

  String? _classOfType(MakiScript script, int type) {
    var t = type;
    while (t >= 0x10000) {
      final v = script.binary.variables[t - 0x10000];
      if (v.subclassOf == null) return v.className;
      t = v.subclassOf! + 0x10000;
    }
    return t < script.binary.classes.length ? script.binary.classes[t] : null;
  }

  void _call(MakiScript script, int importId, int np) {
    final imports = script.binary.imports;
    if (importId < 0 || importId >= imports.length)
      throw MakiError("Invalid function $importId");
    final import = imports[importId];
    _lastCall = "${import.className}.${import.name}";
    final count = np >= 0 ? np : import.params;
    if (count < 0) {
      throw MakiError("Unknown function ${import.className}.${import.name}");
    }
    final types = import.paramTypes;
    final args = List<Object?>.filled(count, null);
    for (var i = 0; i < count; i++) {
      if (_stack.isEmpty) throw MakiError("Stack underflow");
      final slot = _stack.removeLast();
      // Native functions read their arguments as the declared types
      // (GET_SCRIPT_INT and friends).
      args[i] = types == null || i >= types.length
          ? slot.value
          : _convert(types[i], slot);
    }
    if (_stack.isEmpty) throw MakiError("Stack underflow");
    final target = _stack.removeLast().value;
    if (target is! MakiObject) {
      // Once per script and member: a timer calling it would fill the log.
      if (_nullCalls.add("${script.name}/${import.name}")) {
        _log("${script.name}: null object called (${import.name})");
      }
      _stack.add(_slotForReturn(import.returns, null));
      return;
    }
    Object? result;
    try {
      result = target.invoke(this, import.name, args);
    } on MakiError {
      rethrow;
    } on Object catch (error) {
      _log("${script.name}: ${import.name} failed: $error");
      result = null;
    }
    if (identical(result, makiUnhandled)) {
      _report(
        "${makiClasses[target.makiClass]?.name ?? target.makiClass}.${import.name} not implemented",
      );
      result = null;
    }
    _stack.add(_slotForReturn(import.returns, result));
  }

  void _report(String message) {
    if (_reported.add(message)) _log("MAKI: $message");
  }

  _Slot _slotForReturn(String? returns, Object? value) {
    switch (returns) {
      case null:
        return _slotOf(value);
      case "int":
        return _Slot(MakiType.int_, _int(_slotOf(value)));
      case "boolean" || "bool":
        return _Slot(MakiType.boolean, _bool(_slotOf(value)));
      case "float":
        return _Slot(MakiType.float, _double(_slotOf(value)));
      case "double":
        return _Slot(MakiType.double_, _double(_slotOf(value)));
      case "string":
        return _Slot(MakiType.string, value?.toString() ?? "");
      case "any":
        return _slotOf(value);
      default:
        return _Slot(MakiType.object, value is MakiObject ? value : null);
    }
  }

  static Object? _convert(String type, _Slot slot) => switch (type) {
    "int" => _int(slot),
    "float" || "double" => _double(slot),
    "boolean" || "bool" => _bool(slot),
    "string" => slot.value is String ? slot.value : _string(slot),
    _ => slot.value,
  };

  static _Slot _slotOf(Object? value) => switch (value) {
    final int v => _Slot(MakiType.int_, v),
    final double v => _Slot(MakiType.double_, v),
    final bool v => _Slot(MakiType.boolean, v),
    final String v => _Slot(MakiType.string, v),
    _ => _Slot(MakiType.object, value),
  };

  /// A result of an integer operation, typed like its left operand.
  static _Slot _retype(_Slot like, int value) => switch (like.type) {
    MakiType.float || MakiType.double_ => _Slot(like.type, value.toDouble()),
    MakiType.boolean => _Slot(like.type, value != 0),
    _ => _Slot(MakiType.int_, value),
  };

  void _assign(MakiVariable target, _Slot source) {
    switch (target.type) {
      case MakiType.int_:
        target.value = _int(source);
      case MakiType.float || MakiType.double_:
        target.value = _double(source);
      case MakiType.boolean:
        target.value = _bool(source);
      case MakiType.string:
        final v = source.value;
        target.value = v is String ? v : (v == null ? "" : _string(source));
      default:
        final v = source.value;
        _assignObject(target, v is MakiObject ? v : null);
    }
  }

  void _assignObject(MakiVariable target, MakiObject? object) {
    final old = target.value;
    if (identical(old, object)) return;
    if (old is MakiObject && !target.info.transient)
      old.bindings.remove(target);
    target.value = object;
    if (object != null && !target.info.transient) object.bindings.add(target);
  }

  // --- Conversions (SOM::makeInt and friends) -------------------------------

  static int _int(_Slot s) {
    final v = s.value;
    return switch (v) {
      final int i => i,
      final double d => d.isFinite ? d.truncate() : 0,
      final bool b => b ? 1 : 0,
      final String t => _atoi(t),
      _ => 0,
    };
  }

  static double _double(_Slot s) {
    final v = s.value;
    return switch (v) {
      final int i => i.toDouble(),
      final double d => d,
      final bool b => b ? 1.0 : 0.0,
      final String t => _atof(t),
      _ => 0.0,
    };
  }

  static bool _bool(_Slot s) {
    final v = s.value;
    return switch (v) {
      final int i => i != 0,
      final double d => d != 0,
      final bool b => b,
      final String t => switch (t.toLowerCase()) {
        "false" || "f" => false,
        "true" || "t" => true,
        _ => _atoi(t) != 0,
      },
      null => false,
      _ => true,
    };
  }

  static String _string(_Slot s) {
    final v = s.value;
    return switch (v) {
      final double d => d.toString(),
      final bool b => b ? "1" : "0",
      _ => v?.toString() ?? "",
    };
  }

  /// `WTOI`: the leading integer of [text], 0 without one.
  static int _atoi(String text) {
    final match = RegExp(r"^\s*[+-]?\d+").firstMatch(text);
    return match == null ? 0 : int.parse(match[0]!.trim()).toSigned(32);
  }

  /// `WTOF`: the leading number of [text], 0 without one.
  static double _atof(String text) {
    final match = RegExp(
      r"^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?",
    ).firstMatch(text);
    return match == null ? 0 : double.parse(match[0]!.trim());
  }

  bool _compare(int opcode, _Slot a, _Slot b) {
    // Objects compare by identity, and `NULL` is the integer 0 as scripts
    // see it: an empty object variable equals it, and so does 0 itself.
    final av = a.value, bv = b.value;
    if (av is MakiObject || bv is MakiObject || a.type == MakiType.object) {
      Object? nothing(Object? v) => v is int && v == 0 ? null : v;
      final same = identical(nothing(av), nothing(bv));
      if (opcode == 0x08) return same;
      if (opcode == 0x09) return !same;
      return false;
    }
    switch (a.type) {
      case MakiType.int_:
        final x = _int(a);
        final y = _int(b);
        return _ordered(opcode, x.compareTo(y));
      case MakiType.float || MakiType.double_:
        final x = _double(a);
        final y = _double(b);
        if (opcode == 0x08) return x == y;
        if (opcode == 0x09) return x != y;
        return _ordered(opcode, x.compareTo(y));
      case MakiType.boolean:
        final x = _bool(a) ? 1 : 0;
        final y = _bool(b) ? 1 : 0;
        return _ordered(opcode, x.compareTo(y));
      case MakiType.string:
        final x = a.value;
        final y = b.value;
        if (x is String && y is String) {
          // Paths that differ only in their separators are the same file
          // (a script's `folder + "\" + name` against the player's path).
          if ((opcode == 0x08 || opcode == 0x09) &&
              x != y &&
              (x.contains(r"\") || y.contains(r"\")) &&
              wasabiSamePath(x, y)) {
            return opcode == 0x08;
          }
          return _ordered(opcode, x.compareTo(y));
        }
        return _ordered(opcode, identical(x, y) ? 0 : 1);
      default:
        final same = identical(a.value, b.value);
        if (opcode == 0x08) return same;
        if (opcode == 0x09) return !same;
        return false;
    }
  }

  static bool _ordered(int opcode, int c) => switch (opcode) {
    0x08 => c == 0,
    0x09 => c != 0,
    0x0A => c > 0,
    0x0B => c >= 0,
    0x0C => c < 0,
    _ => c <= 0,
  };
}
