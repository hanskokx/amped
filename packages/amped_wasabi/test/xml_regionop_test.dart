import "package:amped_wasabi/src/xml.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("a layer's regionop is its sysregion", () {
    final node = parseXmlFragment('<layer image="a" regionop="-2" />').single;
    expect(node["sysregion"], "-2");
  });

  test("sysregion wins over regionop", () {
    final node = parseXmlFragment(
      '<layer sysregion="sub" regionop="-2" />',
    ).single;
    expect(node["sysregion"], "sub");
  });
}
