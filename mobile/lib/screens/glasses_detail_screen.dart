import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/glasses.dart';
import '../providers/providers.dart';
import '../widgets/glasses_image.dart';

/// Frame details, refreshed from GET /glasses/{id}.
class GlassesDetailScreen extends ConsumerWidget {
  const GlassesDetailScreen({super.key, required this.initial});

  /// Catalogue item shown immediately while the detail request runs.
  final Glasses initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(glassesDetailProvider(initial.id));
    final glasses = switch (detail) {
      AsyncData(:final value) => value,
      _ => initial,
    };
    final isFavorite = ref.watch(favoritesProvider.select((s) => s.contains(glasses.id)));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(glasses.name),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(glasses.id),
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.redAccent : null,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 900 / 540,
              child: Hero(
                tag: 'glasses-${glasses.id}',
                child: GlassesImage(glasses.catalogueImageUrl, fit: BoxFit.cover),
              ),
            ),
          ),
          if (detail.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (detail case AsyncError(:final error))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Showing cached details: $error',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  glasses.name,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                glasses.formattedPrice,
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text(glasses.category), avatar: const Icon(Icons.category_outlined, size: 18)),
          ),
          if (glasses.description != null) ...[
            const SizedBox(height: 12),
            Text(glasses.description!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Try-on overlay', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: GlassesImage(glasses.overlayImageUrl),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Transparent front view placed on your detected eye positions. '
                    'Demo artwork generated for this app; price is illustrative.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              openTryOn(ref, glasses: glasses);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Try on with camera'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              openTryOn(ref, glasses: glasses, launch: TryOnLaunch.pickPhoto);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Try on a photo'),
          ),
        ],
      ),
    );
  }
}
