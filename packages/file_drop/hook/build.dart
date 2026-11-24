import "package:code_assets/code_assets.dart";
import "package:hooks/hooks.dart";
import "package:native_toolchain_c/native_toolchain_c.dart";

/// Compiles the macOS drop target. Other platforms are not supported yet.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS != OS.macOS) return;
    await CBuilder.library(
      name: "file_drop",
      assetName: "src/macos_bindings.dart",
      sources: ["src/file_drop_macos.m"],
      language: Language.objectiveC,
      frameworks: ["Cocoa"],
      flags: ["-fobjc-arc"],
    ).run(input: input, output: output);
  });
}
