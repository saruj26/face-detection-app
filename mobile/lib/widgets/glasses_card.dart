import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/glasses.dart';
import '../providers/providers.dart';
import 'glasses_image.dart';

class GlassesCard extends ConsumerWidget {
  const GlassesCard({super.key, required this.glasses, this.onTap});

  final Glasses glasses;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFavorite = ref.watch(favoritesProvider.select((s) => s.contains(glasses.id)));
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full image at its own aspect ratio, so frames are never cropped.
            AspectRatio(
              aspectRatio: productImageAspect,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Hero(
                      tag: 'glasses-${glasses.id}',
                      child: GlassesImage(glasses.catalogueImageUrl, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                      ),
                      iconSize: 20,
                      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                      onPressed: () => ref.read(favoritesProvider.notifier).toggle(glasses.id),
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.redAccent : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                glasses.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      glasses.category,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    glasses.formattedPrice,
                    style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
