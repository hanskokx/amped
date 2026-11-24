import "package:code_assets/code_assets.dart";
import "package:hooks/hooks.dart";
import "package:native_toolchain_c/native_toolchain_c.dart";

/// Compiles the skin renderer in the app's `native/skin_preview`, the one its
/// Quick Look, Explorer and freedesktop previews use.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final native = input.packageRoot.resolve("../../native/skin_preview/");
    await CBuilder.library(
      name: "skin_preview",
      assetName: "src/bindings.dart",
      sources: [native.resolve("skin_preview.c").toFilePath()],
      includes: [native.toFilePath()],
      flags: ["-O2"],
    ).run(input: input, output: output);
  });
}
