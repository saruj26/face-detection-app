import 'package:flutter/material.dart';

/// Shows a glasses image from a URL or a bundled asset path, with loading and
/// error states. Network failures fall back to the bundled copy (same file
/// name) so the demo catalogue still renders.
class GlassesImage extends StatelessWidget {
  const GlassesImage(this.source, {super.key, this.fit = BoxFit.contain});

  final String source;
  final BoxFit fit;

  bool get _isNetwork => source.startsWith('http://') || source.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final error = _ErrorPlaceholder(color: Theme.of(context).colorScheme.outline);
    if (!_isNetwork) {
      return Image.asset(source, fit: fit, errorBuilder: (_, _, _) => error);
    }
    return Image.network(
      source,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, _, _) => Image.asset(
        'assets/glasses/${Uri.parse(source).pathSegments.last}',
        fit: fit,
        errorBuilder: (_, _, _) => error,
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(Icons.broken_image_outlined, color: color, size: 32));
  }
}
