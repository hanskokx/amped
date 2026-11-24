import "dart:io";

import "package:amped_maki/amped_maki.dart";
import "package:amped_wasabi/src/maki/maki_binary.dart";
import "package:amped_wasabi/src/maki/maki_vm.dart";
import "package:flutter_test/flutter_test.dart";

/// Records every call made to it.
class _Recorder extends MakiObject {
  _Recorder(this.makiClass, this.calls, [this.answers = const {}]);

  @override
  final String makiClass;
  final List<String> calls;
  final Map<String, Object? Function(List<Object?>)> answers;

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    if (member.startsWith("on")) return super.invoke(vm, member, args);
    calls.add("$makiClass.$member(${args.join(", ")})");
    final answer = answers[member];
    return answer == null ? null : answer(args);
  }
}

const _source = r'''
#define LIMIT 4
Global Group frame;
Global Timer ticker;
Global Int total;
Global String label;

Function Int twice(Int a);
Function note(String s);

System.onScriptLoaded() {
  frame = getScriptGroup();
  ticker = new Timer;
  ticker.setDelay(250);
  Int i = 0;
  while (i < LIMIT) {
    total += twice(i);
    i++;
  }
  for (i = 0; i < 10; i++) {
    if (i == 6) { break; }
    if (i % 2 == 1) { continue; }
    total = total + 100;
  }
  label = "Total: " + integerToString(total);
  note(label);
  if (frame != NULL && total > 300) {
    frame.findObject("big").show();
  } else {
    frame.findObject("small").hide();
  }
  if (total < 0 || total == 306) { note("or"); }
}

Int twice(Int a) {
  return a * 2;
}

note(String s) {
  frame.findObject("label").setXmlParam("text", s);
}

ticker.onTimer() {
  ticker.stop();
}

frame.onSetVisible(Int on) {
  if (!on) { note("hidden " + integerToString(on)); }
}
''';

void main() {
  test("compiles scripts the runtime runs", () {
    final dir = Directory.systemTemp.createTempSync("makic");
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File("${dir.path}/test.m")..writeAsStringSync(_source);
    final binary = compileMaki(source.path);
    File("${dir.path}/test.maki").writeAsBytesSync(binary);

    final calls = <String>[];
    final objects = <String, _Recorder>{
      for (final id in ["big", "small", "label"]) id: _Recorder("text", calls),
    };
    final group = _Recorder("group", calls, {
      "findobject": (a) => objects[a.single],
    });
    final system = _Recorder("system", calls, {
      "getscriptgroup": (_) => group,
      "integertostring": (a) => "${a.single}",
    });
    final logged = <String>[];
    final timers = <_Recorder>[];
    final vm = MakiVm(
      instantiate: (cls) {
        if (cls != "timer") return null;
        final timer = _Recorder("timer", calls);
        timers.add(timer);
        return timer;
      },
      log: logged.add,
    );
    vm.load(
      MakiBinary.parse(binary),
      system: system,
      name: "test",
    );
    vm.fire(system, "onscriptloaded");
    expect(logged, isEmpty);
    // 0+2+4+6 = 12, then 100 for each of 0, 2, 4 before breaking at 6.
    expect(calls, contains("timer.setdelay(250)"));
    expect(calls, contains("text.setxmlparam(text, Total: 312)"));
    expect(calls, contains("text.show()"));
    expect(calls, isNot(contains("text.hide()")));
    expect(calls.where((c) => c.contains("or")), isEmpty);

    calls.clear();
    vm.fire(group, "onsetvisible", [0]);
    expect(calls, contains("text.setxmlparam(text, hidden 0)"));
  });

  test("a Class line binds one handler that serves each of its objects", () {
    final dir = Directory.systemTemp.createTempSync("makic");
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File("${dir.path}/c.m")
      ..writeAsStringSync("""
Class Slider Seeker;
Global Seeker a, b;
Seeker.onSetPosition(int p) { }
""");
    final binary = MakiBinary.parse(compileMaki(file.path));
    final subclasses = [
      for (final v in binary.variables)
        if (v.subclassOf != null) v,
    ];
    expect(subclasses, hasLength(2));
    expect(subclasses.map((v) => v.className), everyElement("slider"));
    final handlers = binary.events
        .where((e) => binary.imports[e.import].name == "onsetposition")
        .toList();
    expect(handlers, hasLength(1));
    expect(binary.variables[handlers.single.variable].subclassOf, isNull);
    expect(
      subclasses.map((v) => v.subclassOf),
      everyElement(handlers.single.variable),
    );
  });
}
