import "dart:io";

import "package:amped_wasabi/src/maki/maki_binary.dart";
import "package:amped_wasabi/src/maki/maki_vm.dart";
import "package:flutter_test/flutter_test.dart";

import "amped_modern_skin.dart";

/// Records every call made to it.
class _Recorder extends MakiObject {
  _Recorder(this.makiClass, this.calls, [this.answers = const {}]);

  @override
  final String makiClass;
  final List<String> calls;
  final Map<String, Object? Function(List<Object?>)> answers;

  @override
  Object? invoke(MakiVm vm, String member, List<Object?> args) {
    calls.add("$makiClass.$member(${args.join(", ")})");
    final answer = answers[member];
    return answer == null ? null : answer(args);
  }
}

final File _mute = File("${ampedModern.path}/scripts/mute.maki");

void main() {
  test("runs Amped Modern's mute script", () {
    final calls = <String>[];
    final objects = <String, _Recorder>{
      for (final (id, cls) in const [
        ("mute", "togglebutton"),
        ("songticker", "text"),
        ("infoticker", "text"),
        ("volumebar", "layer"),
      ])
        id: _Recorder(cls, calls),
    };
    final group = _Recorder("group", calls, {
      "findobject": (a) => objects[a.single],
    });
    final system = _Recorder("system", calls, {
      "getruntimeversion": (_) => 5.66,
      "getprivateint": (a) => a[1] == "muted" ? 1 : 0,
      "getscriptgroup": (_) => group,
      "getvolume": (_) => 128,
      "integertostring": (a) => "${a.single}",
      "translate": (a) => a.single,
    });
    final timers = <_Recorder>[];
    final logged = <String>[];
    final vm = MakiVm(
      instantiate: (cls) =>
          cls == "timer" ? (_Recorder("timer", calls)..let(timers.add)) : null,
      log: logged.add,
    );
    final script = vm.load(
      MakiBinary.parse(_mute.readAsBytesSync()),
      system: system,
      name: "mute",
    );
    vm.fire(system, "onscriptloaded");
    expect(logged, isEmpty);
    expect(calls, contains("togglebutton.setactivated(true)"));
    expect(calls, contains("layer.setxmlparam(w, 40)"));
    expect(calls, contains("text.settext(Mute ON)"));
    expect(timers, hasLength(2));
    expect(calls, contains("timer.setdelay(1000)"));

    // The volume handler builds "Volume: 78%" with string concatenation and
    // float math, and unmutes.
    calls.clear();
    vm.fire(system, "onvolumechanged", [200]);
    expect(calls, contains("text.settext(Volume: 78%)"));
    expect(calls, contains("togglebutton.setactivated(false)"));
    expect(calls, contains("layer.setxmlparam(w, 59)"));
    // The shade button is only found by a timer that has not run here, so
    // the script calls a null object, which is reported and skipped.
    expect(logged, ["mute: null object called (setactivated)"]);

    // A click on the mute button (an event of a GUI object held in a
    // variable) mutes: setVolume(0).
    calls.clear();
    vm.fire(objects["mute"]!, "onleftclick");
    expect(calls, contains("system.setvolume(0)"));
    expect(script.unloaded, isFalse);
  });
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
