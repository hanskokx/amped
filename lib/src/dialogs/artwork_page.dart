import "package:flutter/widgets.dart";

/// A picture, as big as the artwork window lets it be, in its own shape on
/// [background] (the skin's list background, as in the Album Art window);
/// nothing while it is not there or can't be loaded.
class ArtworkPage extends StatelessWidget {
  const ArtworkPage({
    required this.image,
    required this.background,
    super.key,
  });

  final ImageProvider? image;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return ColoredBox(
      color: background,
      child: image == null
          ? const SizedBox.expand()
          : Image(
              // A picture that replaces another is not mistaken for it.
              key: ValueKey(image),
              image: image,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.expand(),
            ),
    );
  }
}
