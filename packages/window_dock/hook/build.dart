import "package:code_assets/code_assets.dart";
import "package:hooks/hooks.dart";
import "package:native_toolchain_c/native_toolchain_c.dart";

/// Compiles the macOS native window helpers. Windows and Linux bind directly to
/// `user32` / GTK from Dart, so they need no native build.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS != OS.macOS) return;
    await CBuilder.library(
      name: "window_dock",
      assetName: "src/native/macos_bindings.dart",
      sources: ["src/window_dock_macos.m"],
      language: Language.objectiveC,
      frameworks: ["Cocoa", "QuartzCore"],
      flags: ["-fobjc-arc"],
    ).run(input: input, output: output);
  });
}
