import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/glasses_card.dart';
import 'catalogue_screen.dart';
import 'glasses_detail_screen.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: switch (catalogue) {
        AsyncData(:final value) => () {
            final items = value.items.where((g) => favorites.contains(g.id)).toList();
            if (items.isEmpty) {
              return _EmptyFavorites(
                onBrowse: () => ref.read(navigationProvider.notifier).go(AppTab.catalogue),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.98,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => GlassesCard(
                glasses: items[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => GlassesDetailScreen(initial: items[i])),
                ),
              ),
            );
          }(),
        AsyncError(:final error) => CatalogueError(
            message: error.toString(),
            onRetry: () => ref.invalidate(catalogueProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              'No favorites yet.\nTap the heart on any frame to save it here.\n'
              'Favorites are stored on this device only.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBrowse, child: const Text('Browse frames')),
          ],
        ),
      ),
    );
  }
}
