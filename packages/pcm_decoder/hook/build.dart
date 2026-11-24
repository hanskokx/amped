import "package:code_assets/code_assets.dart";
import "package:hooks/hooks.dart";
import "package:native_toolchain_c/native_toolchain_c.dart";

/// Compiles the decoder with miniaudio, hiding miniaudio's own symbols so
/// they can't clash with the copy inside flutter_soloud.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final windows = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: "pcm_decoder",
      assetName: "pcm_decoder.dart",
      sources: ["src/pcm_decoder.c"],
      includes: ["src"],
      flags: windows ? const [] : const ["-fvisibility=hidden"],
      libraries: windows ? const [] : const ["m"],
      optimizationLevel: OptimizationLevel.o2,
    ).run(input: input, output: output);
  });
}
